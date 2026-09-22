///|
/// The direct-access (username + password) grant is the one browser login that
/// is not an OIDC redirect. The browser resolves an audience exactly like every
/// other route -- `host_and_audience` in `handle_proxy` maps the `Host` header
/// to an operator or enterprise client -- but the route deliberately does not
/// consult the configured redirect URI the way `/auth/oidc/start` does, because
/// there is no browser redirect to make: the credentials are checked against the
/// provider's token endpoint here, and the browser only ever receives the
/// resulting `lnxs_` session.
priv suberror PasswordLoginError {
  InvalidCredentials
  IdentityRejected
  UpstreamUnavailable
}

///|
priv struct PasswordLoginRequest {
  username : String
  password : String
  audience : String
} derive(FromJson)

///|
/// The most a password login body may occupy. The credential fields are bounded
/// far below this; the cap keeps a hostile body from allocating before it is
/// parsed.
const MaximumPasswordRequestBytes : Int = 4096

///|
/// Failures allowed per source before that source is blocked for a window.
const PasswordFailureLimit : Int = 8

///|
/// Window in which failures accumulate, and the block applied once the limit is
/// reached. Both are deliberately simple fixed windows rather than an
/// exponential backoff: the operator login is not a latency-sensitive path.
const PasswordFailureWindowMs : Int64 = 300000L

///|
const PasswordFailureBlockMs : Int64 = 300000L

///|
/// Upper bound on tracked sources. Expired windows are dropped before new ones
/// are admitted; a table that is still full simply stops admitting new sources,
/// so a flood of source addresses cannot grow the table without bound.
const PasswordFailureSources : Int = 1024

///|
priv struct PasswordFailureWindow {
  failures : Int
  window_started_unix_ms : Int64
  blocked_until_unix_ms : Int64
}

///|
/// Bounded, in-process password-failure accounting. It is intentionally not
/// shared state: each identity-gateway process owns one table, so a restart
/// clears it, and it is best effort rather than an authoritative lockout.
priv struct PasswordLoginThrottle {
  mutex : @async.Mutex
  mut windows : Map[String, PasswordFailureWindow]
}

///|
fn PasswordLoginThrottle::new() -> PasswordLoginThrottle {
  { mutex: Mutex(), windows: Map([]), }
}

///|
async fn PasswordLoginThrottle::allows(
  self : PasswordLoginThrottle,
  source : String,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  match self.windows.get(source) {
    None => true
    Some(window) =>
      if window.blocked_until_unix_ms > now_unix_ms {
        false
      } else if window.window_started_unix_ms + PasswordFailureWindowMs <=
        now_unix_ms {
        // The window lapsed; the next failure starts a fresh count.
        ignore(self.windows.remove(source))
        true
      } else {
        true
      }
  }
}

///|
async fn PasswordLoginThrottle::record_failure(
  self : PasswordLoginThrottle,
  source : String,
  now_unix_ms : Int64,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  let tracked = self.windows.get(source)
  if tracked is None && self.windows.length() >= PasswordFailureSources {
    self.prune(now_unix_ms)
    // Still full: the table is the bound, so the source is not tracked.
    if self.windows.length() >= PasswordFailureSources {
      return
    }
  }
  let window = match tracked {
    Some(existing) if existing.window_started_unix_ms + PasswordFailureWindowMs >
      now_unix_ms => { ..existing, failures: existing.failures + 1, }
    _ =>
      {
        failures: 1,
        window_started_unix_ms: now_unix_ms,
        blocked_until_unix_ms: 0L,
      }
  }
  if window.failures >= PasswordFailureLimit {
    self.windows[source] = {
      ..window,
      blocked_until_unix_ms: now_unix_ms + PasswordFailureBlockMs,
    }
  } else {
    self.windows[source] = window
  }
}

///|
async fn PasswordLoginThrottle::record_success(
  self : PasswordLoginThrottle,
  source : String,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  ignore(self.windows.remove(source))
}

///|
fn PasswordLoginThrottle::prune(
  self : PasswordLoginThrottle,
  now_unix_ms : Int64,
) -> Unit {
  let retained : Map[String, PasswordFailureWindow] = Map([])
  for source, window in self.windows {
    if window.blocked_until_unix_ms > now_unix_ms ||
      window.window_started_unix_ms + PasswordFailureWindowMs > now_unix_ms {
      retained[source] = window
    }
  }
  self.windows = retained
}

///|
/// Process-wide failure table used by the route. It is deliberately the only
/// mutable module state in the gateway, and it holds no credential material.
let password_login_failures : PasswordLoginThrottle = PasswordLoginThrottle::new()

///|
fn password_login_audience(value : String) -> BrowserAudience? {
  if value == Operator.name() {
    Some(Operator)
  } else if value == Enterprise.name() {
    Some(Enterprise)
  } else {
    None
  }
}

///|
fn parse_password_login_request(body : String) -> PasswordLoginRequest raise {
  let request : PasswordLoginRequest = @json.from_json(@json.parse(body))
  guard request.username.length() >= 1 &&
    request.username.length() <= 256 &&
    request.password.length() >= 1 &&
    request.password.length() <= 1024 &&
    request.audience.length() <= 64 &&
    !request.username.contains("\u0000") &&
    !request.username.contains("\n") &&
    !request.username.contains("\r") else {
    raise Failure("password login request is invalid")
  }
  request
}

///|
/// The exact resource-owner-password form. Both credential fields are encoded,
/// and the client secret never appears here: it travels only in the
/// `Authorization` header built by `basic_authorization`.
fn password_grant_body(
  client_id : String,
  username : String,
  password : String,
) -> String {
  "grant_type=password&client_id=\{form_encode(client_id)}&username=\{form_encode(username)}&password=\{form_encode(password)}&scope=openid%20profile%20email"
}

///|
/// A rejected grant and an unreachable provider must not look the same to the
/// browser. Keycloak answers a bad username or password with 400
/// `invalid_grant`, and a disabled or mis-scoped client with 401 or 403; all
/// three mean the credentials were not accepted.
fn password_token_failure(status : Int) -> PasswordLoginError {
  if status == 400 || status == 401 || status == 403 {
    PasswordLoginError::InvalidCredentials
  } else {
    PasswordLoginError::UpstreamUnavailable
  }
}

///|
/// The only thing the browser learns about a failure. Upstream error text, the
/// username, and the password are never echoed.
fn password_login_failure_response(error : PasswordLoginError) -> (Int, String) {
  match error {
    PasswordLoginError::InvalidCredentials => (401, "invalid-credentials")
    PasswordLoginError::IdentityRejected => (401, "identity-rejected")
    PasswordLoginError::UpstreamUnavailable =>
      (503, "identity-provider-unavailable")
  }
}

///|
async fn password_token_exchange(
  config : GatewayConfig,
  discovery : OidcDiscovery,
  audience : BrowserAudience,
  username : String,
  password : String,
) -> OidcTokenResponse raise PasswordLoginError {
  let client_id = config.client_id(audience)
  let (response, response_body) = oidc_post_form(
    config,
    discovery.token_endpoint,
    password_grant_body(client_id, username, password),
    basic_authorization(client_id, config.client_secret(audience)),
  ) catch {
    _ => raise PasswordLoginError::UpstreamUnavailable
  }
  guard response.code == 200 else {
    raise password_token_failure(response.code)
  }
  let token : OidcTokenResponse = @json.from_json(@json.parse(response_body)) catch {
    _ => raise PasswordLoginError::UpstreamUnavailable
  }
  guard token.token_type.to_lower() == "bearer" &&
    token.access_token.length() >= 32 &&
    token.access_token.length() <= 8192 &&
    token.id_token.length() >= 64 &&
    token.id_token.length() <= 8192 else {
    raise PasswordLoginError::UpstreamUnavailable
  }
  token
}

///|
/// Builds the verified-identity record from a provider userinfo response. This
/// is the same construction the callback uses; only the subject binding and the
/// usable-email and display-name guards are kept here, so a provider that
/// returns an unusable identity fails closed instead of minting a session.
fn password_identity_cookie(
  config : GatewayConfig,
  host : String,
  audience : BrowserAudience,
  subject : String,
  user : UserInfo,
  now_unix_ms : Int64,
) -> GatewayCookie raise PasswordLoginError {
  guard user.email is Some(email) &&
    safe_registration_claim(email, 320) &&
    email.contains("@") else {
    raise PasswordLoginError::IdentityRejected
  }
  let display_name = match user.name {
    Some(value) => value
    None => user.preferred_username.unwrap_or(email)
  }
  guard safe_registration_claim(display_name, 128) else {
    raise PasswordLoginError::IdentityRejected
  }
  {
    kind: "identity",
    audience: audience.name(),
    host,
    state: "",
    nonce: "",
    verifier: "",
    issuer: config.issuer,
    subject,
    email,
    display_name,
    bearer: "",
    csrf: "",
    created_unix_ms: now_unix_ms,
    last_used_unix_ms: now_unix_ms,
    expires_unix_ms: now_unix_ms + config.session_absolute_ms,
  }
}

///|
/// Runs the direct grant against the configured issuer and validates the result
/// exactly like the authorization-code callback: discovery must stay on the
/// issuer, the ID token is checked against issuer, client, and lifetime, and the
/// userinfo subject and email are verified. The direct grant carries no `nonce`
/// because there was no authorization request to bind one, so the nonce check is
/// skipped; every other claim check is identical.
async fn complete_password_login(
  config : GatewayConfig,
  host : String,
  audience : BrowserAudience,
  username : String,
  password : String,
  now_unix_ms : Int64,
) -> GatewayCookie raise PasswordLoginError {
  let discovery = discover(config) catch {
    _ => raise PasswordLoginError::UpstreamUnavailable
  }
  let token = password_token_exchange(
    config, discovery, audience, username, password,
  )
  let claims = validate_id_token(
    token.id_token,
    config.issuer,
    config.client_id(audience),
    None,
    now_unix_ms,
  ) catch {
    _ => raise PasswordLoginError::IdentityRejected
  }
  let user = verified_userinfo(
    config,
    discovery,
    audience,
    token,
    claims.sub,
    now_unix_ms,
  ) catch {
    _ => raise PasswordLoginError::IdentityRejected
  }
  password_identity_cookie(
    config,
    host,
    audience,
    claims.sub,
    user,
    now_unix_ms,
  )
}

///|
/// `POST /auth/password` -- the unified username/password login.
///
/// Request: `{"username": "...", "password": "...", "audience":
/// "operator"|"enterprise"}`, `Content-Type: application/json`, same origin as
/// the browser host, body bounded by `MaximumPasswordRequestBytes`.
///
/// Response on success: HTTP 200 with the exact `browser_session_body` document
/// `/auth/session` returns, plus the ordinary audience cookie. The session is
/// minted through `issue_controller_session`, the same path `/auth/session`
/// uses, so the stored record is an ordinary `lnxs_` session. The client secret
/// stays in this process.
async fn handle_password_login(
  store : GatewaySessionStore,
  config : GatewayConfig,
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
  host : String,
  audience : BrowserAudience,
) -> Unit {
  guard request.meth == Post && request.path == "/auth/password" else {
    return send_error(connection, 405, "method-not-allowed")
  }
  guard exact_origin(request, host, secure=config.browser_secure()) &&
    header(request.headers, "Content-Type") is Some(content_type) &&
    content_type.has_prefix("application/json") else {
    return send_error(connection, 403, "password-login-origin-rejected")
  }
  let now = @async.now()
  // The source address bounds guessing per client. Behind a reverse proxy every
  // browser shares the proxy address, so this is a best-effort throttle, not an
  // authentication control.
  let source = "\{connection.client_addr()}"
  guard password_login_failures.allows(source, now) else {
    return send_error(connection, 429, "too-many-attempts")
  }
  let body = reader.read_all().binary()
  guard body.length() <= MaximumPasswordRequestBytes else {
    return send_error(connection, 413, "password-request-too-large")
  }
  let parsed = parse_password_login_request(@utf8.decode(body)) catch {
    _ => return send_error(connection, 400, "invalid-password-request")
  }
  guard password_login_audience(parsed.audience) is Some(requested) &&
    requested == audience else {
    return send_error(connection, 400, "invalid-password-audience")
  }
  let identity = complete_password_login(
    config,
    host,
    audience,
    parsed.username,
    parsed.password,
    now,
  ) catch {
    error => {
      let (status, code) = password_login_failure_response(error)
      // A rejected login counts against the source; a provider outage does not,
      // so an unavailable issuer cannot lock out every operator.
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
    200,
    browser_session_body(session),
    "application/json; charset=utf-8",
    headers={
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
      "Vary": "Cookie",
    },
    cookies=[
      browser_cookie(
        config.cookie_name(audience),
        cookie_reference,
        (session.expires_unix_ms - now) / 1000L,
        secure=config.browser_secure(),
      ),
    ],
  )
}
