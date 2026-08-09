///|
test "console validates only optional opaque loopback subjects" {
  assert_true(optional_subject_is_valid(""))
  assert_true(optional_subject_is_valid("subject:opaque-01"))
  assert_true(optional_subject_is_valid("  mtls:sha256:abc123  "))
  assert_false(optional_subject_is_valid("subject with spaces"))
  assert_false(optional_subject_is_valid("../../subject"))
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
      "不透明主体引用（可选）", "凭据仅保存在浏览器内存中",
      "连接并刷新",
    ] {
    assert_true(html.contains(value))
  }
  assert_true(html.contains("https://controller.example.test"))
}
