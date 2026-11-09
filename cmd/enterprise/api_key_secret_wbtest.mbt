///|
test "late API key secret responses cannot cross a closed view or session" {
  let model = {
    ..gateway_auth_test_model(),
    portal: @enterprise_ui.demo_state(),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let key = model.portal.api_keys[0]
  let portal = {
    ..model.portal,
    route: AccountAccess,
    machine_access: {
      ..model.portal.machine_access,
      now_unix_ms: current_unix_ms(),
    },
    api_keys: [
      {
        ..key,
        revoked_unix_ms: None,
        expires_unix_ms: current_unix_ms() + 60000L,
      },
    ],
  }.update(ToggleApiKeySecret(key.key_id))
  let pending = { ..model, portal, }
  let response = Outcome(
    ApiKeySecretLoaded(
      model.session_generation,
      portal.api_key_secret_generation,
      key.key_id,
      "synthetic-secret",
      Reveal,
    ),
  )
  let (shown, _) = update(pending, response, emit)
  assert_true(shown.portal.revealed_api_key is Some(_))
  let closed = { ..pending, portal: portal.update(Navigate(Overview)), }
  let (ignored, _) = update(closed, response, emit)
  assert_true(ignored.portal.revealed_api_key is None)
  let (signed_out, _) = update(signed_out_model(pending), response, emit)
  assert_true(signed_out.portal.revealed_api_key is None)
}

///|
test "late copy feedback does not appear after leaving the key view" {
  let model = {
    ..gateway_auth_test_model(),
    portal: { ..@enterprise_ui.demo_state(), route: AccountAccess, },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let notice = Outcome(
    ApiKeySecretCopied(
      model.session_generation,
      model.portal.api_key_secret_generation,
      model.portal.route,
    ),
  )
  let (copied, _) = update(model, notice, emit)
  assert_eq(copied.portal.success_message, Some("Copied."))
  let moved = { ..model, portal: model.portal.update(Navigate(Models)), }
  let (ignored, _) = update(moved, notice, emit)
  assert_true(ignored == moved)
}
