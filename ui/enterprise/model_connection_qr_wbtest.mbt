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
        service_id: "fixture-model-service",
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

///|
test "stopping an owned service retains saved-key connection settings without creating inference authority" {
  let base = demo_state()
  let service : ExternalModelServiceView = {
    service_id: "existing-service",
    model_alias: "model.chat",
    state: "Stopped",
    ready: false,
    can_stop: true,
    context_window_tokens: None,
  }
  let state = {
    ..base,
    route: Models,
    deliveries: {
      ..base.deliveries,
      loaded: true,
      external_model: Some(service),
      operations: [],
      options: { ..base.deliveries.options, reservations: [], },
    },
  }
  let opened = state.update(OpenModelConnectionQr(service.model_alias))
  assert_true(opened.model_connection_import is Some(_))
  assert_eq(opened.model_connection_import.unwrap().secret, "")
  let html = render(state)
  assert_true(html.contains("Start service"))
  assert_true(html.contains("<summary>Start another service</summary>"))
  assert_true(html.contains("Connection QR"))
  assert_true(html.contains("No active exclusive resource authorization"))
  // No new service is created and no key is minted by opening the chooser.
  assert_true(opened.deliveries == state.deliveries)
  assert_true(opened.api_keys == state.api_keys)
}

///|
test "personal trial connects without machine approval and keeps QR within its output budget" {
  let base = demo_state()
  let membership = base.membership.unwrap()
  let now = base.machine_access.now_unix_ms
  let trial : TrialEntitlementView = {
    consumed_requests: None,
    max_output_tokens: None,
    trial_id: "trial-fixture",
    organization_id: membership.organization_id,
    tenant_ref: membership.tenant_ref,
    project_id: "trial-project",
    allowed_models: ["text.qwen"],
    maximum_requests: 200L,
    starts_unix_ms: now - 1L,
    expires_unix_ms: now + 3600000L,
    api_key_id: None,
    revoked_unix_ms: None,
  }
  let state = {
    ..base,
    route: Models,
    trial: Some(trial),
    deliveries: { ..base.deliveries, external_model: None, },
  }
  assert_true(personal_trial_model(state, "text.qwen"))
  assert_eq(connection_base_url(state, "text.qwen"), "/trial/v1")
  assert_eq(connection_output_budget(state, "text.qwen"), 1024)
  let enlarged = {
    ..state,
    trial: Some({ ..trial, max_output_tokens: Some(8192), }),
  }
  assert_eq(connection_output_budget(enlarged, "text.qwen"), 8192)
  assert_true(render(enlarged).contains("8192"))
  assert_true(
    model_api_example("/trial/v1", "text.qwen", max_tokens=8192).contains(
      "\"max_tokens\":8192",
    ),
  )
  let page = render(state)
  assert_true(page.contains("does not require machine approval"))
  assert_true(page.contains("/trial/v1/chat/completions"))
  let opened = state.update(OpenModelConnectionQr("text.qwen"))
  assert_true(opened.model_connection_import is Some(_))
  let payload = model_connection_import_json(
    "https://example.test/trial/v1",
    "text.qwen",
    "lnx_" + "b".repeat(64),
    max_output_tokens=connection_output_budget(state, "text.qwen"),
  )
  assert_true(
    payload
    is {
      "max_output_tokens": 1024,
      "base_url": "https://example.test/trial/v1",
      ..
    },
  )
  let expired = { ..state, trial: Some({ ..trial, expires_unix_ms: now, }), }
  assert_false(personal_trial_model(expired, "text.qwen"))
  assert_true(
    expired.update(OpenModelConnectionQr("text.qwen")).model_connection_import
    is None,
  )
  let foreign = {
    ..state,
    trial: Some({ ..trial, organization_id: "other-org", }),
  }
  assert_false(personal_trial_model(foreign, "text.qwen"))
  assert_true(
    foreign.update(OpenModelConnectionQr("text.qwen")).model_connection_import
    is None,
  )
}

///|
test "portal decodes deployed trial budget projection" {
  let wire : Json = {
    "trial_id": "trial-wire-fixture",
    "organization_id": "org-fixture",
    "tenant_ref": "tenant-fixture",
    "project_id": "project-fixture",
    "allowed_models": ["text.qwen"],
    "maximum_requests": "0",
    "starts_unix_ms": "1",
    "expires_unix_ms": "9999999999999",
    "consumed_requests": "15",
    "max_input_bytes": 65536,
    "max_output_tokens": 16384,
    "api_key_id": Json::null(),
    "revoked_unix_ms": Json::null(),
  }
  let decoded = decode_trial_projection(wire)
  assert_eq(decoded.unwrap().max_output_tokens, Some(16384))
  assert_eq(decoded.unwrap().consumed_requests, Some(15L))
  let legacy = decode_trial_projection(Json([wire]))
  assert_eq(legacy.unwrap().max_output_tokens, Some(16384))
  assert_eq(decode_trial_projection(Json::null()), None)
  assert_eq(decode_trial_projection(Json::array([])), None)
}
