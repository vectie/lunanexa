///|
/// Customer self-registration.
///
/// The provider is the only authority over identities, so the portal cannot
/// write one itself: it asks the gateway, and the gateway asks the provider's
/// admin API with a credential the deployment gives it for no other purpose.
/// The credential is scoped to user administration and never reaches the
/// browser; the browser receives exactly what a password login returns, so the
/// portal has one session format and one code path after registration.
///
/// Two open questions the deployment, not this file, answers:
///
/// * Whether the gateway holds the credential at all. With
///   `LUNANEXA_OIDC_ADMIN_ORIGIN` unset, `/auth/register` answers 503 and
///   customer accounts must be created by an administrator.
/// * Whether a new account starts with the realm's default required actions.
///   A direct-grant login cannot complete an interactive action, so the body
///   below asks for none -- and this deployment's realm no longer marks
///   `CONFIGURE_TOTP` as a default action, because a default action applied by
///   the realm would override that empty list and leave every new customer
///   unable to sign in ("Account is not fully set up"). Both halves are needed:
///   the empty list for the account, the cleared default for the realm.
///
/// The admin origin must be an origin this gateway is allowed to reach. In this
/// deployment the provider's own pods accept connections from nothing but their
/// edges, so `LUNANEXA_OIDC_ADMIN_ORIGIN` is the same identity internal edge
/// `LUNANEXA_OIDC_TRANSPORT_ORIGIN` names, extended there with a
/// `POST`-only `/admin/realms/<realm>/users` location. Pointing it straight at
/// the provider's service name does not fail at startup; it fails at the first
/// registration with a refused connection.
priv suberror RegistrationError {
  EmailTaken
  PasswordRejected
  RegistrationUnavailable
}

///|
/// The portal's registration form. Registration is by email because the realm
/// sets `registrationEmailAsUsername`, so the provider is the authority on
/// what the username is and the gateway does not invent a second one.
priv struct RegistrationRequest {
  email : String
  display_name : String
  password : String
  audience : String
} derive(FromJson)

///|
/// The most a registration body may occupy. The fields are bounded far below
/// this; the cap keeps a hostile body from allocating before it is parsed.
const MaximumRegistrationRequestBytes : Int = 4096

///|
/// The provider's client-credentials answer. It carries no ID token, so it
/// cannot reuse the browser-facing token record.
priv struct AdminTokenResponse {
  access_token : String
  token_type : String
} derive(FromJson)

///|
/// One line naming the stage that refused a registration. The provider's own
/// text is not repeated here -- only the stage and a status or short reason --
/// because this line is the operator's only view into a route the customer
/// cannot inspect. It goes to stderr: this process buffers stdout, so a line
/// written there can sit unread for as long as the buffer takes to fill.
fn registration_stage_failed(stage : String, detail : String) -> Unit {
  eprintln(
    "[identity-gateway] customer registration failed at \{stage}: \{detail}",
  )
}

///|
/// A registration failure the browser is allowed to distinguish.
fn registration_failure_response(error : RegistrationError) -> (Int, String) {
  match error {
    RegistrationError::EmailTaken => (409, "email-taken")
    RegistrationError::PasswordRejected => (400, "password-rejected")
    RegistrationError::RegistrationUnavailable =>
      (503, "registration-unavailable")
  }
}

///|
/// An email the realm can adopt as a username. The realm rejects malformed
/// addresses anyway; this only stops a request that could never be a username
/// from reaching the provider, and keeps the value inside the bounds the
/// identity assertion later requires.
fn registration_email(value : String) -> String? {
  let trimmed = value.trim().to_owned()
  guard safe_registration_claim(trimmed, 320) &&
    trimmed.length() >= 6 &&
    trimmed.contains("@") &&
    !trimmed.contains(" ") &&
    !trimmed.contains("\t") &&
    !trimmed.has_prefix("@") &&
    !trimmed.has_suffix("@") else {
    return None
  }
  Some(trimmed)
}

///|
/// A display name the identity assertion will accept.
fn registration_display_name(value : String) -> String? {
  let trimmed = value.trim().to_owned()
  guard safe_registration_claim(trimmed, 128) && !trimmed.contains("\t") else {
    return None
  }
  Some(trimmed)
}

///|
fn parse_registration_request(body : String) -> RegistrationRequest raise {
  let request : RegistrationRequest = @json.from_json(@json.parse(body))
  guard registration_email(request.email) is Some(email) &&
    registration_display_name(request.display_name) is Some(display_name) &&
    request.password.length() >= 1 &&
    request.password.length() <= 1024 &&
    request.password.contains("\u0000") == false &&
    request.audience.length() <= 64 else {
    raise Failure("registration request is invalid")
  }
  { ..request, email, display_name, }
}

///|
/// The provider's admin API lives on the provider's own origin, which is not
/// the browser's issuer origin in every deployment, so it is configured rather
/// than derived.
fn registration_endpoint(config : GatewayConfig, path : String) -> String raise {
  guard config.registration_admin_origin is Some(origin) else {
    raise Failure("registration is not configured")
  }
  "\{origin}\{path}"
}

///|
async fn registration_post(
  config : GatewayConfig,
  url : String,
  body : String,
  authorization : String,
  content_type : String,
) -> (@http.Response, String) {
  let (origin, path) = endpoint_origin_and_path(url, true)
  let client = @http.Client(origin, trust=oidc_trust(config))
  defer client.close()
  let response = client.post(path, body, extra_headers={
    "Authorization": authorization,
    "Accept": "application/json",
    "Content-Type": content_type,
  })
  let response_body = client.read_all().text()
  (response, response_body)
}

///|
/// The service account's token. Client credentials only: the gateway has no
/// administrator username or password, and this call is the only place the
/// registration secret is used.
async fn registration_admin_token(
  config : GatewayConfig,
  realm : String,
) -> String raise RegistrationError {
  guard config.registration_client_id is Some(client_id) &&
    config.registration_client_secret is Some(secret) else {
    registration_stage_failed(
      "admin-token", "the service account is not configured",
    )
    raise RegistrationError::RegistrationUnavailable
  }
  let url = registration_endpoint(
    config,
    "/realms/\{realm}/protocol/openid-connect/token",
  ) catch {
    error => {
      registration_stage_failed("admin-token-endpoint", error.to_string())
      raise RegistrationError::RegistrationUnavailable
    }
  }
  let (response, body) = registration_post(
    config,
    url,
    "grant_type=client_credentials&client_id=\{form_encode(client_id)}",
    basic_authorization(client_id, secret),
    "application/x-www-form-urlencoded",
  ) catch {
    error => {
      registration_stage_failed("admin-token-transport", error.to_string())
      raise RegistrationError::RegistrationUnavailable
    }
  }
  guard response.code == 200 else {
    registration_stage_failed("admin-token-status", "HTTP \{response.code}")
    raise RegistrationError::RegistrationUnavailable
  }
  let token : AdminTokenResponse = @json.from_json(@json.parse(body)) catch {
    error => {
      registration_stage_failed("admin-token-body", error.to_string())
      raise RegistrationError::RegistrationUnavailable
    }
  }
  guard token.token_type.to_lower() == "bearer" &&
    token.access_token.length() >= 32 &&
    token.access_token.length() <= 8192 else {
    registration_stage_failed("admin-token-shape", token.token_type)
    raise RegistrationError::RegistrationUnavailable
  }
  token.access_token
}

///|
/// The account the provider is asked to create.
///
/// `emailVerified` is set because this deployment has no mail path, and the
/// realm's own registration flow would require a click the customer can never
/// receive. `requiredActions` is empty for the reason given at the top of this
/// file. `firstName` carries the display name so the assertion and the session
/// show the customer's own words rather than the address they registered with.
fn registration_user_body(request : RegistrationRequest) -> Json {
  let credential : Map[String, Json] = {
    "type": Json::string("password"),
    "value": Json::string(request.password),
    "temporary": Json::boolean(false),
  }
  let no_required_actions : Array[Json] = []
  let credentials : Array[Json] = [Json::object(credential)]
  let fields : Map[String, Json] = {
    "username": Json::string(request.email),
    "email": Json::string(request.email),
    "firstName": Json::string(request.display_name),
    "enabled": Json::boolean(true),
    "emailVerified": Json::boolean(true),
    "requiredActions": Json::array(no_required_actions),
    "credentials": Json::array(credentials),
  }
  Json::object(fields)
}

///|
/// Translate the provider's answer. The provider is the authority on whether an
/// address is already taken and on whether the password meets the realm policy,
/// so both are read from its status and never guessed here.
fn registration_create_failure(status : Int) -> RegistrationError {
  if status == 409 {
    RegistrationError::EmailTaken
  } else if status == 400 {
    RegistrationError::PasswordRejected
  } else if status == 401 || status == 403 {
    // The deployment's service account is not allowed to create users. That is
    // an operator problem, not the customer's, so it reads as unavailable.
    RegistrationError::RegistrationUnavailable
  } else {
    RegistrationError::RegistrationUnavailable
  }
}

///|
async fn registration_create_user(
  config : GatewayConfig,
  realm : String,
  admin_token : String,
  request : RegistrationRequest,
) -> Unit raise RegistrationError {
  let url = registration_endpoint(config, "/admin/realms/\{realm}/users") catch {
    error => {
      registration_stage_failed("create-user-endpoint", error.to_string())
      raise RegistrationError::RegistrationUnavailable
    }
  }
  let (response, _) = registration_post(
    config,
    url,
    registration_user_body(request).stringify(),
    "Bearer \{admin_token}",
    "application/json",
  ) catch {
    error => {
      registration_stage_failed("create-user-transport", error.to_string())
      raise RegistrationError::RegistrationUnavailable
    }
  }
  guard response.code == 201 else {
    registration_stage_failed("create-user-status", "HTTP \{response.code}")
    raise registration_create_failure(response.code)
  }
}

///|
/// `POST /auth/register` -- customer self-registration for the portal.
///
/// Request: `{"email": "...", "display_name": "...", "password": "...",
/// "audience": "enterprise"}`, `Content-Type: application/json`, same origin as
/// the browser host, body bounded by `MaximumRegistrationRequestBytes`.
///
/// The operator audience is refused: the platform has one administrator account
/// and it is not created from a web form.
///
/// Response on success: HTTP 201 with the same session document and cookie
/// `/auth/password` returns, because the account is created and then logged in
/// through exactly that path. The provider's admin credential stays in this
/// process, and no upstream error text is echoed.
async fn handle_registration(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
  host : String,
  audience : BrowserAudience,
) -> Unit {
  guard request.meth == Post && request.path == "/auth/register" else {
    return send_error(connection, 405, "method-not-allowed")
  }
  guard audience == Enterprise else {
    return send_error(connection, 403, "registration-audience-rejected")
  }
  guard exact_origin(request, host, secure=config.browser_secure()) &&
    header(request.headers, "Content-Type") is Some(content_type) &&
    content_type.has_prefix("application/json") else {
    return send_error(connection, 403, "registration-origin-rejected")
  }
  if config.registration_admin_origin is None {
    registration_stage_failed(
      "configuration", "no LUNANEXA_OIDC_ADMIN_ORIGIN in this process",
    )
    return send_error(connection, 503, "registration-unavailable")
  }
  let now = @async.now()
  // Registration shares the login failure table. A run of rejected attempts
  // from one address is bounded the same way, and a completed registration
  // clears it like a successful login does.
  let source = "\{connection.client_addr()}"
  guard password_login_failures.allows(source, now) else {
    return send_error(connection, 429, "too-many-attempts")
  }
  let body = reader.read_all().binary()
  guard body.length() <= MaximumRegistrationRequestBytes else {
    return send_error(connection, 413, "registration-request-too-large")
  }
  let parsed = parse_registration_request(@utf8.decode(body)) catch {
    _ => return send_error(connection, 400, "invalid-registration-request")
  }
  guard password_login_audience(parsed.audience) is Some(requested) &&
    requested == audience else {
    return send_error(connection, 400, "invalid-registration-audience")
  }
  let realm = configured_realm(config.issuer) catch {
    error => {
      registration_stage_failed("realm", error.to_string())
      return send_error(connection, 503, "registration-unavailable")
    }
  }
  // Each step logs its own stage before it raises, so this catch only has to
  // keep the route's single browser-facing code.
  let admin_token = registration_admin_token(config, realm) catch {
    _ => return send_error(connection, 503, "registration-unavailable")
  }
  registration_create_user(config, realm, admin_token, parsed) catch {
    error => {
      let (status, code) = registration_failure_response(error)
      password_login_failures.record_failure(source, now)
      return send_error(connection, status, code)
    }
  }
  // The account exists. From here the request is a password login, so the
  // portal cannot tell a first registration from a later sign-in.
  let identity = complete_password_login(
    config,
    host,
    audience,
    parsed.email,
    parsed.password,
    now,
  ) catch {
    error => {
      let (status, code) = password_login_failure_response(error)
      if status == 401 {
        password_login_failures.record_failure(source, now)
      }
      return send_error(connection, status, code)
    }
  }
  let session = issue_controller_session(config, identity, audience, now) catch {
    _ => return send_error(connection, 503, "identity-session-unavailable")
  }
  let session_id = store.create(session) catch {
    _ => return send_error(connection, 503, "identity-session-unavailable")
  }
  password_login_failures.record_success(source)
  let cookie_reference = encode_cookie_reference(
    session_id,
    config.cookie_secret(audience),
  )
  send_body(
    connection,
    201,
    browser_session_body(session),
    "application/json; charset=utf-8",
    headers={
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
      "Vary": "Cookie",
    },
    cookies=[
      browser_cookie(
        config.cookie_name_for_host(audience, host),
        cookie_reference,
        (session.expires_unix_ms - now) / 1000L,
        secure=config.browser_secure(),
      ),
    ],
  )
}
