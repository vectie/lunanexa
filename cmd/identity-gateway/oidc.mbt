///|
priv struct JwtHeader {
  alg : String
} derive(FromJson)

///|
fn endpoint_origin_and_path(
  url : String,
  require_https : Bool,
) -> (String, String) raise {
  let prefix = if url.has_prefix("https://") {
    "https://"
  } else if !require_https && url.has_prefix("http://") {
    "http://"
  } else {
    raise Failure("endpoint protocol is not allowed")
  }
  let rest = url[prefix.length():]
  guard rest.find("/") is Some(index) && index > 0 else { return (url, "/") }
  let authority = rest[:index]
  guard !authority.contains("@") && authority != "" else {
    raise Failure("endpoint authority is invalid")
  }
  ("\{prefix}\{authority}", rest[index:].to_owned())
}

///|
fn oidc_trust(config : GatewayConfig) -> @tls.TrustedRoot {
  match config.oidc_ca_file {
    Some(path) => CustomPemFile(path)
    None => SystemRoot
  }
}

///|
fn oidc_transport_url(config : GatewayConfig, url : String) -> String raise {
  match config.oidc_transport_origin {
    None => url
    Some(origin) => {
      guard same_issuer_endpoint(config.issuer, url) else {
        raise Failure("OIDC transport endpoint escaped the configured issuer")
      }
      let (public_origin, _) = endpoint_origin_and_path(config.issuer, true)
      "\{origin}\{url[public_origin.length():]}"
    }
  }
}

///|
async fn oidc_get(
  config : GatewayConfig,
  url : String,
  headers : Map[String, String],
) -> (@http.Response, String) {
  let (origin, path) = endpoint_origin_and_path(
    oidc_transport_url(config, url),
    true,
  )
  let client = @http.Client(origin, trust=oidc_trust(config))
  defer client.close()
  let response = client.get(path, extra_headers=headers)
  let body = client.read_all().text()
  (response, body)
}

///|
async fn oidc_post_form(
  config : GatewayConfig,
  url : String,
  body : String,
  authorization : String,
) -> (@http.Response, String) {
  let (origin, path) = endpoint_origin_and_path(
    oidc_transport_url(config, url),
    true,
  )
  let client = @http.Client(origin, trust=oidc_trust(config))
  defer client.close()
  let response = client.post(path, body, extra_headers={
    "Authorization": authorization,
    "Accept": "application/json",
    "Content-Type": "application/x-www-form-urlencoded",
  })
  let response_body = client.read_all().text()
  (response, response_body)
}

///|
fn same_issuer_endpoint(issuer : String, endpoint : String) -> Bool {
  endpoint.has_prefix("\{issuer}/") &&
  !endpoint[issuer.length() + 1:].contains("//") &&
  !endpoint.contains("?") &&
  !endpoint.contains("#") &&
  !endpoint.contains("@") &&
  !endpoint.contains("\\")
}

///|
async fn discover(config : GatewayConfig) -> OidcDiscovery {
  let (response, body) = oidc_get(
    config,
    "\{config.issuer}/.well-known/openid-configuration",
    { "Accept": "application/json" },
  )
  guard response.code == 200 else {
    raise Failure("OIDC discovery was rejected")
  }
  let value : OidcDiscovery = @json.from_json(@json.parse(body))
  let introspection_is_safe = match value.introspection_endpoint {
    Some(endpoint) => same_issuer_endpoint(config.issuer, endpoint)
    None => false
  }
  guard value.issuer == config.issuer &&
    same_issuer_endpoint(config.issuer, value.authorization_endpoint) &&
    same_issuer_endpoint(config.issuer, value.token_endpoint) &&
    same_issuer_endpoint(config.issuer, value.userinfo_endpoint) &&
    introspection_is_safe else {
    raise Failure("OIDC discovery endpoints escaped the configured issuer")
  }
  value
}

///|
fn decode_jwt_part(value : StringView) -> String raise {
  @utf8.decode(@base64.decode(value, url_safe=true))
}

///|
fn audience_matches(value : Json, client_id : String) -> Bool {
  match value {
    String(value) => value == client_id
    Array(values) =>
      values.length() == 1 && values[0] == Json::string(client_id)
    _ => false
  }
}

///|
fn validate_id_token(
  id_token : String,
  issuer : String,
  client_id : String,
  expected_nonce : String,
  now_unix_ms : Int64,
) -> IdTokenClaims raise {
  guard id_token.split(".").collect()
    is [encoded_header, encoded_claims, signature] &&
    signature.length() >= 32 else {
    raise Failure("OIDC ID token is malformed")
  }
  let jwt_header : JwtHeader = @json.from_json(
    @json.parse(decode_jwt_part(encoded_header)),
  )
  guard jwt_header.alg == "RS256" else {
    raise Failure("OIDC ID token algorithm is not allowed")
  }
  let claims : IdTokenClaims = @json.from_json(
    @json.parse(decode_jwt_part(encoded_claims)),
  )
  let now = now_unix_ms / 1000L
  guard claims.iss == issuer &&
    claims.sub.length() >= 1 &&
    claims.sub.length() <= 1024 &&
    audience_matches(claims.aud, client_id) &&
    claims.azp.unwrap_or(client_id) == client_id &&
    claims.nonce == expected_nonce &&
    claims.exp.to_int64() > now &&
    claims.exp.to_int64() <= now + 28800L &&
    claims.nbf.unwrap_or(now.to_int()).to_int64() <= now + 5L &&
    claims.iat.unwrap_or(now.to_int()).to_int64() <= now + 5L &&
    claims.iat.unwrap_or(now.to_int()).to_int64() >= now - 600L else {
    raise Failure("OIDC ID token claims were rejected")
  }
  claims
}

///|
fn basic_authorization(client_id : String, client_secret : String) -> String {
  "Basic \{@base64.encode(@utf8.encode("\{client_id}:\{client_secret}").view())}"
}

///|
async fn exchange_code(
  config : GatewayConfig,
  discovery : OidcDiscovery,
  audience : BrowserAudience,
  code : String,
  verifier : String,
) -> OidcTokenResponse {
  let client_id = config.client_id(audience)
  let body = "grant_type=authorization_code&code=\{form_encode(code)}&redirect_uri=\{form_encode(config.redirect_uri(audience))}&client_id=\{form_encode(client_id)}&code_verifier=\{form_encode(verifier)}"
  let (response, response_body) = oidc_post_form(
    config,
    discovery.token_endpoint,
    body,
    basic_authorization(client_id, config.client_secret(audience)),
  )
  guard response.code == 200 else {
    raise Failure("OIDC authorization code exchange was rejected")
  }
  let token : OidcTokenResponse = @json.from_json(@json.parse(response_body))
  guard token.token_type.to_lower() == "bearer" &&
    token.access_token.length() >= 32 &&
    token.access_token.length() <= 8192 &&
    token.id_token.length() >= 64 &&
    token.id_token.length() <= 8192 else {
    raise Failure("OIDC token response was rejected")
  }
  token
}

///|
async fn verified_userinfo(
  config : GatewayConfig,
  discovery : OidcDiscovery,
  audience : BrowserAudience,
  token : OidcTokenResponse,
  expected_subject : String,
  now_unix_ms : Int64,
) -> UserInfo {
  let (response, body) = oidc_get(config, discovery.userinfo_endpoint, {
    "Authorization": "Bearer \{token.access_token}",
    "Accept": "application/json",
  })
  guard response.code == 200 else {
    raise Failure("OIDC userinfo was rejected")
  }
  let user : UserInfo = @json.from_json(@json.parse(body))
  guard user.sub == expected_subject else {
    raise Failure("OIDC userinfo subject did not match")
  }
  match discovery.introspection_endpoint {
    Some(endpoint) => {
      let client_id = config.client_id(audience)
      let (introspection_response, introspection_body) = oidc_post_form(
        config,
        endpoint,
        "token=\{form_encode(token.access_token)}&token_type_hint=access_token",
        basic_authorization(client_id, config.client_secret(audience)),
      )
      guard introspection_response.code == 200 else {
        raise Failure("OIDC token introspection was rejected")
      }
      let introspection : Introspection = @json.from_json(
        @json.parse(introspection_body),
      )
      let now = now_unix_ms / 1000L
      guard introspection.active &&
        introspection.sub == Some(expected_subject) &&
        (
          introspection.client_id == Some(client_id) ||
          introspection.azp == Some(client_id)
        ) &&
        introspection.exp.unwrap_or(0).to_int64() > now else {
        raise Failure("OIDC access token is not active for this client")
      }
    }
    None => raise Failure("OIDC provider has no introspection endpoint")
  }
  user
}

///|
fn safe_registration_claim(value : String, maximum : Int) -> Bool {
  value.length() > 0 &&
  value.length() <= maximum &&
  !value.contains("\n") &&
  !value.contains("\r") &&
  !value.contains("\u0000")
}

///|
async fn complete_oidc_callback(
  config : GatewayConfig,
  flow : GatewayCookie,
  audience : BrowserAudience,
  code : String,
  now_unix_ms : Int64,
) -> GatewayCookie {
  let discovery = discover(config)
  let token = exchange_code(config, discovery, audience, code, flow.verifier)
  let claims = validate_id_token(
    token.id_token,
    config.issuer,
    config.client_id(audience),
    flow.nonce,
    now_unix_ms,
  )
  let user = verified_userinfo(
    config,
    discovery,
    audience,
    token,
    claims.sub,
    now_unix_ms,
  )
  guard user.email is Some(email) &&
    safe_registration_claim(email, 320) &&
    email.contains("@") else {
    raise Failure("OIDC identity has no usable email")
  }
  let display_name = match user.name {
    Some(value) => value
    None => user.preferred_username.unwrap_or(email)
  }
  guard safe_registration_claim(display_name, 128) else {
    raise Failure("OIDC identity has no usable display name")
  }
  {
    kind: "identity",
    audience: audience.name(),
    host: flow.host,
    state: "",
    nonce: "",
    verifier: "",
    issuer: config.issuer,
    subject: claims.sub,
    email,
    display_name,
    bearer: "",
    csrf: "",
    created_unix_ms: now_unix_ms,
    last_used_unix_ms: now_unix_ms,
    expires_unix_ms: now_unix_ms + config.session_absolute_ms,
  }
}
