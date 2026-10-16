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
