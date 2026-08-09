///|
fn console_state(route : @ui.OperatorRoute) -> @ui.ConsoleState {
  {
    locale: English,
    route,
    overview: {
      active_nodes: 3,
      total_nodes: 4,
      active_models: 1,
      queue_depth: 2,
      alerts: 1,
      recent_changes: 4,
    },
    nodes: [
      {
        node_id: "node-1",
        state: Active,
        architecture: "nvidia-gb10",
        free_memory_mib: 80000,
        workloads: 1,
      },
    ],
    models: [
      {
        model_id: "model.text",
        version: "v1",
        state: Approved,
        license_status: "accepted",
        evaluation_status: "passed",
        compatibility: "DGX Spark",
        alias_name: "text.default",
      },
    ],
    deployments: [
      {
        assignment_id: "assignment-1",
        deployment_id: "deployment-1",
        desired: Ready,
        observed: Ready,
        placement_reason: "warm model and headroom",
      },
    ],
    catalog_templates: [],
    service_deployments: [],
    requests: { count: 10, p95_ms: 50, throughput_per_second: 4, errors: 0 },
    request_details: [
      {
        timestamp_unix_ms: 1000L,
        action: "workload.invoke",
        model_selector: "text.default",
        result: "accepted",
        receipt: "workload:1",
      },
    ],
    stream_events: [
      { sequence: 1, kind: "Chunk", text: "hello", receipt: "" },
      { sequence: 2, kind: "Completed", text: "", receipt: "workload:1" },
    ],
    benchmark_evidence: ["text-short-v1 · p95 50 ms"],
    policies: {
      quota_count: 1,
      data_class_count: 4,
      default_retention: Ephemeral,
      allowed_runtimes: ["text-runtime"],
    },
    audit: [
      {
        actor: "operator",
        decision: "promote",
        evidence: "eval-v1",
        result: "accepted",
        receipt: "receipt-1",
      },
    ],
    users: [
      {
        user_id: "user-1",
        display_name: "Ari Chen",
        email: "ari@example.test",
        state: UserActive,
        last_active: "2 minutes ago",
        grant_count: 1,
      },
      {
        user_id: "user-2",
        display_name: "Mina Rao",
        email: "mina@example.test",
        state: UserInvited,
        last_active: "Never",
        grant_count: 0,
      },
    ],
    access_grants: [
      {
        grant_id: "grant-1",
        user_id: "user-1",
        role: Developer,
        scope: "workspace/team-a",
        expires_at: "2026-08-09 12:00 UTC",
        state: GrantActive,
      },
    ],
    compute_leases: [
      {
        lease_id: "lease-1",
        user_id: "user-1",
        workspace: "research-main",
        resource: "Text generation · 2 concurrent",
        started_at: "2026-08-08 12:00 UTC",
        expires_at: "2026-08-08 18:00 UTC",
        state: Active,
      },
      {
        lease_id: "lease-2",
        user_id: "user-2",
        workspace: "research-pending",
        resource: "Text generation · 1 concurrent",
        started_at: "2026-08-09 08:00 UTC",
        expires_at: "2026-08-09 12:00 UTC",
        state: Requested,
      },
    ],
    confirmation: Some(@ui.confirmation_receipt(DrainNode("node-1"), "node-1")),
    error_message: None,
    success_message: None,
    loading: false,
    operation_name: "register-model",
    operation_body: "{}",
    quick_deployment_id: "",
    quick_template: "",
    quick_replicas: "1",
  }
}

///|
test "all operator routes render from the shared typed state" {
  for route in @ui.all_routes() {
    let html = @ui.render(console_state(route))
    assert_true(html.contains("LunaNexa Cluster Operations"))
    assert_true(html.contains("class=\"sidebar\""))
    assert_true(html.contains("class=\"workspace-topbar\""))
    assert_true(html.contains("Skip to content"))
    assert_true(html.contains("Confirm destructive operation"))
    assert_true(html.contains("aria-label=\"Primary\""))
  }
}

///|
test "catalog route exposes governed one-click deployment controls" {
  let html = @ui.render({ ..console_state(Catalog), confirmation: None })
  assert_true(html.contains("Model service catalog"))
  assert_true(html.contains("One-click model service"))
  assert_true(html.contains("Preflight enforced"))
  assert_true(html.contains("quick-deployment-id"))
  assert_true(html.contains("quick-template"))
  assert_true(html.contains("quick-replicas"))
  assert_true(html.contains("Deploy model service"))
}

///|
test "Simplified Chinese localizes catalog status counts and confirmations" {
  let intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "console:service-1:1000",
    deployment_id: "service-1",
    template: { template_id: "text-small", version: "v1" },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 86400000L,
    promote_when_ready: false,
  }
  let operation : @deployment.DeploymentOperation = {
    operation_id: "operation-1",
    deployment_id: "service-1",
    generation: 1L,
    state: RollingBack,
    plan: {
      plan_id: "plan:service-1:text-small:v1",
      intent,
      template: None,
      replicas: [],
      findings: [],
      executable: false,
      endpoint: None,
    },
    assignment_ids: ["service-1-r1"],
    endpoint: None,
    message: "operator/server-authored message",
    audit_receipt: "audit:service-1:1",
    created_unix_ms: 1000L,
    updated_unix_ms: 2000L,
  }
  let catalog = @ui.render({
    ..console_state(Catalog),
    locale: ChineseSimplified,
    service_deployments: [operation],
    confirmation: Some(
      @ui.confirmation_receipt(
        RollbackServiceDeployment("service-1"),
        "service-1",
      ),
    ),
  })
  for
    label in [
      "模型服务目录", "0 个模板", "1 个操作", "正在回滚", "模型服务操作",
    ] {
    assert_true(catalog.contains(label))
  }
  assert_true(
    catalog.contains(
      "回滚只会移除此模型服务拥有的已签名分配",
    ),
  )
  assert_true(catalog.contains("service-1"))
  assert_true(catalog.contains("audit:service-1:1"))
}

///|
test "Simplified Chinese localizes console chrome and preserves opaque data" {
  let users = @ui.render({
    ..console_state(Users),
    locale: ChineseSimplified,
    confirmation: Some(
      @ui.confirmation_receipt(
        RevokeAccessGrant("grant-1"),
        "grant-1 · user-1 · workspace/team-a",
      ),
    ),
  })
  assert_true(users.contains("LunaNexa 集群运维"))
  assert_true(users.contains("跳转到主要内容"))
  assert_true(users.contains("aria-label=\"主导航\""))
  assert_true(users.contains("用户与访问权限"))
  assert_true(users.contains("限定范围的访问授权"))
  assert_true(users.contains("已激活"))
  assert_true(users.contains("已邀请"))
  assert_true(users.contains("确认破坏性操作"))
  assert_true(
    users.contains("撤销此授权会移除其限定范围的访问权限"),
  )
  assert_true(users.contains("ari@example.test"))
  assert_true(users.contains("grant-1 · user-1 · workspace/team-a"))
  assert_true(users.contains("workspace/team-a"))
  assert_true(users.contains("value=\"zh-CN\""))
  assert_true(users.contains("min-height: 44px"))
  assert_true(users.contains("html[lang^=\"zh\"]"))
  let leases = @ui.render({
    ..console_state(Leases),
    locale: ChineseSimplified,
    confirmation: None,
  })
  assert_true(leases.contains("计算租约与工作区租约"))
  assert_true(leases.contains("文本生成 · 2 路并发"))
  assert_true(leases.contains("待审批"))
  assert_true(leases.contains("research-main"))
}

///|
test "generated labels relocalize while raw placement rationale stays untouched" {
  let english = console_state(Deployments)
  let chinese = @ui.render({
    ..english,
    locale: ChineseSimplified,
    deployments: [
      {
        ..english.deployments[0],
        placement_reason: "placement/server-note-原样",
      },
    ],
    users: [{ ..english.users[1], last_active: "Never" }],
    confirmation: None,
  })
  assert_true(chinese.contains("placement/server-note-原样"))
  let chinese_users = @ui.render({
    ..english,
    locale: ChineseSimplified,
    route: Users,
    users: [{ ..english.users[1], last_active: "Never" }],
    confirmation: None,
  })
  assert_true(chinese_users.contains("从未"))
}

///|
test "Simplified Chinese status copy follows each resource lifecycle" {
  let access = console_state(Users)
  let access_html = @ui.render({
    ..access,
    locale: ChineseSimplified,
    users: [
      { ..access.users[0], state: UserActive },
      { ..access.users[0], state: UserInvited },
      { ..access.users[0], state: UserSuspended },
      { ..access.users[0], state: UserRevoked },
    ],
    access_grants: [
      { ..access.access_grants[0], state: GrantActive },
      { ..access.access_grants[0], state: GrantExpired },
      { ..access.access_grants[0], state: GrantRevoked },
    ],
    confirmation: None,
  })
  for
    label in [
      "已激活", "已邀请", "已暂停", "已撤销", "有效", "已过期",
    ] {
    assert_true(access_html.contains(label))
  }
  let leases = console_state(Leases)
  let leases_html = @ui.render({
    ..leases,
    locale: ChineseSimplified,
    compute_leases: [
      { ..leases.compute_leases[0], state: Requested },
      { ..leases.compute_leases[0], state: Active },
      { ..leases.compute_leases[0], state: Suspended },
      { ..leases.compute_leases[0], state: Expired },
      { ..leases.compute_leases[0], state: Revoked },
    ],
    confirmation: None,
  })
  for label in ["待审批", "有效", "已暂停", "已过期", "已撤销"] {
    assert_true(leases_html.contains(label))
  }
  let nodes = console_state(Nodes)
  let nodes_html = @ui.render({
    ..nodes,
    locale: ChineseSimplified,
    nodes: [
      { ..nodes.nodes[0], state: Active },
      { ..nodes.nodes[0], state: Enrolling },
      { ..nodes.nodes[0], state: Cordoned },
      { ..nodes.nodes[0], state: Draining },
      { ..nodes.nodes[0], state: Unreachable },
      { ..nodes.nodes[0], state: Retired },
    ],
    confirmation: None,
  })
  for
    label in [
      "正常", "注册中", "已封锁调度", "正在排空", "无法访问", "已退役",
    ] {
    assert_true(nodes_html.contains(label))
  }
  let models = console_state(Models)
  let models_html = @ui.render({
    ..models,
    locale: ChineseSimplified,
    models: [
      { ..models.models[0], state: Candidate },
      { ..models.models[0], state: Verified },
      { ..models.models[0], state: Evaluated },
      { ..models.models[0], state: Approved },
      { ..models.models[0], state: Deprecated },
      { ..models.models[0], state: Revoked },
    ],
    confirmation: None,
  })
  for
    label in [
      "候选", "已验证", "已评测", "已批准", "已弃用", "已撤销",
    ] {
    assert_true(models_html.contains(label))
  }
  let deployments = console_state(Deployments)
  let deployments_html = @ui.render({
    ..deployments,
    locale: ChineseSimplified,
    deployments: [
      { ..deployments.deployments[0], observed: Pending },
      { ..deployments.deployments[0], observed: Preparing },
      { ..deployments.deployments[0], observed: Starting },
      { ..deployments.deployments[0], observed: Ready },
      { ..deployments.deployments[0], observed: Draining },
      { ..deployments.deployments[0], observed: Degraded },
      { ..deployments.deployments[0], observed: Failed },
      { ..deployments.deployments[0], observed: Stopped },
    ],
    confirmation: None,
  })
  for
    label in [
      "待处理", "准备中", "启动中", "就绪", "正在排空", "已降级",
      "失败", "已停止",
    ] {
    assert_true(deployments_html.contains(label))
  }
}

///|
test "Simplified Chinese maps known semantic codes and preserves unknown values" {
  let models = console_state(Models)
  let models_html = @ui.render({
    ..models,
    locale: ChineseSimplified,
    models: [
      {
        ..models.models[0],
        license_status: "accepted",
        evaluation_status: "passed",
        compatibility: "vendor-architecture/raw",
        alias_name: "alias.raw-v1",
      },
      {
        ..models.models[0],
        model_id: "model.missing",
        license_status: "missing",
        evaluation_status: "missing",
      },
      {
        ..models.models[0],
        model_id: "model.failed",
        license_status: "vendor-license-state",
        evaluation_status: "failed",
      },
    ],
    confirmation: None,
  })
  for
    value in [
      "许可证 · 已接受", "评测 · 已通过", "未记录", "评测 · 未通过",
    ] {
    assert_true(models_html.contains(value))
  }
  for raw in ["vendor-license-state", "vendor-architecture/raw", "alias.raw-v1"] {
    assert_true(models_html.contains(raw))
  }
  let requests = console_state(Requests)
  let request_html = @ui.render({
    ..requests,
    locale: ChineseSimplified,
    request_details: [
      { ..requests.request_details[0], result: "accepted" },
      {
        ..requests.request_details[0],
        action: "workload.vendor-action",
        result: "vendor-result",
        receipt: "receipt:opaque-2",
      },
    ],
    stream_events: [
      { sequence: 1, kind: "Chunk", text: "raw chunk", receipt: "" },
      { sequence: 2, kind: "Completed", text: "", receipt: "receipt:done" },
      { sequence: 3, kind: "Failed", text: "raw failure", receipt: "" },
      { sequence: 4, kind: "Cancelled", text: "", receipt: "" },
      {
        sequence: 5,
        kind: "VendorEvent",
        text: "raw vendor output",
        receipt: "receipt:vendor",
      },
    ],
    confirmation: None,
  })
  for value in ["已接受", "数据块", "已完成", "失败", "已取消"] {
    assert_true(request_html.contains(value))
  }
  for
    raw in [
      "workload.vendor-action", "vendor-result", "receipt:opaque-2", "VendorEvent",
      "raw vendor output", "receipt:vendor",
    ] {
    assert_true(request_html.contains(raw))
  }
  let benchmark_html = @ui.render({
    ..console_state(Benchmarks),
    locale: ChineseSimplified,
    benchmark_evidence: [
      "profile.raw · p95 50 ms · 4/s · failures 2‰ · run.raw-1",
    ],
    confirmation: None,
  })
  assert_true(benchmark_html.contains("失败率 2‰"))
  assert_true(benchmark_html.contains("profile.raw"))
  assert_true(benchmark_html.contains("run.raw-1"))
  let nodes = console_state(Nodes)
  let nodes_html = @ui.render({
    ..nodes,
    locale: ChineseSimplified,
    nodes: [
      { ..nodes.nodes[0], architecture: "unreported" },
      { ..nodes.nodes[0], architecture: "vendor-arch/raw" },
    ],
    confirmation: None,
  })
  assert_true(nodes_html.contains("未上报"))
  assert_true(nodes_html.contains("vendor-arch/raw"))
  let audit = console_state(Audit)
  let audit_html = @ui.render({
    ..audit,
    locale: ChineseSimplified,
    audit: [
      { ..audit.audit[0], result: "accepted" },
      {
        ..audit.audit[0],
        decision: "decision.raw",
        evidence: "evidence.raw",
        result: "vendor-result",
        receipt: "receipt:audit-raw",
      },
    ],
    confirmation: None,
  })
  assert_true(audit_html.contains("已接受"))
  for
    raw in [
      "decision.raw", "evidence.raw", "vendor-result", "receipt:audit-raw",
    ] {
    assert_true(audit_html.contains(raw))
  }
}

///|
test "language selector remains available through loading and error states" {
  let html = @ui.render({
    ..console_state(Overview),
    locale: ChineseSimplified,
    loading: true,
    error_message: Some("controller/raw-error"),
    confirmation: None,
  })
  assert_true(html.contains("for=\"console-locale\""))
  assert_true(html.contains("id=\"console-locale\""))
  assert_true(html.contains("正在加载当前集群状态"))
  assert_true(html.contains("无法完成此操作：controller/raw-error"))
  assert_true(html.contains("text-transform: none"))
  assert_true(html.contains(".topbar-actions { width: 100%; flex-wrap: wrap"))
}

///|
test "empty and error states remain explicit" {
  let state = console_state(Nodes)
  let html = @ui.render({ ..state, nodes: [], error_message: Some("offline") })
  assert_true(html.contains("No nodes enrolled"))
  assert_true(html.contains("Unable to complete the operation: offline"))
  assert_true(html.contains("@media (max-width: 40rem)"))
}

///|
test "overview distinguishes healthy, attention, and awaiting telemetry states" {
  let attention = @ui.render(console_state(Overview))
  let healthy = @ui.render({
    ..console_state(Overview),
    overview: { ..console_state(Overview).overview, active_nodes: 4, alerts: 0 },
    confirmation: None,
  })
  let awaiting = @ui.render({ ..@ui.default_state(), confirmation: None })
  assert_true(attention.contains("Cluster needs attention"))
  assert_true(attention.contains("Review required"))
  assert_true(healthy.contains("Cluster operational"))
  assert_true(healthy.contains("No active incidents"))
  assert_true(awaiting.contains("Awaiting cluster telemetry"))
  assert_true(awaiting.contains("Connect the controller and enroll a node"))
  assert_true(awaiting.contains("Telemetry unavailable"))
}

///|
test "users route presents identity, scope, expiry, and confirmed revoke" {
  let state = console_state(Users)
  let html = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        RevokeAccessGrant("grant-1"),
        "grant-1 · user-1 · workspace/team-a",
      ),
    ),
  })
  assert_true(html.contains("Users &amp; access"))
  assert_true(html.contains("ari@example.test"))
  assert_true(html.contains("Developer"))
  assert_true(html.contains("workspace/team-a"))
  assert_true(html.contains("2026-08-09 12:00 UTC"))
  assert_true(html.contains("Revoke…"))
  assert_true(html.contains("Activate user user-2"))
  assert_true(html.contains("Suspend user user-1"))
  assert_true(html.contains("Revoke user user-1"))
  assert_true(html.contains("Revoking this grant removes its scoped access"))
  assert_true(html.contains("grant-1 · user-1 · workspace/team-a"))
}

///|
test "leases route keeps owner, resource, status, expiry, and action together" {
  let state = console_state(Leases)
  let html = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        EndComputeLease("lease-1"),
        "lease-1 · user-1 · text generation",
      ),
    ),
  })
  assert_true(html.contains("Compute &amp; workspace leases"))
  assert_true(html.contains("research-main"))
  assert_true(html.contains("Text generation · 2 concurrent"))
  assert_true(html.contains("Expires 2026-08-08 18:00 UTC"))
  assert_true(html.contains("End lease…"))
  assert_true(html.contains("Activate lease lease-2"))
  assert_true(html.contains("Running work may be interrupted"))
  assert_true(html.contains("overflow-x: auto"))
}

///|
test "user suspension and revocation require scoped confirmations" {
  let state = console_state(Users)
  let suspended = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        SuspendUser("user-1"),
        "user-1 · Ari Chen · ari@example.test",
      ),
    ),
  })
  let revoked = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        RevokeUser("user-1"),
        "user-1 · Ari Chen · ari@example.test",
      ),
    ),
  })
  assert_true(suspended.contains("Suspending this identity"))
  assert_true(revoked.contains("Revoking this identity is terminal"))
  assert_true(revoked.contains("user-1 · Ari Chen · ari@example.test"))
}

///|
test "management routes render explicit empty states" {
  let state = console_state(Users)
  let users_html = @ui.render({
    ..state,
    users: [],
    access_grants: [],
    confirmation: None,
  })
  let leases_html = @ui.render({
    ..state,
    route: Leases,
    compute_leases: [],
    confirmation: None,
  })
  assert_true(users_html.contains("No user identities are available"))
  assert_true(users_html.contains("No access grants are available"))
  assert_true(leases_html.contains("No compute or workspace leases are active"))
}

///|
test "policies route exposes keyboard-accessible typed operations" {
  let html = @ui.render(console_state(Policies))
  assert_true(html.contains("Typed operator operation"))
  assert_true(html.contains("operation-name"))
  assert_true(html.contains("operation-body"))
  assert_true(html.contains("Publish assignment for controller signing"))
  assert_true(html.contains("Validate and submit"))
}

///|
test "requests route renders bounded payload-free receipt detail" {
  let html = @ui.render(console_state(Requests))
  assert_true(html.contains("workload.invoke"))
  assert_true(html.contains("text.default"))
  assert_true(html.contains("workload:1"))
  assert_true(html.contains("excludes raw payloads"))
  assert_true(html.contains("Latest live stream"))
  assert_true(html.contains("hello"))
}

///|
test "UI-to-UI operator flow uses contract lifecycle states" {
  let commands = [
    @ui.OperatorCommand::EnrollNode,
    RegisterModel,
    VerifyModel,
    EvaluateModel,
    ApproveModel,
    DeployModel,
    MarkReady,
    InvokeRequest,
    CompleteRequest,
    DrainNode,
    ObserveReroute,
    RollbackModel,
  ]
  let mut workflow = @ui.OperatorWorkflow::initial()
  for command in commands {
    workflow = workflow.apply(command)
  }
  assert_eq(workflow.node_state, Draining)
  assert_eq(workflow.model_state, Approved)
  assert_eq(workflow.workload_state, Succeeded)
  assert_true(workflow.rerouted)
  assert_eq(workflow.receipts.length(), 12)
}
