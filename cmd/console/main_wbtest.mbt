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
        quick_replicas: "1",
      },
      1000L,
    )
    is None,
  )
  let ready : @ui.ConsoleState = {
    ..@ui.demo_state(),
    quick_deployment_id: "service-1",
    quick_replicas: "1",
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
  for replicas in ["", "0", "-1", "65", "1e2", "1.5", "NaN", "∞"] {
    assert_true(
      quick_deployment_intent(
        { ..base, quick_deployment_id: "service-1", quick_replicas: replicas },
        1L,
      )
      is None,
    )
  }
  for replicas in ["1", "2", "64"] {
    assert_true(
      quick_deployment_intent(
        { ..base, quick_deployment_id: "service-1", quick_replicas: replicas },
        1L,
      )
      is Some(_),
    )
  }
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
    inference_credential: "inference-secret",
    inference_subject_ref: "subject:opaque-1",
    commercial_organization: "org-1",
    demo_mode: false,
    console: state,
    next_directive_generation: 42L,
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
    operation_name: "set-quota",
    operation_body: "{\"tenant_ref\":\"team-a\"}",
    quick_deployment_id: "service-1",
    quick_template: "text-small@v1",
    quick_replicas: "2",
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
  assert_eq(merged.operation_name, "set-quota")
  assert_eq(merged.operation_body, "{\"tenant_ref\":\"team-a\"}")
  assert_eq(merged.quick_deployment_id, "service-1")
  assert_eq(merged.quick_template, "text-small@v1")
  assert_eq(merged.quick_replicas, "2")
  assert_eq(merged.success_message, Some("配置已提交。"))
  assert_eq(merged.overview.total_nodes, 2)
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
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: false,
    console: { ..@ui.default_state(), locale: ChineseSimplified },
    next_directive_generation: 1L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  for
    value in [
      "控制器连接", "需要凭据", "运维令牌", "审计令牌", "推理令牌（可选）",
      "商业组织（可选）", "不透明主体引用（可选）", "凭据仅保存在浏览器内存中",
      "连接并刷新",
    ] {
    assert_true(html.contains(value))
  }
  assert_true(html.contains("https://controller.example.test"))
}

///|
#warnings("-alert_unstable")
test "demo mode presents a read-only cluster snapshot" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    console: @ui.demo_state(),
    next_directive_generation: 1L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let html = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(app_view(model, emit))
  })
  assert_true(html.contains("Read-only demo snapshot"))
  assert_true(html.contains("4/4 machines running"))
}

///|
test "demo mode exercises one-click preflight without controller mutation" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    credential: "",
    audit_credential: "",
    inference_credential: "",
    inference_subject_ref: "",
    commercial_organization: "",
    demo_mode: true,
    console: { ..@ui.demo_state(), route: Catalog },
    next_directive_generation: 1L,
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
  assert_eq(submitted.console.service_deployments.length(), 0)
}
