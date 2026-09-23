///|
test "console registers H3 components independently of the whole revision" {
  assert_eq(model_local_component("MiniMax/MiniMax-H3/FL2VA"), "FL2VA")
  assert_eq(model_local_component("MiniMax/MiniMax-H3/Ref2VA"), "Ref2VA")
  assert_eq(model_local_component("MiniMax/MiniMax-H3"), "")
}

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
      { ..base, quick_deployment_id: "a".repeat(length), },
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
      quick_deployment_intent({ ..base, quick_deployment_id: hostile, }, 1L)
      is None,
    )
  }
  guard quick_deployment_intent(
      { ..base, quick_deployment_id: "service-1", },
      1L,
    )
    is Some(intent) else {
    fail("fixed-capacity intent should be valid")
  }
  assert_eq(intent.replicas, 1)
  assert_eq(intent.topology_profile, None)
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    quick_topology: Cx7Pair,
    success_message: Some("配置已提交。"),
  }
  let loaded : @ui.ConsoleState = {
    ..@ui.default_state(),
    locale: English,
    route: Overview,
    overview: { ..@ui.default_state().overview, total_nodes: 2, },
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
  assert_eq(merged.quick_topology, Cx7Pair)
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    console: { ..@ui.default_state(), operator_authenticated: true, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
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
    "能源谷“创未来”生态街区 | Cluster Operations",
  )
  assert_eq(
    console_document_title(ChineseSimplified),
    "能源谷“创未来”生态街区 | 集群运维",
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    console: { ..@ui.default_state(), locale: English, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Operator login"))
  assert_true(html.contains("Operator access starts here."))
  assert_true(html.contains("/auth/oidc/start?audience=operator"))
  assert_true(html.contains("login-username"))
  assert_true(html.contains("login-password"))
  // The draft is empty, so the form cannot be submitted yet.
  assert_false(operator_login_draft_complete(model))
  assert_true(html.contains("login-operator-token"))
  assert_true(html.contains("Local development token fallback"))
  assert_false(html.contains("Primary navigation"))
  assert_false(html.contains("Model registry"))
}

///|
#warnings("-alert_unstable")
test "unconfigured public HTTP origin renders login landing but blocks credential entry" {
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
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(
    html.contains("This address is not the configured Operator origin"),
  )
  assert_true(html.contains("disabled"))
  assert_true(html.contains("Open the configured Operator address"))
  assert_false(html.contains("/auth/oidc/start?audience=operator"))
  assert_true(html.contains("login-username"))
  assert_true(html.contains("login-password"))
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
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("/auth/oidc/start?audience=operator"))
  assert_true(html.contains("Continue with organization sign-in"))
  assert_true(html.contains("login-username"))
  assert_true(html.contains("login-password"))
  // HTTPS is available, so the password route is usable and the browser may
  // let the operator's password manager fill it.
  assert_true(login_transport_allowed(model.endpoint))
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
test "operator login needs both halves and drops the password once it is used" {
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
    login_username: "wlc",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  assert_false(operator_login_draft_complete(model))
  let (unsubmitted, _) = update_live(model, OperatorLoginSubmitted, emit)
  assert_false(unsubmitted.console.loading)
  let (submitted, _) = update_live(
    { ..model, login_password: "synthetic-password-not-a-real-account", },
    OperatorLoginSubmitted,
    emit,
  )
  assert_true(submitted.console.loading)
  // A refusal keeps the draft so the operator can correct it.
  let (refused, _) = update_live(
    submitted,
    OperatorLoginRefused(
      English,
      password_login_refusal(English, {
        status: 401,
        body: "{\"error\":\"invalid-credentials\"}",
      }),
    ),
    emit,
  )
  assert_false(refused.console.loading)
  assert_eq(refused.login_password, "synthetic-password-not-a-real-account")
  assert_true(
    refused.console.error_message.unwrap().contains("username or password"),
  )
  // The session replaces the password; the username stays for the next visit.
  let (signed_in, _) = update_live(
    submitted,
    GatewaySessionLoaded({
      session_token: "lnxs_operator-session",
      csrf_token: "csrf-memory-only",
      expires_unix_ms: 9999999999999L,
    }),
    emit,
  )
  assert_eq(signed_in.login_password, "")
  assert_eq(signed_in.login_username, "wlc")
}

///|
test "the gateway's refusal codes choose the operator-facing copy" {
  let refusal = fn(body : String) -> String {
    password_login_refusal(English, { status: 401, body, })
  }
  assert_true(
    refusal("{\"error\":\"invalid-credentials\"}").contains(
      "username or password",
    ),
  )
  assert_true(
    refusal("{\"error\":\"identity-rejected\"}").contains(
      "platform administrator",
    ),
  )
  assert_true(
    refusal("{\"error\":\"identity-provider-unavailable\"}").contains(
      "unavailable",
    ),
  )
  assert_true(
    refusal("{\"error\":\"too-many-attempts\"}").contains("five minutes"),
  )
  assert_true(refusal("not json").contains("refused the sign-in"))
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    console: { ..@ui.demo_state(), route: Leases, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
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
    console: { ..@ui.demo_state(), route: Nodes, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
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
    console: { ..@ui.demo_state(), route: Catalog, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
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
test "the topology picker submits the admitted CX7 pair for one replica" {
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
    console: { ..@ui.demo_state(), route: Catalog, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (named, _) = update(
    model,
    Console(QuickDeploymentIdChanged("demo-pair")),
    emit,
  )
  let (single, _) = update(
    named,
    Console(QuickTopologyChanged("single-machine")),
    emit,
  )
  assert_eq(single.console.quick_topology, SingleMachine)
  guard quick_deployment_intent(single.console, 1000L) is Some(one_machine) else {
    fail("one machine intent should be valid")
  }
  assert_eq(one_machine.topology_profile, None)
  assert_eq(one_machine.replicas, 1)
  let (paired, _) = update(
    single,
    Console(QuickTopologyChanged("cx7-pair")),
    emit,
  )
  assert_eq(paired.console.quick_topology, Cx7Pair)
  guard quick_deployment_intent(paired.console, 1000L) is Some(pair) else {
    fail("a CX7 pair intent should be valid")
  }
  assert_eq(pair.topology_profile, Some(@contracts.cx7_pair_topology_profile))
  assert_eq(pair.replicas, 1)
  assert_true(pair.to_json().stringify().contains("\"cx7-pair-v1\""))
  let (submitted, _) = update(paired, Console(SubmitQuickDeployment), emit)
  assert_eq(
    submitted.console.success_message,
    Some(
      "Demo preflight passed for demo-pair. No controller operation was created.",
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    console: { ..@ui.demo_state(), route: ContractDocuments, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    memory_measured: true,
    utilization_per_mille: 500,
    cpu_per_mille: 500,
    cpu_measured: true,
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
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let polled = [
    cluster_poll_test_row("node-1", Unreachable, "Unassigned"),
    cluster_poll_test_row("node-2", Active, "Unassigned"),
  ]
  let (stale, _) = update_live(
    model,
    Outcome(ClusterPolled(2L, polled, [])),
    emit,
  )
  assert_true(stale == model)
  let (current, _) = update_live(
    model,
    Outcome(ClusterPolled(3L, polled, [])),
    emit,
  )
  assert_eq(current.console.nodes.length(), 2)
  assert_eq(current.console.nodes[0].state, Unreachable)
  assert_eq(current.console.nodes[1].node_id, "node-2")
  assert_eq(current.console.overview.active_nodes, 1)
  assert_eq(current.console.overview.total_nodes, 2)
}

///|
fn node_row_sample(
  node_id : String,
  metric : String,
  value : Double,
) -> @contracts.TelemetrySample {
  {
    node_id,
    deployment_id: "",
    metric,
    value,
    timestamp_unix_ms: current_unix_ms(),
  }
}

///|
/// A heartbeat whose signed inventory claims the whole declared pool is free,
/// which is how a unified-memory descriptor is rendered today.
fn node_row_heartbeat(
  node_id : String,
  declared_memory_mib~ : Int,
) -> @contracts.NodeHeartbeat {
  {
    node_id,
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id,
      agent_version: "0.1.0",
      os_release: "linux",
      runtime_names: [],
      accelerators: [
        {
          device_id: "gpu-0",
          architecture: "nvidia-gb10",
          memory_total_mib: declared_memory_mib,
          memory_free_mib: declared_memory_mib,
          healthy: true,
        },
      ],
      labels: Map([]),
      taints: [],
    },
    running_deployments: [],
    runtime_endpoints: None,
    timestamp_unix_ms: current_unix_ms(),
    signature: "",
  }
}

///|
fn node_row_telemetry(
  samples : Array[@contracts.TelemetrySample],
) -> ConsoleTelemetrySnapshot {
  { samples, benchmark_summaries: [], }
}

///|
test "node sensors reject expired future and workload-scoped samples" {
  let fresh = node_row_sample("node-1", "accelerator_power_watts", 11.46)
  let samples = [
    fresh,
    { ..fresh, value: 900.0, timestamp_unix_ms: current_unix_ms() - 60001L, },
    { ..fresh, value: 800.0, timestamp_unix_ms: current_unix_ms() + 60000L, },
    { ..fresh, value: 700.0, deployment_id: "workload-1", },
  ]
  assert_eq(
    latest_node_sensor_value(samples, "node-1", fresh.metric),
    Some(11.46),
  )
  assert_eq(latest_node_metric([], "node-1", fresh.metric), -1)
  assert_eq(
    latest_node_sensor_value(
      [{ ..fresh, timestamp_unix_ms: current_unix_ms() - 60001L, }],
      "node-1",
      fresh.metric,
    ),
    None,
  )
  let row = build_node_rows(
      [node_row_heartbeat("node-1", declared_memory_mib=124608)],
      node_row_telemetry(samples),
      None,
      English,
    )[0]
  assert_eq(row.power_watts, 11.46)
  assert_eq(row.temperature_celsius, -1)
  assert_eq(row.utilization_per_mille, -1)
  assert_true(row.active_assignment.contains("not machine idle"))
}

///|
test "node rows prefer measured host memory over the declared inventory" {
  let node_id = "node-1"
  let rows = build_node_rows(
    [node_row_heartbeat(node_id, declared_memory_mib=65536)],
    node_row_telemetry([
      node_row_sample(node_id, "host_memory_total_mib", 122880.0),
      node_row_sample(node_id, "host_memory_used_mib", 40960.0),
      node_row_sample(node_id, "accelerator_memory_total_mib", 65536.0),
      node_row_sample(node_id, "accelerator_memory_used_mib", 1024.0),
      node_row_sample(node_id, "host_cpu_utilization_per_mille", 0.0),
    ]),
    None,
    English,
  )
  let row = rows[0]
  assert_eq(row.total_memory_mib, 122880)
  assert_eq(row.used_memory_mib, 40960)
  assert_eq(row.free_memory_mib, 81920)
  assert_true(row.memory_measured)
  assert_true(row.cpu_measured)
  assert_eq(row.cpu_per_mille, 0)
}

///|
test "node rows fall back to accelerator memory and derive free from it" {
  let node_id = "node-1"
  let rows = build_node_rows(
    [node_row_heartbeat(node_id, declared_memory_mib=65536)],
    node_row_telemetry([
      node_row_sample(node_id, "accelerator_memory_total_mib", 32768.0),
      node_row_sample(node_id, "accelerator_memory_used_mib", 8192.0),
    ]),
    None,
    English,
  )
  let row = rows[0]
  assert_eq(row.total_memory_mib, 32768)
  assert_eq(row.free_memory_mib, 24576)
  assert_true(row.memory_measured)
  assert_false(row.cpu_measured)
  assert_eq(row.cpu_per_mille, 0)
}

///|
test "node rows never present the declared inventory as memory evidence" {
  let node_id = "node-1"
  let declared_only_rows = build_node_rows(
    [node_row_heartbeat(node_id, declared_memory_mib=65536)],
    node_row_telemetry([]),
    None,
    English,
  )
  let declared_only = declared_only_rows[0]
  assert_eq(declared_only.total_memory_mib, 65536)
  assert_eq(declared_only.used_memory_mib, 0)
  assert_false(declared_only.memory_measured)
  // A host total without an availability sample cannot back a free figure, and
  // the declared "free" is a copy of the declared total.
  let host_total_only_rows = build_node_rows(
    [node_row_heartbeat(node_id, declared_memory_mib=65536)],
    node_row_telemetry([
      node_row_sample(node_id, "host_memory_total_mib", 122880.0),
    ]),
    None,
    English,
  )
  let host_total_only = host_total_only_rows[0]
  assert_false(host_total_only.memory_measured)
  assert_eq(host_total_only.used_memory_mib, 0)
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
    login_username: "",
    personal_login: false,
    login_password: "",
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
    { ..model, console: { ..model.console, operator_authenticated: false, }, },
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
test "alert window narrows the incident calendar to whole Beijing days" {
  let today = alerts_window_test_row("alert-today", 1789808400000L, Unread)
  let yesterday = alerts_window_test_row(
    "alert-yesterday",
    1789745400000L,
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
test "Beijing midnight changes the alert day at 16:00 UTC" {
  let before_midnight = 1789747199000L
  let after_midnight = 1789747201000L
  assert_eq(@ui.alert_day_label(before_midnight), "2026-09-18")
  assert_eq(@ui.alert_day_label(after_midnight), "2026-09-19")
  let rows = [
    alerts_window_test_row("previous-day", before_midnight, Unread),
    alerts_window_test_row("new-day", after_midnight, Unread),
  ]
  let visible = @ui.filter_alerts(rows, Today, after_midnight)
  assert_eq(visible.length(), 1)
  assert_eq(visible[0].notification_id, "new-day")
}

///|
test "alert calendar groups by day newest first and counts only filtered open incidents" {
  let rows = [
    alerts_window_test_row("alert-today-open", 1789808400000L, Unread),
    alerts_window_test_row("alert-today-resolved", 1789808400000L, Resolved),
    alerts_window_test_row("alert-yesterday-open", 1789745400000L, Acknowledged),
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
    console: { ..@ui.default_state(), operator_authenticated: true, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
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
  assert_true(widened == { ..narrowed, alerts_window: AllAlerts, })
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
    console: { ..@ui.default_state(), operator_authenticated: true, route, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
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
    "/v1/accounts", "/v1/accounts/trial-summary", "/v1/onboarding/access-packages",
    "/v1/workspace", "/v1/exclusive-node-leases",
  ])
  assert_eq(console_read_group_paths(DeploymentReads, ""), [
    "/v1/assignments", "/v1/service-deployments",
  ])
  // The commerce loader reads the production-readiness projection alongside
  // the snapshot, so the operator's offline-commerce route shows what is
  // blocking the pipeline without a second trip.
  assert_eq(console_read_group_paths(CommerceReads, ""), [
    "/v1/portal/operator/snapshot", "/v1/offline-commerce/operator/snapshot", "/v1/offline-commerce/operator/readiness",
  ])
  assert_eq(console_read_group_paths(CommerceReads, "org-northstar"), [
    "/v1/portal/operator/snapshot", "/v1/offline-commerce/operator/snapshot", "/v1/offline-commerce/operator/readiness",
    "/v1/commercial/organizations/org-northstar/snapshot", "/v1/commercial/organizations/org-northstar/integrations",
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
  let demo = { ..deferred_read_test_model(Audit), demo_mode: true, }
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
  // A later core reload refreshes the alert evidence rather than preserving stale counts.
  let (reloaded, _) = update_live(
    merged,
    Outcome(Loaded({ ..@ui.default_state(), route: Alerts, loading: false, })),
    emit,
  )
  assert_eq(reloaded.console.notifications.length(), 0)
  assert_eq(reloaded.console.notification_deliveries.length(), 0)
  assert_eq(reloaded.console.overview.alerts, 0)
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
    Outcome(Loaded({ ..@ui.default_state(), route: Models, loading: false, })),
    emit,
  )
  assert_eq(reloaded.console.model_imports.length(), 1)
  assert_eq(reloaded.console.notifications.length(), 0)
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
    topology_profile: None,
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
    Outcome(
      Loaded({ ..@ui.default_state(), route: Deployments, loading: false, }),
    ),
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
    pending_organizations: [],
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
        subject_ref: "subject-1",
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
  assert_eq(
    merged.console.trial_summary.map(summary => summary.active_trials),
    Some(2),
  )
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
    Outcome(Loaded({ ..@ui.default_state(), route: Users, loading: false, })),
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
      alerts_window_test_row("alert-yesterday", 1789745400000L, Acknowledged),
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

///|
/// The digest, licence identity and managed-store revision one adopted
/// candidate carries into the per-row onboarding controls.
fn onboarding_candidate_row() -> @ui.ModelRow {
  {
    model_id: "model.minicpm5-1b",
    version: "modelscope-main",
    state: Candidate,
    license_status: "missing",
    evaluation_status: "missing",
    compatibility: "nvidia-sm121",
    alias_name: "—",
    license_id: "license.minicpm5-apache",
    artifact_uri: "modelstore://qwen3635ba3bfp8",
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  }
}

///|
/// The verified import the adopted candidate came from. Its declared SPDX text
/// is what the licence form prefills, exactly as the control plane records it
/// at adoption.
fn onboarding_verified_import() -> @ui.ModelImportRow {
  {
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
    local_directory: "qwen3635ba3bfp8",
    artifact_uri: "modelstore://qwen3635ba3bfp8",
    license: "apache-2.0",
    error_code: "",
    cancel_requested: false,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
  }
}

///|
fn model_onboarding_test_model() -> AppModel {
  let base = deferred_read_test_model(Models)
  {
    ..base,
    console: {
      ..base.console,
      models: [onboarding_candidate_row()],
      model_imports: [onboarding_verified_import()],
    },
  }
}

///|
test "model onboarding controls address the canonical registry routes" {
  assert_eq(model_onboarding_path(AcceptLicense), "/v1/licenses")
  assert_eq(model_onboarding_path(VerifyArtifact), "/v1/verifications")
  assert_eq(model_onboarding_path(ApproveVersion), "/v1/models/approve")
  assert_eq(model_onboarding_path(PromoteAlias), "/v1/aliases/promote")
  assert_eq(runtime_registration_path(), "/v1/runtimes")
}

///|
test "a registry refusal is reported with the control plane's own message" {
  let error : Error = Failure::Failure(
    "HTTP 409: {\"error\":{\"code\":\"RegistryRejected\",\"message\":\"model approval prerequisites were not met\",\"retryable\":false}}",
  )
  assert_eq(
    http_failure_detail(error),
    "model approval prerequisites were not met",
  )
  // A body that is not the canonical envelope keeps the raw transport detail
  // rather than inventing an explanation.
  let plain : Error = Failure::Failure("HTTP 503: upstream unavailable")
  assert_true(
    http_failure_detail(plain).contains("HTTP 503: upstream unavailable"),
  )
}

///|
test "licence acceptance validates, prefills the citation, and builds the record" {
  let model = model_onboarding_test_model()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (opened, _) = update(
    model,
    Console(BeginLicenseAcceptance("model.minicpm5-1b", "modelscope-main")),
    emit,
  )
  let draft = opened.console.model_license_draft
  assert_eq(draft.model_id, "model.minicpm5-1b")
  assert_eq(draft.version, "modelscope-main")
  assert_eq(draft.license_id, "license.minicpm5-apache")
  assert_eq(draft.evidence_ref, "modelscope-license:apache-2.0")
  let (submitting, _) = update(opened, Console(SubmitModelLicense), emit)
  assert_true(submitting.console.loading)
  assert_eq(submitting.console.error_message, None)
  assert_eq(
    model_license_body(draft),
    "{\"license_id\":\"license.minicpm5-apache\",\"model_id\":\"model.minicpm5-1b\",\"status\":\"Accepted\",\"accepted_by\":\"operator\",\"evidence_ref\":\"modelscope-license:apache-2.0\"}",
  )
  // An empty citation is the one field the operator must not omit.
  let (cleared, _) = update(
    opened,
    Console(LicenseEvidenceChanged("   ")),
    emit,
  )
  let (rejected, _) = update(cleared, Console(SubmitModelLicense), emit)
  assert_false(rejected.console.loading)
  assert_true(rejected.console.error_message is Some(_))
  let (dismissed, _) = update(opened, Console(DismissLicenseAcceptance), emit)
  assert_eq(dismissed.console.model_license_draft.model_id, "")
}

///|
test "artifact verification and approval both come from the row's own evidence" {
  let model = model_onboarding_test_model()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let row = onboarding_candidate_row()
  let (verifying, _) = update(
    model,
    Console(VerifyModelArtifact(row.model_id, row.version)),
    emit,
  )
  assert_true(verifying.console.loading)
  assert_eq(verifying.console.error_message, None)
  assert_eq(
    model_verification_body(row),
    "{\"kind\":\"managed-revision\",\"subject\":\"modelstore://qwen3635ba3bfp8\",\"digest\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provenance_verified\":true}",
  )
  let (approving, _) = update(
    model,
    Console(ApproveModelVersion(row.model_id, row.version)),
    emit,
  )
  assert_true(approving.console.loading)
  assert_eq(
    model_approval_body(row.model_id, row.version),
    "{\"model_id\":\"model.minicpm5-1b\",\"version\":\"modelscope-main\"}",
  )
  // A version the console never listed cannot be verified from thin air.
  let (missing, _) = update(
    model,
    Console(VerifyModelArtifact("model.unknown", "v1")),
    emit,
  )
  assert_false(missing.console.loading)
  assert_true(missing.console.error_message is Some(_))
}

///|
test "alias promotion defaults to a model-id slug and submits a canary stage" {
  let model = model_onboarding_test_model()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (opened, _) = update(
    model,
    Console(BeginAliasPromotion("model.minicpm5-1b", "modelscope-main")),
    emit,
  )
  let draft = opened.console.model_alias_draft
  assert_eq(draft.alias_name, "model.minicpm5-1b")
  let (named, _) = update(
    opened,
    Console(AliasNameChanged("text.default")),
    emit,
  )
  assert_eq(named.console.model_alias_draft.alias_name, "text.default")
  let (submitting, _) = update(named, Console(SubmitAliasPromotion), emit)
  assert_true(submitting.console.loading)
  assert_eq(submitting.console.error_message, None)
  assert_eq(
    model_promotion_body(named.console.model_alias_draft),
    "{\"alias_name\":\"text.default\",\"model_id\":\"model.minicpm5-1b\",\"version\":\"modelscope-main\",\"stage\":\"Canary\",\"actor\":\"operator\"}",
  )
  let (blank, _) = update(opened, Console(AliasNameChanged("  ")), emit)
  let (rejected, _) = update(blank, Console(SubmitAliasPromotion), emit)
  assert_false(rejected.console.loading)
  assert_true(rejected.console.error_message is Some(_))
}

///|
test "runtime registration mirrors the registry's own shape checks" {
  let model = model_onboarding_test_model()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let draft = model.console.runtime_draft
  assert_eq(draft.name, "")
  assert_eq(draft.version, "")
  assert_eq(draft.architecture, "nvidia-sm121")
  assert_eq(draft.capability, TextGenerate)
  assert_false(draft.supports_batching)
  assert_false(draft.supports_multi_node)
  // A malformed digest is refused before a request is built.
  let (named, _) = update(
    model,
    Console(RuntimeNameChanged("text-runtime-v2")),
    emit,
  )
  let (versioned, _) = update(
    named,
    Console(RuntimeVersionChanged("runtime-v2")),
    emit,
  )
  let (digested, _) = update(
    versioned,
    Console(RuntimeImageDigestChanged("sha256:not-a-digest")),
    emit,
  )
  let (refused, _) = update(digested, Console(SubmitRuntimeRegistration), emit)
  assert_false(refused.console.loading)
  assert_true(refused.console.error_message is Some(_))
  let (valid, _) = update(
    versioned,
    Console(
      RuntimeImageDigestChanged(
        "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ),
    ),
    emit,
  )
  let (toggled, _) = update(valid, Console(RuntimeBatchingToggled), emit)
  assert_true(toggled.console.runtime_draft.supports_batching)
  let (submitted, _) = update(toggled, Console(SubmitRuntimeRegistration), emit)
  assert_true(submitted.console.loading)
  assert_eq(submitted.console.error_message, None)
  assert_eq(
    runtime_registration_body(toggled.console.runtime_draft),
    "{\"name\":\"text-runtime-v2\",\"image_digest\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"version\":\"runtime-v2\",\"architectures\":[\"nvidia-sm121\"],\"capabilities\":[\"TextGenerate\"],\"supports_batching\":true,\"supports_multi_node\":false}",
  )
  // A rejected or retried registration keeps the operator's own fields.
  assert_eq(submitted.console.runtime_draft, toggled.console.runtime_draft)
}

///|
test "demo mode previews the onboarding and runtime controls without mutation" {
  let base = @ui.demo_state()
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
    console: { ..base, route: Models, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (opened, _) = update(
    model,
    Console(BeginLicenseAcceptance("lunanexa.text.general", "v3")),
    emit,
  )
  assert_eq(
    opened.console.model_license_draft.model_id,
    "lunanexa.text.general",
  )
  let (submitted, _) = update(opened, Console(SubmitModelLicense), emit)
  assert_eq(
    submitted.console.success_message,
    Some("Demo is read-only; no controller operation was sent or persisted."),
  )
  assert_eq(submitted.console.models, base.models)
  assert_eq(
    submitted.console.model_license_draft,
    opened.console.model_license_draft,
  )
}

///|
test "a refused console write is matched on its transport status, not its Repr" {
  let conflict : Error = Failure::Failure(
    "HTTP 409: {\"error\":{\"code\":\"TemplateRejected\",\"message\":\"catalog template registration was rejected\",\"retryable\":false}}",
  )
  assert_true(http_status_is(conflict, 409))
  assert_false(http_status_is(conflict, 403))
  assert_false(http_status_is(conflict, 401))
  let denied : Error = Failure::Failure(
    "HTTP 403: {\"error\":{\"code\":\"Forbidden\",\"message\":\"operator authority is required\",\"retryable\":false}}",
  )
  assert_true(http_status_is(denied, 403))
  assert_false(http_status_is(denied, 409))
  // The two helpers answer different questions: the detail helper unwraps the
  // control plane's own envelope, so the status line is gone by the time it
  // answers and a handler that keyed on it would never match.
  assert_eq(
    http_failure_detail(conflict),
    "catalog template registration was rejected",
  )
  assert_false(http_failure_detail(conflict).contains("HTTP 409"))
  let offline : Error = Failure::Failure("TypeError: Failed to fetch")
  assert_false(http_status_is(offline, 401))
  assert_true(http_failure_detail(offline).contains("Failed to fetch"))
}

///|
/// The registered model and runtime the catalog template form draws its
/// prefill from: one adopted candidate with its verified import, and the text
/// runtime the registry admitted.
fn template_test_model() -> AppModel {
  let base = deferred_read_test_model(Catalog)
  {
    ..base,
    console: {
      ..base.console,
      models: [onboarding_candidate_row()],
      model_imports: [onboarding_verified_import()],
      registered_runtimes: [
        {
          name: "text-runtime",
          image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          version: "runtime-v1",
          architectures: ["nvidia-gb10"],
          capabilities: [TextGenerate],
          supports_batching: false,
          supports_multi_node: false,
        },
      ],
    },
  }
}

///|
test "the catalog template form prefills from the registry and builds the signed body" {
  let model = template_test_model()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (picked, _) = update(
    model,
    Console(TemplateModelSelected("model.minicpm5-1b@modelscope-main")),
    emit,
  )
  let draft = picked.console.template_draft
  assert_eq(draft.model_id, "model.minicpm5-1b")
  assert_eq(draft.model_version, "modelscope-main")
  assert_eq(draft.artifact_uri, "modelstore://qwen3635ba3bfp8")
  assert_eq(
    draft.artifact_digest,
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  // The import already reported the byte count, and a managed revision is
  // signed by the source manifest the control plane wrote beside it.
  assert_eq(draft.artifact_size_bytes, "2171355326")
  assert_eq(
    draft.artifact_signature_ref,
    "modelstore://qwen3635ba3bfp8/lunanexa-source-manifest.json",
  )
  // This candidate carries no registered alias, so its own id is the selector.
  assert_eq(draft.model_selector, "model.minicpm5-1b")
  let (runtime_picked, _) = update(
    picked,
    Console(TemplateRuntimeSelected("text-runtime@runtime-v1")),
    emit,
  )
  let draft = runtime_picked.console.template_draft
  assert_eq(draft.runtime_name, "text-runtime")
  assert_eq(draft.runtime_version, "runtime-v1")
  assert_eq(
    draft.runtime_image_digest,
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  assert_eq(draft.runtime_architectures, "nvidia-gb10")
  assert_eq(draft.architecture, "nvidia-gb10")
  assert_eq(draft.capability, TextGenerate)
  // An unnamed runtime selection leaves the operator's own fields alone.
  let (unmatched, _) = update(
    runtime_picked,
    Console(TemplateRuntimeSelected("vision-runtime@runtime-v9")),
    emit,
  )
  assert_eq(unmatched.console.template_draft, draft)
  // Naming the template is what makes the draft submittable.
  let (versioned, _) = update(
    runtime_picked,
    Console(TemplateTextChanged(TemplateVersion, "v1")),
    emit,
  )
  let (titled, _) = update(
    versioned,
    Console(TemplateTextChanged(TemplateDisplayName, "Text small")),
    emit,
  )
  let (named, _) = update(
    titled,
    Console(TemplateTextChanged(TemplateId, "text-small")),
    emit,
  )
  assert_true(@ui.template_draft_valid(named.console.template_draft))
  // A number outside the planner's bound is caught before a request is built.
  let (over_bound, _) = update(
    named,
    Console(TemplateTextChanged(TemplateAcceleratorCount, "65")),
    emit,
  )
  assert_true(
    template_registration_body(over_bound.console.template_draft) is None,
  )
  let (refused, _) = update(
    over_bound,
    Console(SubmitTemplateRegistration),
    emit,
  )
  assert_false(refused.console.loading)
  assert_true(refused.console.error_message is Some(_))
  let (fixed, _) = update(
    over_bound,
    Console(TemplateTextChanged(TemplateAcceleratorCount, "1")),
    emit,
  )
  let (submitted, _) = update(fixed, Console(SubmitTemplateRegistration), emit)
  assert_true(submitted.console.loading)
  assert_eq(submitted.console.error_message, None)
  let body = template_registration_body(fixed.console.template_draft).unwrap()
  let sent : @deployment.ModelServiceTemplate = @json.from_json(
    @json.parse(body),
  )
  assert_eq(sent.template_id, "text-small")
  assert_eq(sent.version, "v1")
  assert_eq(sent.display_name, "Text small")
  assert_eq(sent.model_id, "model.minicpm5-1b")
  assert_eq(sent.model_version, "modelscope-main")
  assert_eq(sent.model_selector, "model.minicpm5-1b")
  assert_eq(sent.artifact.uri, "modelstore://qwen3635ba3bfp8")
  assert_eq(sent.artifact.size_bytes, 2171355326L)
  assert_eq(
    sent.artifact.signature_ref,
    "modelstore://qwen3635ba3bfp8/lunanexa-source-manifest.json",
  )
  assert_eq(sent.runtime.name, "text-runtime")
  assert_eq(sent.runtime.architectures, ["nvidia-gb10"])
  assert_eq(sent.runtime.capabilities, [TextGenerate])
  assert_false(sent.runtime.supports_batching)
  assert_false(sent.runtime.supports_multi_node)
  assert_eq(sent.capability, TextGenerate)
  assert_eq(sent.architecture, "nvidia-gb10")
  assert_eq(sent.resources.accelerator_count, 1)
  assert_eq(sent.resources.accelerator_memory_mib, 32768)
  assert_eq(sent.resources.cpu_millis, 4000)
  assert_eq(sent.resources.memory_mib, 65536)
  // A template reaches the controller and the artifact store, and nothing else.
  assert_true(sent.network.allow_controller)
  assert_true(sent.network.allow_artifact_store)
  assert_eq(sent.network.allowed_egress, [])
  assert_eq(sent.health.readiness_path, "/health")
  assert_eq(sent.health.interval_ms, 5000)
  assert_eq(sent.health.failure_threshold, 6)
  assert_eq(sent.health.termination_grace_ms, 60000)
  assert_eq(sent.data_policy.classification, Internal)
  assert_eq(sent.data_policy.retention, Ephemeral)
  assert_eq(sent.secret_refs, ["runtime-token"])
  assert_eq(sent.rollout.canary_replicas, 1)
  assert_false(sent.rollout.automatic_promotion)
  assert_true(sent.rollout.automatic_rollback)
  assert_eq(sent.rollout.readiness_timeout_ms, 600000L)
  // The control plane signs a template itself and refuses a caller that
  // supplies either half, so both go out empty.
  assert_eq(sent.approval_receipt, "")
  assert_eq(sent.signature, "")
  // Int64 fields travel as JSON strings; Int fields stay numbers.
  assert_true(body.contains("\"size_bytes\":\"2171355326\""))
  assert_true(body.contains("\"readiness_timeout_ms\":\"600000\""))
  assert_true(body.contains("\"interval_ms\":5000"))
  assert_true(body.contains("\"accelerator_count\":1"))
  assert_true(body.contains("\"retention\":\"Ephemeral\""))
  // The body is a template the deployment service's own planner accepts.
  try @deployment.validate_template(sent, require_signature=false) catch {
    _ => fail("the console built a template the planner refuses")
  } noraise {
    _ => ()
  }
}

///|
test "an evaluation capture carries its consent receipt into the body" {
  let model = template_test_model()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let draft = {
    ..@ui.empty_template_draft(),
    template_id: "text-capture",
    version: "v1",
    display_name: "Text capture",
    model_selector: "text.default",
    model_id: "model.minicpm5-1b",
    model_version: "modelscope-main",
    artifact_uri: "modelstore://qwen3635ba3bfp8",
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    artifact_size_bytes: "2171355326",
    artifact_signature_ref: "modelstore://qwen3635ba3bfp8/lunanexa-source-manifest.json",
    runtime_name: "text-runtime",
    runtime_version: "runtime-v1",
    runtime_image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    runtime_architectures: "nvidia-gb10",
    architecture: "nvidia-gb10",
    capability: TextGenerate,
  }
  let (captured, _) = update(
    { ..model, console: { ..model.console, template_draft: draft, }, },
    Console(TemplateFlagToggled(CaptureForEvaluation)),
    emit,
  )
  assert_true(captured.console.template_draft.capture_for_evaluation)
  // A capture without a receipt is one the planner refuses, so no body is built.
  assert_true(
    template_registration_body(captured.console.template_draft) is None,
  )
  let (receipted, _) = update(
    captured,
    Console(TemplateTextChanged(TemplateConsentReceipt, "consent:evaluation:1")),
    emit,
  )
  let body = template_registration_body(receipted.console.template_draft).unwrap()
  assert_true(body.contains("\"EvaluationCapture\""))
  assert_true(body.contains("consent:evaluation:1"))
  assert_true(body.contains("\"Ephemeral\"") == false)
  // Turning the capture off clears the reuse switches with it.
  let (released, _) = update(
    receipted,
    Console(TemplateFlagToggled(CaptureForEvaluation)),
    emit,
  )
  assert_false(released.console.template_draft.capture_for_evaluation)
  assert_false(released.console.template_draft.allow_cache)
  assert_false(released.console.template_draft.allow_training_reuse)
  assert_true(
    template_registration_body(released.console.template_draft)
    .unwrap()
    .contains("\"Ephemeral\""),
  )
}

///|
test "demo mode previews the catalog template form without mutation" {
  let base = @ui.demo_state()
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
    console: { ..base, route: Catalog, },
    console_read_groups: Map([]),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
    cluster_poll_generation: 0L,
    login_username: "",
    personal_login: false,
    login_password: "",
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (picked, _) = update(
    model,
    Console(TemplateModelSelected("lunanexa.text.general@v3")),
    emit,
  )
  let draft = picked.console.template_draft
  assert_eq(draft.model_id, "lunanexa.text.general")
  assert_eq(draft.artifact_uri, "modelstore://lunanexa.text.general/v3")
  assert_eq(draft.model_selector, "text.default")
  let (runtime_picked, _) = update(
    picked,
    Console(TemplateRuntimeSelected("text-runtime@runtime-v1")),
    emit,
  )
  assert_eq(
    runtime_picked.console.template_draft.runtime_architectures,
    "nvidia-gb10",
  )
  let (submitted, _) = update(
    runtime_picked,
    Console(SubmitTemplateRegistration),
    emit,
  )
  assert_eq(
    submitted.console.success_message,
    Some("Demo is read-only; no controller operation was sent or persisted."),
  )
  assert_eq(submitted.console.catalog_templates, base.catalog_templates)
}

///|
#warnings("-alert_unstable")
test "the interactive catalog view renders the template form for a live operator" {
  let emit : @rabbita.Emit[@ui.ConsoleMessage] = Emit(_ => @rabbita.none)
  let picked = template_test_model().console.template_draft
  let state = {
    ..@ui.demo_state(),
    route: Catalog,
    template_draft: {
      ..picked,
      template_id: "text-small",
      version: "v1",
      display_name: "Text small",
      model_id: "lunanexa.text.general",
      model_version: "v3",
      model_selector: "text.default",
      artifact_uri: "modelstore://lunanexa.text.general/v3",
      artifact_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      artifact_size_bytes: "16000000000",
      artifact_signature_ref: "modelstore://lunanexa.text.general/v3/lunanexa-source-manifest.json",
      runtime_name: "text-runtime",
      runtime_version: "runtime-v1",
      runtime_image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      runtime_architectures: "nvidia-gb10",
      architecture: "nvidia-gb10",
    },
    operator_authenticated: true,
  }
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(@ui.interactive_view(state, emit))
  })
  // The form is drawn beside the picker it feeds, and the operator's own draft
  // is what every control carries.
  assert_true(html.contains("id=\"template-model-picker\""))
  assert_true(html.contains("value=\"lunanexa.text.general@v3\" selected"))
  assert_true(html.contains("value=\"text-runtime@runtime-v1\" selected"))
  assert_true(html.contains("value=\"text-small\""))
  // A draft that satisfies every rule leaves the submit control live.
  let label_at = html.find("Register template").unwrap()
  let mut button_tag = ""
  for segment in html[:label_at].split("<button") {
    button_tag = segment.to_owned()
  }
  assert_false(button_tag.contains("disabled"))
}
