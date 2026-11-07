///|
fn shared_session_config() -> GatewayConfig {
  {
    ..password_test_config("http://relay:8081"),
    operator_host: "suanli.example.com",
    enterprise_host: "suanli.example.com",
    alternate_https_port: true,
    operator_redirect_uri: "https://suanli.example.com/mana/auth/oidc/callback",
    enterprise_redirect_uri: "https://suanli.example.com/user/auth/oidc/callback",
    session_idle_ms: 60000L,
    session_absolute_ms: 60000L,
  }
}

///|
test "existing authenticated sessions work across internal and external HTTPS ports" {
  let config = shared_session_config()
  for audience in [Enterprise, Operator] {
    for
      signed_in in [
        "suanli.example.com", "suanli.example.com:443", "suanli.example.com:8443",
      ] {
      let session : GatewayCookie = {
        kind: "session",
        audience: audience.name(),
        host: signed_in,
        state: "",
        nonce: "",
        verifier: "",
        issuer: config.issuer,
        subject: "subject-test",
        email: "test@example.test",
        display_name: "Test",
        bearer: "lnxs_test",
        csrf: "test-csrf",
        created_unix_ms: 1000L,
        last_used_unix_ms: 1000L,
        expires_unix_ms: 61000L,
      }
      for
        target in [
          "suanli.example.com", "suanli.example.com:443", "suanli.example.com:8443",
        ] {
        assert_true(
          valid_cookie_session(session, target, audience, config, 2000L),
        )
        assert_false(
          valid_cookie_session(session, target, audience, config, 62000L),
        )
        assert_false(
          valid_cookie_session(
            { ..session, audience: "unrelated", },
            target,
            audience,
            config,
            2000L,
          ),
        )
      }
      for
        target in [
          "suanli.example.com:5005", "other.example.com", "suanli.example.com:8444",
        ] {
        assert_false(
          valid_cookie_session(session, target, audience, config, 2000L),
        )
      }
    }
  }
}

///|
test "legacy 8443 cookies migrate without overriding an existing shared session" {
  let config = shared_session_config()
  let name = config.cookie_name(Enterprise)
  let reference = encode_cookie_reference(
    "shared-session",
    config.cookie_secret(Enterprise),
  )
  let old = encode_cookie_reference(
    "legacy-session",
    config.cookie_secret(Enterprise),
  )
  for host in ["suanli.example.com", "suanli.example.com:8443"] {
    assert_eq(config.cookie_name_for_host(Enterprise, host), name)
    assert_eq(
      browser_cookie_reference(
        config,
        { "Cookie": "\{name}_8443=\{old}" },
        Enterprise,
        host,
      ),
      Some(old),
    )
    assert_eq(
      browser_cookie_reference(
        config,
        { "Cookie": "\{name}=\{reference}; \{name}_8443=\{old}" },
        Enterprise,
        host,
      ),
      Some(reference),
    )
    // An invalid shared cookie must not revive a previous legacy login.
    assert_eq(
      browser_cookie_reference(
        config,
        { "Cookie": "\{name}=invalid; \{name}_8443=\{old}" },
        Enterprise,
        host,
      ),
      Some("invalid"),
    )
    assert_true(
      browser_cookie_reference(
        config,
        { "Cookie": "\{name}_8443=\{old}" },
        Operator,
        host,
      )
      is None,
    )
  }
  assert_eq(legacy_port_cookie_cleanup(config, Enterprise).length(), 1)
  assert_eq(
    legacy_port_cookie_cleanup(
      { ..config, alternate_https_port: false, },
      Enterprise,
    ).length(),
    0,
  )
}

///|
test "explicit 443 Host accepts the browser normalized origin without enabling cross-origin writes" {
  let request : @http.Request = {
    meth: Post,
    path: "/auth/logout",
    headers: {
      "Origin": "https://suanli.example.com",
      "Sec-Fetch-Site": "same-origin",
    },
  }
  assert_true(exact_origin(request, "suanli.example.com:443"))
  assert_false(exact_origin(request, "suanli.example.com:8443"))
  assert_false(
    exact_origin(
      {
        ..request,
        headers: {
          "Origin": "https://attacker.example",
          "Sec-Fetch-Site": "cross-site",
        },
      },
      "suanli.example.com:443",
    ),
  )
}
