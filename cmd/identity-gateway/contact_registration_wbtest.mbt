///|
test "phone registration uses real phone identity and retains acquisition without inventing email" {
  let request = parse_registration_request(
    "{\"phone\":\"13800138000\",\"display_name\":\"创作者\",\"password\":\"123456\",\"audience\":\"enterprise\",\"acquisition\":{\"source\":\"display-qr\",\"campaign\":\"campaign-01\",\"entry\":\"/activity/entry.html\"}}",
  )
  assert_eq(registration_contact(request), "+8613800138000")
  let body = registration_user_body(request)
  assert_true(
    body
    is {
      "username": "+8613800138000",
      "attributes": {
        "phone_number_verified": ["false"],
        "acquisition_source": ["display-qr"],
        ..
      },
      ..
    },
  )
  assert_true(body is Object(fields) && fields.get("email") is None)
  assert_eq(
    parse_password_login_request(
      "{\"username\":\"13800138000\",\"password\":\"123456\",\"audience\":\"enterprise\"}",
    ).username,
    "+8613800138000",
  )
}

///|
test "contact registration requires exactly one valid contact and six password characters" {
  for
    contact in [
      "\"phone\":\"123\"", "\"phone\":\"13800138000\",\"email\":\"a@example.test\"",
      "\"phone\":\"13800138000\"",
    ] {
    let password = if contact == "\"phone\":\"13800138000\"" {
      "12345"
    } else {
      "123456"
    }
    try
      ignore(
        parse_registration_request(
          "{" +
          contact +
          ",\"display_name\":\"创作者\",\"password\":\"" +
          password +
          "\",\"audience\":\"enterprise\"}",
        ),
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid contact accepted")
    }
  }
}
