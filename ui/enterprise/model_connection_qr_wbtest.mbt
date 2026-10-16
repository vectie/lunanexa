///|
test "private connection QR contains generic settings and is erased on dismissal and navigation" {
  let base = demo_state()
  let state = {
    ..base,
    route: Models,
    deliveries: {
      ..base.deliveries,
      external_model: Some({
        model_alias: "glm-5.3.flash",
        state: "Running",
        can_stop: true,
        ready: true,
        context_window_tokens: Some(850000),
      }),
    },
  }
  let opened = state.update(OpenModelConnectionQr("glm-5.3.flash"))
  assert_eq(opened.route, Models)
  assert_true(opened.model_connection_import is Some(_))
  let secret = "lnx_" + "a".repeat(64)
  let filled = {
    ..opened,
    model_connection_import: opened.model_connection_import.map(value => {
      ..value,
      secret,
    }),
  }
  let initial = render(opened)
  assert_true(initial.contains("Select a key"))
  assert_true(initial.contains("id=\"api-key-connection-dismiss\""))
  assert_false(initial.contains("Paste your saved"))
  assert_false(initial.contains("model-connection-qr-secret"))
  assert_false(initial.contains("Create a new key"))
  let payload = model_connection_import_json(
    "https://example.invalid/user/v1", "glm-5.3.flash", secret,
  )
  guard payload is Object(fields) else { fail("missing descriptor") }
  assert_eq(fields["version"], Json::string("openai.connection.v1"))
  assert_eq(fields["api_key"], Json::string(secret))
  assert_eq(fields["model"], Json::string("glm-5.3.flash"))
  assert_eq(fields["max_output_tokens"], Json::number(16384.0))
  let html = render(filled)
  assert_true(html.contains("Private client connection QR"))
  assert_false(html.contains("/docs/?page=qr-entry"))
  assert_false(html.contains("data:image"))
  assert_true(
    filled.update(DismissModelConnectionQr).model_connection_import is None,
  )
  let pending = { ..filled, api_key_secret_request: Some("pending-key"), }
  let closed = pending.update(DismissModelConnectionQr)
  assert_true(closed.api_key_secret_request is None)
  assert_true(
    closed.api_key_secret_generation > pending.api_key_secret_generation,
  )
  assert_true(filled.update(Navigate(Overview)).model_connection_import is None)
  assert_true(
    filled.update(SelfService(SelectOrganization("different"))).model_connection_import
    is None,
  )
  assert_true(
    filled.update(CreateModelApiKey("glm-5.3.flash")).model_connection_import
    is None,
  )
  assert_true(
    state.update(UseSavedKeyForConnectionQr("missing")).model_connection_import
    is None,
  )
  assert_true(
    state.update(OpenModelConnectionQr("unavailable")).model_connection_import
    is None,
  )
  assert_false(valid_connection_secret("api-key-record-id"))
}
