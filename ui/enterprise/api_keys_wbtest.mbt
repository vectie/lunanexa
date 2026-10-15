///|
test "key creation decodes nullable and legacy array API URLs" {
  let credential = demo_state().api_keys[0].to_json()
  for
    url in [
      ("https://api.example.invalid" : Json),
      (["https://api.example.invalid"] : Json),
    ] {
    let issued : IssuedApiKeyView = @json.from_json({
      "credential": credential,
      "secret": "fixture-secret",
      "api_base_url": url,
    })
    assert_eq(issued.api_base_url, Some("https://api.example.invalid"))
    assert_eq(issued.secret, "fixture-secret")
  }
  for url in [Json::null(), ([] : Json)] {
    let issued : IssuedApiKeyView = @json.from_json({
      "credential": credential,
      "secret": "fixture-secret",
      "api_base_url": url,
    })
    assert_eq(issued.api_base_url, None)
  }
}

///|
test "private model key form and unlimited key card omit quota controls" {
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
    api_key_issue_draft: {
      ..base.api_key_issue_draft,
      allowed_models: "glm-5.3.flash",
      display_name: "GLM",
    },
    api_key_issue_open: true,
  }
  assert_true(api_key_uses_reserved_model(state))
  let form = render(state)
  assert_false(form.contains("api-key-maximum-requests"))
  assert_true(form.contains("api-key-lifetime"))
  let shared = {
    ..state,
    api_key_issue_draft: {
      ..state.api_key_issue_draft,
      allowed_models: "shared.model",
    },
  }
  assert_false(api_key_uses_reserved_model(shared))
  let shared_form = render(shared)
  assert_true(shared_form.contains("api-key-maximum-requests"))
  let advanced_start = shared_form
    .find("<details class=\"api-key-advanced\">")
    .unwrap()
  let advanced_rest = shared_form[advanced_start:]
  let advanced = advanced_rest[:advanced_rest
    .to_owned()
    .find("</details>")
    .unwrap()]
  assert_true(advanced.contains("<summary>Advanced</summary>"))
  for id in ["api-key-project-id", "api-key-models", "api-key-maximum-requests"] {
    assert_true(advanced.contains(id))
  }
  assert_true(advanced.contains("scope-picker"))
  assert_false(advanced.contains("api-key-display-name"))
  assert_false(advanced.contains("api-key-lifetime"))
  assert_false(shared_form.contains("Trial keys follow trial limits"))
  let key = {
    ..base.api_keys[0],
    maximum_requests: 0L,
    consumed_requests: 1000001L,
  }
  assert_eq(
    api_key_state(English, key, base.machine_access.now_unix_ms).1,
    "active",
  )
  let account = render({ ..base, route: AccountAccess, api_keys: [key], })
  assert_false(account.contains("role=\"progressbar\""))
  assert_false(account.contains("1000001 / 0"))
}

///|
test "key creation error is visible inside its dialog" {
  let base = demo_state()
  let dialog = render({
    ..base,
    route: Models,
    api_key_issue_open: true,
    error_message: Some("Key creation failed"),
  })
  assert_true(dialog.contains("role=\"alert\""))
  assert_true(dialog.contains("Key creation failed"))
}

///|
test "company overview omits an unrelated expired personal trial" {
  let base = demo_state()
  let trial : TrialEntitlementView = {
    trial_id: "old-trial",
    organization_id: "old-trial-org",
    tenant_ref: "old-trial-tenant",
    project_id: "old-trial-project",
    allowed_models: ["text.qwen"],
    maximum_requests: 100L,
    starts_unix_ms: base.machine_access.now_unix_ms - 7200000L,
    expires_unix_ms: base.machine_access.now_unix_ms - 3600000L,
    api_key_id: None,
    revoked_unix_ms: None,
  }
  let page = render({ ..base, route: Overview, trial: Some(trial), })
  assert_false(page.contains("text.qwen"))
  assert_false(page.contains("Create trial API key"))
}
