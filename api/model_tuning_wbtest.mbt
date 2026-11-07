///|
test "compute prefix opt-in does not enable payload retention" {
  let value = decode_openai_chat(
    "{\"model\":\"test\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}",
  ).unwrap()
  let authority : @access.ApiAuthorization = {
    key_id: "key",
    tenant_ref: "tenant",
    subject_ref: "subject",
    organization_id: "org",
    project_id: "project",
  }
  for enabled in [false, true] {
    let headers : Map[String, String] = if enabled {
      { "x-lunanexa-prefix-cache": "tenant" }
    } else {
      {}
    }
    let (request, _) = openai_workload(
      value,
      authority,
      headers,
      true,
      1000L,
      @settings.default_global_admin_settings().request_budgets,
    )
    assert_true(request.data_policy.retention is Ephemeral)
    assert_false(request.data_policy.allow_cache)
    assert_eq(request.payload is { "runtime_prefix_cache": true, .. }, enabled)
  }
  let (opted, _) = openai_workload(
    { ..value, runtime_prefix_cache: Some(true), },
    authority,
    {},
    true,
    1000L,
    @settings.default_global_admin_settings().request_budgets,
  )
  assert_true(opted.payload is { "runtime_prefix_cache": true, .. })
  assert_false(opted.data_policy.allow_cache)
}

///|
test "cache usage survives final stream without duplicating answer text" {
  assert_eq(
    cache_usage_only({
      "output_text": "private answer",
      "chunks": [{ "text_delta": "private answer" }],
      "cached_input_tokens": 4096,
    }),
    Some({ "cached_input_tokens": 4096 }),
  )
  assert_eq(cache_usage_only({ "cached_input_tokens": -1 }), None)
  assert_eq(cache_usage_only({ "output_text": "private answer" }), None)
}
