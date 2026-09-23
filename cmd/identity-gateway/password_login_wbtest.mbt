///|
fn password_test_config(relay_endpoint : String) -> GatewayConfig {
  {
    mode: Proxy,
    listen_address: "127.0.0.1:0",
    issuer: "https://identity.example/realms/lunanexa",
    canonical_identity_issuer: None,
    oidc_transport_origin: None,
    oidc_ca_file: None,
    operator_host: "operator.example",
    enterprise_host: "enterprise.example",
    alternate_https_port: false,
    browser_oidc_enabled: true,
    operator_redirect_uri: "https://operator.example/auth/oidc/callback",
    enterprise_redirect_uri: "https://enterprise.example/auth/oidc/callback",
    operator_client_id: "lunanexa-operator",
    enterprise_client_id: "lunanexa-enterprise",
    operator_client_secret: "operator-client-secret",
    enterprise_client_secret: "enterprise-client-secret",
    operator_cookie_name: "__Host-operator",
    enterprise_cookie_name: "__Host-enterprise",
    operator_cookie_secret: "operator-cookie-secret-32-bytes-000",
    enterprise_cookie_secret: "enterprise-cookie-secret-32-bytes",
    assertion_secret: "identity-assertion-secret-32-bytes",
    database_url: "postgres://database",
    relay_endpoint,
    control_endpoint: "http://control:8080",
    operator_upstream: "http://operator:8080",
    enterprise_upstream: "http://enterprise:8080",
    session_idle_ms: 1800000L,
    session_absolute_ms: 28800000L,
    assertion_lifetime_ms: 30000L,
    registration_admin_origin: None,
    registration_client_id: None,
    registration_client_secret: None,
  }
}

///|
fn password_test_identity(now : Int64) -> GatewayCookie {
  {
    kind: "identity",
    audience: "operator",
    host: "operator.example",
    state: "",
    nonce: "",
    verifier: "",
    issuer: "https://identity.example/realms/lunanexa",
    subject: "operator-subject",
    email: "operator@example.test",
    display_name: "Operator User",
    bearer: "",
    csrf: "",
    created_unix_ms: now,
    last_used_unix_ms: now,
    expires_unix_ms: now + 28800000L,
  }
}

///|
test "password login accepts only the configured audience names" {
  assert_true(password_login_audience("operator") == Some(Operator))
  assert_true(password_login_audience("enterprise") == Some(Enterprise))
  for
    rejected in [
      "", "Operator", "admin", "operator ", " operator", "operator\n", "enterprise2",
    ] {
    assert_true(password_login_audience(rejected) == None)
  }
}

///|
test "password login body is bounded and requires both credentials" {
  let parsed = parse_password_login_request(
    "{\"username\":\"alice@example.test\",\"password\":\"correct horse\",\"audience\":\"operator\"}",
  )
  assert_eq(parsed.username, "alice@example.test")
  assert_eq(parsed.password, "correct horse")
  assert_eq(parsed.audience, "operator")
  for
    rejected in [
      "", "{}", "{\"username\":\"alice\",\"audience\":\"operator\"}", "{\"password\":\"secret\",\"audience\":\"operator\"}",
      "{\"username\":\"\",\"password\":\"secret\",\"audience\":\"operator\"}", "{\"username\":\"alice\",\"password\":\"\",\"audience\":\"operator\"}",
      "{\"username\":\"ali\\nce\",\"password\":\"secret\",\"audience\":\"operator\"}",
    ] {
    try ignore(parse_password_login_request(rejected)) catch {
      _ => ()
    } noraise {
      _ => fail("invalid password login body accepted: \{rejected}")
    }
  }
}

///|
test "password grant keeps the secret out of the request body" {
  let body = password_grant_body(
    "lunanexa-operator", "alice@example.test", "p@ss word+&",
  )
  assert_true(body.contains("grant_type=password"))
  assert_true(body.contains("client_id=lunanexa-operator"))
  assert_true(body.contains("username=alice%40example.test"))
  assert_true(body.contains("password=p%40ss%20word%2B%26"))
  assert_true(body.contains("scope=openid%20profile%20email"))
  assert_false(body.contains("operator-client-secret"))
  // The audience client secret travels only in the server-side authorization
  // header, never in anything the browser can see.
  let authorization = basic_authorization(
    "lunanexa-operator", "operator-client-secret",
  )
  assert_true(authorization.has_prefix("Basic "))
  assert_eq(
    @utf8.decode(@base64.decode(authorization[6:])),
    "lunanexa-operator:operator-client-secret",
  )
}

///|
test "rejected credentials map to a bare 401 and an outage to a distinct 503" {
  assert_eq(
    password_login_failure_response(password_token_failure(400)),
    (401, "invalid-credentials"),
  )
  assert_eq(
    password_login_failure_response(password_token_failure(401)),
    (401, "invalid-credentials"),
  )
  assert_eq(
    password_login_failure_response(password_token_failure(403)),
    (401, "invalid-credentials"),
  )
  assert_eq(
    password_login_failure_response(password_token_failure(500)),
    (503, "identity-provider-unavailable"),
  )
  assert_eq(
    password_login_failure_response(password_token_failure(503)),
    (503, "identity-provider-unavailable"),
  )
  // Nothing but the stable code reaches the browser.
  assert_eq(
    error_body("invalid-credentials"),
    "{\"error\":\"invalid-credentials\"}",
  )
}

///|
test "the direct grant validates an id token without a nonce" {
  let header = base64url(@utf8.encode("{\"alg\":\"RS256\"}").exact_view())
  let claims = base64url(
    @utf8.encode(
      "{\"iss\":\"https://identity.example/realms/lunanexa\",\"sub\":\"subject-1\",\"aud\":\"lunanexa-operator\",\"azp\":\"lunanexa-operator\",\"exp\":2000,\"nbf\":900,\"iat\":900}",
    ).exact_view(),
  )
  let token = "\{header}.\{claims}.abcdefghijklmnopqrstuvwxyz0123456789"
  let decoded = validate_id_token(
    token,
    "https://identity.example/realms/lunanexa",
    "lunanexa-operator",
    None,
    1000000L,
  )
  assert_eq(decoded.sub, "subject-1")
  // Keycloak may also emit an empty nonce for the direct grant; only a real
  // nonce means the token was minted for a different flow.
  let empty_nonce_claims = base64url(
    @utf8.encode(
      "{\"iss\":\"https://identity.example/realms/lunanexa\",\"sub\":\"subject-1\",\"aud\":\"lunanexa-operator\",\"azp\":\"lunanexa-operator\",\"exp\":2000,\"nbf\":900,\"iat\":900,\"nonce\":\"\"}",
    ).exact_view(),
  )
  let empty_nonce_token = "\{header}.\{empty_nonce_claims}.abcdefghijklmnopqrstuvwxyz0123456789"
  assert_eq(
    validate_id_token(
      empty_nonce_token,
      "https://identity.example/realms/lunanexa",
      "lunanexa-operator",
      None,
      1000000L,
    ).sub,
    "subject-1",
  )
  // A direct grant has no authorization request to bind, so an expected nonce
  // must reject a token that carries none.
  try
    validate_id_token(
      token,
      "https://identity.example/realms/lunanexa",
      "lunanexa-operator",
      Some("nonce-from-redirect"),
      1000000L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("a nonce-bound check must reject a nonce-less direct-grant token")
  }
}

///|
test "a provider identity without a usable email fails closed" {
  let config = password_test_config("http://relay:8081")
  let usable : UserInfo = {
    sub: "subject-1",
    email: Some("alice@example.test"),
    name: Some("Alice"),
    preferred_username: None,
  }
  let cookie = password_identity_cookie(
    config,
    "operator.example",
    Operator,
    "subject-1",
    usable,
    1000L,
  )
  assert_eq(cookie.kind, "identity")
  assert_eq(cookie.audience, "operator")
  assert_eq(cookie.host, "operator.example")
  assert_eq(cookie.email, "alice@example.test")
  assert_eq(cookie.display_name, "Alice")
  assert_eq(cookie.expires_unix_ms, 28801000L)
  for
    unusable in [
      { ..usable, email: None, },
      { ..usable, email: Some("not-an-email"), },
      { ..usable, email: Some(""), },
      { ..usable, name: Some("Alice\r\nX-LunaNexa-Identity-Subject: forged"), },
    ] {
    try
      ignore(
        password_identity_cookie(
          config,
          "operator.example",
          Operator,
          "subject-1",
          unusable,
          1000L,
        ),
      )
    catch {
      PasswordLoginError::IdentityRejected => ()
      _ => fail("unexpected password login error")
    } noraise {
      _ => fail("unusable provider identity must be rejected")
    }
  }
}

///|
async test "password failures throttle one source without touching the others" {
  let throttle = PasswordLoginThrottle::new()
  let now = 1000000L
  assert_true(throttle.allows("203.0.113.7", now))
  for index = 0; index < PasswordFailureLimit; index = index + 1 {
    throttle.record_failure("203.0.113.7", now)
  }
  assert_false(throttle.allows("203.0.113.7", now))
  // Another source is unaffected by the first source's failures.
  assert_true(throttle.allows("203.0.113.8", now))
  // The block lapses once the window is over.
  assert_true(throttle.allows("203.0.113.7", now + PasswordFailureBlockMs + 1L))
  // A successful login clears a source's failures.
  for index = 0; index < PasswordFailureLimit; index = index + 1 {
    throttle.record_failure("203.0.113.8", now)
  }
  assert_false(throttle.allows("203.0.113.8", now))
  throttle.record_success("203.0.113.8")
  assert_true(throttle.allows("203.0.113.8", now))
  // The table is bounded: never more tracked sources than the cap.
  for index = 0; index < PasswordFailureSources + 16; index = index + 1 {
    throttle.record_failure("198.51.100.\{index}", now)
  }
  assert_true(throttle.windows.length() <= PasswordFailureSources)
}

///|
/// The password route mints the session through `issue_controller_session`, the
/// same call `/auth/session` makes after an OIDC callback. This stands in for
/// the control plane with a loopback listener so the mint path is exercised
/// without a live Keycloak or PostgreSQL.
async test "a verified password identity mints an ordinary lnxs session" {
  let now = @async.now()
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(
        (request, reader, connection) => {
          ignore(reader.read_all())
          guard request.meth == Post &&
            request.path == "/v1/auth/session:exchange" else {
            connection.send_response(404, "Not Found", extra_headers={
              "Content-Length": "0",
            })
            connection.end_response()
            return
          }
          let expires = (now + 600000L).to_string()
          let body = "{\"session\":{\"expires_unix_ms\":\"" +
            expires +
            "\"},\"secret\":\"lnxs_password_session_secret_at_least_32_bytes\"}"
          connection.send_response(201, "Created", extra_headers={
            "Content-Type": "application/json",
            "Content-Length": body.length().to_string(),
          })
          connection.write_string(body)
          connection.end_response()
        },
        allow_failure=true,
      )
    }
    let config = password_test_config("http://\{server.addr}")
    let session = issue_controller_session(
      config,
      password_test_identity(now),
      Operator,
      now,
    )
    assert_eq(session.kind, "session")
    assert_eq(session.audience, "operator")
    assert_eq(session.host, "operator.example")
    assert_true(session.bearer.has_prefix("lnxs_"))
    assert_eq(session.bearer, "lnxs_password_session_secret_at_least_32_bytes")
    assert_eq(session.csrf.length(), 43)
    assert_eq(session.expires_unix_ms, now + 600000L)
    let body = browser_session_body(session)
    assert_true(
      body.contains(
        "\"session_token\":\"lnxs_password_session_secret_at_least_32_bytes\"",
      ),
    )
    assert_true(body.contains("\"csrf_token\":\"\{session.csrf}\""))
    assert_true(
      body.contains("\"expires_unix_ms\":\"\{(now + 600000L).to_string()}\""),
    )
    server.close()
  }
}
