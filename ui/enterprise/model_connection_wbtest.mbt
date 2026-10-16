///|
test "MaaS connection metadata accepts live and older controller responses" {
  let live : ExternalModelServiceView = @json.from_json({
    "model_alias": "glm-5.3.flash",
    "state": "Running",
    "can_stop": true,
    "ready": true,
    "context_window_tokens": [850000],
  })
  assert_eq(live.context_window_tokens, Some(850000))
  assert_eq(model_context_label(live.context_window_tokens), "850000")
  let nullable : ExternalModelServiceView = @json.from_json({
    "model_alias": "glm-5.3.flash",
    "state": "Running",
    "can_stop": true,
    "ready": true,
    "context_window_tokens": 65536,
  })
  assert_eq(model_context_label(nullable.context_window_tokens), "64K")
  let older : ExternalModelServiceView = @json.from_json({
    "model_alias": "glm-5.3.flash",
    "state": "Running",
    "can_stop": true,
    "ready": false,
  })
  assert_eq(older.context_window_tokens, None)
  assert_eq(model_context_label(older.context_window_tokens), "—")
}

///|
test "private model call example uses chat completion without secrets or infrastructure prerequisites" {
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
  let value : OneTimeApiKeySecret = {
    key_id: "test-key",
    display_name: "GLM",
    secret: "never-copy-this",
    allowed_models: ["glm-5.3.flash"],
    api_base_url: Some("https://api.example.invalid"),
    tenant_ref: "company",
    memory_ceiling_mib: None,
  }
  let example = api_key_first_call_example(state, value)
  assert_true(example.contains("/user/v1/chat/completions"))
  assert_true(example.contains("glm-5.3.flash"))
  assert_true(example.contains("$API_KEY"))
  for hidden in ["never-copy-this", "uuidgen", "memory_mib", "/workloads", "jq"] {
    assert_false(example.contains(hidden))
  }
  let page = render(state)
  assert_true(page.contains("Manage API keys"))
  assert_true(page.contains("Copy Call example"))
  assert_true(page.contains("TRAE setup"))
  assert_true(page.contains("Full URL: on"))
  assert_true(page.contains("16384"))
  assert_true(page.contains("/chat/completions"))
  assert_true(page.contains("RequestBudgetExceeded"))
  assert_false(page.contains("<details class=\"ln-advanced\" open"))
  assert_true(page.contains("/docs/?page=client-api"))
  let overview = render({
    ..state,
    route: Overview,
    deliveries: { ..state.deliveries, loaded: true, },
  })
  assert_true(overview.contains("API ready"))
  assert_true(overview.contains("glm-5.3.flash"))
  assert_false(overview.contains("No dedicated service has been started"))
  let reserved = {
    ..state,
    route: MachineAccess,
    machine_access: { ..state.machine_access, machines: [], },
    deliveries: {
      ..state.deliveries,
      options: {
        reservations: [
          {
            reservation_id: "company-reservation",
            label: "company machines",
            node_count: 2,
            expires_at_ms: state.machine_access.now_unix_ms + 86400000L,
          },
        ],
        templates: [],
      },
    },
  }
  let machines = render(reserved)
  assert_true(machines.contains("Company reserved machines"))
  assert_true(machines.contains("Open model API"))
  assert_false(machines.contains("No published delivery templates"))
  let expired = {
    ..reserved,
    deliveries: {
      ..reserved.deliveries,
      options: {
        ..reserved.deliveries.options,
        reservations: [
          { ..reserved.deliveries.options.reservations[0], expires_at_ms: 1L, },
        ],
      },
    },
  }
  assert_false(render(expired).contains("Company reserved machines"))
  let shared = api_key_first_call_example(state, {
    ..value,
    allowed_models: ["text.qwen"],
  })
  assert_true(shared.contains("/v1/workloads"))
  let hostile = model_api_example(
    "https://api.example.invalid/v1", "model'$(never-run)",
  )
  assert_true(hostile.contains("'\"'\"'"))
}

///|
test "connection examples retain safe credential handling for normal stream and discovery" {
  let base = "https://suanli.kechuangfuwu.com:8443/user/v1/"
  let unary = model_api_example(base, "glm-5.3.flash")
  let streaming = model_api_example(base, "glm-5.3.flash", stream=true)
  assert_true(unary.contains("test -n \"$API_KEY\" && curl"))
  assert_true(unary.contains("\"max_tokens\":1024"))
  assert_true(unary.contains("\"stream\":false"))
  assert_true(streaming.contains("--no-buffer"))
  assert_true(streaming.contains("\"stream\":true"))
  let discovery = model_discovery_example(base)
  assert_true(discovery.contains("/user/v1/models'"))
  for example in [unary, streaming, discovery] {
    assert_true(example.contains("Authorization: Bearer $API_KEY"))
    assert_false(example.contains("//chat"))
    assert_false(example.contains("//models"))
    assert_false(example.contains("api-key-"))
  }
}
