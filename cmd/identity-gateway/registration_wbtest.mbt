///|
fn registration_test_request() -> RegistrationRequest {
  {
    email: "buyer@example.test",
    display_name: "Example Buyer",
    password: "Correct-Horse-9!",
    audience: "enterprise",
  }
}

///|
test "registration accepts only an address the realm can adopt as a username" {
  let accepted = parse_registration_request(
    "{\"email\":\"  buyer@example.test \",\"display_name\":\" Example Buyer \",\"password\":\"Correct-Horse-9!\",\"audience\":\"enterprise\"}",
  )
  // The provider stores the address as the username, so the surrounding
  // whitespace must not survive into the account.
  assert_eq(accepted.email, "buyer@example.test")
  assert_eq(accepted.display_name, "Example Buyer")
  for
    rejected in [
      "", "{}", "not json", "{\"display_name\":\"Example Buyer\",\"password\":\"Correct-Horse-9!\",\"audience\":\"enterprise\"}",
      "{\"email\":\"buyer@example.test\",\"password\":\"Correct-Horse-9!\",\"audience\":\"enterprise\"}",
      "{\"email\":\"buyer@example.test\",\"display_name\":\"Example Buyer\",\"audience\":\"enterprise\"}",
      "{\"email\":\"buyer@example.test\",\"display_name\":\"Example Buyer\",\"password\":\"\",\"audience\":\"enterprise\"}",
      "{\"email\":\"buyer@example.test\",\"display_name\":\"\",\"password\":\"Correct-Horse-9!\",\"audience\":\"enterprise\"}",
      "{\"email\":\"no-at-sign\",\"display_name\":\"Example Buyer\",\"password\":\"secret\",\"audience\":\"enterprise\"}",
      "{\"email\":\"@example.test\",\"display_name\":\"Example Buyer\",\"password\":\"secret\",\"audience\":\"enterprise\"}",
      "{\"email\":\"buyer@example.test\",\"display_name\":\"Example\\nBuyer\",\"password\":\"secret\",\"audience\":\"enterprise\"}",
    ] {
    try ignore(parse_registration_request(rejected)) catch {
      _ => ()
    } noraise {
      _ => fail("invalid registration body accepted: \{rejected}")
    }
  }
}

///|
test "the created account carries the display name and no required actions" {
  let body = registration_user_body(registration_test_request()).stringify()
  let decoded : Json = @json.parse(body)
  assert_true(
    decoded
    is {
      "username": String("buyer@example.test"),
      "email": String("buyer@example.test"),
      "firstName": String("Example Buyer"),
      "enabled": True,
      "emailVerified": True,
      "requiredActions": Array([]),
      "credentials": Array([Object(_)]),
      ..
    },
  )
  // A direct-grant login cannot complete an interactive action, so a new
  // account must not be handed one. The realm's default CONFIGURE_TOTP is
  // deliberately not requested here; see the note at the top of registration.mbt.
  assert_false(body.contains("CONFIGURE_TOTP"))
  assert_false(body.contains("UPDATE_PASSWORD"))
  guard decoded is { "credentials": Array(credentials), .. } &&
    credentials[0] is Object(credential) else {
    fail("registration body has no password credential")
  }
  // The realm requires a chosen password, not a temporary one it would then
  // have to rotate through a screen this flow cannot render.
  assert_eq(credential.get("type"), Some(Json::string("password")))
  assert_eq(credential.get("temporary"), Some(Json::boolean(false)))
  assert_eq(credential.get("value"), Some(Json::string("Correct-Horse-9!")))
}

///|
test "provider status decides which registration failure the browser sees" {
  // The provider is the authority on both collisions and password policy.
  assert_eq(
    registration_failure_response(registration_create_failure(409)),
    (409, "email-taken"),
  )
  assert_eq(
    registration_failure_response(registration_create_failure(400)),
    (400, "password-rejected"),
  )
  // A service account that may not create users is an operator problem, and
  // telling the customer "forbidden" would be a false accusation.
  assert_eq(
    registration_failure_response(registration_create_failure(401)),
    (503, "registration-unavailable"),
  )
  assert_eq(
    registration_failure_response(registration_create_failure(403)),
    (503, "registration-unavailable"),
  )
  assert_eq(
    registration_failure_response(registration_create_failure(500)),
    (503, "registration-unavailable"),
  )
  assert_eq(error_body("email-taken"), "{\"error\":\"email-taken\"}")
}

///|
test "the registration realm is read from the issuer, not configured twice" {
  assert_eq(
    configured_realm("https://106.39.18.146:5006/realms/lunanexa"),
    "lunanexa",
  )
  assert_eq(
    configured_realm("http://identity.example/realms/tenant-a"),
    "tenant-a",
  )
  for
    rejected in [
      "https://identity.example", "https://identity.example/admin", "https://identity.example/realms",
      "https://identity.example/realms/", "https://identity.example/realms/a/b",
      "https://identity.example/realms/bad name",
    ] {
    try ignore(configured_realm(rejected)) catch {
      _ => ()
    } noraise {
      _ => fail("issuer without a usable realm accepted: \{rejected}")
    }
  }
}

///|
test "the admin API is addressed only through a configured origin" {
  let config = password_test_config("http://relay:8081")
  // Nothing is configured, so registration must fail closed rather than fall
  // back to a guess about where the provider's admin API lives.
  try
    ignore(registration_endpoint(config, "/admin/realms/lunanexa/users"))
  catch {
    _ => ()
  } noraise {
    _ => fail("an unconfigured admin origin must not yield an endpoint")
  }
  let configured = {
    ..config,
    registration_admin_origin: Some("https://id.example:8443"),
    registration_client_id: Some("lunanexa-registration"),
    registration_client_secret: Some("registration-client-secret-32-byte"),
  }
  assert_eq(
    registration_endpoint(configured, "/admin/realms/lunanexa/users"),
    "https://id.example:8443/admin/realms/lunanexa/users",
  )
  assert_true(
    password_login_failure_response(PasswordLoginError::InvalidCredentials) ==
    (401, "invalid-credentials"),
  )
}
