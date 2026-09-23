///|
test "one HTTPS host keeps management and user sessions in separate paths" {
  validate_browser_redirects(
    "https://suanli.kechuangfuwu.com/mana/auth/oidc/callback", "https://suanli.kechuangfuwu.com/user/auth/oidc/callback",
    true,
  )
  let config = {
    ..password_test_config("http://relay:8081"),
    issuer: "http://identity.example/realms/lunanexa",
    operator_host: "suanli.kechuangfuwu.com",
    enterprise_host: "suanli.kechuangfuwu.com",
    alternate_https_port: true,
    browser_oidc_enabled: false,
    operator_redirect_uri: "https://suanli.kechuangfuwu.com/mana/auth/oidc/callback",
    enterprise_redirect_uri: "https://suanli.kechuangfuwu.com/user/auth/oidc/callback",
  }
  assert_true(config.browser_secure())
  assert_eq(config.browser_scheme(), "https")
  assert_true(
    config.browser_audience("suanli.kechuangfuwu.com", Some("/mana")) ==
    Some(Operator),
  )
  assert_true(
    config.browser_audience("suanli.kechuangfuwu.com", Some("/user")) ==
    Some(Enterprise),
  )
  assert_true(config.browser_audience("suanli.kechuangfuwu.com", None) is None)
  assert_true(
    config.browser_audience("suanli.kechuangfuwu.com:8443", Some("/mana")) ==
    Some(Operator),
  )
  assert_true(
    config.browser_audience("suanli.kechuangfuwu.com:8443", Some("/user")) ==
    Some(Enterprise),
  )
  for
    denied in [
      "suanli.kechuangfuwu.com:5002", "suanli.kechuangfuwu.com:8444", "suanli.kechuangfuwu.com:443",
      "attacker.example:8443",
    ] {
    assert_true(config.browser_audience(denied, Some("/user")) is None)
  }
  assert_eq(
    config.redirect_uri_for_host(Operator, "suanli.kechuangfuwu.com"),
    config.operator_redirect_uri,
  )
  assert_eq(
    config.redirect_uri_for_host(Operator, "suanli.kechuangfuwu.com:8443"),
    "https://suanli.kechuangfuwu.com:8443/mana/auth/oidc/callback",
  )
  assert_eq(
    config.redirect_uri_for_host(Enterprise, "suanli.kechuangfuwu.com:8443"),
    "https://suanli.kechuangfuwu.com:8443/user/auth/oidc/callback",
  )
  assert_eq(
    config.cookie_name_for_host(Enterprise, "suanli.kechuangfuwu.com"),
    config.enterprise_cookie_name,
  )
  assert_eq(
    config.cookie_name_for_host(Enterprise, "suanli.kechuangfuwu.com:8443"),
    "\{config.enterprise_cookie_name}_8443",
  )
  assert_true(
    config.browser_audience("attacker.example", Some("/mana")) is None,
  )
  assert_eq(config.public_ui_path(Operator), "/mana/")
  assert_eq(config.public_ui_path(Enterprise), "/user/")
  assert_eq(
    oidc_transport_url(
      {
        ..config,
        oidc_transport_origin: Some("https://identity.internal:8443"),
      },
      "http://identity.example/realms/lunanexa/.well-known/openid-configuration",
    ),
    "https://identity.internal:8443/realms/lunanexa/.well-known/openid-configuration",
  )
}
