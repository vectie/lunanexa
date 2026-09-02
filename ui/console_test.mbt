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
        total_memory_mib: 122880,
        free_memory_mib: 80000,
        used_memory_mib: 42880,
        utilization_per_mille: 420,
        temperature_celsius: 47,
        power_watts: 78,
        workloads: 1,
        lease_holder: "org-1 · user-1",
        active_assignment: "deployment-1",
        last_seen: "Just now",
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
    notifications: [
      {
        notification_id: "alert-node-1",
        code: "NodeUnreachable",
        severity: Critical,
        lifecycle: Unread,
        topic: ClusterHealth,
        created_unix_ms: 1786200000000L,
        generation: 1L,
        node_ref: "node-1",
        assigned_to: "",
        silenced_until_unix_ms: None,
      },
    ],
    notification_deliveries: [
      {
        delivery_id: "delivery-alert-node-1-email",
        notification_id: "alert-node-1",
        channel: Email,
        state: DeadLetter,
        attempt_count: 5,
        updated_unix_ms: 1786200300000L,
        last_error_code: "ProviderUnavailable",
      },
    ],
    accounts: [
      {
        account_id: "account-operator",
        subject_ref: "subject-operator",
        identity_issuer: "https://identity.example.test",
        display_name: "Ari Chen",
        email: "ari@example.test",
        identity_receipt: "identity:receipt:1",
        roles: [PlatformOperator, AuditReader],
        state: Active,
        created_unix_ms: 1786200000000L,
        updated_unix_ms: 1786200300000L,
      },
    ],
    authenticated_account: Some({
      account_id: "account-operator",
      subject_ref: "subject-operator",
      identity_issuer: "https://identity.example.test",
      display_name: "Ari Chen",
      email: "ari@example.test",
      identity_receipt: "identity:receipt:1",
      roles: [PlatformOperator, AuditReader],
      state: Active,
      created_unix_ms: 1786200000000L,
      updated_unix_ms: 1786200300000L,
    }),
    account_sessions: [
      {
        session_id: "session-current",
        account_id: "account-operator",
        created_unix_ms: 1786200000000L,
        expires_unix_ms: 1786240000000L,
        last_used_unix_ms: 1786200300000L,
        revoked_unix_ms: None,
      },
    ],
    account_invite: {
      account_id: "",
      subject_ref: "",
      identity_issuer: "",
      identity_subject: "",
      display_name: "",
      email: "",
      identity_receipt: "",
      roles: [EnterpriseUser],
    },
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
    exclusive_node_leases: [
      {
        lease_id: "exclusive-lease-1",
        node_id: "node-1",
        subject_ref: "subject-1",
        unix_username: "alice",
        expires_at: "2026-08-09 18:00 UTC",
        state: "Active",
        generation: 4L,
      },
    ],
    cost_centers: [
      {
        cost_center_id: "cc-1",
        organization_id: "org-1",
        display_name: "Research",
        parent_cost_center_id: "—",
        project_count: 2,
        provisional_spend: "CNY 100.00",
        budget_posture: "Within budget",
      },
    ],
    agreements: [
      {
        agreement_id: "agreement-1",
        agreement_type: "Data processing",
        template_version: "dpa-v1",
        organization_id: "org-1",
        state: "Executed",
        evidence_receipt: "evidence:agreement:1",
      },
    ],
    enterprise_lease_requests: [
      {
        request_id: "request-1",
        organization_id: "org-1",
        subject_ref: "subject-1",
        project_id: "project-1",
        unix_username: "alice",
        requested_models: "model.text",
        state: "Submitted",
        generation: 1L,
        assigned_node_id: "—",
      },
    ],
    portal_node_id: "node-1",
    qualified_services: [
      {
        provider: "LunaFide",
        capability: "Identity · signature · payment · invoice",
        environment: "TestOnly",
        state: "Available",
        evidence_policy: "Tenant-bound callbacks",
        production_ready: false,
      },
    ],
    offline_commerce: @offline_commerce.default_state(English, OperatorCommerce),
    contract_documents: @contract_documents.default_state(
      @i18n.default_locale(),
      actor_owner=ManagerOperator,
    ),
    production_readiness: {
      ready: false,
      loading: false,
      blocker_codes: ["ExternalObservabilityNotReady"],
      error: None,
    },
    confirmation: Some(@ui.confirmation_receipt(DrainNode("node-1"), "node-1")),
    error_message: None,
    success_message: None,
    loading: false,
    operator_authenticated: true,
    model_source_query: "MiniCPM",
    model_source_results: [],
    model_source_total: 0L,
    model_imports: [],
    operation_name: "register-model",
    operation_body: "{}",
    quick_deployment_id: "",
    quick_template: "",
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
test "operator offline commerce route is actionable and bilingual" {
  let demo = @ui.demo_state()
  let english = @ui.render({ ..demo, route: OfflineCommerce })
  assert_true(english.contains("Offline reconciliation desk"))
  assert_true(english.contains("Accept exact digest"))
  let chinese = @ui.render({
    ..demo,
    route: OfflineCommerce,
    locale: ChineseSimplified,
  })
  assert_eq(demo.offline_commerce.locale, English)
  assert_true(chinese.contains("线下材料核验台"))
  assert_true(chinese.contains("接受此文件摘要"))
}

///|
test "commercial and qualified-service routes expose bounded evidence" {
  let base = console_state(CostCenters)
  let cost_centers = @ui.render(base)
  assert_true(cost_centers.contains("Cost center governance"))
  assert_true(cost_centers.contains("cc-1"))
  assert_true(cost_centers.contains("CNY 100.00"))
  let agreements = @ui.render({ ..base, route: Agreements })
  assert_true(agreements.contains("Digital agreement lifecycle"))
  assert_true(agreements.contains("agreement-1"))
  assert_true(agreements.contains("evidence:agreement:1"))
  assert_true(agreements.contains("Enterprise lease requests"))
  assert_true(agreements.contains("request-1"))
  assert_true(agreements.contains("portal-node-id"))
  assert_true(agreements.contains("Approve"))
  assert_true(agreements.contains("Reject"))
  let qualified = @ui.render({ ..base, route: QualifiedServices })
  assert_true(qualified.contains("LunaFide"))
  assert_true(qualified.contains("TestOnly"))
  assert_true(qualified.contains("Not ready"))
  assert_true(qualified.contains("not a qualified trust service"))
}

///|
test "alerts route localizes durable incident state and actions" {
  let state = console_state(Alerts)
  let english = @ui.render(state)
  assert_true(english.contains("Operator alert center"))
  assert_true(english.contains("Node heartbeat is stale"))
  assert_true(english.contains("Acknowledge"))
  assert_true(english.contains("Silence 1h"))
  assert_true(english.contains("Resolve"))
  assert_true(english.contains("Delivery outbox"))
  assert_true(english.contains("delivery-alert-node-1-email"))
  assert_true(english.contains("Dead letter"))
  assert_true(english.contains("Redrive"))
  assert_false(english.contains("recipient"))
  let chinese = @ui.render({ ..state, locale: ChineseSimplified })
  assert_true(chinese.contains("运维告警中心"))
  assert_true(chinese.contains("节点心跳已超时"))
  assert_true(chinese.contains("静默 1 小时"))
  assert_true(chinese.contains("通知投递队列"))
  assert_true(chinese.contains("死信"))
  assert_true(chinese.contains("重新投递"))
  assert_true(chinese.contains("投递供应商不可用"))
}

///|
test "dead-letter redrive confirmation carries the delivery generation" {
  let state = console_state(Alerts)
  let confirmation = @ui.confirmation_receipt(
    RedriveNotificationDelivery(
      "delivery-alert-node-1-email", 5, 1786200300000L,
    ),
    "delivery-alert-node-1-email · attempt 5 · generation 1786200300000",
  )
  let english = @ui.render({ ..state, confirmation: Some(confirmation) })
  assert_true(english.contains("Confirm delivery redrive"))
  assert_true(english.contains("attempt count 5"))
  assert_true(english.contains("1786200300000"))
  assert_true(english.contains("Confirm redrive"))
  let chinese = @ui.render({
    ..state,
    locale: ChineseSimplified,
    confirmation: Some(confirmation),
  })
  assert_true(chinese.contains("确认重新投递"))
  assert_true(chinese.contains("尝试次数仍为 5"))
}

///|
test "Chinese agreement governance localizes known semantic codes" {
  let html = @ui.render({
    ..console_state(Agreements),
    locale: ChineseSimplified,
    confirmation: None,
  })
  assert_true(html.contains("数据处理"))
  assert_true(html.contains("已执行"))
  assert_true(html.contains("待运维审核"))
  assert_false(html.contains(">Data processing<"))
  assert_false(html.contains(">Submitted<"))
}

///|
test "typed operation surface exposes commercial and technical commands" {
  let html = @ui.render({ ..console_state(Policies), confirmation: None })
  assert_true(html.contains("Create organization"))
  assert_true(html.contains("Create cost center"))
  assert_true(html.contains("Register agreement template"))
  assert_true(html.contains("Register external evidence"))
  assert_true(html.contains("Create enterprise membership"))
  assert_true(html.contains("Publish portal agreement"))
  assert_false(html.contains("Evaluate autoscaling"))
  assert_true(html.contains("Validate transfer grant"))
}

///|
test "commercial rows escape adversarial tenant and provider values" {
  let hostile = "<img src=x onerror=alert(1)>"
  let base = console_state(CostCenters)
  let cost_centers = @ui.render({
    ..base,
    cost_centers: [{ ..base.cost_centers[0], display_name: hostile }],
  })
  assert_false(cost_centers.contains(hostile))
  assert_true(cost_centers.contains("&lt;img"))
  let qualified = @ui.render({
    ..base,
    route: QualifiedServices,
    qualified_services: [{ ..base.qualified_services[0], provider: hostile }],
  })
  assert_false(qualified.contains(hostile))
  assert_true(qualified.contains("&lt;img"))
}

///|
test "demo snapshot presents the four-node nine-model fleet" {
  let state = @ui.demo_state()
  assert_eq(state.overview.active_nodes, 4)
  assert_eq(state.overview.total_nodes, 4)
  assert_eq(state.overview.active_models, 9)
  assert_eq(state.nodes.length(), 4)
  assert_eq(state.models.length(), 9)
  assert_eq(state.catalog_templates.length(), 1)
  let overview = @ui.render(state)
  assert_true(overview.contains("4 of 4"))
  assert_true(overview.contains("9"))
  assert_true(overview.contains("Ready for one-click deployment"))
  assert_true(overview.contains("Open one-click deployment"))
  let nodes = @ui.render({ ..state, route: Nodes })
  assert_true(nodes.contains("dgx-spark-04"))
  let models = @ui.render({ ..state, route: Models })
  assert_true(models.contains("lunanexa.speech.transcribe"))
}

///|
test "node management exposes expandable telemetry and exclusive lease evidence" {
  let state = console_state(Nodes)
  let html = @ui.render({ ..state, confirmation: None })
  assert_true(html.contains("Cluster topology"))
  assert_true(html.contains("Operator access"))
  assert_true(html.contains("Management plane"))
  assert_true(html.contains("Compute plane"))
  assert_true(html.contains("class=\"topology-graph\""))
  assert_true(html.contains("class=\"graph-edge graph-edge-https\""))
  assert_true(html.contains("mTLS + heartbeat"))
  assert_true(html.contains("PostgreSQL"))
  assert_true(html.contains("Model storage"))
  assert_true(html.contains("Management plane ↔ Compute nodes"))
  assert_true(html.contains("node-1"))
  assert_true(html.contains("class=\"node-record\""))
  assert_true(html.contains("Resource telemetry"))
  assert_true(html.contains("GPU utilization"))
  assert_true(html.contains("42%"))
  assert_true(html.contains("org-1 · user-1"))
  assert_true(html.contains("One lease · one machine"))
  assert_true(html.contains("Last heartbeat · Just now"))
  assert_true(html.contains("<progress"))
}

///|
test "node topology states missing compute links without inventing a healthy fleet" {
  let state = console_state(Nodes)
  let html = @ui.render({
    ..state,
    nodes: [],
    overview: { ..state.overview, active_nodes: 0, total_nodes: 0 },
    confirmation: None,
  })
  assert_true(html.contains("Cluster topology"))
  assert_true(html.contains("No compute link established"))
  assert_true(html.contains("Enrollment required"))
  assert_true(html.contains("No nodes enrolled"))
  assert_true(html.contains(">0</strong>"))
  assert_true(html.contains(" compute nodes"))
  assert_false(html.contains("node-1"))
}

///|
test "node topology is fully localized in Chinese" {
  let state = console_state(Nodes)
  let html = @ui.render({
    ..state,
    locale: ChineseSimplified,
    confirmation: None,
  })
  for
    label in [
      "集群拓扑", "运维访问", "管理平面", "计算平面", "连接清单与信任边界",
    ] {
    assert_true(html.contains(label))
  }
  assert_false(html.contains(">Cluster topology<"))
}

///|
test "node detail escapes hostile lease and assignment evidence" {
  let state = console_state(Nodes)
  let hostile = "<img src=x onerror=alert(1)>"
  let html = @ui.render({
    ..state,
    nodes: [
      { ..state.nodes[0], lease_holder: hostile, active_assignment: hostile },
    ],
    confirmation: None,
  })
  assert_false(html.contains(hostile))
  assert_false(html.contains("<img"))
  assert_true(html.contains("&lt;img"))
}

///|
test "catalog route exposes governed one-click deployment controls" {
  let html = @ui.render({ ..console_state(Catalog), confirmation: None })
  assert_true(html.contains("Model service catalog"))
  assert_true(html.contains("One-click model service"))
  assert_true(html.contains("Preflight enforced"))
  assert_true(html.contains("Select approved template"))
  assert_true(html.contains("Preflight and deploy"))
  assert_true(html.contains("quick-deployment-id"))
  assert_true(html.contains("quick-template"))
  assert_true(html.contains("One service · one assigned machine"))
  assert_false(html.contains("quick-replicas"))
  assert_true(html.contains("Deploy model service"))
}

///|
test "demo snapshot covers operational routes with representative records" {
  let state = @ui.demo_state()
  assert_eq(state.nodes.length(), 4)
  assert_eq(state.models.length(), 9)
  assert_true(state.deployments.length() > 0)
  assert_true(state.service_deployments.length() > 0)
  assert_true(state.request_details.length() > 0)
  assert_true(state.stream_events.length() > 0)
  assert_true(state.users.length() > 0)
  assert_true(state.access_grants.length() > 0)
  assert_true(state.compute_leases.length() > 0)
}

///|
test "catalog escapes adversarial operator and template text" {
  let demo = @ui.demo_state()
  let hostile = "<img src=x onerror=alert(1)>"
  let html = @ui.render({
    ..demo,
    route: Catalog,
    quick_deployment_id: hostile,
    catalog_templates: [{ ..demo.catalog_templates[0], display_name: hostile }],
  })
  assert_false(html.contains(hostile))
  assert_false(html.contains("<img"))
  assert_false(html.contains("onerror=alert(1)>"))
  assert_true(html.contains("&lt;img"))
}

///|
test "one-click form blocks hostile names and fixes capacity to one machine" {
  let demo = @ui.demo_state()
  let hostile_name = @ui.render({
    ..demo,
    route: Catalog,
    quick_deployment_id: "<script>alert(1)</script>",
  })
  assert_true(hostile_name.contains("aria-invalid=\"true\""))
  assert_true(hostile_name.contains("field-help field-error"))
  assert_true(hostile_name.contains("disabled"))
  let valid = @ui.render({
    ..demo,
    route: Catalog,
    quick_deployment_id: "valid-service",
  })
  assert_true(valid.contains("aria-invalid=\"false\""))
  assert_true(valid.contains("Capacity is fixed."))
  assert_false(valid.contains("type=\"number\""))
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
  assert_true(benchmark_html.contains("failures 2‰"))
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
  assert_true(html.contains("Open enrollment policy"))
  let deployments = @ui.render({
    ..console_state(Deployments),
    deployments: [],
    confirmation: None,
  })
  assert_true(deployments.contains("Open one-click deployment"))
  assert_true(deployments.contains("exactly one eligible machine"))
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
test "authoritative readiness blockers disable launch and render bilingually" {
  let base = @ui.demo_state()
  let blocked = @ui.render({
    ..base,
    production_readiness: {
      ready: false,
      loading: false,
      blocker_codes: [
        "GuideDiagnosticsUnavailable", "ExclusiveLeaseExpiryReconcilerUnavailable",
      ],
      error: None,
    },
  })
  assert_true(blocked.contains("Deployment prerequisites remain"))
  assert_true(blocked.contains("Guide diagnostics"))
  assert_true(blocked.contains("Lease expiry controller"))
  assert_true(blocked.contains("disabled"))
  let chinese = @ui.render({
    ..base,
    locale: ChineseSimplified,
    production_readiness: {
      ready: false,
      loading: false,
      blocker_codes: ["ExternalObservabilityNotReady"],
      error: None,
    },
  })
  assert_true(chinese.contains("外部可观测性导出"))
  assert_true(chinese.contains("仍有部署前提未满足"))
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
test "users route manages external accounts without exposing identity digests or secrets" {
  let state = console_state(Users)
  let html = @ui.render(state)
  assert_true(html.contains("Signed-in account"))
  assert_true(html.contains("External identity mappings"))
  assert_true(html.contains("Invite an external identity"))
  assert_true(html.contains("account-provider-subject"))
  assert_true(html.contains("type=\"password\""))
  assert_true(html.contains("Platform operator"))
  assert_true(html.contains("Audit reader"))
  assert_true(html.contains("aria-pressed=\"true\""))
  assert_true(html.contains("session-current"))
  assert_false(html.contains("identity_subject_sha256"))
  assert_false(html.contains("secret_sha256"))
  assert_false(html.contains("session_token"))
}

///|
test "account lifecycle and role changes require scoped typed confirmations" {
  let state = console_state(Users)
  let activate = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        ActivateAccount("account-operator"),
        "account-operator · Ari Chen · ari@example.test",
      ),
    ),
  })
  assert_true(activate.contains("Confirm account change"))
  assert_true(
    activate.contains("external identity to exchange a fresh browser session"),
  )
  let roles = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        SetAccountRoles("account-operator", [AuditReader]),
        "account-operator · Ari Chen · ari@example.test",
      ),
    ),
  })
  assert_true(roles.contains("replaces the account"))
  assert_true(roles.contains("LunaNexa roles"))
  assert_true(roles.contains("Audit reader"))
  let revoked = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        RevokeAccount("account-operator"),
        "account-operator · Ari Chen · ari@example.test",
      ),
    ),
  })
  assert_true(revoked.contains("terminal"))
  assert_true(revoked.contains("revokes every browser session"))
}

///|
test "account role controls preserve one typed role and responsive access" {
  assert_eq(@ui.account_roles_after_toggle([EnterpriseUser], EnterpriseUser), [
    EnterpriseUser,
  ])
  assert_eq(
    @ui.account_roles_after_toggle(
      [PlatformOperator, AuditReader],
      PlatformOperator,
    ),
    [AuditReader],
  )
  let html = @ui.render(console_state(Users))
  assert_true(html.contains("min-height: 44px"))
  assert_true(
    html.contains(".account-invite-grid { grid-template-columns: 1fr; }"),
  )
  assert_true(
    html.contains(".account-table .resource-table { min-width: 66rem; }"),
  )
  assert_true(html.contains("prefers-reduced-motion: reduce"))
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
  assert_true(html.contains("Lease operations"))
  assert_true(html.contains("Fail-closed cleanup boundary"))
  assert_true(html.contains("Exclusive machine leases"))
  assert_true(html.contains("exclusive-lease-1"))
  assert_true(html.contains("Terminate &amp; clean…"))
  assert_true(html.contains("research-main"))
  assert_true(html.contains("Text generation · 2 concurrent"))
  assert_true(html.contains("Expires 2026-08-08 18:00 UTC"))
  assert_true(html.contains("End lease…"))
  assert_true(html.contains("Activate lease lease-2"))
  assert_true(html.contains("Running work may be interrupted"))
  assert_true(html.contains("overflow-x: auto"))
}

///|
test "exclusive lease termination confirmation explains cleanup quarantine" {
  let state = console_state(Leases)
  let html = @ui.render({
    ..state,
    confirmation: Some(
      @ui.confirmation_receipt(
        TerminateExclusiveNodeLease("exclusive-lease-1", 4L),
        "exclusive-lease-1 · node-1 · alice · generation 4",
      ),
    ),
  })
  assert_true(html.contains("immediately revokes"))
  assert_true(html.contains("interrupts all tenant processes"))
  assert_true(html.contains("any failure quarantines it"))
  assert_true(html.contains("generation 4"))
}

///|
test "exclusive lease table escapes hostile identity and node text" {
  let base = console_state(Leases)
  let hostile = "<img src=x onerror=alert(1)>"
  let html = @ui.render({
    ..base,
    exclusive_node_leases: [
      {
        ..base.exclusive_node_leases[0],
        subject_ref: hostile,
        node_id: hostile,
      },
    ],
  })
  assert_false(html.contains(hostile))
  assert_true(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
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
test "models route exposes ModelScope browse and import workflow" {
  let html = @ui.render(console_state(Models))
  assert_true(html.contains("Find and import a model"))
  assert_true(html.contains("model-source-query"))
  assert_true(html.contains("Search ModelScope"))
  assert_false(html.contains("Candidate registration manifest (JSON)"))
}

///|
test "model source search stays disabled until operator authentication succeeds" {
  let disconnected = @ui.render({
    ..console_state(Models),
    operator_authenticated: false,
  })
  let connected = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
  })
  assert_true(
    disconnected.contains(
      "Sign in with operator authority to browse and import models.",
    ),
  )
  assert_true(disconnected.contains("disabled"))
  assert_true(
    connected.contains(
      "Downloads are durable; checksum verification is not signature approval.",
    ),
  )
}

///|
test "failed model import exposes an operator retry action" {
  let failed : ModelImportRow = {
    import_id: "ms-failed-1",
    source: "modelscope",
    model_id: "OpenBMB/MiniCPM5-1B",
    revision: "master",
    state: Failed,
    files_total: 11,
    files_completed: 3,
    bytes_total: 2171355326L,
    bytes_completed: 67108864L,
    manifest_digest: "",
    artifact_uri: "",
    license: "apache-2.0",
    error_code: "upstream-rejected",
    cancel_requested: false,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
  }
  let candidate : ModelSourceCatalogRow = {
    id: failed.model_id,
    display_name: "MiniCPM5-1B",
    description: "small model",
    downloads: 1L,
    likes: 1L,
    license: failed.license,
    tasks: ["text-generation"],
    created_at: "",
    last_modified: "",
    file_size: failed.bytes_total,
    params: 1080632832L,
    tags: [],
    private: false,
    gated: false,
  }
  let html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    model_source_results: [candidate],
    model_imports: [failed],
  })
  assert_true(html.contains("upstream-rejected"))
  assert_true(html.contains(">Retry</button>"))
  let verified_html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    model_source_results: [candidate],
    model_imports: [
      {
        ..failed,
        state: Verified,
        files_completed: failed.files_total,
        bytes_completed: failed.bytes_total,
        manifest_digest: "sha256:0123456789abcdef",
        artifact_uri: "modelstore://modelscope/ms-failed-1",
        error_code: "",
      },
    ],
  })
  assert_true(
    verified_html.contains("Passed · ModelScope file sizes and SHA-256"),
  )
  assert_true(
    verified_html.contains("Pending · Deployable package and signature"),
  )
  assert_true(verified_html.contains("Approve for users"))
  assert_true(verified_html.contains("disabled"))
}

///|
test "empty model registry points to governed ModelScope onboarding" {
  let html = @ui.render({ ..console_state(Models), models: [] })
  assert_true(html.contains("No models registered yet"))
  assert_true(html.contains("Search ModelScope above and start a download"))
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
