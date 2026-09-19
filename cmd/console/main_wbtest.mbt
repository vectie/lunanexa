///|
test "console validates only optional opaque loopback subjects" {
  assert_true(optional_subject_is_valid(""))
  assert_true(optional_subject_is_valid("subject:opaque-01"))
  assert_true(optional_subject_is_valid("  mtls:sha256:abc123  "))
  assert_false(optional_subject_is_valid("subject with spaces"))
  assert_false(optional_subject_is_valid("../../subject"))
}

///|
test "console validates tenant-scoped commercial organization identifiers" {
  assert_true(commercial_organization_is_valid(""))
  assert_true(commercial_organization_is_valid("org:research-01"))
  assert_false(commercial_organization_is_valid("../organizations/admin"))
  assert_false(commercial_organization_is_valid("org with spaces"))
  assert_false(commercial_organization_is_valid("a".repeat(161)))
}

///|
test "console workspace lifecycle routes match the operator API" {
  assert_eq(
    workspace_lifecycle_path(ActivateWorkspaceUser("user-1")),
    "/v1/workspace/users/user-1:activate",
  )
  assert_eq(
    workspace_lifecycle_path(SuspendWorkspaceUser("user-1")),
    "/v1/workspace/users/user-1:suspend",
  )
  assert_eq(
    workspace_lifecycle_path(RevokeWorkspaceUser("user-1")),
    "/v1/workspace/users/user-1:revoke",
  )
  assert_eq(
    workspace_lifecycle_path(ActivateWorkspaceLease("lease-1")),
    "/v1/workspace/leases/lease-1:activate",
  )
}

///|
test "console service deployment action routes stay canonical" {
  assert_eq(
    service_deployment_action_path("service-1", "promote"),
    "/v1/service-deployments/service-1/promote",
  )
  assert_eq(
    service_deployment_action_path("service-1", "rollback"),
    "/v1/service-deployments/service-1/rollback",
  )
  assert_eq(
    service_deployment_action_path("service-1", "delete"),
    "/v1/service-deployments/service-1/delete",
  )
  assert_true(
    quick_deployment_intent(
      {
        ..@ui.default_state(),
        quick_deployment_id: "service-1",
        quick_template: "missing@v1",
      },
      1000L,
    )
    is None,
  )
  let ready : @ui.ConsoleState = {
    ..@ui.demo_state(),
    quick_deployment_id: "service-1",
  }
  guard quick_deployment_intent(ready, 1000L) is Some(first) else {
    fail("expected a valid quick deployment intent")
  }
  guard quick_deployment_intent(ready, 2000L) is Some(retry) else {
    fail("expected a valid retry intent")
  }
  assert_eq(first.idempotency_key, "console:service-1")
  assert_eq(retry.idempotency_key, first.idempotency_key)
}

///|
test "console quick-deployment fuzz matches the public intent boundary" {
  let base = @ui.demo_state()
  for length in 0..<=140 {
    let candidate = quick_deployment_intent(
      { ..base, quick_deployment_id: "a".repeat(length) },
      length.to_int64(),
    )
    assert_eq(candidate is Some(_), length > 0 && length <= 128)
  }
  for
    hostile in [
      "../service", "service/name", "service name", "service\nname", "<script>alert(1)</script>",
      "服务",
    ] {
    assert_true(
      quick_deployment_intent({ ..base, quick_deployment_id: hostile }, 1L)
      is None,
    )
  }
  guard quick_deployment_intent(
      { ..base, quick_deployment_id: "service-1" },
      1L,
    )
    is Some(intent) else {
    fail("fixed-capacity intent should be valid")
  }
  assert_eq(intent.replicas, 1)
}

///|
test "console confirmation scope binds the selected identity" {
  let users : Array[@ui.UserAccessRow] = [
    {
      user_id: "user-1",
      display_name: "Ari Chen",
      email: "ari@example.test",
      state: UserActive,
      last_active: "Never",
      grant_count: 1,
    },
  ]
  assert_eq(
    user_confirmation_scope(users, "user-1"),
    "user-1 · Ari Chen · ari@example.test",
  )
  assert_eq(user_confirmation_scope(users, "missing"), "missing")
  let prepared = prepare_user_confirmation(
    { ..@ui.default_state(), users, },
    "user-1",
    SuspendUser("user-1"),
  )
  guard prepared.confirmation is Some(confirmation) else {
    fail("expected a user confirmation")
  }
  assert_eq(confirmation.action, SuspendUser("user-1"))
  assert_eq(confirmation.scope, "user-1 · Ari Chen · ari@example.test")
}

///|
test "exclusive machine termination confirmation binds node user and generation" {
  let state : @ui.ConsoleState = {
    ..@ui.default_state(),
    route: Leases,
    exclusive_node_leases: [
      {
        lease_id: "exclusive-lease-1",
        node_id: "dgx-spark-02",
        subject_ref: "subject-2",
        unix_username: "tenant2",
        expires_at: "2026-08-12 18:00 UTC",
        state: "Active",
        generation: 7L,
      },
    ],
  }
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "operator-secret",
    audit_credential: "audit-secret",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: state,
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (prepared, _) = update_live(
    model,
    Console(BeginTerminateExclusiveNodeLease("exclusive-lease-1", 7L)),
    emit,
  )
  guard prepared.console.confirmation is Some(confirmation) else {
    fail("expected an exclusive lease cleanup confirmation")
  }
  assert_eq(
    confirmation.action,
    TerminateExclusiveNodeLease("exclusive-lease-1", 7L),
  )
  assert_eq(
    confirmation.scope,
    "exclusive-lease-1 · dgx-spark-02 · tenant2 · generation 7",
  )
}

///|
test "locale switch is local and preserves operational session state" {
  let state : @ui.ConsoleState = {
    ..@ui.default_state(),
    locale: English,
    route: Policies,
    stream_events: [
      {
        sequence: 1,
        kind: "Chunk",
        text: "opaque output",
        receipt: "receipt:stream-1",
      },
    ],
    confirmation: Some(@ui.confirmation_receipt(DrainNode("node-1"), "node-1")),
    error_message: Some("server-provided error"),
    success_message: Some("server-provided success"),
    operation_name: "invoke-workload",
    operation_body: "{\"model_selector\":\"text.default\"}",
  }
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "operator-secret",
    audit_credential: "audit-secret",
    csrf_token: "",
    inference_credential: "inference-secret",
    inference_subject_ref: "subject:opaque-1",
    commercial_organization: "org-1",
    demo_mode: false,
    alerts_window: Today,
    console: state,
    console_read_groups: Map([]),
    next_directive_generation: 42L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let switched = switch_app_locale(model, ChineseSimplified)
  assert_eq(switched.console.locale, ChineseSimplified)
  assert_eq(switched.console.route, Policies)
  assert_eq(switched.console.operation_name, "invoke-workload")
  assert_eq(
    switched.console.operation_body,
    "{\"model_selector\":\"text.default\"}",
  )
  assert_eq(switched.console.confirmation, state.confirmation)
  assert_true(switched.console.stream_events == state.stream_events)
  assert_true(switched.console.error_message is None)
  assert_true(switched.console.success_message is None)
  assert_eq(switched.credential, "operator-secret")
  assert_eq(switched.audit_credential, "audit-secret")
  assert_eq(switched.inference_credential, "inference-secret")
  assert_eq(switched.commercial_organization, "org-1")
}

///|
test "loaded controller state keeps the selected route and locale" {
  let current : @ui.ConsoleState = {
    ..@ui.default_state(),
    locale: ChineseSimplified,
    route: Policies,
    model_source_query: "MiniCPM",
    model_source_results: [],
    model_source_total: 0L,
    model_imports: [],
    model_adoption_draft: {
      import_id: "ms-import-1",
      model_id: "model.minicpm5-1b",
      version: "modelscope-main",
      license_id: "license.minicpm5-apache",
      compatible_architectures: "nvidia-gb10",
      minimum_memory_mib: "8192",
    },
    model_adopted_imports: ["ms-import-complete"],
    operation_name: "set-quota",
    operation_body: "{\"tenant_ref\":\"team-a\"}",
    quick_deployment_id: "service-1",
    quick_template: "text-small@v1",
    success_message: Some("配置已提交。"),
  }
  let loaded : @ui.ConsoleState = {
    ..@ui.default_state(),
    locale: English,
    route: Overview,
    overview: { ..@ui.default_state().overview, total_nodes: 2 },
  }
  let merged = merge_loaded_console(current, loaded)
  assert_eq(merged.locale, ChineseSimplified)
  assert_eq(merged.route, Policies)
  assert_eq(merged.model_source_query, "MiniCPM")
  assert_eq(merged.model_adoption_draft.import_id, "ms-import-1")
  assert_eq(merged.model_adopted_imports, ["ms-import-complete"])
  assert_eq(merged.operation_name, "set-quota")
  assert_eq(merged.operation_body, "{\"tenant_ref\":\"team-a\"}")
  assert_eq(merged.quick_deployment_id, "service-1")
  assert_eq(merged.quick_template, "text-small@v1")
  assert_eq(merged.success_message, Some("配置已提交。"))
  assert_eq(merged.overview.total_nodes, 2)
}

///|
test "model source search is edited independently from generic operations" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "operator-secret",
    audit_credential: "audit-secret",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.default_state(),
      route: Models,
      operation_body: "{\"tenant_ref\":\"team-a\"}",
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (edited, _) = update_live(
    model,
    Console(ModelSourceQueryChanged("OpenBMB")),
    emit,
  )
  assert_eq(edited.console.model_source_query, "OpenBMB")
  assert_eq(edited.console.operation_body, "{\"tenant_ref\":\"team-a\"}")
}

///|
test "verified S3 model adoption is validated, stateful, and route-bound" {
  assert_eq(
    model_adoption_path("ms-import-1"),
    "/v1/model-sources/modelscope/imports/ms-import-1:adopt",
  )
  assert_true(
    model_adoption_intent({
      import_id: "ms-import-1",
      model_id: "../model",
      version: "v1",
      license_id: "license-1",
      compatible_architectures: "nvidia-gb10",
      minimum_memory_mib: "8192",
    })
    is None,
  )
  guard model_adoption_intent({
      import_id: "ms-import-1",
      model_id: " model.minicpm5-1b ",
      version: " modelscope-main ",
      license_id: " license.minicpm5-apache ",
      compatible_architectures: " nvidia-gb10, nvidia-ampere ",
      minimum_memory_mib: " 8192 ",
    })
    is Some(intent) else {
    fail("expected a valid adoption intent")
  }
  assert_eq(intent.model_id, "model.minicpm5-1b")
  assert_eq(intent.compatible_architectures, ["nvidia-gb10", "nvidia-ampere"])
  assert_eq(intent.minimum_memory_mib, 8192)
  let verified : @ui.ModelImportRow = {
    import_id: "ms-import-1",
    source: "modelscope",
    model_id: "OpenBMB/MiniCPM5-1B",
    revision: "master",
    state: Verified,
    files_total: 11,
    files_completed: 11,
    bytes_total: 2171355326L,
    bytes_completed: 2171355326L,
    manifest_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    local_directory: "",
    artifact_uri: "s3://models/modelscope/ms-import-1",
    license: "apache-2.0",
    error_code: "",
    cancel_requested: false,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
  }
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "operator-secret",
    audit_credential: "audit-secret",
    csrf_token: "csrf-secret",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.default_state(),
      route: Models,
      operator_authenticated: true,
      model_imports: [verified],
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (opened, _) = update_live(
    model,
    Console(BeginModelAdoption(verified.import_id)),
    emit,
  )
  assert_eq(opened.console.model_adoption_draft.import_id, verified.import_id)
  let (invalid, _) = update_live(opened, Console(SubmitModelAdoption), emit)
  assert_false(invalid.console.loading)
  assert_true(invalid.console.error_message is Some(_))
  let ready = {
    ..opened,
    console: {
      ..opened.console,
      model_adoption_draft: {
        import_id: verified.import_id,
        model_id: intent.model_id,
        version: intent.version,
        license_id: intent.license_id,
        compatible_architectures: "nvidia-gb10, nvidia-ampere",
        minimum_memory_mib: "8192",
      },
    },
  }
  let (submitting, _) = update_live(ready, Console(SubmitModelAdoption), emit)
  assert_true(submitting.console.loading)
  assert_eq(submitting.console.error_message, None)
  let (completed, _) = update_live(
    ready,
    Outcome(
      ModelAdopted(
        English,
        verified.import_id,
        "Registered as Candidate; gates remain.",
      ),
    ),
    emit,
  )
  assert_eq(completed.console.model_adoption_draft.import_id, "")
  assert_eq(completed.console.model_adopted_imports, [verified.import_id])
  assert_true(completed.console.loading)
  assert_true(
    completed.console.success_message
    .unwrap_or("")
    .contains("Registered as Candidate"),
  )
}

///|
test "changing an operator credential clears authenticated UI authority" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "old-operator-secret",
    audit_credential: "audit-secret",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: { ..@ui.default_state(), operator_authenticated: true },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (changed, _) = update_live(
    model,
    CredentialChanged("new-operator-secret"),
    emit,
  )
  assert_eq(changed.credential, "new-operator-secret")
  assert_false(changed.console.operator_authenticated)
}

///|
test "console document titles use the shared locale contract" {
  assert_eq(
    console_document_title(English),
    "能源谷“创未来”街区算力平台 | Cluster Operations",
  )
  assert_eq(
    console_document_title(ChineseSimplified),
    "能源谷“创未来”街区算力平台 | 集群运维",
  )
}

///|
test "async notices fall back to the current locale after a language switch" {
  assert_eq(
    locale_fenced_notice(
      ChineseSimplified,
      ChineseSimplified,
      "详细错误。",
      "Operation failed.",
      "操作失败。",
    ),
    "详细错误。",
  )
  assert_eq(
    locale_fenced_notice(
      ChineseSimplified,
      English,
      "Detailed English failure.",
      "Operation failed.",
      "操作失败。",
    ),
    "操作失败。",
  )
  assert_eq(
    locale_fenced_notice(
      English,
      ChineseSimplified,
      "旧语言的错误。",
      "Controller refresh failed.",
      "控制器刷新失败。",
    ),
    "Controller refresh failed.",
  )
}

///|
#warnings("-alert_unstable")
test "Simplified Chinese connection drawer localizes security copy" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.default_state(),
      locale: ChineseSimplified,
      operator_authenticated: true,
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  for
    value in [
      "控制器连接", "需要凭据", "账户会话", "推理令牌（可选）",
      "商业组织（可选）", "不透明主体引用（可选）", "账户会话仅保存在浏览器内存中",
      "连接并刷新",
    ] {
    assert_true(html.contains(value))
  }
  assert_true(html.contains("https://controller.example.test"))
}

///|
#warnings("-alert_unstable")
test "unauthenticated operator sees login gate instead of console shell" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4174",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: { ..@ui.default_state(), locale: English },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Operator login"))
  assert_true(html.contains("Operator access starts here."))
  assert_true(html.contains("/auth/oidc/start?audience=operator"))
  assert_true(html.contains("login-account-session"))
  assert_true(html.contains("login-operator-token"))
  assert_true(html.contains("Local development token fallback"))
  assert_false(html.contains("Primary navigation"))
  assert_false(html.contains("Model registry"))
}

///|
#warnings("-alert_unstable")
test "public plain HTTP renders login landing but blocks credential entry" {
  let model : AppModel = {
    endpoint: "http://106.39.18.146:4174",
    credential: "operator-secret",
    audit_credential: "audit-secret",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: @ui.default_state(),
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(
    html.contains("Administrative login is blocked on public plain HTTP"),
  )
  assert_true(html.contains("disabled"))
  assert_true(html.contains("Organization sign-in requires HTTPS"))
  assert_false(html.contains("/auth/oidc/start?audience=operator"))
  assert_true(html.contains("login-account-session"))
  assert_false(html.contains("login-operator-token"))
  assert_false(html.contains("login-audit-token"))
  assert_false(html.contains("Model registry"))
}

///|
#warnings("-alert_unstable")
test "remote HTTPS login offers OIDC and never renders static token fallback" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: @ui.default_state(),
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("/auth/oidc/start?audience=operator"))
  assert_true(html.contains("Continue with organization sign-in"))
  assert_true(html.contains("login-account-session"))
  assert_false(html.contains("login-operator-token"))
  assert_false(html.contains("login-audit-token"))
  assert_false(html.contains("localStorage"))
}

///|
test "one account session supplies operator and audit authority in memory" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: @ui.default_state(),
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (pasted, _) = update_live(
    model,
    AccountSessionChanged("lnxs_session-value"),
    emit,
  )
  assert_eq(pasted.credential, "lnxs_session-value")
  assert_eq(pasted.audit_credential, "lnxs_session-value")
  let (bootstrapped, _) = update_live(
    model,
    GatewaySessionLoaded({
      session_token: "lnxs_gateway-session",
      csrf_token: "csrf-memory-only",
      expires_unix_ms: 9999999999999L,
    }),
    emit,
  )
  assert_eq(bootstrapped.credential, "lnxs_gateway-session")
  assert_eq(bootstrapped.audit_credential, "lnxs_gateway-session")
  assert_eq(bootstrapped.csrf_token, "csrf-memory-only")
  assert_true(bootstrapped.console.loading)
}

///|
test "logout clears authorities and loaded operator state" {
  let model : AppModel = {
    endpoint: "https://controller.example.test",
    credential: "operator-secret",
    audit_credential: "audit-secret",
    csrf_token: "csrf-memory-only",
    inference_credential: "inference-secret",
    inference_subject_ref: "subject-one",
    commercial_organization: "org-one",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.demo_state(),
      operator_authenticated: true,
      locale: ChineseSimplified,
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (logged_out, _) = update_live(model, Logout, emit)
  assert_eq(logged_out.credential, "")
  assert_eq(logged_out.audit_credential, "")
  assert_eq(logged_out.csrf_token, "")
  assert_eq(logged_out.inference_credential, "")
  assert_eq(logged_out.console.locale, ChineseSimplified)
  assert_false(logged_out.console.operator_authenticated)
  assert_eq(logged_out.console.models.length(), 0)
}

///|
#warnings("-alert_unstable")
test "demo mode presents a read-only cluster snapshot" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    alerts_window: Today,
    console: @ui.demo_state(),
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Read-only demo snapshot"))
  assert_true(html.contains("4/4 machines running"))
}

///|
test "demo mode previews exclusive cleanup confirmation without mutation" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    alerts_window: Today,
    console: { ..@ui.demo_state(), route: Leases },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let lease = model.console.exclusive_node_leases[0]
  let (prepared, _) = update(
    model,
    Console(BeginTerminateExclusiveNodeLease(lease.lease_id, lease.generation)),
    emit,
  )
  assert_true(prepared.console.confirmation is Some(_))
  let (confirmed, _) = update(
    prepared,
    Console(
      ConfirmAction(
        TerminateExclusiveNodeLease(lease.lease_id, lease.generation),
      ),
    ),
    emit,
  )
  assert_true(confirmed.console.confirmation is None)
  assert_eq(
    confirmed.console.success_message,
    Some("Demo is read-only; the operation was previewed but not persisted."),
  )
}

///|
test "demo mode previews every destructive node operation without mutation" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    alerts_window: Today,
    console: { ..@ui.demo_state(), route: Nodes },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let node_id = model.console.nodes[0].node_id
  let (prepared, _) = update(model, Console(BeginCordon(node_id)), emit)
  assert_true(prepared.console.confirmation is Some(_))
  let (confirmed, _) = update(
    prepared,
    Console(ConfirmAction(CordonNode(node_id))),
    emit,
  )
  assert_true(confirmed.console.confirmation is None)
  assert_eq(
    confirmed.console.success_message,
    Some("Demo is read-only; the operation was previewed but not persisted."),
  )
  assert_eq(confirmed.console.nodes, model.console.nodes)
}

///|
test "demo mode exercises one-click preflight without controller mutation" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    alerts_window: Today,
    console: { ..@ui.demo_state(), route: Catalog },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (named, _) = update(
    model,
    Console(QuickDeploymentIdChanged("demo-service")),
    emit,
  )
  assert_eq(named.console.quick_deployment_id, "demo-service")
  let (submitted, _) = update(named, Console(SubmitQuickDeployment), emit)
  assert_eq(
    submitted.console.success_message,
    Some(
      "Demo preflight passed for demo-service. No controller operation was created.",
    ),
  )
  assert_eq(
    submitted.console.service_deployments,
    model.console.service_deployments,
  )
}

///|
test "navigation clears stale operation notices and confirmation" {
  let initial = @ui.demo_state()
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    alerts_window: Today,
    console: {
      ..initial,
      success_message: Some("stale success"),
      error_message: Some("stale error"),
      confirmation: Some(
        @ui.confirmation_receipt(CordonNode("dgx-spark-01"), "dgx-spark-01"),
      ),
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (next, _) = update(model, Console(Navigate(Catalog)), emit)
  assert_eq(next.console.route, Catalog)
  assert_true(next.console.success_message is None)
  assert_true(next.console.error_message is None)
  assert_true(next.console.confirmation is None)
}

///|
test "contract tab and field changes schedule one generation-fenced preview" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    alerts_window: Today,
    console: { ..@ui.demo_state(), route: ContractDocuments },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (selected, _) = update(
    model,
    Console(ContractDocuments(SelectForm(ReservationApplication))),
    emit,
  )
  assert_eq(selected.contract_preview_generation, 1L)
  assert_eq(
    selected.console.contract_documents.selected_form,
    Some(ReservationApplication),
  )
  assert_true(selected.console.contract_documents.preview_loading)
  let (changed, _) = update(
    selected,
    Console(
      ContractDocuments(
        FieldChanged("reservation.operator_comment", "档期已核验"),
      ),
    ),
    emit,
  )
  assert_eq(changed.contract_preview_generation, 2L)
  assert_true(
    changed.console.contract_documents.draft_values.any(value => {
      value.field_id == "reservation.operator_comment" &&
      value.value == "档期已核验"
    }),
  )
  guard changed.console.contract_documents.preview_request() is Some(request) else {
    fail("expected pending preview request")
  }
  let (after_stale, _) = update(changed, ContractPreviewDue(1L, request), emit)
  assert_eq(after_stale.contract_preview_generation, 2L)
  assert_eq(
    after_stale.console.contract_documents.draft_values,
    changed.console.contract_documents.draft_values,
  )
}

///|
test "contract approval and governance controls route through the operator shell" {
  let approval : @contractdoc.ContractApproval = {
    approval_id: "approval-shell-1",
    packet_id: "packet-shell-1",
    action: "close:Expired",
    expected_revision: 1L,
    payload: {
      evidence_sha256: None,
      signed_on: None,
      kind: Some(Expired),
      reason: Some("term ended"),
      amount_minor_units: Some(10000L),
      packet_values_sha256: None,
    },
    initiator: "operator-a",
    created_unix_ms: 1000L,
    status: Pending,
    decided_by: None,
    decided_unix_ms: None,
    decision_reason: None,
  }
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4174",
    credential: "operator-b-token",
    audit_credential: "audit-token",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "tenant-shell",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.default_state(),
      route: ContractDocuments,
      contract_documents: {
        ..@contract_documents.default_state(
          English,
          actor_owner=ManagerOperator,
        ),
        approvals: [approval],
      },
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (reviewing, _) = update_live(
    model,
    Console(ContractDocuments(ApproveApproval(approval.approval_id))),
    emit,
  )
  assert_eq(
    reviewing.console.contract_documents.confirmation,
    Some(ApprovePending(approval.approval_id)),
  )
  let (approving, _) = update_live(
    reviewing,
    Console(
      ContractDocuments(ConfirmAction(ApprovePending(approval.approval_id))),
    ),
    emit,
  )
  assert_true(approving.console.contract_documents.loading)
  assert_eq(approving.console.contract_documents.error_message, None)
  let (rejecting, _) = update_live(
    model,
    Console(ContractDocuments(BeginRejectApproval(approval.approval_id))),
    emit,
  )
  assert_true(
    rejecting.console.contract_documents.confirmation
    is Some(RejectApproval(_, _)),
  )
  let (exporting, _) = update_live(
    model,
    Console(ContractDocuments(ExportGovernance("tenant-shell"))),
    emit,
  )
  assert_true(exporting.console.contract_documents.loading)
  let (conflicted, _) = update_live(
    model,
    Outcome(ContractConflict(English)),
    emit,
  )
  assert_true(conflicted.console.contract_documents.loading)
  assert_true(
    conflicted.console.contract_documents.error_message
    .unwrap_or("")
    .contains("latest revision"),
  )
}

///|
test "model import polling is generation fenced and logout invalidates it" {
  let downloading : @ui.ModelImportRow = {
    import_id: "ms-import-1",
    source: "modelscope",
    model_id: "OpenBMB/MiniCPM5-1B",
    revision: "master",
    state: Downloading,
    files_total: 11,
    files_completed: 2,
    bytes_total: 2171355326L,
    bytes_completed: 1048576L,
    manifest_digest: "",
    local_directory: "",
    artifact_uri: "",
    license: "apache-2.0",
    error_code: "",
    cancel_requested: false,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
  }
  let verified = {
    ..downloading,
    state: Verified,
    files_completed: 11,
    bytes_completed: downloading.bytes_total,
    manifest_digest: "sha256:0123456789abcdef",
    local_directory: "",
    updated_unix_ms: 1200L,
  }
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4174",
    credential: "operator-token",
    audit_credential: "audit-token",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Models,
      model_imports: [downloading],
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 7L,
    cluster_poll_generation: 7L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (stale, _) = update_live(
    model,
    Outcome(ModelImportsPolled(6L, [verified])),
    emit,
  )
  assert_eq(stale.console.model_imports[0].state, Downloading)
  let (current, _) = update_live(
    model,
    Outcome(ModelImportsPolled(7L, [verified])),
    emit,
  )
  assert_eq(current.console.model_imports[0].state, Verified)
  let (logged_out, _) = update_live(model, Logout, emit)
  assert_eq(logged_out.model_import_poll_generation, 8L)
  assert_eq(logged_out.cluster_poll_generation, 8L)
  assert_eq(logged_out.credential, "")
  assert_false(logged_out.console.operator_authenticated)
}

///|
fn cluster_poll_test_row(
  node_id : String,
  state : @contracts.NodeState,
  lease_holder : String,
) -> @ui.NodeRow {
  {
    node_id,
    state,
    architecture: "dgx-spark",
    total_memory_mib: 131072,
    free_memory_mib: 65536,
    used_memory_mib: 65536,
    utilization_per_mille: 500,
    temperature_celsius: 41,
    power_watts: 320,
    workloads: 1,
    lease_holder,
    active_assignment: "deployment-1",
    last_seen: "Just now",
  }
}

///|
test "cluster poll refreshes nodes only for the live generation" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4174",
    credential: "operator-token",
    audit_credential: "audit-token",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Overview,
      nodes: [cluster_poll_test_row("node-1", Active, "org-1 · tenant1")],
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 3L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let polled = [
    cluster_poll_test_row("node-1", Unreachable, "Unassigned"),
    cluster_poll_test_row("node-2", Active, "Unassigned"),
  ]
  let (stale, _) = update_live(model, Outcome(ClusterPolled(2L, polled)), emit)
  assert_true(stale == model)
  let (current, _) = update_live(
    model,
    Outcome(ClusterPolled(3L, polled)),
    emit,
  )
  assert_eq(current.console.nodes.length(), 2)
  assert_eq(current.console.nodes[0].state, Unreachable)
  assert_eq(current.console.nodes[1].node_id, "node-2")
  assert_eq(current.console.overview.active_nodes, 1)
  assert_eq(current.console.overview.total_nodes, 2)
}

///|
test "cluster poll failure retries quietly and stops on authorization loss" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4174",
    credential: "operator-token",
    audit_credential: "audit-token",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Overview,
    },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 5L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (retried, _) = update_live(
    model,
    Outcome(ClusterPollFailed(5L, false)),
    emit,
  )
  assert_true(retried == model)
  assert_eq(retried.console.error_message, None)
  let (unauthorized, _) = update_live(
    model,
    Outcome(ClusterPollFailed(5L, true)),
    emit,
  )
  assert_true(unauthorized == model)
  assert_eq(unauthorized.console.error_message, None)
  let (stale, _) = update_live(
    model,
    Outcome(ClusterPollFailed(4L, false)),
    emit,
  )
  assert_true(stale == model)
  let (due_stale, _) = update_live(model, ClusterPollDue(4L), emit)
  assert_true(due_stale == model)
  let (signed_out, _) = update_live(
    { ..model, console: { ..model.console, operator_authenticated: false } },
    ClusterPollDue(5L),
    emit,
  )
  assert_false(signed_out.console.operator_authenticated)
}

///|
fn alerts_window_test_row(
  notification_id : String,
  created_unix_ms : Int64,
  lifecycle : @notifications.NotificationLifecycle,
) -> @ui.NotificationRow {
  {
    notification_id,
    code: "node.heartbeat_stale",
    severity: Critical,
    lifecycle,
    topic: ClusterHealth,
    created_unix_ms,
    generation: 1L,
    node_ref: "node-1",
    assigned_to: "",
    silenced_until_unix_ms: None,
  }
}

///|
/// 2026-09-19T09:00:00Z, the operator's "now" for the alert window cases.
let alerts_window_now_ms : Int64 = 1789808400000L

///|
test "alert window narrows the incident calendar to whole UTC days" {
  let today = alerts_window_test_row("alert-today", 1789808400000L, Unread)
  let yesterday = alerts_window_test_row(
    "alert-yesterday",
    1789774200000L,
    Unread,
  )
  let last_week = alerts_window_test_row(
    "alert-last-week",
    1789560000000L,
    Acknowledged,
  )
  let last_month = alerts_window_test_row(
    "alert-last-month",
    1788220800000L,
    Unread,
  )
  let older = alerts_window_test_row("alert-older", 1786752000000L, Resolved)
  let rows = [today, yesterday, last_week, last_month, older]
  let today_window : @ui.AlertsWindow = Today
  assert_eq(
    @ui.filter_alerts(rows, today_window, alerts_window_now_ms).length(),
    1,
  )
  assert_eq(
    @ui.filter_alerts(rows, today_window, alerts_window_now_ms)[0].notification_id,
    "alert-today",
  )
  assert_eq(
    @ui.filter_alerts(rows, Last7Days, alerts_window_now_ms).length(),
    3,
  )
  assert_eq(
    @ui.filter_alerts(rows, Last30Days, alerts_window_now_ms).length(),
    4,
  )
  assert_eq(
    @ui.filter_alerts(rows, AllAlerts, alerts_window_now_ms).length(),
    5,
  )
  // The window control round-trips through its storage value.
  assert_eq(today_window.storage_value(), "today")
  assert_eq(@ui.parse_alerts_window("last-30-days"), Last30Days)
  assert_eq(@ui.parse_alerts_window("unrecognized"), AllAlerts)
}

///|
test "alert calendar groups by day newest first and counts only filtered open incidents" {
  let rows = [
    alerts_window_test_row("alert-today-open", 1789808400000L, Unread),
    alerts_window_test_row("alert-today-resolved", 1789808400000L, Resolved),
    alerts_window_test_row("alert-yesterday-open", 1789774200000L, Acknowledged),
  ]
  assert_eq(@ui.alert_day_label(1789808400000L), "2026-09-19")
  let visible = @ui.filter_alerts(rows, AllAlerts, alerts_window_now_ms)
  let days = @ui.group_alerts_by_day(visible)
  assert_eq(days.length(), 2)
  assert_eq(days[0].0, "2026-09-19")
  assert_eq(days[0].1.length(), 2)
  assert_eq(days[1].0, "2026-09-18")
  assert_eq(days[1].1[0].notification_id, "alert-yesterday-open")
  // The open counter follows the window: yesterday's incident is excluded by
  // `Today`, and resolved incidents are never open.
  assert_eq(
    @ui.open_alert_count(@ui.filter_alerts(rows, Today, alerts_window_now_ms)),
    1,
  )
  assert_eq(@ui.open_alert_count(visible), 2)
}

///|
test "alert window selection is carried on the operator model" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4174",
    credential: "operator-token",
    audit_credential: "audit-token",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    alerts_window: Today,
    console: { ..@ui.default_state(), operator_authenticated: true },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (narrowed, _) = update_live(
    model,
    Console(AlertsWindowChanged(Today)),
    emit,
  )
  assert_eq(narrowed.alerts_window, Today)
  let (widened, _) = update_live(
    narrowed,
    Console(AlertsWindowChanged(AllAlerts)),
    emit,
  )
  assert_eq(widened.alerts_window, AllAlerts)
  // Changing the window is local view state: no controller read is scheduled.
  assert_true(widened == { ..narrowed, alerts_window: AllAlerts })
}

///|
fn deferred_read_test_model(route : @ui.OperatorRoute) -> AppModel {
  {
    endpoint: "http://127.0.0.1:4174",
    credential: "operator-token",
    audit_credential: "audit-token",
    csrf_token: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "org-northstar",
    demo_mode: false,
    alerts_window: Today,
    console: { ..@ui.default_state(), operator_authenticated: true, route },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
  }
}

///|
test "page-scoped reads map routes to groups and load each group once" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  assert_true(console_read_group_for_route(Alerts) is Some(AlertsReads))
  assert_true(console_read_group_for_route(Models) is Some(ModelsReads))
  assert_true(console_read_group_for_route(Catalog) is Some(DeploymentReads))
  assert_true(
    console_read_group_for_route(Deployments) is Some(DeploymentReads),
  )
  assert_true(console_read_group_for_route(Audit) is Some(AuditReads))
  assert_true(console_read_group_for_route(Requests) is Some(AuditReads))
  assert_true(console_read_group_for_route(Users) is Some(AccessReads))
  assert_true(console_read_group_for_route(Leases) is Some(AccessReads))
  assert_true(
    console_read_group_for_route(ContractDocuments) is Some(ContractReads),
  )
  assert_true(console_read_group_for_route(CostCenters) is Some(CommerceReads))
  assert_true(console_read_group_for_route(Agreements) is Some(CommerceReads))
  assert_true(
    console_read_group_for_route(QualifiedServices) is Some(CommerceReads),
  )
  assert_true(
    console_read_group_for_route(OfflineCommerce) is Some(CommerceReads),
  )
  // The landing page stays core-only: it must not pay for the alert list, the
  // model-source import list, or the account and deployment directory.
  assert_true(console_read_group_for_route(Overview) is None)
  assert_true(
    deferred_read_pending(deferred_read_test_model(Overview), Alerts)
    is Some(AlertsReads),
  )
  assert_true(
    deferred_read_pending(deferred_read_test_model(Overview), Models)
    is Some(ModelsReads),
  )
  assert_true(
    deferred_read_pending(deferred_read_test_model(Overview), Deployments)
    is Some(DeploymentReads),
  )
  assert_true(console_read_group_for_route(Nodes) is None)
  // The warm-up list for a group is the list its loader requests, apart from
  // the core paths the loader shares with the first paint. The deployment
  // loader reads `/v1/nodes` for the `observed` flag, and that path is already
  // in the core warm-up list.
  assert_eq(console_read_group_paths(AlertsReads, ""), [
    "/v1/notifications/operator", "/v1/notifications/operator/deliveries",
  ])
  assert_eq(console_read_group_paths(ModelsReads, ""), [
    "/v1/model-sources/modelscope/imports",
  ])
  assert_eq(console_read_group_paths(AccessReads, ""), [
    "/v1/accounts",
    "/v1/accounts/trial-summary",
    "/v1/onboarding/access-packages",
    "/v1/workspace",
    "/v1/exclusive-node-leases",
  ])
  assert_eq(console_read_group_paths(DeploymentReads, ""), [
    "/v1/assignments", "/v1/service-deployments",
  ])

  let model = deferred_read_test_model(Overview)
  assert_true(deferred_read_pending(model, Audit) is Some(AuditReads))
  let (opened, _) = update_live(model, Console(Navigate(Audit)), emit)
  assert_true(opened.console_read_groups.contains(AuditReads))
  assert_eq(opened.console_read_groups.length(), 1)
  // The group is scheduled, so a repeat visit must not fetch again.
  assert_true(deferred_read_pending(opened, Audit) is None)
  let (away, _) = update_live(opened, Console(Navigate(Overview)), emit)
  assert_eq(away.console_read_groups.length(), 1)
  let (returned, _) = update_live(away, Console(Navigate(Audit)), emit)
  assert_eq(returned.console_read_groups.length(), 1)
  assert_true(returned.console_read_groups.contains(AuditReads))
  // A route without a group never records one.
  let (overview, _) = update_live(returned, Console(Navigate(Nodes)), emit)
  assert_eq(overview.console_read_groups.length(), 1)
  assert_true(deferred_read_pending(model, Nodes) is None)

  // A failed read leaves the group unloaded, silent, and signed in, so the next
  // visit retries it.
  let (failed, _) = update_live(
    returned,
    Outcome(DeferredReadFailed(AuditReads)),
    emit,
  )
  assert_false(failed.console_read_groups.contains(AuditReads))
  assert_eq(failed.console.error_message, None)
  assert_eq(failed.console.success_message, None)
  assert_true(failed.console.operator_authenticated)
  assert_eq(failed.credential, "operator-token")
  assert_true(deferred_read_pending(failed, Audit) is Some(AuditReads))

  // The read-only demo snapshot never schedules a controller read.
  let demo = { ..deferred_read_test_model(Audit), demo_mode: true }
  let (demo_opened, _) = update_live(demo, Console(Navigate(Audit)), emit)
  assert_eq(demo_opened.console_read_groups.length(), 0)

  // A signed-out console never schedules one either.
  let signed_out = {
    ..deferred_read_test_model(Audit),
    console: {
      ..@ui.default_state(),
      operator_authenticated: false,
      route: Audit,
    },
  }
  assert_true(deferred_read_pending(signed_out, Audit) is None)
}

///|
test "a merged page-scoped read touches only its own group" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = deferred_read_test_model(Audit)
  let payload : AuditReadPayload = {
    rows: [
      {
        actor: "operator-a",
        decision: "workload.invoke",
        evidence: "text.default",
        result: "accepted",
        receipt: "audit:1",
      },
    ],
    request_details: [
      {
        timestamp_unix_ms: 1789808400000L,
        action: "workload.invoke",
        model_selector: "text.default",
        result: "accepted",
        receipt: "audit:1",
      },
    ],
    request_count: 7,
    request_errors: 2,
    recent_changes: 1,
  }
  let (opened, _) = update_live(model, Console(Navigate(Audit)), emit)
  let (merged, _) = update_live(
    opened,
    Outcome(DeferredReadLoaded(English, AuditReads, GroupAudit(payload))),
    emit,
  )
  assert_true(merged.console_read_groups.contains(AuditReads))
  assert_eq(merged.console_read_groups.get(AuditReads), Some(true))
  assert_eq(merged.console.audit.length(), 1)
  assert_eq(merged.console.request_details.length(), 1)
  assert_eq(merged.console.requests.count, 7)
  assert_eq(merged.console.requests.errors, 2)
  assert_eq(merged.console.overview.recent_changes, 1)
  // Fields owned by other groups and by the operator stay untouched.
  assert_eq(merged.console.cost_centers.length(), 0)
  assert_eq(merged.console.route, Audit)
  assert_eq(merged.console.notifications.length(), 0)
  assert_eq(merged.console_read_groups.length(), 1)

  // A locale switch between scheduling and completion drops the read, re-arms
  // the group, and keeps the console silent.
  let (chinese, _) = update_live(
    opened,
    Console(LocaleChanged(ChineseSimplified)),
    emit,
  )
  let (fenced, _) = update_live(
    chinese,
    Outcome(DeferredReadLoaded(English, AuditReads, GroupAudit(payload))),
    emit,
  )
  assert_eq(fenced.console.audit.length(), 0)
  assert_false(fenced.console_read_groups.contains(AuditReads))
  assert_eq(fenced.console.error_message, None)
  assert_true(deferred_read_pending(fenced, Audit) is Some(AuditReads))

  // A read that outlived its session (sign-out or credential change) is
  // dropped instead of merged into the next session's state.
  let (signed_out, _) = update_live(opened, Logout, emit)
  assert_eq(signed_out.console_read_groups.length(), 0)
  let (dropped, _) = update_live(
    signed_out,
    Outcome(DeferredReadLoaded(English, AuditReads, GroupAudit(payload))),
    emit,
  )
  assert_eq(dropped.console.audit.length(), 0)
  assert_eq(dropped.console.requests.count, 0)
  assert_false(dropped.console_read_groups.contains(AuditReads))
}

///|
test "the commerce group carries node lessee labels without refetching nodes" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = {
    ..deferred_read_test_model(CostCenters),
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: CostCenters,
      nodes: [cluster_poll_test_row("node-1", Active, "Unassigned")],
    },
  }
  let payload : CommerceReadPayload = {
    cost_centers: [],
    agreements: [],
    qualified_services: [],
    enterprise_lease_requests: [],
    offline_commerce: @offline_commerce.default_state(English, OperatorCommerce),
    node_lease_holders: [("node-1", "org-northstar · alice")],
  }
  let (opened, _) = update_live(model, Console(Navigate(CostCenters)), emit)
  assert_true(opened.console_read_groups.contains(CommerceReads))
  let (merged, _) = update_live(
    opened,
    Outcome(DeferredReadLoaded(English, CommerceReads, GroupCommerce(payload))),
    emit,
  )
  assert_true(merged.console_read_groups.contains(CommerceReads))
  assert_eq(merged.console.nodes.length(), 1)
  assert_eq(merged.console.nodes[0].lease_holder, "org-northstar · alice")
  // Every other node field is carried over from the core read.
  assert_eq(merged.console.nodes[0].state, Active)
  assert_eq(merged.console.nodes[0].architecture, "dgx-spark")
}

///|
test "the alerts group replaces only the notification projections" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = {
    ..deferred_read_test_model(Overview),
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Overview,
      // Core-loaded fields that the deferred merge must leave alone.
      accounts: @ui.default_state().accounts,
      cost_centers: [],
      audit: [
        {
          actor: "operator-a",
          decision: "cluster.snapshot",
          evidence: "fleet",
          result: "accepted",
          receipt: "audit:core",
        },
      ],
    },
  }
  // Opening the Alerts page is what schedules the group; the landing page never
  // does.
  assert_true(deferred_read_pending(model, Overview) is None)
  let (opened, _) = update_live(model, Console(Navigate(Alerts)), emit)
  assert_true(opened.console_read_groups.contains(AlertsReads))
  let payload : AlertsReadPayload = {
    notifications: [
      alerts_window_test_row("alert-open", 1789808400000L, Unread),
      alerts_window_test_row("alert-resolved", 1789808400000L, Resolved),
    ],
    notification_deliveries: [
      {
        delivery_id: "delivery-alert-open-email",
        notification_id: "alert-open",
        channel: Email,
        state: DeadLetter,
        attempt_count: 5,
        updated_unix_ms: 1789808500000L,
        last_error_code: "ProviderUnavailable",
      },
    ],
  }
  let (merged, _) = update_live(
    opened,
    Outcome(DeferredReadLoaded(English, AlertsReads, GroupAlerts(payload))),
    emit,
  )
  assert_true(merged.console_read_groups.contains(AlertsReads))
  assert_eq(merged.console.notifications.length(), 2)
  assert_eq(merged.console.notification_deliveries.length(), 1)
  assert_eq(
    merged.console.notification_deliveries[0].delivery_id,
    "delivery-alert-open-email",
  )
  // The open-alert counter is a projection of the merged rows, so it follows
  // them instead of staying at the core's zero.
  assert_eq(merged.console.overview.alerts, 1)
  // Fields owned by other groups stay untouched.
  assert_eq(merged.console.audit.length(), 1)
  assert_eq(merged.console.audit[0].receipt, "audit:core")
  assert_eq(merged.console.route, Alerts)
  assert_eq(merged.console_read_groups.length(), 1)
  // A later core reload preserves the merged alert list and its counter.
  let (reloaded, _) = update_live(
    merged,
    Outcome(Loaded({ ..@ui.default_state(), route: Alerts, loading: false })),
    emit,
  )
  assert_eq(reloaded.console.notifications.length(), 2)
  assert_eq(reloaded.console.notification_deliveries.length(), 1)
  assert_eq(reloaded.console.overview.alerts, 1)
}

///|
test "the models group replaces only the model-import list" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = {
    ..deferred_read_test_model(Models),
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Models,
      // Core- and other-group-owned rows the merge must leave alone.
      notifications: [
        alerts_window_test_row("alert-open", 1789808400000L, Unread),
      ],
      audit: [
        {
          actor: "operator-a",
          decision: "cluster.snapshot",
          evidence: "fleet",
          result: "accepted",
          receipt: "audit:core",
        },
      ],
    },
  }
  assert_true(deferred_read_pending(model, Models) is Some(ModelsReads))
  let (opened, _) = update_live(model, Console(Navigate(Models)), emit)
  assert_true(opened.console_read_groups.contains(ModelsReads))
  let payload : ModelImportReadPayload = {
    imports: [
      {
        import_id: "ms-import-1",
        source: "modelscope",
        model_id: "OpenBMB/MiniCPM5-1B",
        revision: "master",
        state: Downloading,
        files_total: 11,
        files_completed: 2,
        bytes_total: 2171355326L,
        bytes_completed: 1048576L,
        manifest_digest: "",
        local_directory: "",
        artifact_uri: "",
        license: "apache-2.0",
        error_code: "",
        cancel_requested: false,
        created_unix_ms: 1000L,
        updated_unix_ms: 1100L,
      },
    ],
  }
  let (merged, _) = update_live(
    opened,
    Outcome(DeferredReadLoaded(English, ModelsReads, GroupModels(payload))),
    emit,
  )
  assert_true(merged.console_read_groups.contains(ModelsReads))
  assert_eq(merged.console.model_imports.length(), 1)
  assert_eq(merged.console.model_imports[0].import_id, "ms-import-1")
  // Fields owned by the core read and by other groups stay untouched.
  assert_eq(merged.console.notifications.length(), 1)
  assert_eq(merged.console.audit.length(), 1)
  assert_eq(merged.console.audit[0].receipt, "audit:core")
  assert_eq(merged.console.route, Models)
  assert_eq(merged.console_read_groups.length(), 1)
  // An active download re-arms the import poll, which the core load can no
  // longer start because it does not carry the list.
  assert_eq(
    merged.model_import_poll_generation,
    opened.model_import_poll_generation + 1L,
  )
  // A later core reload preserves the merged import list.
  let (reloaded, _) = update_live(
    merged,
    Outcome(Loaded({ ..@ui.default_state(), route: Models, loading: false })),
    emit,
  )
  assert_eq(reloaded.console.model_imports.length(), 1)
  assert_eq(reloaded.console.notifications.length(), 1)
}

///|
test "the deployment group replaces the deployment rows and their operations" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = {
    ..deferred_read_test_model(Deployments),
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Deployments,
      // Access-group rows the deployment merge must leave alone.
      exclusive_node_leases: [
        {
          lease_id: "lease-exclusive-1",
          node_id: "node-1",
          subject_ref: "subject-a",
          unix_username: "alice",
          expires_at: "Unavailable",
          state: "Active",
          generation: 1L,
        },
      ],
    },
  }
  assert_true(
    deferred_read_pending(model, Deployments) is Some(DeploymentReads),
  )
  let (opened, _) = update_live(model, Console(Navigate(Deployments)), emit)
  assert_true(opened.console_read_groups.contains(DeploymentReads))
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "console:service-1:1000",
    deployment_id: "service-1",
    template: { template_id: "text-small", version: "v1", },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 86400000L,
    promote_when_ready: false,
  }
  let operation : @deployment.DeploymentOperation = {
    operation_id: "operation-1",
    deployment_id: "service-1",
    generation: 1L,
    state: Reconciling,
    plan: {
      plan_id: "plan:service-1:text-small:v1",
      intent,
      template: None,
      replicas: [],
      findings: [],
      executable: true,
      endpoint: None,
    },
    assignment_ids: ["service-1-r1"],
    endpoint: None,
    message: "",
    audit_receipt: "audit:service-1:1",
    created_unix_ms: 1000L,
    updated_unix_ms: 2000L,
  }
  let payload : DeploymentReadPayload = {
    deployments: [
      {
        assignment_id: "service-1-r1",
        deployment_id: "service-1",
        desired: Ready,
        observed: Preparing,
        placement_reason: "node-1 · #1",
      },
    ],
    service_deployments: [operation],
  }
  let (merged, _) = update_live(
    opened,
    Outcome(
      DeferredReadLoaded(English, DeploymentReads, GroupDeployment(payload)),
    ),
    emit,
  )
  assert_true(merged.console_read_groups.contains(DeploymentReads))
  assert_eq(merged.console.deployments.length(), 1)
  assert_eq(merged.console.deployments[0].assignment_id, "service-1-r1")
  // The `observed` flag is computed by the loader against the heartbeats it
  // reads itself, and the merge carries the verdict through unchanged.
  assert_eq(merged.console.deployments[0].observed, Preparing)
  assert_eq(merged.console.service_deployments.length(), 1)
  assert_eq(merged.console.service_deployments[0].operation_id, "operation-1")
  // Fields owned by other groups and by the core read stay untouched.
  assert_eq(merged.console.exclusive_node_leases.length(), 1)
  assert_eq(merged.console.users.length(), 0)
  assert_eq(merged.console.route, Deployments)
  assert_eq(merged.console_read_groups.length(), 1)
  // A later core reload preserves both merged fields, so the Deployments-page
  // actions that read the operation list still see it.
  let (reloaded, _) = update_live(
    merged,
    Outcome(Loaded({ ..@ui.default_state(), route: Deployments, loading: false })),
    emit,
  )
  assert_eq(reloaded.console.deployments.length(), 1)
  assert_eq(reloaded.console.service_deployments.length(), 1)
}

///|
test "the access group replaces only the account and workspace rows" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let model = {
    ..deferred_read_test_model(Users),
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Users,
      // Deployment-group rows the access merge must leave alone.
      deployments: [
        {
          assignment_id: "service-1-r1",
          deployment_id: "service-1",
          desired: Ready,
          observed: Ready,
          placement_reason: "node-1 · #1",
        },
      ],
    },
  }
  let (opened, _) = update_live(model, Console(Navigate(Users)), emit)
  assert_true(opened.console_read_groups.contains(AccessReads))
  let payload : AccessReadPayload = {
    accounts: [
      {
        account_id: "account-1",
        subject_ref: "subject-a",
        identity_issuer: "https://identity.example",
        display_name: "Alice",
        email: "alice@example.com",
        identity_receipt: "receipt:1",
        roles: [EnterpriseUser],
        state: Active,
        created_unix_ms: 1000L,
        updated_unix_ms: 2000L,
      },
    ],
    trial_summary: Some({
      registered_trials: 3,
      active_trials: 2,
      expired_trials: 1,
      converted_trials: 0,
    }),
    access_packages: [],
    users: [
      {
        user_id: "user-1",
        display_name: "Alice",
        email: "alice@example.com",
        state: UserActive,
        last_active: "Never",
        grant_count: 1,
      },
    ],
    access_grants: [
      {
        grant_id: "grant-1",
        user_id: "user-1",
        role: Developer,
        scope: "org-northstar",
        expires_at: "Unavailable",
        state: GrantActive,
      },
    ],
    compute_leases: [
      {
        lease_id: "lease-1",
        user_id: "user-1",
        workspace: "org-northstar",
        resource: "1 × dgx-spark",
        started_at: "Unavailable",
        expires_at: "Unavailable",
        state: Active,
      },
    ],
    exclusive_node_leases: [],
  }
  let (merged, _) = update_live(
    opened,
    Outcome(DeferredReadLoaded(English, AccessReads, GroupAccess(payload))),
    emit,
  )
  assert_true(merged.console_read_groups.contains(AccessReads))
  assert_eq(merged.console.accounts.length(), 1)
  assert_eq(merged.console.accounts[0].display_name, "Alice")
  assert_eq(merged.console.trial_summary.map(summary => summary.active_trials), Some(2))
  assert_eq(merged.console.users.length(), 1)
  assert_eq(merged.console.users[0].user_id, "user-1")
  assert_eq(merged.console.access_grants.length(), 1)
  assert_eq(merged.console.compute_leases.length(), 1)
  assert_eq(merged.console.exclusive_node_leases.length(), 0)
  // The deployment rows belong to the other group and stay as they were.
  assert_eq(merged.console.deployments.length(), 1)
  assert_eq(merged.console.deployments[0].assignment_id, "service-1-r1")
  assert_eq(merged.console_read_groups.length(), 1)
  // A later core reload preserves the merged account and workspace rows.
  let (reloaded, _) = update_live(
    merged,
    Outcome(Loaded({ ..@ui.default_state(), route: Users, loading: false })),
    emit,
  )
  assert_eq(reloaded.console.accounts.length(), 1)
  assert_eq(reloaded.console.users.length(), 1)
  assert_eq(reloaded.console.access_grants.length(), 1)
  assert_eq(reloaded.console.deployments.length(), 1)
}

///|
test "pages whose read group is not loaded render their empty state" {
  let routes : Array[@ui.OperatorRoute] = [
    Alerts,
    Models,
    Catalog,
    Deployments,
    Users,
    Leases,
    Audit,
    Requests,
    ContractDocuments,
    CostCenters,
    Agreements,
    QualifiedServices,
    OfflineCommerce,
  ]
  for route in routes {
    // The core read set leaves these pages empty until their group arrives;
    // that intermediate state must render cleanly.
    let html = @ui.render({
      ..@ui.default_state(),
      route,
      operator_authenticated: true,
    })
    assert_true(html.length() > 0)
  }
}

///|
#warnings("-alert_unstable")
test "the alerts page renders its day calendar for the selected window" {
  let emit : @rabbita.Emit[@ui.ConsoleMessage] = Emit(_ => @rabbita.none)
  let state = {
    ..@ui.default_state(),
    route: Alerts,
    notifications: [
      alerts_window_test_row("alert-today", 1789808400000L, Unread),
      alerts_window_test_row("alert-yesterday", 1789774200000L, Acknowledged),
    ],
  }
  let today_html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @ui.interactive_view(
        state,
        emit,
        alerts_window=Today,
        now_unix_ms=alerts_window_now_ms,
      ),
    )
  })
  // The window picker is present and the counter follows the filtered set.
  assert_true(today_html.contains("alerts-window"))
  assert_true(today_html.contains("2026-09-19"))
  assert_false(today_html.contains("2026-09-18"))
  assert_true(today_html.contains("1 of 2 incidents shown"))
  let all_html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @ui.interactive_view(
        state,
        emit,
        alerts_window=AllAlerts,
        now_unix_ms=alerts_window_now_ms,
      ),
    )
  })
  assert_true(all_html.contains("2026-09-19"))
  assert_true(all_html.contains("2026-09-18"))
  assert_true(all_html.contains("2 of 2 incidents shown"))
}
