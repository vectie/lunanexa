///|
test "embedded workbench uses the customer portal API and session scope" {
  let origin = "https://suanli.kechuangfuwu.com:8443"
  assert_eq(site_api_endpoint(origin, "/user/workbench/"), origin + "/user")
  assert_eq(site_api_endpoint(origin, "/workbench/"), origin)
  assert_eq(site_api_endpoint(origin, "/user-other/workbench/"), origin)
}

///|
test "workbench only sends credentials to an HTTPS or loopback origin" {
  assert_true(endpoint_is_safe("https://lunanexa.example"))
  assert_true(endpoint_is_safe("http://127.0.0.1:8080"))
  assert_true(endpoint_is_safe("http://localhost:8080"))
  assert_false(endpoint_is_safe("http://lunanexa.example"))
  assert_false(endpoint_is_safe("https://user:password@lunanexa.example"))
  assert_false(endpoint_is_safe("https://lunanexa.example/path"))
  assert_false(endpoint_is_safe("https://lunanexa.example?token=value"))
  assert_false(endpoint_is_safe("not a URL"))
  assert_true(optional_subject_is_valid(""))
  assert_true(optional_subject_is_valid("subject:opaque-01"))
  assert_false(optional_subject_is_valid("subject with spaces"))
}

///|
test "model choices require an explicit valid server allowlist" {
  assert_eq(authorized_models_from_json({}), [])
  assert_eq(authorized_models_from_json({ "allowed_models": "text.default" }), [])
  assert_eq(
    authorized_models_from_json({
      "allowed_models": ["text.qwen", "bad model", "text.qwen", "text.vision"],
    }),
    ["text.qwen", "text.vision"],
  )
}

///|
test "trial bootstrap rejects expired wrong-type and missing-CSRF sessions" {
  let session : TrialBrowserSession = {
    session_token: "lnxs_test-only",
    csrf_token: "csrf-test-only",
    expires_unix_ms: 100L,
  }
  assert_true(valid_trial_browser_session(session, 99L))
  assert_false(valid_trial_browser_session(session, 100L))
  assert_false(
    valid_trial_browser_session(
      { ..session, session_token: "lnxk_test-only", },
      99L,
    ),
  )
  assert_false(valid_trial_browser_session({ ..session, csrf_token: "", }, 99L))
}

///|
test "bootstrap surfaces rejected route and status without raw server details" {
  validate_bootstrap_reply("{\"authorized\":true}", "/v1/workspace/self")
  try
    validate_bootstrap_reply(
      "{\"public_error\":{\"status\":401,\"code\":\"browser-bearer-rejected\",\"message\":\"do not expose this upstream detail\",\"retryable\":false}}",
      "/v1/workspace/self",
    )
  catch {
    WorkbenchClientError::PublicRejected(code, message, _, stale, retryable) => {
      assert_eq(code, "browser-bearer-rejected")
      assert_eq(message, "GET /v1/workspace/self · HTTP 401")
      assert_true(stale)
      assert_false(retryable)
      assert_false(message.contains("upstream detail"))
    }
    _ => fail("expected a classified bootstrap rejection")
  } noraise {
    _ => fail("expected route rejection")
  }
}

///|
#warnings("-alert_unstable")
test "public plain HTTP workbench blocks credential entry before transport" {
  let model : AppModel = {
    endpoint: "http://203.0.113.10:3000",
    scoped_token: "",
    subject_ref: "",
    demo_mode: false,
    connecting: false,
    clock_generation: 0L,
    global_policy_generation: 0L,
    global_max_output_units: 0,
    workbench: @workbench_ui.default_state(0L),
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Credential entry is blocked on public plain HTTP"))
  assert_true(html.contains("id=\"workspace-token\""))
  assert_true(html.contains("disabled=\"disabled\" type=\"password\""))
}

///|
test "workbench builds an ephemeral bounded canonical workload" {
  let envelope = make_workload(@workbench_ui.demo_state(), 2000000000000L)
  assert_eq(envelope.version, @contracts.contract_version)
  assert_eq(envelope.tenant_ref, "tenant-opaque-demo")
  assert_eq(envelope.capability, TextGenerate)
  guard envelope.payload is { "input": String(prompt), .. } else {
    fail("runtime input must use the canonical text shape")
  }
  assert_true(prompt.contains("instruction"))
  assert_true(prompt.contains("Hello from LunaNexa"))
  assert_true(envelope.data_policy.retention is Ephemeral)
  assert_false(envelope.data_policy.allow_cache)
  assert_false(envelope.data_policy.allow_training_reuse)
  assert_eq(envelope.resource_ceiling.max_accelerator_memory_mib, 8192)
  assert_eq(envelope.deadline_unix_ms, 2000000030000L)
  assert_false(envelope.stream)
}

///|
test "normalized text is readable while structured results remain available" {
  assert_eq(
    normalized_output_text({ "output_text": "第一条\n第二条" }),
    "第一条\n第二条",
  )
  assert_eq(normalized_output_text(Json("回答")), "回答")
  assert_eq(
    normalized_output_text({
      "id": "response-id",
      "output": [
        {
          "type": "message",
          "role": "assistant",
          "content": [{ "type": "output_text", "text": "业务答案" }],
        },
      ],
      "usage": { "input_tokens": 84 },
    }),
    "业务答案",
  )
  assert_eq(normalized_output_text({ "count": 3 }), "{\"count\":3}")
}

///|
test "trial workbench uses selected catalog resources without shrinking output" {
  let memory = trial_model_memory(
    "[{\"alias_name\":\"text.qwen\",\"minimum_memory_mib\":24576},{\"alias_name\":\"other\",\"minimum_memory_mib\":8192}]",
    "text.qwen",
  )
  assert_eq(memory, 24576)
  let state = @workbench_ui.demo_state()
  let envelope = make_workload(
    state,
    2000000000000L,
    memory_ceiling_mib=memory,
    runtime_ms=120000L,
    classification=Confidential,
  )
  assert_eq(envelope.resource_ceiling.max_accelerator_memory_mib, 24576)
  assert_eq(envelope.deadline_unix_ms, 2000000120000L)
  assert_true(envelope.data_policy.classification is Confidential)
  assert_eq(
    envelope.resource_ceiling.max_output_units,
    make_workload(state, 2000000000000L).resource_ceiling.max_output_units,
  )
  try trial_model_memory("[]", "missing") catch {
    WorkbenchClientError::PublicRejected(code, _, _, stale, _) => {
      assert_eq(code, "ModelMetadataUnavailable")
      assert_false(stale)
    }
    _ => fail("expected missing catalog error")
  } noraise {
    _ => fail("missing model must not use an invented resource ceiling")
  }
}

///|
fn demo_workbench_state(
  now_unix_ms : Int64,
  locale : @i18n.Locale,
  model_selector : String,
) -> @workbench_ui.WorkbenchState {
  let seeded = @workbench_ui.demo_state().update(LocaleChanged(locale))
  let lease = match seeded.lease {
    Some(value) =>
      Some({
        ..value,
        starts_unix_ms: now_unix_ms - 3600000L,
        expires_unix_ms: now_unix_ms + 21600000L,
      })
    None => None
  }
  { ..seeded, now_unix_ms, lease, model_selector, }
}

///|
test "demo workbench uses a current bounded lease without changing contract data" {
  let now = 1786464000000L
  let state = demo_workbench_state(now, ChineseSimplified, "text.default")
  assert_true(@workbench_ui.lease_ready(state))
  assert_true(@workbench_ui.can_send(state))
  assert_eq(state.now_unix_ms, now)
  assert_eq(state.locale, ChineseSimplified)
  assert_eq(state.model_selector, "text.default")
  guard state.lease is Some(lease) else { fail("missing demo lease") }
  assert_eq(lease.tenant_ref, "tenant-opaque-demo")
  assert_true(lease.starts_unix_ms < now)
  assert_true(lease.expires_unix_ms > now)
}

///|
test "workbench declares canonical UTF-8 payload bytes including JSON overhead" {
  let base = @workbench_ui.demo_state()
  let unicode = base
    .update(
      InstructionChanged("解释这个值：月亮，并保留引号 \"ok\"。"),
    )
    .update(DraftChanged("fn main { println(\"月亮🌙\") }"))
  let envelope = make_workload(unicode, 2000000000000L)
  let canonical_bytes = @utf8.encode(envelope.payload.stringify()).length()
  assert_eq(envelope.resource_ceiling.max_input_units, canonical_bytes)
  assert_true(
    canonical_bytes >
    unicode.instruction.length() +
    @workbench_ui.active_file(unicode).unwrap().content.length(),
  )
}

///|
test "late public failures localize when consumed, not when requested" {
  let detail = PublicDetail("WorkspaceRateExceeded", "", true)
  let english = public_failure_message(English, detail)
  let chinese = public_failure_message(ChineseSimplified, detail)
  assert_true(english.contains("The workload was rejected."))
  assert_true(english.contains("You may retry."))
  assert_true(chinese.contains("工作负载已被拒绝。"))
  assert_true(chinese.contains("可以重试。"))
  assert_false(chinese.contains("The workload was rejected."))
  assert_true(
    public_failure_message(ChineseSimplified, WorkspaceLoadUnavailable).contains(
      "无法加载工作区",
    ),
  )
}

///|
test "workbench interactions refresh time and expire stale readiness" {
  let state = @workbench_ui.demo_state()
  guard state.lease is Some(lease) else { fail("missing demo lease") }
  let expired = update_workbench_at(
    state,
    InstructionChanged(state.instruction),
    lease.expires_unix_ms,
  )
  assert_eq(expired.now_unix_ms, lease.expires_unix_ms)
  assert_false(@workbench_ui.lease_ready(expired))
  assert_false(@workbench_ui.can_send(expired))
  assert_true(expired.error_message.unwrap().contains("no longer active"))
}

///|
test "authorization failures invalidate the cached lease fail closed" {
  let state = @workbench_ui.demo_state()
  let invalidated = state_after_public_failure(
    state,
    "WorkspaceAccessDenied: lease expired.",
    "receipt-denied",
    true,
    state.now_unix_ms + 1L,
  )
  assert_true(invalidated.lease is None)
  assert_false(@workbench_ui.can_send(invalidated))
  assert_true(
    invalidated.error_message
    .unwrap()
    .contains("Workspace authorization was invalidated"),
  )
  let transient = state_after_public_failure(
    state,
    "NoPlacement: retry later.",
    "",
    false,
    state.now_unix_ms + 1L,
  )
  assert_true(transient.lease is Some(_))
}

///|
test "workspace rate and concurrency admission errors preserve authorization" {
  assert_false(
    http_error_invalidates_authorization(429, "WorkspaceRateExceeded"),
  )
  assert_false(
    http_error_invalidates_authorization(429, "WorkspaceConcurrencyExceeded"),
  )
  assert_false(
    http_error_invalidates_authorization(409, "WorkloadAlreadyActive"),
  )
  assert_true(
    http_error_invalidates_authorization(403, "WorkspaceAccessDenied"),
  )
  let state = @workbench_ui.demo_state()
  let rate_limited = state_after_public_failure(
    state,
    "WorkspaceRateExceeded: hourly request allowance exhausted. You may retry.",
    "",
    http_error_invalidates_authorization(429, "WorkspaceRateExceeded"),
    state.now_unix_ms + 1L,
  )
  assert_true(rate_limited.lease is Some(_))
  assert_true(@workbench_ui.lease_ready(rate_limited))
  assert_true(@workbench_ui.can_send(rate_limited))
}

///|
test "only the newest connection generation may advance the lease clock" {
  let state = @workbench_ui.demo_state()
  let now = state.now_unix_ms + 60000L
  let stale = advance_clock_if_current(state, 8L, 7L, now)
  assert_true(stale is None)
  let current = advance_clock_if_current(state, 8L, 8L, now)
  guard current is Some(advanced) else {
    fail("the current clock generation should advance")
  }
  assert_eq(advanced.now_unix_ms, now)
}

///|
test "workbench locale metadata is guarded and local failures follow the locale" {
  let locale = @i18n.parse_locale("zh-CN")
  inspect(
    workbench_title(locale),
    content="能源谷“创未来”街区算力平台 开发者工作台",
  )
  let _ = stored_locale()
  persist_locale(locale.storage_value())
  sync_document_locale(locale)
  let state = @workbench_ui.demo_state().update(LocaleChanged(locale))
  guard state.lease is Some(lease) else { fail("missing demo lease") }
  let expired = workbench_at(state, lease.expires_unix_ms)
  assert_true(
    expired.error_message.unwrap().contains("工作区租约已不再有效"),
  )
  let invalidated = state_after_public_failure(
    state,
    "WorkspaceAccessDenied: lease expired.",
    "receipt-denied",
    true,
    state.now_unix_ms + 1L,
  )
  assert_true(
    invalidated.error_message
    .unwrap()
    .contains("WorkspaceAccessDenied: lease expired."),
  )
  assert_true(
    invalidated.error_message.unwrap().contains("访问权限已失效"),
  )
}
