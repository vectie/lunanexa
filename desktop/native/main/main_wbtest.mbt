///|
test "expired malformed and absent sessions fail closed" {
  let session = {
    session_token: "lnxs_test",
    csrf_token: "csrf",
    expires_unix_ms: 100L,
  }
  assert_true(valid_session(session, 99L))
  assert_false(valid_session(session, 100L))
  assert_false(valid_session({ ..session, csrf_token: "", }, 99L))
  assert_false(valid_session({ ..session, session_token: "other", }, 99L))
}

///|
test "Operator manifest binds its release origin without a source IP" {
  let source = "{\"identifier\":\"dev.vectie.lunanexa.operator\",\"runtime\":{\"webviews\":[{\"label\":\"operator\",\"url\":\"https://manage.example.test:8443/console/\",\"initializationScripts\":[]}]}}"
  let (result, origin) = desktop_manifest(source)
  assert_eq(origin, "https://manage.example.test:8443")
  assert_true(result.contains(origin + "/console/"))
  assert_false(result.contains("lunanexa-public-http-origin"))
  let (http_result, http_origin) = desktop_manifest(
    source.replace(
      old="https://manage.example.test:8443",
      new="http://10.1.2.3:4174",
    ),
  )
  assert_eq(http_origin, "http://10.1.2.3:4174")
  assert_true(http_result.contains("location.origin !=="))
  assert_true(http_result.contains("lunanexa-public-http-origin"))
  try desktop_manifest("{}") catch {
    _ => ()
  } noraise {
    _ => fail("invalid manifest accepted")
  }
  try
    desktop_manifest(
      source.replace(
        old="dev.vectie.lunanexa.operator",
        new="dev.vectie.lunanexa.enterprise",
      ),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("enterprise accepted")
  }
  for
    invalid in [
      source.replace(old="/console/", new="/other/"),
      source.replace(old="manage.example.test", new="user@manage.example.test"),
    ] {
    try desktop_manifest(invalid) catch {
      _ => ()
    } noraise {
      _ => fail("invalid Operator origin accepted")
    }
  }
}
