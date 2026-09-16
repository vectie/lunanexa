///|
async fn post_internal(
  endpoint : String,
  path : String,
  body : String,
  headers : Map[String, String],
) -> (@http.Response, String) {
  let (origin, base_path) = endpoint_origin_and_path(endpoint, false)
  guard base_path == "/" else {
    raise Failure("internal endpoint must be an origin")
  }
  let client = @http.Client(origin)
  defer client.close()
  let response = client.post(path, body, extra_headers=headers)
  (response, client.read_all().text())
}

///|
fn assertion_headers(
  config : GatewayConfig,
  identity : GatewayCookie,
  registration : Bool,
  issued : Int64,
  expires : Int64,
  nonce : String,
) -> Map[String, String] {
  let canonical = if registration {
    "lunanexa.identity.registration.v1\n\{identity.issuer}\n\{identity.subject}\n\{identity.email}\n\{identity.display_name}\n\{issued}\n\{expires}\n\{nonce}"
  } else {
    "lunanexa.identity.assertion.v1\n\{identity.issuer}\n\{identity.subject}\n\{issued}\n\{expires}\n\{nonce}"
  }
  let signature = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(config.assertion_secret).view(),
      @utf8.encode(canonical).view(),
    ),
  )
  let headers : Map[String, String] = {
    "Accept": "application/json",
    "Content-Type": "application/json",
    "X-LunaNexa-Identity-Issuer": identity.issuer,
    "X-LunaNexa-Identity-Subject": identity.subject,
    "X-LunaNexa-Identity-Issued-At": issued.to_string(),
    "X-LunaNexa-Identity-Expires-At": expires.to_string(),
    "X-LunaNexa-Identity-Nonce": nonce,
    "X-LunaNexa-Identity-Signature": "sha256:\{signature}",
  }
  if registration {
    headers["X-LunaNexa-Identity-Email"] = identity.email
    headers["X-LunaNexa-Identity-Display-Name"] = identity.display_name
  }
  headers
}

///|
async fn controller_identity_post(
  config : GatewayConfig,
  identity : GatewayCookie,
  registration : Bool,
  lifetime_ms : Int64,
) -> (@http.Response, String) {
  let issued = @async.now()
  let expires = issued + config.assertion_lifetime_ms
  let nonce = random_token(24)
  let path = if registration {
    "/v1/auth/register"
  } else {
    "/v1/auth/session:exchange"
  }
  post_internal(
    config.relay_endpoint,
    path,
    "{\"lifetime_ms\":\"\{lifetime_ms}\"}",
    assertion_headers(config, identity, registration, issued, expires, nonce),
  )
}

///|
async fn issue_controller_session(
  config : GatewayConfig,
  identity : GatewayCookie,
  audience : BrowserAudience,
  now : Int64,
) -> GatewayCookie {
  let maximum_expiry = if identity.expires_unix_ms <
    now + config.session_absolute_ms {
    identity.expires_unix_ms
  } else {
    now + config.session_absolute_ms
  }
  let lifetime = maximum_expiry - now
  guard lifetime >= 60000L else {
    raise Failure("verified identity is too close to expiry")
  }
  let (exchange_response, exchange_body) = controller_identity_post(
    config, identity, false, lifetime,
  )
  let issued : IssuedControllerSession = if exchange_response.code == 201 {
    @json.from_json(@json.parse(exchange_body))
  } else if exchange_requires_registration(exchange_response.code) {
    let (register_response, register_body) = controller_identity_post(
      config, identity, true, lifetime,
    )
    guard register_response.code == 201 else {
      raise Failure("LunaNexa account registration was rejected")
    }
    let registered : RegisteredControllerSession = @json.from_json(
      @json.parse(register_body),
    )
    registered.session
  } else {
    raise Failure("LunaNexa session exchange was rejected")
  }
  guard issued.secret.has_prefix("lnxs_") &&
    issued.secret.length() >= 32 &&
    issued.secret.length() <= 512 &&
    issued.session.expires_unix_ms > now else {
    raise Failure("LunaNexa session response was invalid")
  }
  let expires = if issued.session.expires_unix_ms < maximum_expiry {
    issued.session.expires_unix_ms
  } else {
    maximum_expiry
  }
  {
    ..identity,
    kind: "session",
    audience: audience.name(),
    bearer: issued.secret,
    csrf: random_token(32),
    last_used_unix_ms: now,
    expires_unix_ms: expires,
  }
}

///|
fn exchange_requires_registration(status : Int) -> Bool {
  // The account store deliberately maps an unknown external identity to 401;
  // older deployments used 404. Registration remains separately signed and
  // will reject suspended or conflicting existing accounts.
  status == 401 || status == 404
}

///|
async fn revoke_controller_session(
  config : GatewayConfig,
  bearer : String,
) -> Int {
  let (response, _) = post_internal(
    config.control_endpoint,
    "/v1/auth/logout",
    "{}",
    {
      "Authorization": "Bearer \{bearer}",
      "Accept": "application/json",
      "Content-Type": "application/json",
    },
  )
  response.code
}

///|
fn relay_identity_headers(
  headers : Map[String, String],
) -> Map[String, String]? {
  let names = [
    "X-LunaNexa-Identity-Issuer", "X-LunaNexa-Identity-Subject", "X-LunaNexa-Identity-Issued-At",
    "X-LunaNexa-Identity-Expires-At", "X-LunaNexa-Identity-Nonce", "X-LunaNexa-Identity-Signature",
  ]
  let forwarded : Map[String, String] = {
    "Accept": "application/json",
    "Content-Type": "application/json",
  }
  for name in names {
    guard header(headers, name) is Some(value) && value.length() <= 2048 else {
      return None
    }
    forwarded[name] = value
  }
  match header(headers, "X-LunaNexa-Identity-Email") {
    Some(value) => forwarded["X-LunaNexa-Identity-Email"] = value
    None => ()
  }
  match header(headers, "X-LunaNexa-Identity-Display-Name") {
    Some(value) => forwarded["X-LunaNexa-Identity-Display-Name"] = value
    None => ()
  }
  Some(forwarded)
}
