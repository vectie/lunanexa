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
test "only the Operator manifest receives the pinned transport opt-in" {
  let source = "{\"identifier\":\"dev.vectie.lunanexa.operator\",\"runtime\":{\"webviews\":[{\"label\":\"operator\",\"initializationScripts\":[]}]}}"
  let result = desktop_manifest(source)
  assert_true(result.contains(origin + "/console/"))
  assert_true(result.contains("location.origin !=="))
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
}
