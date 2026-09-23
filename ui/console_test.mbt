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
    storage_nodes: [],
    nodes: [
      {
        node_id: "node-1",
        state: Active,
        architecture: "nvidia-gb10",
        total_memory_mib: 122880,
        free_memory_mib: 80000,
        used_memory_mib: 42880,
        memory_measured: true,
        utilization_per_mille: 420,
        cpu_per_mille: 250,
        cpu_measured: true,
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
        license_id: "license.model.text",
        artifact_uri: "modelstore://model.text/v1",
        artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
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
    service_deployments: [],
    requests: { count: 10, p95_ms: 50, throughput_per_second: 4, errors: 0, },
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
      { sequence: 1, kind: "Chunk", text: "hello", receipt: "", },
      { sequence: 2, kind: "Completed", text: "", receipt: "workload:1", },
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
    trial_summary: None,
    announcement_draft: @ui.empty_announcement_draft(),
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
    access_package_draft: {
      identity_issuer: "https://identity.example.test",
      identity_subject: "",
      display_name: "",
      email: "",
      organization_id: "org-1",
      tenant_ref: "tenant-1",
      lifetime_days: 30,
      identity_verified: false,
    },
    access_packages: [],
    pending_organizations: [],
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
    resource_delivery: @ui.default_resource_delivery_panel(),
    compute_leases: [
      {
        lease_id: "lease-1",
        user_id: "user-1",
        subject_ref: "subject-1",
        workspace: "research-main",
        resource: "Text generation · 2 concurrent",
        started_at: "2026-08-08 12:00 UTC",
        expires_at: "2026-08-08 18:00 UTC",
        state: Active,
      },
      {
        lease_id: "lease-2",
        user_id: "user-2",
        subject_ref: "subject-2",
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
    model_adoption_draft: {
      import_id: "",
      model_id: "",
      version: "",
      license_id: "",
      compatible_architectures: "",
      minimum_memory_mib: "",
    },
    model_adopted_imports: [],
    model_local_directories: [],
    model_local_draft: { directory: "", repository: "", revision: "master", },
    model_license_draft: @ui.empty_model_license_draft(),
    model_alias_draft: @ui.empty_model_alias_draft(),
    runtime_draft: @ui.default_runtime_draft(),
    template_draft: @ui.empty_template_draft(),
    operation_name: "register-model",
    operation_body: "{}",
    quick_deployment_id: "",
    quick_template: "",
    quick_topology: SingleMachine,
  }
}

///|
test "all operator routes render from the shared typed state" {
  for route in @ui.all_routes() {
    let html = @ui.render(console_state(route))
    assert_true(
      html.contains("能源谷“创未来”生态街区 Cluster Operations"),
    )
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
  let english = @ui.render({ ..demo, route: OfflineCommerce, })
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
  let agreements = @ui.render({ ..base, route: Agreements, })
  assert_true(agreements.contains("Digital agreement lifecycle"))
  assert_true(agreements.contains("agreement-1"))
  assert_true(agreements.contains("evidence:agreement:1"))
  assert_true(agreements.contains("Enterprise lease requests"))
  assert_true(agreements.contains("request-1"))
  assert_true(agreements.contains("portal-node-id"))
  assert_true(agreements.contains("Approve"))
  assert_true(agreements.contains("Reject"))
  let qualified = @ui.render({ ..base, route: QualifiedServices, })
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
  let chinese = @ui.render({ ..state, locale: ChineseSimplified, })
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
  let english = @ui.render({ ..state, confirmation: Some(confirmation), })
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
  let html = @ui.render({ ..console_state(Policies), confirmation: None, })
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
    cost_centers: [{ ..base.cost_centers[0], display_name: hostile, }],
  })
  assert_false(cost_centers.contains(hostile))
  assert_true(cost_centers.contains("&lt;img"))
  let qualified = @ui.render({
    ..base,
    route: QualifiedServices,
    qualified_services: [{ ..base.qualified_services[0], provider: hostile, }],
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
  assert_true(overview.contains("Choose a service template"))
  assert_true(overview.contains("Open service catalog"))
  assert_false(overview.contains("Ready for one-click deployment"))
  let nodes = @ui.render({ ..state, route: Nodes, })
  assert_true(nodes.contains("dgx-spark-04"))
  let models = @ui.render({ ..state, route: Models, })
  assert_true(models.contains("lunanexa.speech.transcribe"))
}

///|
test "node management exposes expandable telemetry and exclusive lease evidence" {
  let state = console_state(Nodes)
  let html = @ui.render({ ..state, confirmation: None, })
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
  assert_true(html.contains("CPU utilization"))
  assert_true(html.contains("25%"))
  assert_true(html.contains("available ·"))
  assert_true(html.contains("org-1 · user-1"))
  assert_false(html.contains("One lease · one machine"))
  assert_false(html.contains("Placement model"))
  assert_true(html.contains("Last heartbeat · Just now"))
  assert_true(html.contains("<progress"))
}

///|
test "Spark unified memory and fractional sensors are rendered without inventing VRAM" {
  let state = console_state(Nodes)
  let node = {
    ..state.nodes[0],
    architecture: "nvidia-sm121",
    total_memory_mib: 124608,
    used_memory_mib: 110788,
    free_memory_mib: 13820,
    cpu_per_mille: 3,
    power_watts: 11.46,
  }
  let html = @ui.render({ ..state, nodes: [node], confirmation: None, })
  assert_true(html.contains("Unified memory"))
  assert_true(html.contains("121.7 GiB"))
  assert_true(html.contains("13.5 GiB"))
  assert_true(html.contains("CPU/GPU shared pool"))
  assert_true(html.contains("0.3%"))
  assert_true(html.contains("11.46 W"))
  assert_false(html.contains("N/A"))
  let missing = @ui.render({
    ..state,
    nodes: [
      {
        ..node,
        utilization_per_mille: -1,
        temperature_celsius: -1,
        power_watts: -1.0,
      },
    ],
    confirmation: None,
  })
  assert_true(missing.contains("Unavailable / stale"))
  assert_false(missing.contains("-1 °C"))
  assert_false(missing.contains("-1 W"))
}

///|
test "node telemetry says not reported instead of printing an unmeasured zero" {
  let state = console_state(Nodes)
  let unmeasured = {
    ..state.nodes[0],
    free_memory_mib: 122880,
    used_memory_mib: 0,
    memory_measured: false,
    cpu_per_mille: 0,
    cpu_measured: false,
  }
  let html = @ui.render({ ..state, nodes: [unmeasured], confirmation: None, })
  assert_true(html.contains("Not reported"))
  assert_true(html.contains("no memory sample reported"))
  assert_true(html.contains("no memory measurement reported"))
  assert_false(html.contains("free (measured)"))
  assert_false(html.contains("122880 MiB"))
  assert_false(html.contains("MiB total"))
  assert_true(html.contains("GPU utilization"))
  assert_true(html.contains("42%"))
  let chinese = @ui.render({
    ..state,
    locale: ChineseSimplified,
    nodes: [unmeasured],
    confirmation: None,
  })
  assert_true(chinese.contains("未上报"))
  assert_true(chinese.contains("CPU 利用率"))
}

///|
test "storage node monitoring is separate from four GPU compute nodes" {
  let state = console_state(Nodes)
  let measured : @ui.StorageNodeRow = {
    node_id: "management-storage",
    state: "healthy",
    total_bytes: Some(1099511627776L),
    used_bytes: Some(274877906944L),
    available_bytes: Some(824633720832L),
    total_inodes: Some(1000000L),
    available_inodes: Some(800000L),
    sampled_at_ms: 1000L,
  }
  let html = @ui.render({ ..state, storage_nodes: [measured], })
  assert_true(html.contains("Storage nodes"))
  assert_true(html.contains("management-storage"))
  assert_true(html.contains("768.0 GiB"))
  assert_true(html.contains("Available inodes"))
  assert_true(html.contains(" compute nodes"))
  assert_eq(state.overview.total_nodes, 4)
  let unavailable = @ui.render({
    ..state,
    locale: ChineseSimplified,
    storage_nodes: [{ ..measured, state: "unavailable", total_bytes: None, }],
  })
  assert_true(unavailable.contains("存储节点"))
  assert_true(unavailable.contains("采集失败"))
  assert_true(unavailable.contains("无法采集配置的存储挂载卷"))
}

///|
test "node topology states missing compute links without inventing a healthy fleet" {
  let state = console_state(Nodes)
  let html = @ui.render({
    ..state,
    nodes: [],
    overview: { ..state.overview, active_nodes: 0, total_nodes: 0, },
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
  let baseline = @ui.render({ ..state, confirmation: None, })
  let hostile = "<img src=x onerror=alert(1)>"
  let html = @ui.render({
    ..state,
    nodes: [
      { ..state.nodes[0], lease_holder: hostile, active_assignment: hostile, },
    ],
    confirmation: None,
  })
  assert_false(html.contains(hostile))
  // Static branding images are allowed; hostile evidence cannot add an image.
  assert_eq(html.split("<img").count(), baseline.split("<img").count())
  assert_true(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
}

///|
test "catalog route exposes governed one-click deployment controls" {
  let html = @ui.render({ ..console_state(Catalog), confirmation: None, })
  assert_true(html.contains("Model service catalog"))
  assert_true(html.contains("One-click model service"))
  assert_true(html.contains("Preflight enforced"))
  assert_true(html.contains("Select approved template"))
  assert_true(html.contains("Preflight and deploy"))
  assert_true(html.contains("quick-deployment-id"))
  assert_true(html.contains("quick-template"))
  assert_true(html.contains("quick-topology"))
  assert_true(html.contains(">One machine<"))
  assert_true(html.contains(">CX7 pair (two machines)<"))
  assert_true(html.contains("One service · one assigned machine"))
  assert_false(html.contains("One service · one validated CX7 pair"))
  assert_false(html.contains("quick-replicas"))
  assert_true(html.contains("Deploy model service"))
}

///|
/// The rendered `Deploy model service` button tag, so a test can tell a control
/// offered to this operator from one that is only drawn disabled.
fn quick_deploy_button_tag(html : String) -> String {
  let prefix = match html.find("Deploy model service") {
    Some(offset) => html[:offset]
    None => return ""
  }
  let mut tag = ""
  for segment in prefix.split("<button") {
    tag = segment.to_owned()
  }
  tag
}

///|
test "one-click deployment offers only the two admitted topologies" {
  let base = {
    ..console_state(Catalog),
    confirmation: None,
    quick_deployment_id: "text-service",
    quick_template: "text-small@v1",
  }
  let single = @ui.render({ ..base, quick_topology: SingleMachine, })
  assert_true(single.contains("value=\"single-machine\" selected"))
  assert_true(single.contains("<option value=\"cx7-pair\""))
  assert_true(single.contains("One service · one assigned machine"))
  assert_false(single.contains("One service · one validated CX7 pair"))
  let pair = @ui.render({ ..base, quick_topology: Cx7Pair, })
  assert_true(pair.contains("value=\"cx7-pair\" selected"))
  assert_true(pair.contains("<option value=\"single-machine\""))
  assert_true(pair.contains("One service · one validated CX7 pair"))
  assert_false(pair.contains("One service · one assigned machine"))
}

///|
test "one-click deployment is offered only to an authenticated operator" {
  let base = {
    ..console_state(Catalog),
    confirmation: None,
    quick_deployment_id: "text-service",
    quick_template: "text-small@v1",
  }
  let authenticated = @ui.render({ ..base, operator_authenticated: true, })
  let authenticated_tag = quick_deploy_button_tag(authenticated)
  assert_true(authenticated_tag.contains("primary-button"))
  assert_false(authenticated_tag.contains("disabled"))
  let anonymous = @ui.render({ ..base, operator_authenticated: false, })
  let anonymous_tag = quick_deploy_button_tag(anonymous)
  assert_true(anonymous_tag.contains("primary-button"))
  assert_true(anonymous_tag.contains("disabled"))
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
test "operator WebIDE onboarding compresses setup into guided milestones" {
  let state = @ui.demo_state()
  let item = {
    ..state.access_packages[0],
    lease_state: Some(Requested),
    ready: false,
    can_enable: true,
    state: "ReadyToEnable",
  }
  let html = @ui.render({
    ..state,
    route: Users,
    access_packages: [item],
    confirmation: None,
  })
  assert_true(html.contains("Create WebIDE access"))
  assert_true(html.contains("Person &amp; organization"))
  assert_true(html.contains("Scope review"))
  assert_true(html.contains("Enterprise user + Developer"))
  assert_true(html.contains("100 requests/hour"))
  assert_true(html.contains("Identity"))
  assert_true(html.contains("Organization"))
  assert_true(html.contains("MasterLease"))
  assert_true(html.contains("Workspace &amp; models"))
  assert_true(html.contains("Enable WebIDE"))
  assert_true(html.contains("Technical evidence"))
  assert_true(html.contains("Open audit log"))
  assert_true(html.contains("Advanced: create account only"))
}

///|
test "catalog escapes adversarial operator and template text" {
  let demo = @ui.demo_state()
  let baseline = @ui.render({ ..demo, route: Catalog, })
  let hostile = "<img src=x onerror=alert(1)>"
  let html = @ui.render({
    ..demo,
    route: Catalog,
    quick_deployment_id: hostile,
    catalog_templates: [{ ..demo.catalog_templates[0], display_name: hostile, }],
  })
  assert_false(html.contains(hostile))
  assert_eq(html.split("<img").count(), baseline.split("<img").count())
  assert_false(html.contains("onerror=alert(1)>"))
  assert_true(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
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
  assert_true(
    users.contains("能源谷“创未来”生态街区 集群运维"),
  )
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
    users: [{ ..english.users[1], last_active: "Never", }],
    confirmation: None,
  })
  assert_true(chinese.contains("placement/server-note-原样"))
  let chinese_users = @ui.render({
    ..english,
    locale: ChineseSimplified,
    route: Users,
    users: [{ ..english.users[1], last_active: "Never", }],
    confirmation: None,
  })
  assert_true(chinese_users.contains("从未"))
}

///|
test "operator users page reviews pending company registrations" {
  let html = @ui.render({
    ..console_state(Users),
    locale: ChineseSimplified,
    pending_organizations: [
      {
        organization_id: "organization-pending-1",
        display_name: "测试企业",
        legal_name: "测试企业有限公司",
        country_code: "CN",
        registration_number: "91310000TEST000001",
        registered_address: "上海市",
        contact_email: "contact@example.invalid",
      },
    ],
  })
  assert_true(html.contains("待审核企业注册"))
  assert_true(html.contains("测试企业有限公司"))
  assert_true(html.contains("审核通过企业注册"))
}

///|
test "Simplified Chinese status copy follows each resource lifecycle" {
  let access = console_state(Users)
  let access_html = @ui.render({
    ..access,
    locale: ChineseSimplified,
    users: [
      { ..access.users[0], state: UserActive, },
      { ..access.users[0], state: UserInvited, },
      { ..access.users[0], state: UserSuspended, },
      { ..access.users[0], state: UserRevoked, },
    ],
    access_grants: [
      { ..access.access_grants[0], state: GrantActive, },
      { ..access.access_grants[0], state: GrantExpired, },
      { ..access.access_grants[0], state: GrantRevoked, },
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
      { ..leases.compute_leases[0], state: Requested, },
      { ..leases.compute_leases[0], state: Active, },
      { ..leases.compute_leases[0], state: Suspended, },
      { ..leases.compute_leases[0], state: Expired, },
      { ..leases.compute_leases[0], state: Revoked, },
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
      { ..nodes.nodes[0], state: Active, },
      { ..nodes.nodes[0], state: Enrolling, },
      { ..nodes.nodes[0], state: Cordoned, },
      { ..nodes.nodes[0], state: Draining, },
      { ..nodes.nodes[0], state: Unreachable, },
      { ..nodes.nodes[0], state: Retired, },
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
      { ..models.models[0], state: Candidate, },
      { ..models.models[0], state: Verified, },
      { ..models.models[0], state: Evaluated, },
      { ..models.models[0], state: Approved, },
      { ..models.models[0], state: Deprecated, },
      { ..models.models[0], state: Revoked, },
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
      { ..deployments.deployments[0], observed: Pending, },
      { ..deployments.deployments[0], observed: Preparing, },
      { ..deployments.deployments[0], observed: Starting, },
      { ..deployments.deployments[0], observed: Ready, },
      { ..deployments.deployments[0], observed: Draining, },
      { ..deployments.deployments[0], observed: Degraded, },
      { ..deployments.deployments[0], observed: Failed, },
      { ..deployments.deployments[0], observed: Stopped, },
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
      { ..requests.request_details[0], result: "accepted", },
      {
        ..requests.request_details[0],
        action: "workload.vendor-action",
        result: "vendor-result",
        receipt: "receipt:opaque-2",
      },
    ],
    stream_events: [
      { sequence: 1, kind: "Chunk", text: "raw chunk", receipt: "", },
      { sequence: 2, kind: "Completed", text: "", receipt: "receipt:done", },
      { sequence: 3, kind: "Failed", text: "raw failure", receipt: "", },
      { sequence: 4, kind: "Cancelled", text: "", receipt: "", },
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
      { ..nodes.nodes[0], architecture: "unreported", },
      { ..nodes.nodes[0], architecture: "vendor-arch/raw", },
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
      { ..audit.audit[0], result: "accepted", },
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
  let html = @ui.render({ ..state, nodes: [], error_message: Some("offline"), })
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
    overview: {
      ..console_state(Overview).overview,
      active_nodes: 4,
      alerts: 0,
    },
    confirmation: None,
  })
  let awaiting = @ui.render({ ..@ui.default_state(), confirmation: None, })
  assert_true(attention.contains("Cluster needs attention"))
  assert_true(attention.contains("Review required"))
  assert_true(healthy.contains("Node heartbeats healthy"))
  assert_true(healthy.contains("No active incidents"))
  assert_true(awaiting.contains("Awaiting cluster telemetry"))
  assert_true(awaiting.contains("Connect the controller and enroll a node"))
  assert_true(awaiting.contains("Telemetry unavailable"))
}

///|
test "platform blockers remain visible without disabling catalog navigation" {
  let base = @ui.demo_state()
  let blocked = @ui.render({
    ..base,
    production_readiness: {
      ready: false,
      loading: false,
      blocker_codes: [
        "GuideDiagnosticsUnavailable", "ExclusiveLeaseExpiryReconcilerUnavailable",
        "CommercialProviderAdapterUnavailable",
      ],
      error: None,
    },
  })
  assert_true(blocked.contains("Choose a service template"))
  assert_true(blocked.contains("Guide diagnostics"))
  assert_true(blocked.contains("Lease expiry controller"))
  assert_true(blocked.contains("CommercialProviderAdapterUnavailable"))
  assert_true(blocked.contains("separate from catalog access"))
  assert_true(
    blocked.contains(
      "controller checks authorization and model/resource readiness before deployment",
    ),
  )
  assert_false(blocked.contains("Ready for one-click deployment"))
  let mut action = ""
  for index, segment in blocked.split("<button").to_array() {
    let button = segment.split("</button>").to_array()[0]
    if index > 0 && button.contains("readiness-action") {
      action = button.to_owned()
    }
  }
  assert_true(action.contains("Open service catalog"))
  assert_false(action.contains("disabled"))
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
  assert_true(chinese.contains("选择服务模板"))
  assert_true(
    chinese.contains("平台整体生产验收（不限制浏览目录）"),
  )
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
  assert_true(html.contains("Advanced: create account only"))
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
test "model import recovery and adoption preserve every safety gate" {
  let failed : @ui.ModelImportRow = {
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
    local_directory: "",
    artifact_uri: "",
    license: "apache-2.0",
    error_code: "upstream-rejected",
    cancel_requested: false,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
  }
  let candidate : @ui.ModelSourceCatalogRow = {
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
  let verified_managed = {
    ..failed,
    state: Verified,
    files_completed: failed.files_total,
    bytes_completed: failed.bytes_total,
    manifest_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    local_directory: "qwen3635ba3bfp8",
    artifact_uri: "modelstore://qwen3635ba3bfp8",
    error_code: "",
  }
  let verified_html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    model_source_results: [candidate],
    model_imports: [verified_managed],
  })
  assert_true(
    verified_html.contains("Checksum passed; three publication checks remain"),
  )
  assert_true(
    verified_html.contains("Pending · Artifact integrity and provenance"),
  )
  assert_true(verified_html.contains("Pending · License acceptance"))
  assert_true(
    !verified_html.contains("Pending · Evaluation for this exact digest"),
  )
  assert_true(verified_html.contains("Pending · Explicit operator approval"))
  // A revision the control plane serves itself is adoptable, exactly like an
  // upstream object; it does not bypass any later gate.
  assert_true(verified_html.contains("Adopt as Candidate"))
  let unsupported = {
    ..verified_managed,
    local_directory: "",
    artifact_uri: "file:///data/models/qwen3635ba3bfp8",
  }
  let unsupported_html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    model_source_results: [candidate],
    model_imports: [unsupported],
  })
  assert_true(unsupported_html.contains("Not ready for registry adoption"))
  assert_false(unsupported_html.contains("Adopt as Candidate"))
  let verified_s3 = {
    ..verified_managed,
    local_directory: "",
    artifact_uri: "s3://models/modelscope/ms-failed-1",
  }
  let adoptable_html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    model_source_results: [candidate],
    model_imports: [verified_s3],
  })
  assert_true(adoptable_html.contains("Adopt as Candidate"))
  assert_false(adoptable_html.contains("model-adoption-id"))
  let form_html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    model_source_results: [candidate],
    model_imports: [verified_s3],
    model_adoption_draft: {
      import_id: verified_s3.import_id,
      model_id: "model.minicpm5-1b",
      version: "modelscope-main",
      license_id: "license.minicpm5-apache",
      compatible_architectures: "nvidia-gb10, nvidia-ampere",
      minimum_memory_mib: "8192",
    },
  })
  for
    id in [
      "model-adoption-id", "model-adoption-version", "model-adoption-license", "model-adoption-architectures",
      "model-adoption-memory",
    ] {
    assert_true(form_html.contains(id))
  }
  assert_true(form_html.contains("Register Candidate"))
  assert_true(form_html.contains("Creates Candidate + pending license only"))
  let detached_html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    model_source_results: [],
    model_imports: [verified_s3],
  })
  assert_true(detached_html.contains("Imports awaiting a next action"))
  assert_true(detached_html.contains("Visible after refresh or sign-in"))
  assert_true(detached_html.contains("Adopt as Candidate"))
  let chinese_html = @ui.render({
    ..console_state(Models),
    locale: ChineseSimplified,
    operator_authenticated: true,
    model_source_results: [candidate],
    model_imports: [verified_s3],
  })
  assert_true(
    chinese_html.contains("校验已通过；仍需完成三项发布检查"),
  )
  assert_true(chinese_html.contains("登记为候选模型"))
}

///|
test "empty model registry points to governed ModelScope onboarding" {
  let html = @ui.render({ ..console_state(Models), models: [], })
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

///|
test "a local registration is submittable only with a store directory and an upstream identity" {
  let directory : @ui.ModelLocalDirectoryRow = {
    directory: "qwen3635ba3bfp8",
    files: 57,
    bytes: 37493018221L,
    registered: false,
  }
  let state = {
    ..console_state(Models),
    operator_authenticated: true,
    model_local_directories: [directory],
  }
  let draft : @ui.ModelLocalRegistrationDraft = {
    directory: "qwen3635ba3bfp8",
    repository: "Qwen/Qwen3.6-35B-A3B-FP8",
    revision: "master",
  }
  assert_true(@ui.model_local_registration_valid(state, draft))
  assert_false(
    @ui.model_local_registration_valid(state, { ..draft, directory: "", }),
  )
  assert_false(
    @ui.model_local_registration_valid(state, {
      ..draft,
      directory: "not-offered",
    }),
  )
  assert_false(
    @ui.model_local_registration_valid(state, { ..draft, repository: "Qwen", }),
  )
  assert_false(
    @ui.model_local_registration_valid(state, {
      ..draft,
      repository: "Qwen/Qwen3.6/extra",
    }),
  )
  assert_false(
    @ui.model_local_registration_valid(state, {
      ..draft,
      revision: "master branch",
    }),
  )
  assert_false(
    @ui.model_local_registration_valid(
      {
        ..state,
        model_local_directories: [{ ..directory, registered: true, }],
      },
      draft,
    ),
  )
}

///|
/// The rendered `<button>` tag whose label is `label`, so a test can tell a
/// control offered to this operator from one that is only drawn disabled.
fn button_tag_for(html : String, label : String) -> String {
  let prefix = match html.find(label) {
    Some(offset) => html[:offset]
    None => return ""
  }
  let mut tag = ""
  for segment in prefix.split("<button") {
    tag = segment.to_owned()
  }
  tag
}

///|
/// The rendered `<input>` tag opened for `id`, including the `checked` property
/// that a boolean toggle writes after the attributes.
fn input_tag_for(html : String, id : String) -> String {
  let needle = "id=\"" + id + "\""
  guard html.find(needle) is Some(start) else { return "" }
  let rest = html[start:]
  guard rest.find(">") is Some(end) else { return "" }
  rest[:end].to_owned()
}

///|
/// The whole rendered `<input>` element for `id`. A `disabled` attribute is
/// written before the id, so the tag helper above would cut it off.
fn input_element_for(html : String, id : String) -> String {
  let needle = "id=\"" + id + "\""
  guard html.find(needle) is Some(start) else { return "" }
  let mut opened = ""
  for segment in html[:start].split("<input") {
    opened = segment.to_owned()
  }
  let rest = html[start:]
  guard rest.find(">") is Some(end) else { return "" }
  "<input" + opened + rest[:end].to_owned()
}

///|
/// One adopted candidate, with the licence identity and managed-store revision
/// the registry reported for it.
fn candidate_model_row() -> @ui.ModelRow {
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
test "registered ModelScope artifacts are not offered for adoption again" {
  let registered : @ui.ModelImportRow = {
    import_id: "ms-registered-1",
    source: "modelscope",
    model_id: "OpenBMB/MiniCPM5-1B",
    revision: "master",
    state: Verified,
    files_total: 1,
    files_completed: 1,
    bytes_total: 1024L,
    bytes_completed: 1024L,
    manifest_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    artifact_uri: "modelstore://qwen3635ba3bfp8",
    license: "apache-2.0",
    local_directory: "qwen3635ba3bfp8",
    error_code: "",
    cancel_requested: false,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
  }
  let pending = {
    ..registered,
    import_id: "ms-unregistered-2",
    artifact_uri: "modelstore://different-artifact",
  }
  assert_false(
    @ui.model_import_needs_registration(registered, [candidate_model_row()]),
  )
  let legacy_store_uri = {
    ..registered,
    import_id: "ms-legacy-alias",
    artifact_uri: "modelstore://modelscope/ms-registered-1",
  }
  let corrected_store_model = {
    ..candidate_model_row(),
    artifact_uri: "modelstore://models/modelscope/ms-registered-1",
  }
  assert_false(
    @ui.model_import_needs_registration(legacy_store_uri, [
      corrected_store_model,
    ]),
  )
  assert_true(
    @ui.model_import_needs_registration(pending, [candidate_model_row()]),
  )
  let html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    models: [candidate_model_row()],
    model_imports: [registered, pending],
  })
  assert_false(html.contains("ms-registered-1"))
  assert_true(html.contains("ms-unregistered-2"))
  assert_true(html.contains("Adopt as Candidate"))
  let legacy_html = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    models: [corrected_store_model],
    model_imports: [legacy_store_uri],
  })
  assert_false(legacy_html.contains("ms-legacy-alias"))
  let searched = @ui.render({
    ..console_state(Models),
    operator_authenticated: true,
    models: [candidate_model_row()],
    model_source_results: [
      {
        id: registered.model_id,
        display_name: "MiniCPM5-1B",
        description: "small model",
        downloads: 1L,
        likes: 1L,
        license: registered.license,
        tasks: ["text-generation"],
        created_at: "",
        last_modified: "",
        file_size: registered.bytes_total,
        params: 1000000000L,
        tags: [],
        private: false,
        gated: false,
      },
    ],
    model_imports: [registered],
  })
  assert_true(searched.contains("Already registered in the model registry"))
  assert_false(searched.contains("Adopt as Candidate"))
}

///|
test "candidate rows expose licence, verification, approval and promotion controls" {
  let base = console_state(Models)
  let html = @ui.render({ ..base, models: [candidate_model_row()], })
  assert_true(html.contains("Accept licence…"))
  assert_true(html.contains("Verify artifact"))
  assert_true(html.contains(">Approve</button>"))
  assert_true(html.contains("Promote alias…"))
  // The registry owns the order: a premature step is answered with its own
  // refusal rather than hidden behind a disabled control.
  assert_false(button_tag_for(html, "Verify artifact").contains("disabled"))
  assert_false(button_tag_for(html, "Promote alias…").contains("disabled"))
}

///|
test "candidate onboarding controls need operator authority" {
  let base = console_state(Models)
  let html = @ui.render({
    ..base,
    models: [candidate_model_row()],
    operator_authenticated: false,
  })
  for label in ["Accept licence…", "Verify artifact", "Promote alias…"] {
    assert_true(button_tag_for(html, label).contains("disabled"))
  }
}

///|
test "licence and alias forms follow the selected candidate row" {
  let base = console_state(Models)
  let licence = @ui.render({
    ..base,
    models: [candidate_model_row()],
    model_license_draft: {
      model_id: "model.minicpm5-1b",
      version: "modelscope-main",
      license_id: "license.minicpm5-apache",
      evidence_ref: "modelscope-license:apache-2.0",
    },
  })
  assert_true(
    licence.contains("Accept licence for model.minicpm5-1b · modelscope-main"),
  )
  assert_true(licence.contains("model-license-id"))
  assert_true(licence.contains("model-license-evidence"))
  assert_true(licence.contains("value=\"license.minicpm5-apache\""))
  assert_true(licence.contains("value=\"modelscope-license:apache-2.0\""))
  assert_true(licence.contains(">Accept licence</button>"))
  assert_false(licence.contains("model-alias-name"))
  let alias_html = @ui.render({
    ..base,
    models: [candidate_model_row()],
    model_alias_draft: {
      model_id: "model.minicpm5-1b",
      version: "modelscope-main",
      alias_name: "text.default",
    },
  })
  assert_true(alias_html.contains("model-alias-name"))
  assert_true(alias_html.contains("value=\"text.default\""))
  assert_true(alias_html.contains(">Promote alias</button>"))
  assert_false(alias_html.contains("model-license-id"))
  // A draft opened for another version never borrows this row's controls.
  let elsewhere = @ui.render({
    ..base,
    models: [candidate_model_row()],
    model_license_draft: {
      model_id: "model.somewhere-else",
      version: "v1",
      license_id: "license.elsewhere",
      evidence_ref: "modelscope-license:mit",
    },
  })
  assert_false(elsewhere.contains("model-license-id"))
}

///|
test "policies page registers a runtime profile from its own controls" {
  let base = console_state(Policies)
  let html = @ui.render(base)
  assert_true(html.contains("Register a runtime profile"))
  assert_true(html.contains("runtime-name"))
  assert_true(html.contains("runtime-version"))
  assert_true(html.contains("runtime-image-digest"))
  assert_true(html.contains("runtime-architecture"))
  assert_true(html.contains("runtime-capability"))
  assert_true(html.contains("runtime-batching"))
  assert_true(html.contains("runtime-multi-node"))
  assert_true(html.contains("value=\"nvidia-sm121\""))
  assert_true(html.contains("value=\"TextGenerate\" selected"))
  assert_false(input_tag_for(html, "runtime-batching").contains("checked"))
  // The default draft is incomplete, so the registry is not asked yet.
  assert_true(button_tag_for(html, "Register runtime").contains("disabled"))
  let ready = @ui.render({
    ..base,
    runtime_draft: {
      name: "text-runtime-v2",
      version: "runtime-v2",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      architecture: "nvidia-sm121",
      capability: TextGenerate,
      supports_batching: true,
      supports_multi_node: false,
    },
  })
  assert_true(input_tag_for(ready, "runtime-batching").contains("checked"))
  assert_false(input_tag_for(ready, "runtime-multi-node").contains("checked"))
  assert_false(button_tag_for(ready, "Register runtime").contains("disabled"))
}

///|
test "runtime registration stays localized and needs operator authority" {
  let base = console_state(Policies)
  let chinese = @ui.render({
    ..base,
    locale: ChineseSimplified,
    runtime_draft: {
      name: "text-runtime-v2",
      version: "runtime-v2",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      architecture: "nvidia-sm121",
      capability: TextGenerate,
      supports_batching: false,
      supports_multi_node: false,
    },
  })
  assert_true(chinese.contains("注册运行时配置"))
  assert_true(chinese.contains("注册运行时"))
  let disconnected = @ui.render({
    ..base,
    operator_authenticated: false,
    runtime_draft: {
      name: "text-runtime-v2",
      version: "runtime-v2",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      architecture: "nvidia-sm121",
      capability: TextGenerate,
      supports_batching: false,
      supports_multi_node: false,
    },
  })
  assert_true(
    button_tag_for(disconnected, "Register runtime").contains("disabled"),
  )
}

///|
/// A catalog template every planner rule admits, so a test can flip one field
/// and watch the decision change.
fn registered_template_draft() -> @ui.TemplateDraft {
  {
    ..@ui.empty_template_draft(),
    template_id: "text-small",
    version: "v1",
    display_name: "Text small",
    description: "Approved DGX Spark text service",
    model_selector: "text.default",
    model_id: "model.text",
    model_version: "v1",
    artifact_uri: "modelstore://model.text/v1",
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    artifact_size_bytes: "16000000000",
    artifact_signature_ref: "modelstore://model.text/v1/lunanexa-source-manifest.json",
    runtime_name: "text-runtime",
    runtime_version: "runtime-v1",
    runtime_image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    runtime_architectures: "nvidia-gb10",
    architecture: "nvidia-gb10",
    capability: TextGenerate,
  }
}

///|
test "the template form groups every field, prefilled from what the console knows" {
  let base = console_state(Catalog)
  let html = @ui.render({ ..base, template_draft: registered_template_draft(), })
  assert_true(html.contains("Register a catalog template"))
  assert_true(html.contains("Preflight still applies"))
  assert_true(html.contains("Registers one immutable model-service template."))
  for
    id in [
      "template-registration-title", "template-model-picker", "template-runtime-picker",
      "template-id", "template-version", "template-display-name", "template-description",
      "template-model-selector", "template-artifact-uri", "template-artifact-digest",
      "template-artifact-size", "template-artifact-signature", "template-runtime-name",
      "template-runtime-version", "template-runtime-image-digest", "template-runtime-architectures",
      "template-architecture", "template-capability", "template-classification",
      "template-accelerator-count", "template-accelerator-memory", "template-cpu-millis",
      "template-memory", "template-secret-refs", "template-readiness-path", "template-health-interval",
      "template-failure-threshold", "template-termination-grace", "template-consent-receipt",
      "template-canary-replicas", "template-readiness-timeout", "template-runtime-multi-node",
      "template-capture-for-evaluation", "template-allow-cache", "template-allow-training-reuse",
      "template-automatic-promotion", "template-automatic-rollback",
    ] {
    assert_true(html.contains("id=\"\{id}\""))
  }
  // Seven decisions rather than one wall of inputs.
  for
    legend in [
      "Template identity", "Model and artifact", "Runtime", "Resources and secrets",
      "Health probes", "Data policy", "Rollout",
    ] {
    assert_true(html.contains(legend))
  }
  // The pickers show the registered model and runtime the draft names.
  assert_true(html.contains("value=\"model.text@v1\" selected"))
  assert_true(html.contains("value=\"text-runtime@runtime-v1\" selected"))
  // A bounded field answers to the planner's bound, not to browser validation.
  assert_false(html.contains("template-accelerator-count\" type=\"number\""))
  // The reuse switches are only reachable inside an evaluation capture, and
  // the capability select offers only what the chosen runtime serves.
  assert_true(
    input_element_for(html, "template-allow-cache").contains("disabled"),
  )
  assert_false(
    input_element_for(html, "template-automatic-rollback").contains("disabled"),
  )
  assert_false(html.contains("value=\"EmbeddingCreate\""))
  // The raw-JSON panel keeps its registration operation.
  assert_true(
    @ui.render(console_state(Policies)).contains("value=\"register-template\""),
  )
}

///|
test "the template form is offered only to an authenticated operator" {
  let base = console_state(Catalog)
  let ready = { ..base, template_draft: registered_template_draft(), }
  let authenticated = @ui.render({ ..ready, operator_authenticated: true, })
  assert_false(
    button_tag_for(authenticated, "Register template").contains("disabled"),
  )
  let anonymous = @ui.render({ ..ready, operator_authenticated: false, })
  assert_true(
    button_tag_for(anonymous, "Register template").contains("disabled"),
  )
  // The default draft names nothing, so the control plane is never asked.
  let empty = @ui.render({
    ..ready,
    template_draft: @ui.empty_template_draft(),
  })
  assert_true(button_tag_for(empty, "Register template").contains("disabled"))
}

///|
test "the template form mirrors the planner's cross-field rules" {
  let draft = registered_template_draft()
  assert_true(@ui.template_draft_valid(draft))
  // The template's architecture must be one its runtime declares.
  assert_false(
    @ui.template_draft_valid({ ..draft, architecture: "nvidia-h100", }),
  )
  assert_false(
    @ui.template_draft_valid({ ..draft, runtime_architectures: "nvidia-sm121", }),
  )
  assert_true(
    @ui.template_draft_valid({
      ..draft,
      runtime_architectures: "nvidia-gb10, nvidia-sm121",
    }),
  )
  // An evaluation capture must name its consent receipt...
  assert_false(
    @ui.template_draft_valid({ ..draft, capture_for_evaluation: true, }),
  )
  assert_true(
    @ui.template_draft_valid({
      ..draft,
      capture_for_evaluation: true,
      evaluation_consent_receipt: "consent:evaluation:2026-01",
    }),
  )
  // ...and an ephemeral template may neither cache nor reuse a payload.
  assert_false(@ui.template_draft_valid({ ..draft, allow_cache: true, }))
  assert_false(
    @ui.template_draft_valid({ ..draft, allow_training_reuse: true, }),
  )
  // Clearing the capture clears the two switches with it.
  let captured = @ui.template_draft_with_flag(
    {
      ..draft,
      capture_for_evaluation: true,
      evaluation_consent_receipt: "consent:evaluation:2026-01",
      allow_cache: true,
      allow_training_reuse: true,
    },
    CaptureForEvaluation,
    false,
  )
  assert_false(captured.capture_for_evaluation)
  assert_false(captured.allow_cache)
  assert_false(captured.allow_training_reuse)
  assert_true(@ui.template_draft_valid(captured))
  // Every number keeps the bound the deployment service enforces.
  assert_false(@ui.template_draft_valid({ ..draft, accelerator_count: "65", }))
  assert_false(@ui.template_draft_valid({ ..draft, accelerator_count: "1.5", }))
  assert_false(@ui.template_draft_valid({ ..draft, canary_replicas: "0", }))
  assert_false(
    @ui.template_draft_valid({ ..draft, artifact_size_bytes: "1099511627777", }),
  )
  assert_false(
    @ui.template_draft_valid({ ..draft, readiness_timeout_ms: "86400001", }),
  )
  assert_false(@ui.template_draft_valid({ ..draft, readiness_path: "health", }))
  // A secret reference list is comma-separated, unique and optional; the
  // transports the artifact gateway materializes are `s3://` and `modelstore://`.
  assert_true(@ui.template_draft_valid({ ..draft, secret_refs: "", }))
  assert_false(
    @ui.template_draft_valid({
      ..draft,
      secret_refs: "runtime-token, runtime-token",
    }),
  )
  assert_false(
    @ui.template_draft_valid({
      ..draft,
      artifact_uri: "file:///data/models/text",
    }),
  )
  assert_true(
    @ui.template_draft_valid({ ..draft, artifact_uri: "s3://models/text/v1", }),
  )
  // A managed revision is signed by its own source manifest.
  assert_true(
    @ui.template_draft_valid({
      ..draft,
      artifact_signature_ref: "modelstore://model.text/v1/lunanexa-source-manifest.json",
    }),
  )
  assert_false(
    @ui.template_draft_valid({ ..draft, artifact_signature_ref: "file:///sig", }),
  )
  assert_false(@ui.template_draft_valid({ ..draft, display_name: "", }))
  assert_false(@ui.template_draft_valid({ ..draft, template_id: "", }))
}
