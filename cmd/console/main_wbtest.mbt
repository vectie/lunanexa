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
    console: state,
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: state,
    next_directive_generation: 42L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: {
      ..@ui.default_state(),
      route: Models,
      operation_body: "{\"tenant_ref\":\"team-a\"}",
    },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: { ..@ui.default_state(), operator_authenticated: true },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
  assert_eq(console_document_title(English), "LunaNexa | Cluster Operations")
  assert_eq(
    console_document_title(ChineseSimplified),
    "LunaNexa | 集群运维",
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
    console: {
      ..@ui.default_state(),
      locale: ChineseSimplified,
      operator_authenticated: true,
    },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: { ..@ui.default_state(), locale: English },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: @ui.default_state(),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: @ui.default_state(),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: @ui.default_state(),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: {
      ..@ui.demo_state(),
      operator_authenticated: true,
      locale: ChineseSimplified,
    },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: @ui.demo_state(),
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: { ..@ui.demo_state(), route: Leases },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: { ..@ui.demo_state(), route: Nodes },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: { ..@ui.demo_state(), route: Catalog },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: {
      ..initial,
      success_message: Some("stale success"),
      error_message: Some("stale error"),
      confirmation: Some(
        @ui.confirmation_receipt(CordonNode("dgx-spark-01"), "dgx-spark-01"),
      ),
    },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: { ..@ui.demo_state(), route: ContractDocuments },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 0L,
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
    console: {
      ..@ui.default_state(),
      operator_authenticated: true,
      route: Models,
      model_imports: [downloading],
    },
    next_directive_generation: 1L,
    contract_preview_generation: 0L,
    model_import_poll_generation: 7L,
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
  assert_eq(logged_out.credential, "")
  assert_false(logged_out.console.operator_authenticated)
}
