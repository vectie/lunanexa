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
test "workbench builds an ephemeral bounded canonical workload" {
  let envelope = make_workload(@workbench_ui.demo_state(), 2000000000000L)
  assert_eq(envelope.version, @contracts.contract_version)
  assert_eq(envelope.tenant_ref, "tenant-opaque-demo")
  assert_eq(envelope.capability, TextGenerate)
  assert_true(envelope.data_policy.retention is Ephemeral)
  assert_false(envelope.data_policy.allow_cache)
  assert_false(envelope.data_policy.allow_training_reuse)
  assert_eq(envelope.resource_ceiling.max_accelerator_memory_mib, 8192)
  assert_eq(envelope.deadline_unix_ms, 2000000030000L)
  assert_false(envelope.stream)
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
  inspect(workbench_title(locale), content="LunaNexa 开发者工作台")
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
