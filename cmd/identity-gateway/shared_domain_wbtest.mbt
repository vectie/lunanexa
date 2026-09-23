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
