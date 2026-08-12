///|
pub(all) struct OverviewMetrics {
  active_nodes : Int
  total_nodes : Int
  active_models : Int
  queue_depth : Int
  alerts : Int
  recent_changes : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeRow {
  node_id : String
  state : @contracts.NodeState
  architecture : String
  total_memory_mib : Int
  free_memory_mib : Int
  used_memory_mib : Int
  utilization_per_mille : Int
  temperature_celsius : Int
  power_watts : Int
  workloads : Int
  lease_holder : String
  active_assignment : String
  last_seen : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ModelRow {
  model_id : String
  version : String
  state : @contracts.ModelState
  license_status : String
  evaluation_status : String
  compatibility : String
  alias_name : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeploymentRow {
  assignment_id : String
  deployment_id : String
  desired : @contracts.DeploymentState
  observed : @contracts.DeploymentState
  placement_reason : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RequestMetrics {
  count : Int
  p95_ms : Int
  throughput_per_second : Int
  errors : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RequestDetail {
  timestamp_unix_ms : Int64
  action : String
  model_selector : String
  result : String
  receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct StreamEventView {
  sequence : Int
  kind : String
  text : String
  receipt : String
} derive(Eq)

///|
pub(all) struct PolicySummary {
  quota_count : Int
  data_class_count : Int
  default_retention : @contracts.RetentionPolicy
  allowed_runtimes : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AuditRow {
  actor : String
  decision : String
  evidence : String
  result : String
  receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UserAccessRow {
  user_id : String
  display_name : String
  email : String
  state : @workspace.WorkspaceUserState
  last_active : String
  grant_count : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AccessGrantRow {
  grant_id : String
  user_id : String
  role : @workspace.WorkspaceAccess
  scope : String
  expires_at : String
  state : @workspace.WorkspaceAccessGrantState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ComputeLeaseRow {
  lease_id : String
  user_id : String
  workspace : String
  resource : String
  started_at : String
  expires_at : String
  state : @workspace.WorkspaceLeaseState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExclusiveNodeLeaseRow {
  lease_id : String
  node_id : String
  subject_ref : String
  unix_username : String
  expires_at : String
  state : String
  generation : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CostCenterRow {
  cost_center_id : String
  organization_id : String
  display_name : String
  parent_cost_center_id : String
  project_count : Int
  provisional_spend : String
  budget_posture : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AgreementRow {
  agreement_id : String
  agreement_type : String
  template_version : String
  organization_id : String
  state : String
  evidence_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EnterpriseLeaseRequestRow {
  request_id : String
  organization_id : String
  subject_ref : String
  project_id : String
  unix_username : String
  requested_models : String
  state : String
  generation : Int64
  assigned_node_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct QualifiedServiceRow {
  provider : String
  capability : String
  environment : String
  state : String
  evidence_policy : String
  production_ready : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum DestructiveAction {
  CordonNode(String)
  DrainNode(String)
  StopDeployment(String)
  RollbackAlias(String)
  RollbackServiceDeployment(String)
  DeleteServiceDeployment(String)
  SuspendUser(String)
  RevokeUser(String)
  RevokeAccessGrant(String)
  EndComputeLease(String)
  TerminateExclusiveNodeLease(String, Int64)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Confirmation {
  action : DestructiveAction
  scope : String
  receipt : String
  confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ConsoleState {
  locale : @i18n.Locale
  route : OperatorRoute
  overview : OverviewMetrics
  nodes : Array[NodeRow]
  models : Array[ModelRow]
  deployments : Array[DeploymentRow]
  catalog_templates : Array[@deployment.ModelServiceTemplate]
  service_deployments : Array[@deployment.DeploymentOperation]
  requests : RequestMetrics
  request_details : Array[RequestDetail]
  stream_events : Array[StreamEventView]
  benchmark_evidence : Array[String]
  policies : PolicySummary
  audit : Array[AuditRow]
  users : Array[UserAccessRow]
  access_grants : Array[AccessGrantRow]
  compute_leases : Array[ComputeLeaseRow]
  exclusive_node_leases : Array[ExclusiveNodeLeaseRow]
  cost_centers : Array[CostCenterRow]
  agreements : Array[AgreementRow]
  enterprise_lease_requests : Array[EnterpriseLeaseRequestRow]
  portal_node_id : String
  qualified_services : Array[QualifiedServiceRow]
  confirmation : Confirmation?
  error_message : String?
  success_message : String?
  loading : Bool
  operation_name : String
  operation_body : String
  quick_deployment_id : String
  quick_template : String
} derive(Eq)

///|
pub(all) enum ConsoleMessage {
  LocaleChanged(@i18n.Locale)
  Navigate(OperatorRoute)
  BeginCordon(String)
  BeginDrain(String)
  BeginRollback(String)
  BeginStopDeployment(String)
  BeginRollbackServiceDeployment(String)
  BeginDeleteServiceDeployment(String)
  PromoteServiceDeployment(String)
  ActivateUser(String)
  BeginSuspendUser(String)
  BeginRevokeUser(String)
  BeginRevokeAccessGrant(String)
  ActivateComputeLease(String)
  BeginEndComputeLease(String)
  BeginTerminateExclusiveNodeLease(String, Int64)
  DismissConfirmation
  ConfirmAction(DestructiveAction)
  Refresh
  OperationChanged(String)
  OperationBodyChanged(String)
  SubmitOperation
  QuickDeploymentIdChanged(String)
  QuickTemplateChanged(String)
  SubmitQuickDeployment
  PortalNodeChanged(String)
  ApproveEnterpriseLease(String, Int64)
  RejectEnterpriseLease(String, Int64)
} derive(Eq)

///|
pub fn confirmation_receipt(
  action : DestructiveAction,
  scope : String,
) -> Confirmation {
  {
    action,
    scope,
    receipt: "confirm:\{scope}:\{Repr(action)}",
    confirmed: false,
  }
}

///|
pub fn default_state() -> ConsoleState {
  {
    locale: @i18n.default_locale(),
    route: Overview,
    overview: {
      active_nodes: 0,
      total_nodes: 0,
      active_models: 0,
      queue_depth: 0,
      alerts: 0,
      recent_changes: 0,
    },
    nodes: [],
    models: [],
    deployments: [],
    catalog_templates: [],
    service_deployments: [],
    requests: { count: 0, p95_ms: 0, throughput_per_second: 0, errors: 0 },
    request_details: [],
    stream_events: [],
    benchmark_evidence: [],
    policies: {
      quota_count: 0,
      data_class_count: 4,
      default_retention: Ephemeral,
      allowed_runtimes: [],
    },
    audit: [],
    users: [],
    access_grants: [],
    compute_leases: [],
    exclusive_node_leases: [],
    cost_centers: [],
    agreements: [],
    enterprise_lease_requests: [],
    portal_node_id: "",
    qualified_services: [],
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operation_name: "register-model",
    operation_body: "",
    quick_deployment_id: "",
    quick_template: "",
  }
}

/// A deterministic, read-only snapshot for product demos and UI review.
/// It is never used by the live controller loading path.

///|
pub fn demo_state() -> ConsoleState {
  let nodes : Array[NodeRow] = [
    {
      node_id: "dgx-spark-01",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 81920,
      used_memory_mib: 40960,
      utilization_per_mille: 420,
      temperature_celsius: 46,
      power_watts: 76,
      workloads: 1,
      lease_holder: "org-northstar · alice",
      active_assignment: "deployment-qwen-eval",
      last_seen: "≤ 1 s",
    },
    {
      node_id: "dgx-spark-02",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 79872,
      used_memory_mib: 43008,
      utilization_per_mille: 610,
      temperature_celsius: 51,
      power_watts: 89,
      workloads: 1,
      lease_holder: "org-acme · bob",
      active_assignment: "deployment-vision-review",
      last_seen: "≤ 1 s",
    },
    {
      node_id: "dgx-spark-03",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 80896,
      used_memory_mib: 41984,
      utilization_per_mille: 80,
      temperature_celsius: 38,
      power_watts: 42,
      workloads: 0,
      lease_holder: "",
      active_assignment: "",
      last_seen: "3 s",
    },
    {
      node_id: "dgx-spark-04",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 79872,
      used_memory_mib: 43008,
      utilization_per_mille: 30,
      temperature_celsius: 36,
      power_watts: 39,
      workloads: 0,
      lease_holder: "",
      active_assignment: "",
      last_seen: "5 s",
    },
  ]
  let models : Array[ModelRow] = [
    {
      model_id: "lunanexa.text.general",
      version: "v3",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "text.default",
    },
    {
      model_id: "lunanexa.text.fast",
      version: "v2",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "text.fast",
    },
    {
      model_id: "lunanexa.text.reasoning",
      version: "v1",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "text.reasoning",
    },
    {
      model_id: "lunanexa.code.assist",
      version: "v4",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "code.assist",
    },
    {
      model_id: "lunanexa.embedding.multilingual",
      version: "v2",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "embedding.multilingual",
    },
    {
      model_id: "lunanexa.embedding.base",
      version: "v1",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "embedding.default",
    },
    {
      model_id: "lunanexa.vision.general",
      version: "v2",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "vision.default",
    },
    {
      model_id: "lunanexa.rerank.base",
      version: "v1",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "rerank.default",
    },
    {
      model_id: "lunanexa.speech.transcribe",
      version: "v2",
      state: Approved,
      license_status: "accepted",
      evaluation_status: "passed",
      compatibility: "DGX Spark",
      alias_name: "speech.transcribe",
    },
  ]
  let templates : Array[@deployment.ModelServiceTemplate] = [
    {
      template_id: "text-small",
      version: "v1",
      display_name: "Text small",
      description: "Approved DGX Spark text service",
      model_selector: "text.default",
      model_id: "lunanexa.text.general",
      model_version: "v3",
      artifact: {
        digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        uri: "s3://models/lunanexa.text.general/v3",
        size_bytes: 16000000000L,
        signature_ref: "s3://models/lunanexa.text.general/v3.sig",
      },
      runtime: {
        name: "text-runtime",
        image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        version: "runtime-v1",
        architectures: ["nvidia-gb10"],
        capabilities: [TextGenerate],
        supports_batching: false,
        supports_multi_node: false,
      },
      capability: TextGenerate,
      architecture: "nvidia-gb10",
      resources: {
        accelerator_count: 1,
        accelerator_memory_mib: 24000,
        cpu_millis: 4000,
        memory_mib: 32000,
      },
      network: {
        allow_controller: true,
        allow_artifact_store: true,
        allowed_egress: [],
      },
      health: {
        readiness_path: "/health",
        interval_ms: 1000,
        failure_threshold: 3,
        termination_grace_ms: 30000,
      },
      data_policy: {
        classification: Internal,
        retention: Ephemeral,
        allow_cache: false,
        allow_training_reuse: false,
      },
      secret_refs: ["runtime-token"],
      rollout: {
        canary_replicas: 1,
        automatic_promotion: false,
        automatic_rollback: true,
        readiness_timeout_ms: 60000L,
      },
      approval_receipt: "catalog:text-small:v1",
      signature: "demo-signed",
    },
  ]
  {
    ..default_state(),
    overview: {
      active_nodes: 4,
      total_nodes: 4,
      active_models: 9,
      queue_depth: 1,
      alerts: 0,
      recent_changes: 6,
    },
    nodes,
    models,
    catalog_templates: templates,
    requests: { count: 1842, p95_ms: 142, throughput_per_second: 38, errors: 3 },
    benchmark_evidence: [
      "demo-throughput · p95 142 ms · 38/s · failures 1‰ · demo-run-01",
    ],
    policies: {
      quota_count: 6,
      data_class_count: 4,
      default_retention: Ephemeral,
      allowed_runtimes: ["text-runtime", "embedding-runtime", "vision-runtime"],
    },
    audit: [
      {
        actor: "demo-operator",
        decision: "cluster.snapshot",
        evidence: "4-node demo fleet",
        result: "accepted",
        receipt: "demo:audit:01",
      },
    ],
    exclusive_node_leases: [
      {
        lease_id: "lease-northstar-alice",
        node_id: "dgx-spark-01",
        subject_ref: "subject-alice",
        unix_username: "alice",
        expires_at: "2026-08-12T18:00:00Z",
        state: "Active",
        generation: 4L,
      },
    ],
    cost_centers: [
      {
        cost_center_id: "cc-research",
        organization_id: "org-luna",
        display_name: "Research",
        parent_cost_center_id: "—",
        project_count: 3,
        provisional_spend: "CNY 12,840.00",
        budget_posture: "Within budget",
      },
      {
        cost_center_id: "cc-platform",
        organization_id: "org-luna",
        display_name: "Platform",
        parent_cost_center_id: "—",
        project_count: 2,
        provisional_spend: "CNY 8,120.00",
        budget_posture: "Approval at 80%",
      },
    ],
    agreements: [
      {
        agreement_id: "agreement-capacity-2026",
        agreement_type: "Reserved capacity",
        template_version: "capacity-v2",
        organization_id: "org-luna",
        state: "Executed",
        evidence_receipt: "evidence:agreement:2026:01",
      },
      {
        agreement_id: "agreement-dpa-2026",
        agreement_type: "Data processing",
        template_version: "dpa-v1",
        organization_id: "org-luna",
        state: "Awaiting signature",
        evidence_receipt: "evidence:agreement:2026:02",
      },
    ],
    enterprise_lease_requests: [
      {
        request_id: "request-eval-042",
        organization_id: "org-northstar",
        subject_ref: "subject-alice",
        project_id: "project-vision-lab",
        unix_username: "alice",
        requested_models: "qwen3-32b, bge-m3",
        state: "Submitted",
        generation: 1L,
        assigned_node_id: "—",
      },
    ],
    portal_node_id: "dgx-spark-04",
    qualified_services: [
      {
        provider: "LunaFide",
        capability: "Identity · signature · payment · invoice",
        environment: "TestOnly",
        state: "Available",
        evidence_policy: "Signed, sequenced, tenant-bound callbacks",
        production_ready: false,
      },
    ],
    quick_template: "text-small@v1",
  }
}

///|
fn localized(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
fn generated_time_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "Never" | "从未" => "从未"
      "Unavailable" | "不可用" => "不可用"
      _ => value
    }
  } else {
    match value {
      "Never" | "从未" => "Never"
      "Unavailable" | "不可用" => "Unavailable"
      _ => value
    }
  }
}

///|
fn architecture_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() && value == "unreported" {
    "未上报"
  } else {
    value
  }
}

///|
fn license_evidence_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "accepted" => "已接受"
      "missing" => "未记录"
      _ => value
    }
  } else {
    value
  }
}

///|
fn evaluation_evidence_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "passed" => "已通过"
      "missing" => "未记录"
      "failed" => "未通过"
      _ => value
    }
  } else {
    value
  }
}

///|
fn result_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() && value == "accepted" {
    "已接受"
  } else {
    value
  }
}

///|
fn stream_kind_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "Chunk" => "数据块"
      "Completed" => "已完成"
      "Failed" => "失败"
      "Cancelled" => "已取消"
      _ => value
    }
  } else {
    value
  }
}

///|
fn benchmark_evidence_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    value.replace_all(old=" · failures ", new=" · 失败率 ")
  } else {
    value
  }
}

///|
fn lease_resource_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    value
    .replace_all(old="No inference capabilities", new="无推理能力")
    .replace_all(old="Text generation", new="文本生成")
    .replace_all(old="Embeddings", new="嵌入")
    .replace_all(old="Image generation", new="图像生成")
    .replace_all(old="Video generation", new="视频生成")
    .replace_all(old="Audio generation", new="音频生成")
    .replace_all(old=" concurrent", new=" 路并发")
  } else {
    value
    .replace_all(old="无推理能力", new="No inference capabilities")
    .replace_all(old="文本生成", new="Text generation")
    .replace_all(old="嵌入", new="Embeddings")
    .replace_all(old="图像生成", new="Image generation")
    .replace_all(old="视频生成", new="Video generation")
    .replace_all(old="音频生成", new="Audio generation")
    .replace_all(old=" 路并发", new=" concurrent")
  }
}

///|
fn route_label(locale : @i18n.Locale, route : OperatorRoute) -> String {
  match route {
    Overview => localized(locale, "Overview", "概览")
    Users => localized(locale, "Users & access", "用户与访问权限")
    Leases => localized(locale, "Leases", "租约")
    CostCenters => localized(locale, "Cost centers", "成本中心")
    Agreements => localized(locale, "Agreements", "数字协议")
    QualifiedServices => localized(locale, "Qualified services", "资质服务")
    Nodes => localized(locale, "Nodes", "节点")
    Models => localized(locale, "Models", "模型")
    Catalog => localized(locale, "Catalog", "目录")
    Deployments => localized(locale, "Deployments", "部署")
    Requests => localized(locale, "Requests", "请求")
    Benchmarks => localized(locale, "Benchmarks", "基准测试")
    Policies => localized(locale, "Policies", "策略")
    Audit => localized(locale, "Audit", "审计")
  }
}

///|
fn route_description(locale : @i18n.Locale, route : OperatorRoute) -> String {
  match route {
    Overview =>
      localized(
        locale, "Live capacity, service posture, and recent control-plane activity.",
        "查看实时容量、服务状态与近期控制平面活动。",
      )
    Users =>
      localized(
        locale, "Identity lifecycle and scoped access to LunaNexa services.", "管理身份生命周期与 LunaNexa 服务的限定范围访问权限。",
      )
    Leases =>
      localized(
        locale, "Time-bounded exclusive-node leases: one tenant, one user, one machine.",
        "管理有时限的独占节点租约：一个租户、一个用户、一台机器。",
      )
    CostCenters =>
      localized(
        locale, "Tenant hierarchy, metered spend, budgets, quotas, and finance evidence.",
        "管理租户层级、计量支出、预算、配额与财务证据。",
      )
    Agreements =>
      localized(
        locale, "Versioned clickwrap and e-signature lifecycles with immutable evidence receipts.",
        "管理带不可变证据回执的版本化点击接受与电子签名生命周期。",
      )
    QualifiedServices =>
      localized(
        locale, "Provider-neutral identity, signature, payment, and invoice integration posture.",
        "查看供应商中立的身份、签名、支付与发票集成状态。",
      )
    Nodes =>
      localized(
        locale, "Hardware inventory, workload pressure, and maintenance controls.",
        "查看硬件清单、工作负载压力与维护控制。",
      )
    Models =>
      localized(
        locale, "Approved artifacts, evaluation evidence, and serving aliases.",
        "查看已批准模型制品、评测证据与服务模型别名。",
      )
    Catalog =>
      localized(
        locale, "Approved templates, deterministic preflight, and one-click model services.",
        "管理已批准模板、确定性预检与一键模型服务。",
      )
    Deployments =>
      localized(
        locale, "Desired state, observed readiness, and placement decisions.", "对比期望状态、实际就绪状态与放置决策。",
      )
    Requests =>
      localized(
        locale, "Bounded request telemetry and payload-free workload receipts.",
        "查看有边界的请求遥测与不含载荷的工作负载回执。",
      )
    Benchmarks =>
      localized(
        locale, "Comparable performance evidence for approved runtime profiles.",
        "比较已批准运行时配置的性能证据。",
      )
    Policies =>
      localized(
        locale, "Quotas, retention, runtime policy, and typed operator operations.",
        "管理配额、保留策略、运行时策略与类型化运维操作。",
      )
    Audit =>
      localized(
        locale, "Immutable decisions, evidence, results, and correlation receipts.",
        "追踪不可变的决策、证据、结果与关联回执。",
      )
  }
}

///|
fn command(
  emit : @rabbita.Emit[ConsoleMessage]?,
  message : ConsoleMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[ConsoleMessage]?,
  wrap : (String) -> ConsoleMessage,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn navigation(
  locale : @i18n.Locale,
  current : OperatorRoute,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.nav(
    attrs=@html.Attrs::build().aria_label(
      localized(locale, "Primary", "主导航"),
    ),
    [
      @html.p(class="nav-group-label", localized(locale, "Monitor", "监控")),
      nav_link(locale, Overview, current, emit),
      nav_link(locale, Nodes, current, emit),
      nav_link(locale, Models, current, emit),
      nav_link(locale, Catalog, current, emit),
      nav_link(locale, Deployments, current, emit),
      nav_link(locale, Requests, current, emit),
      @html.p(class="nav-group-label", localized(locale, "Govern", "治理")),
      nav_link(locale, Users, current, emit),
      nav_link(locale, Leases, current, emit),
      nav_link(locale, CostCenters, current, emit),
      nav_link(locale, Agreements, current, emit),
      nav_link(locale, Policies, current, emit),
      @html.p(class="nav-group-label", localized(locale, "Evidence", "证据")),
      nav_link(locale, QualifiedServices, current, emit),
      nav_link(locale, Benchmarks, current, emit),
      nav_link(locale, Audit, current, emit),
    ],
  )
}

///|
fn nav_link(
  locale : @i18n.Locale,
  route : OperatorRoute,
  current : OperatorRoute,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let label = route_label(locale, route)
  @html.button(
    type_="button",
    class=if route == current { "nav-link active" } else { "nav-link" },
    on_click=command(emit, Navigate(route)),
    attrs=@html.Attrs::build().aria_current(
      if route == current {
        "page"
      } else {
        "false"
      },
    ),
    [@html.span(class="nav-indicator", ""), @html.span(label)],
  )
}

///|
fn stat(
  label : String,
  value : String,
  detail : String,
  tone : String,
) -> @rabbita.Html {
  @html.div(class="stat stat-\{tone}", [
    @html.dt(label),
    @html.dd(value),
    @html.span(class="stat-detail", detail),
  ])
}

///|
fn readiness_item(
  locale : @i18n.Locale,
  ready : Bool,
  label : String,
  detail : String,
) -> @rabbita.Html {
  @html.li(
    class=if ready { "readiness-item ready" } else { "readiness-item" },
    [
      @html.span(
        class="readiness-mark",
        attrs=@html.Attrs::build().aria_hidden("true"),
        if ready {
          "✓"
        } else {
          "!"
        },
      ),
      @html.div([
        @html.strong(label),
        @html.span(
          class="secondary",
          if ready {
            detail
          } else {
            localized(locale, "Action required · ", "需要操作 · ") +
            detail
          },
        ),
      ]),
    ],
  )
}

///|
fn deployment_ready(state : ConsoleState) -> Bool {
  state.overview.total_nodes == 4 &&
  state.overview.active_nodes == 4 &&
  state.overview.alerts == 0 &&
  state.overview.active_models > 0 &&
  state.catalog_templates.length() > 0
}

///|
fn overview_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("overview-title"), [
    @html.div(class="overview-grid", [
      @html.div(
        class=if state.overview.total_nodes == 0 {
          "health-panel health-panel-unknown"
        } else if state.overview.alerts == 0 {
          "health-panel health-panel-ok"
        } else {
          "health-panel health-panel-warning"
        },
        [
          @html.p(
            class="eyebrow",
            localized(state.locale, "Cluster posture", "集群状态"),
          ),
          @html.div(class="health-title", [
            @html.span(
              class="health-dot",
              attrs=@html.Attrs::build().aria_hidden("true"),
              "",
            ),
            @html.h2(
              id="overview-title",
              if state.overview.total_nodes == 0 {
                localized(
                  state.locale,
                  "Awaiting cluster telemetry",
                  "等待集群遥测",
                )
              } else if state.overview.alerts == 0 {
                localized(
                  state.locale,
                  "Cluster operational",
                  "集群运行正常",
                )
              } else {
                localized(
                  state.locale,
                  "Cluster needs attention",
                  "集群需要关注",
                )
              },
            ),
          ]),
          @html.p(
            class="health-copy",
            if state.overview.total_nodes == 0 {
              localized(
                state.locale,
                "Connect the controller and enroll a node to establish live cluster posture.",
                "连接控制器并注册节点，以建立实时集群状态。",
              )
            } else if state.overview.alerts == 0 {
              localized(
                state.locale,
                "All reported services are within their expected operating state.",
                "所有已上报服务均处于预期运行状态。",
              )
            } else {
              localized(
                state.locale,
                "\{state.overview.alerts} alert signals require operator review before the next change window.",
                "下一个变更窗口前，需要运维人员检查 \{state.overview.alerts} 个告警信号。",
              )
            },
          ),
          @html.dl(class="health-facts", [
            @html.div([
              @html.dt(
                localized(state.locale, "Node availability", "节点可用性"),
              ),
              @html.dd(
                localized(
                  state.locale,
                  "\{state.overview.active_nodes} of \{state.overview.total_nodes}",
                  "\{state.overview.active_nodes} / \{state.overview.total_nodes}",
                ),
              ),
            ]),
            @html.div([
              @html.dt(
                localized(state.locale, "Serving models", "服务中模型"),
              ),
              @html.dd(state.overview.active_models.to_string()),
            ]),
            @html.div([
              @html.dt(
                localized(state.locale, "Pending queue", "待处理队列"),
              ),
              @html.dd(state.overview.queue_depth.to_string()),
            ]),
          ]),
        ],
      ),
      @html.aside(class="activity-panel", [
        @html.p(
          class="eyebrow",
          localized(state.locale, "Change activity", "变更活动"),
        ),
        @html.p(
          class="activity-value",
          state.overview.recent_changes.to_string(),
        ),
        @html.p(
          class="activity-label",
          localized(
            state.locale,
            "recent control-plane changes",
            "项近期控制平面变更",
          ),
        ),
        @html.div(class="activity-divider", ""),
        @html.p(class="activity-note", [
          @html.strong(localized(state.locale, "Audit ready", "审计就绪")),
          @html.span(
            localized(
              state.locale,
              "Every consequential action produces a receipt.",
              "每项重要操作都会生成回执。",
            ),
          ),
        ]),
      ]),
    ]),
    @html.dl(class="stats", [
      stat(
        localized(state.locale, "Available nodes", "可用节点"),
        "\{state.overview.active_nodes}/\{state.overview.total_nodes}",
        if state.overview.total_nodes == 0 {
          localized(state.locale, "Telemetry unavailable", "遥测不可用")
        } else {
          localized(state.locale, "Ready for placement", "可用于放置")
        },
        if state.overview.total_nodes == 0 {
          "neutral"
        } else if state.overview.active_nodes == state.overview.total_nodes {
          "ok"
        } else {
          "warning"
        },
      ),
      stat(
        localized(state.locale, "Active models", "服务中模型"),
        state.overview.active_models.to_string(),
        localized(
          state.locale,
          "Approved and serving",
          "已批准并提供服务",
        ),
        "neutral",
      ),
      stat(
        localized(state.locale, "Queued requests", "排队请求"),
        state.overview.queue_depth.to_string(),
        localized(state.locale, "Awaiting admission", "等待准入"),
        if state.overview.queue_depth == 0 {
          "ok"
        } else {
          "neutral"
        },
      ),
      stat(
        localized(state.locale, "Open alerts", "未解决告警"),
        state.overview.alerts.to_string(),
        if state.overview.total_nodes == 0 {
          localized(state.locale, "Telemetry unavailable", "遥测不可用")
        } else if state.overview.alerts == 0 {
          localized(state.locale, "No active incidents", "无未解决事件")
        } else {
          localized(state.locale, "Review required", "需要检查")
        },
        if state.overview.total_nodes == 0 {
          "neutral"
        } else if state.overview.alerts == 0 {
          "ok"
        } else {
          "danger"
        },
      ),
    ]),
    @html.section(
      class="readiness-panel",
      attrs=@html.Attrs::build().aria_labelledby("deployment-readiness-title"),
      [
        @html.div(class="readiness-copy", [
          @html.p(
            class="eyebrow",
            localized(state.locale, "Deployment launchpad", "部署启动台"),
          ),
          @html.h2(
            id="deployment-readiness-title",
            if deployment_ready(state) {
              localized(
                state.locale,
                "Ready for one-click deployment",
                "已可一键部署",
              )
            } else {
              localized(
                state.locale,
                "Deployment prerequisites remain",
                "仍有部署前提未满足",
              )
            },
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "This live gate mirrors the final operator checks in the deployment guide. The controller still performs the authoritative preflight on click.",
              "此实时门禁对应部署指南中的最终运维检查。点击后控制器仍会执行权威预检。",
            ),
          ),
          @html.button(
            type_="button",
            class="primary-button readiness-action",
            disabled=!deployment_ready(state),
            on_click=command(emit, Navigate(Catalog)),
            localized(
              state.locale,
              "Open one-click deployment",
              "打开一键部署",
            ),
          ),
        ]),
        @html.ul(class="readiness-list", [
          readiness_item(
            state.locale,
            state.overview.total_nodes == 4,
            localized(
              state.locale,
              "Four DGX nodes enrolled",
              "已注册四台 DGX 节点",
            ),
            localized(
              state.locale,
              "\{state.overview.total_nodes} of 4 reporting telemetry",
              "4 台中有 \{state.overview.total_nodes} 台上报遥测",
            ),
          ),
          readiness_item(
            state.locale,
            state.overview.active_nodes == 4 && state.overview.alerts == 0,
            localized(state.locale, "Fleet healthy", "机群健康"),
            localized(
              state.locale,
              "\{state.overview.active_nodes} active · \{state.overview.alerts} alerts",
              "\{state.overview.active_nodes} 台活跃 · \{state.overview.alerts} 个告警",
            ),
          ),
          readiness_item(
            state.locale,
            state.overview.active_models > 0,
            localized(
              state.locale,
              "Approved model available",
              "已有批准模型",
            ),
            localized(
              state.locale,
              "\{state.overview.active_models} approved models",
              "\{state.overview.active_models} 个已批准模型",
            ),
          ),
          readiness_item(
            state.locale,
            state.catalog_templates.length() > 0,
            localized(
              state.locale,
              "Service template approved",
              "服务模板已批准",
            ),
            localized(
              state.locale,
              "\{state.catalog_templates.length()} immutable templates",
              "\{state.catalog_templates.length()} 个不可变模板",
            ),
          ),
        ]),
      ],
    ),
  ])
}

///|
fn status_badge(label : String, tone : String) -> @rabbita.Html {
  @html.span(class="status status-\{tone}", label)
}

///|
fn user_state_badge(
  locale : @i18n.Locale,
  state : @workspace.WorkspaceUserState,
) -> @rabbita.Html {
  match state {
    UserActive => status_badge(localized(locale, "Active", "已激活"), "ok")
    UserInvited =>
      status_badge(localized(locale, "Invited", "已邀请"), "pending")
    UserSuspended =>
      status_badge(localized(locale, "Suspended", "已暂停"), "muted")
    UserRevoked =>
      status_badge(localized(locale, "Revoked", "已撤销"), "muted")
  }
}

///|
fn grant_state_badge(
  locale : @i18n.Locale,
  state : @workspace.WorkspaceAccessGrantState,
) -> @rabbita.Html {
  match state {
    GrantActive => status_badge(localized(locale, "Active", "有效"), "ok")
    GrantExpired =>
      status_badge(localized(locale, "Expired", "已过期"), "warning")
    GrantRevoked =>
      status_badge(localized(locale, "Revoked", "已撤销"), "muted")
  }
}

///|
fn access_label(
  locale : @i18n.Locale,
  access : @workspace.WorkspaceAccess,
) -> String {
  match access {
    Administrator => localized(locale, "Administrator", "管理员")
    Developer => localized(locale, "Developer", "开发者")
    Observer => localized(locale, "Observer", "观察者")
  }
}

///|
fn lease_state_badge(
  locale : @i18n.Locale,
  state : @workspace.WorkspaceLeaseState,
) -> @rabbita.Html {
  match state {
    Requested =>
      status_badge(localized(locale, "Requested", "待审批"), "pending")
    Active => status_badge(localized(locale, "Active", "有效"), "ok")
    Suspended =>
      status_badge(localized(locale, "Suspended", "已暂停"), "warning")
    Expired => status_badge(localized(locale, "Expired", "已过期"), "muted")
    Revoked => status_badge(localized(locale, "Revoked", "已撤销"), "muted")
  }
}

///|
fn exclusive_lease_state_badge(
  locale : @i18n.Locale,
  state : String,
) -> @rabbita.Html {
  let (label, tone) = match state {
    "Active" => (localized(locale, "Active", "有效"), "ok")
    "Completed" => (localized(locale, "Sanitized", "已清理"), "ok")
    "Cancelled" => (localized(locale, "Cancelled", "已取消"), "neutral")
    "Quarantined" => (localized(locale, "Quarantined", "已隔离"), "danger")
    "Expiring" => (localized(locale, "Expiring", "正在到期"), "warning")
    "Draining" => (localized(locale, "Draining", "正在排空"), "warning")
    "RevokingAccess" =>
      (localized(locale, "Revoking access", "正在撤销访问"), "warning")
    "Sanitizing" => (localized(locale, "Sanitizing", "正在清理"), "warning")
    "Provisioning" =>
      (localized(locale, "Provisioning", "正在开通"), "pending")
    "Reserved" => (localized(locale, "Reserved", "已预留"), "pending")
    _ => (state, "neutral")
  }
  status_badge(label, tone)
}

///|
fn node_state_badge(
  locale : @i18n.Locale,
  state : @contracts.NodeState,
) -> @rabbita.Html {
  match state {
    Active => status_badge(localized(locale, "Active", "正常"), "ok")
    Enrolling =>
      status_badge(localized(locale, "Enrolling", "注册中"), "pending")
    Cordoned =>
      status_badge(localized(locale, "Cordoned", "已封锁调度"), "warning")
    Draining =>
      status_badge(localized(locale, "Draining", "正在排空"), "warning")
    Unreachable =>
      status_badge(localized(locale, "Unreachable", "无法访问"), "danger")
    Retired => status_badge(localized(locale, "Retired", "已退役"), "muted")
  }
}

///|
fn model_state_badge(
  locale : @i18n.Locale,
  state : @contracts.ModelState,
) -> @rabbita.Html {
  match state {
    Approved => status_badge(localized(locale, "Approved", "已批准"), "ok")
    Candidate =>
      status_badge(localized(locale, "Candidate", "候选"), "pending")
    Verified =>
      status_badge(localized(locale, "Verified", "已验证"), "pending")
    Evaluated =>
      status_badge(localized(locale, "Evaluated", "已评测"), "pending")
    Deprecated =>
      status_badge(localized(locale, "Deprecated", "已弃用"), "warning")
    Revoked => status_badge(localized(locale, "Revoked", "已撤销"), "danger")
  }
}

///|
fn deployment_state_badge(
  locale : @i18n.Locale,
  state : @contracts.DeploymentState,
) -> @rabbita.Html {
  match state {
    Ready => status_badge(localized(locale, "Ready", "就绪"), "ok")
    Pending =>
      status_badge(localized(locale, "Pending", "待处理"), "pending")
    Preparing =>
      status_badge(localized(locale, "Preparing", "准备中"), "pending")
    Starting =>
      status_badge(localized(locale, "Starting", "启动中"), "pending")
    Draining =>
      status_badge(localized(locale, "Draining", "正在排空"), "warning")
    Degraded =>
      status_badge(localized(locale, "Degraded", "已降级"), "warning")
    Failed => status_badge(localized(locale, "Failed", "失败"), "danger")
    Stopped => status_badge(localized(locale, "Stopped", "已停止"), "muted")
  }
}

///|
fn service_operation_state_badge(
  locale : @i18n.Locale,
  state : @deployment.DeploymentOperationState,
) -> @rabbita.Html {
  match state {
    Submitted =>
      status_badge(localized(locale, "Submitted", "已提交"), "pending")
    Blocked => status_badge(localized(locale, "Blocked", "已阻止"), "danger")
    Planned =>
      status_badge(localized(locale, "Planned", "已规划"), "pending")
    Reconciling =>
      status_badge(localized(locale, "Reconciling", "协调中"), "pending")
    Ready => status_badge(localized(locale, "Ready", "就绪"), "ok")
    Degraded =>
      status_badge(localized(locale, "Degraded", "已降级"), "warning")
    RollingBack =>
      status_badge(localized(locale, "Rolling back", "正在回滚"), "warning")
    RolledBack =>
      status_badge(localized(locale, "Rolled back", "已回滚"), "muted")
    Failed => status_badge(localized(locale, "Failed", "失败"), "danger")
    Deleted => status_badge(localized(locale, "Deleted", "已删除"), "muted")
  }
}

///|
fn users_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("users-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="users-title",
          localized(state.locale, "Users & access", "用户与访问权限"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Manage control-plane identities and time-bounded access grants. This view does not expose node credentials.",
            "管理控制平面身份和有时限的访问授权。此视图不会公开节点凭据。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.users.length()} users · \{state.access_grants.length()} grants",
          "\{state.users.length()} 位用户 · \{state.access_grants.length()} 项授权",
        ),
      ),
    ]),
    if state.users.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No user identities are available. Use Policies → Invite user to create the first typed workspace record.",
          "暂无用户身份。请使用“策略 → 邀请用户”创建第一条类型化工作区记录。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(state.locale, "Cluster users", "集群用户"),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "User", "用户")),
              @html.th(scope=Col, localized(state.locale, "Status", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Last active", "最近活动"),
              ),
              @html.th(scope=Col, localized(state.locale, "Grants", "授权")),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for user in state.users => {
                @html.tr([
                  @html.td([
                    @html.strong(user.display_name),
                    @html.span(class="secondary", user.email),
                    @html.span(class="mono secondary", user.user_id),
                  ]),
                  @html.td(user_state_badge(state.locale, user.state)),
                  @html.td(generated_time_label(state.locale, user.last_active)),
                  @html.td(user.grant_count.to_string()),
                  @html.td(class="row-actions", [
                    if user.state == UserInvited || user.state == UserSuspended {
                      @html.button(
                        type_="button",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Activate user \{user.user_id}",
                          "激活用户 \{user.user_id}",
                        ),
                        on_click=command(emit, ActivateUser(user.user_id)),
                        localized(state.locale, "Activate", "激活"),
                      )
                    } else {
                      @html.nothing
                    },
                    if user.state == UserActive {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Suspend user \{user.user_id}",
                          "暂停用户 \{user.user_id}",
                        ),
                        on_click=command(emit, BeginSuspendUser(user.user_id)),
                        localized(state.locale, "Suspend…", "暂停…"),
                      )
                    } else {
                      @html.nothing
                    },
                    if user.state != UserRevoked {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Revoke user \{user.user_id}",
                          "撤销用户 \{user.user_id}",
                        ),
                        on_click=command(emit, BeginRevokeUser(user.user_id)),
                        localized(state.locale, "Revoke…", "撤销…"),
                      )
                    } else {
                      @html.span(
                        class="secondary",
                        localized(state.locale, "No actions", "无可用操作"),
                      )
                    },
                  ]),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.h3(localized(state.locale, "Access grants", "访问授权")),
    if state.access_grants.length() == 0 {
      @html.p(
        class="empty-state compact",
        localized(
          state.locale,
          "No access grants are available.",
          "暂无访问授权。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Scoped access grants",
              "限定范围的访问授权",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Principal", "主体"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Role / scope", "角色 / 范围"),
              ),
              @html.th(scope=Col, localized(state.locale, "Status", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Expires", "到期时间"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for grant in state.access_grants => {
                @html.tr([
                  @html.td([
                    @html.strong(grant.user_id),
                    @html.span(class="mono secondary", grant.grant_id),
                  ]),
                  @html.td([
                    @html.strong(access_label(state.locale, grant.role)),
                    @html.span(class="secondary", grant.scope),
                  ]),
                  @html.td(grant_state_badge(state.locale, grant.state)),
                  @html.td(generated_time_label(state.locale, grant.expires_at)),
                  @html.td(
                    @html.button(
                      type_="button",
                      class="danger-secondary",
                      disabled=grant.state != GrantActive,
                      title=localized(
                        state.locale,
                        "Revoke grant \{grant.grant_id}",
                        "撤销授权 \{grant.grant_id}",
                      ),
                      on_click=command(
                        emit,
                        BeginRevokeAccessGrant(grant.grant_id),
                      ),
                      localized(state.locale, "Revoke…", "撤销…"),
                    ),
                  ),
                ])
              }
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn leases_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("leases-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="leases-title",
          localized(state.locale, "Lease operations", "租约运维"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Exclusive machine access and workspace capacity are separate authorities. Ending machine access always revokes credentials, stops tenant work, sanitizes the node, and verifies a clean baseline before placement resumes.",
            "独占机器访问与工作区容量属于不同权限。结束机器访问时，系统必须撤销凭据、停止租户工作、清理节点并验证干净基线，随后才能恢复调度。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.exclusive_node_leases.count_if(lease => lease.state == "Active")} machines leased · \{state.compute_leases.count_if(lease => lease.state == Active)} workspace leases",
          "\{state.exclusive_node_leases.count_if(lease => lease.state == "Active")} 台机器租用中 · \{state.compute_leases.count_if(lease => lease.state == Active)} 项工作区租约",
        ),
      ),
    ]),
    @html.div(class="lease-cleanup-policy", [
      @html.strong(
        localized(
          state.locale,
          "Fail-closed cleanup boundary",
          "故障关闭式清理边界",
        ),
      ),
      @html.p(
        localized(
          state.locale,
          "Natural expiry and early termination use the same generation-fenced path: revoke → sanitize → verify → release. Any failed or stale evidence quarantines the DGX.",
          "自然到期与提前终止使用同一条代际隔离路径：撤销 → 清理 → 验证 → 释放。任何失败或过期证据都会隔离该 DGX。",
        ),
      ),
    ]),
    @html.div(class="subsection-heading", [
      @html.div([
        @html.h3(
          localized(
            state.locale,
            "Exclusive machine leases",
            "独占机器租约",
          ),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "A node remains fenced until the cleanup helper returns generation-bound verification evidence.",
            "节点会保持隔离，直到清理助手返回绑定到对应代际的验证证据。",
          ),
        ),
      ]),
    ]),
    if state.exclusive_node_leases.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No exclusive machine leases are recorded.",
          "暂无独占机器租约。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Exclusive machine lease cleanup state",
              "独占机器租约清理状态",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                localized(state.locale, "Lease / user", "租约 / 用户"),
              ),
              @html.th(localized(state.locale, "Node", "节点")),
              @html.th(localized(state.locale, "State", "状态")),
              @html.th(localized(state.locale, "Expires", "到期时间")),
              @html.th(localized(state.locale, "Generation", "代际")),
              @html.th(localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for lease in state.exclusive_node_leases => {
                @html.tr([
                  @html.td([
                    @html.strong(lease.unix_username),
                    @html.span(class="mono secondary", lease.lease_id),
                    @html.span(class="mono secondary", lease.subject_ref),
                  ]),
                  @html.td(class="mono", lease.node_id),
                  @html.td(
                    exclusive_lease_state_badge(state.locale, lease.state),
                  ),
                  @html.td(generated_time_label(state.locale, lease.expires_at)),
                  @html.td(class="mono", lease.generation.to_string()),
                  @html.td(class="row-actions", [
                    if lease.state == "Requested" ||
                      lease.state == "Reserved" ||
                      lease.state == "Provisioning" ||
                      lease.state == "Active" ||
                      lease.state == "Quarantined" {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Terminate exclusive lease \{lease.lease_id}",
                          "终止独占租约 \{lease.lease_id}",
                        ),
                        on_click=command(
                          emit,
                          BeginTerminateExclusiveNodeLease(
                            lease.lease_id,
                            lease.generation,
                          ),
                        ),
                        localized(
                          state.locale,
                          "Terminate & clean…",
                          "终止并清理…",
                        ),
                      )
                    } else {
                      @html.span(
                        class="secondary",
                        localized(
                          state.locale,
                          if lease.state == "Completed" ||
                            lease.state == "Cancelled" {
                            "No actions"
                          } else {
                            "Cleanup in progress"
                          },
                          if lease.state == "Completed" ||
                            lease.state == "Cancelled" {
                            "无可用操作"
                          } else {
                            "清理进行中"
                          },
                        ),
                      )
                    },
                  ]),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.div(class="subsection-heading", [
      @html.div([
        @html.h3(
          localized(
            state.locale,
            "Workspace capacity leases",
            "工作区容量租约",
          ),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "These grant control-plane capacity only and never grant direct DGX login access.",
            "这些租约只授予控制平面容量，绝不会直接授予 DGX 登录权限。",
          ),
        ),
      ]),
    ]),
    if state.compute_leases.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No compute or workspace leases are active. Use Policies → Create workspace lease after the user and access grant exist; it never grants direct node access.",
          "暂无有效的计算租约或工作区租约。用户和访问授权就绪后，请使用“策略 → 创建工作区租约”；租约绝不会授予节点直接访问权限。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Compute and workspace leases",
              "计算租约与工作区租约",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Lease / owner", "租约 / 所有者"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Workspace", "工作区"),
              ),
              @html.th(scope=Col, localized(state.locale, "Resource", "资源")),
              @html.th(scope=Col, localized(state.locale, "Status", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Window", "有效期"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for lease in state.compute_leases => {
                @html.tr([
                  @html.td([
                    @html.strong(lease.user_id),
                    @html.span(class="mono secondary", lease.lease_id),
                  ]),
                  @html.td(lease.workspace),
                  @html.td(lease_resource_label(state.locale, lease.resource)),
                  @html.td(lease_state_badge(state.locale, lease.state)),
                  @html.td([
                    @html.span(
                      localized(
                        state.locale,
                        "Starts \{generated_time_label(state.locale, lease.started_at)}",
                        "开始于 \{generated_time_label(state.locale, lease.started_at)}",
                      ),
                    ),
                    @html.span(
                      class="secondary",
                      localized(
                        state.locale,
                        "Expires \{generated_time_label(state.locale, lease.expires_at)}",
                        "到期于 \{generated_time_label(state.locale, lease.expires_at)}",
                      ),
                    ),
                  ]),
                  @html.td(class="row-actions", [
                    if lease.state == Requested {
                      @html.button(
                        type_="button",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Activate lease \{lease.lease_id}",
                          "激活租约 \{lease.lease_id}",
                        ),
                        on_click=command(
                          emit,
                          ActivateComputeLease(lease.lease_id),
                        ),
                        localized(state.locale, "Activate", "激活"),
                      )
                    } else {
                      @html.nothing
                    },
                    if lease.state == Active {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "End lease \{lease.lease_id}",
                          "结束租约 \{lease.lease_id}",
                        ),
                        on_click=command(
                          emit,
                          BeginEndComputeLease(lease.lease_id),
                        ),
                        localized(
                          state.locale,
                          "End lease…",
                          "结束租约…",
                        ),
                      )
                    } else if lease.state != Requested {
                      @html.span(
                        class="secondary",
                        localized(state.locale, "No actions", "无可用操作"),
                      )
                    } else {
                      @html.nothing
                    },
                  ]),
                ])
              }
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn nodes_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("nodes-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="nodes-title",
          localized(state.locale, "Hardware nodes", "硬件节点"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Inspect placement capacity and move nodes through controlled maintenance states.",
            "检查放置容量，并通过受控维护状态管理节点。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.nodes.length()} enrolled",
          "已注册 \{state.nodes.length()} 个",
        ),
      ),
    ]),
    if state.nodes.length() == 0 {
      @html.div(class="empty-state empty-state-action", [
        @html.strong(
          localized(state.locale, "No nodes enrolled", "尚未注册节点"),
        ),
        @html.p(
          localized(
            state.locale,
            "Create a short-lived enrollment token, start the node daemon, then refresh telemetry.",
            "请创建短期有效的注册令牌、启动节点守护进程，然后刷新遥测。",
          ),
        ),
        @html.button(
          type_="button",
          on_click=command(emit, Navigate(Policies)),
          localized(
            state.locale,
            "Open enrollment policy",
            "打开注册策略",
          ),
        ),
      ])
    } else {
      @html.div(
        class="node-list",
        [
          for node in state.nodes => node_item(state.locale, node, emit)
        ],
      )
    },
  ])
}

///|
fn node_item(
  locale : @i18n.Locale,
  node : NodeRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let lease_holder = if node.lease_holder == "" {
    localized(locale, "Unassigned", "未分配")
  } else {
    node.lease_holder
  }
  let active_assignment = if node.active_assignment == "" {
    localized(locale, "Idle", "空闲")
  } else {
    node.active_assignment
  }
  let utilization_percent = (node.utilization_per_mille / 10).clamp(
    min=0,
    max=100,
  )
  let memory_percent = if node.total_memory_mib > 0 {
    (node.used_memory_mib * 100 / node.total_memory_mib).clamp(min=0, max=100)
  } else {
    0
  }
  @html.details(class="node-record", [
    @html.summary(class="node-summary", [
      @html.div(class="node-identity", [
        @html.strong(node.node_id),
        @html.span(
          class="mono secondary",
          architecture_label(locale, node.architecture),
        ),
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(localized(locale, "State", "状态")),
        node_state_badge(locale, node.state),
      ]),
      @html.div(class="node-summary-cell node-memory-summary", [
        @html.span(localized(locale, "GPU memory", "GPU 内存")),
        @html.strong("\{node.free_memory_mib} MiB"),
        @html.small(localized(locale, "free", "可用")),
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(localized(locale, "GPU utilization", "GPU 利用率")),
        @html.strong("\{utilization_percent}%"),
      ]),
      @html.div(class="node-summary-cell node-lease-summary", [
        @html.span(localized(locale, "Exclusive lease", "独占租约")),
        @html.strong(lease_holder),
      ]),
      @html.span(
        class="node-expand-cue",
        localized(locale, "Inspect", "查看详情"),
      ),
    ]),
    @html.div(class="node-detail", [
      @html.div(class="node-detail-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(locale, "Live node evidence", "节点实时证据"),
          ),
          @html.h3(localized(locale, "Resource telemetry", "资源遥测")),
        ]),
        @html.span(
          class="secondary",
          localized(
            locale,
            "Last heartbeat · \{node.last_seen}",
            "最近心跳 · \{node.last_seen}",
          ),
        ),
      ]),
      @html.div(class="node-metrics", [
        @html.div(class="node-metric", [
          @html.span(localized(locale, "GPU utilization", "GPU 利用率")),
          @html.strong("\{utilization_percent}%"),
          @html.progress(
            value=utilization_percent,
            max=100,
            "\{utilization_percent}%",
          ),
        ]),
        @html.div(class="node-metric", [
          @html.span(localized(locale, "Memory used", "已用内存")),
          @html.strong("\{node.used_memory_mib} MiB"),
          @html.progress(value=memory_percent, max=100, "\{memory_percent}%"),
          @html.small(
            localized(
              locale,
              "\{node.total_memory_mib} MiB total",
              "总计 \{node.total_memory_mib} MiB",
            ),
          ),
        ]),
        @html.div(class="node-metric", [
          @html.span(localized(locale, "Temperature", "温度")),
          @html.strong("\{node.temperature_celsius} °C"),
          @html.small(
            localized(
              locale, "Maximum observed sensor", "已观测传感器最大值",
            ),
          ),
        ]),
        @html.div(class="node-metric", [
          @html.span(localized(locale, "Power draw", "功耗")),
          @html.strong("\{node.power_watts} W"),
          @html.small(
            localized(
              locale, "Node-reported GPU aggregate", "节点上报 GPU 汇总",
            ),
          ),
        ]),
      ]),
      @html.dl(class="node-facts", [
        @html.div([
          @html.dt(localized(locale, "Lease holder", "租约持有者")),
          @html.dd(lease_holder),
        ]),
        @html.div([
          @html.dt(localized(locale, "Assignment", "当前分配")),
          @html.dd(class="mono", active_assignment),
        ]),
        @html.div([
          @html.dt(localized(locale, "Running services", "运行服务")),
          @html.dd(node.workloads.to_string()),
        ]),
        @html.div([
          @html.dt(localized(locale, "Placement model", "放置模型")),
          @html.dd(
            localized(
              locale, "One lease · one machine", "一个租约 · 一台机器",
            ),
          ),
        ]),
      ]),
      @html.div(class="node-detail-actions", [
        @html.p(
          localized(
            locale, "Maintenance changes are confirmation-gated and recorded with an audit receipt.",
            "维护变更必须二次确认，并生成审计回执。",
          ),
        ),
        @html.div(class="row-actions", [
          @html.button(
            type_="button",
            title=localized(
              locale,
              "Cordon \{node.node_id}",
              "封锁调度 \{node.node_id}",
            ),
            on_click=command(emit, BeginCordon(node.node_id)),
            localized(locale, "Cordon…", "封锁调度…"),
          ),
          @html.button(
            type_="button",
            class="danger-secondary",
            title=localized(
              locale,
              "Drain \{node.node_id}",
              "排空 \{node.node_id}",
            ),
            on_click=command(emit, BeginDrain(node.node_id)),
            localized(locale, "Drain…", "排空…"),
          ),
        ]),
      ]),
    ]),
  ])
}

///|
fn models_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("models-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="models-title",
          localized(state.locale, "Model registry", "模型注册表"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Review serving eligibility, evaluation posture, and approved aliases.",
            "检查服务资格、评测状态和已批准的模型别名。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.models.length()} artifacts",
          "\{state.models.length()} 个模型制品",
        ),
      ),
    ]),
    if state.models.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No model artifacts registered.",
          "尚未注册模型制品。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Registered model artifacts",
              "已注册模型制品",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Model", "模型")),
              @html.th(
                scope=Col,
                localized(state.locale, "Lifecycle", "生命周期"),
              ),
              @html.th(scope=Col, localized(state.locale, "Evidence", "证据")),
              @html.th(
                scope=Col,
                localized(state.locale, "Compatibility", "兼容性"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Serving alias", "服务模型别名"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for model in state.models => model_item(state.locale, model, emit)
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn model_item(
  locale : @i18n.Locale,
  model : ModelRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.tr([
    @html.td([
      @html.strong(model.model_id),
      @html.span(class="mono secondary", model.version),
    ]),
    @html.td(model_state_badge(locale, model.state)),
    @html.td([
      @html.span(
        localized(
          locale,
          "License · \{license_evidence_label(locale, model.license_status)}",
          "许可证 · \{license_evidence_label(locale, model.license_status)}",
        ),
      ),
      @html.span(
        class="secondary",
        localized(
          locale,
          "Evaluation · \{evaluation_evidence_label(locale, model.evaluation_status)}",
          "评测 · \{evaluation_evidence_label(locale, model.evaluation_status)}",
        ),
      ),
    ]),
    @html.td(model.compatibility),
    @html.td(class="mono", model.alias_name),
    @html.td(
      if model.alias_name == "—" {
        @html.span(
          class="secondary",
          localized(locale, "No alias", "无模型别名"),
        )
      } else {
        @html.button(
          type_="button",
          class="danger-secondary",
          on_click=command(emit, BeginRollback(model.alias_name)),
          localized(locale, "Roll back…", "回滚…"),
        )
      },
    ),
  ])
}

///|
fn quick_service_name_valid(value : String) -> Bool {
  @contracts.valid_identifier(value.trim().to_owned(), maximum_length=128)
}

///|
fn catalog_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let template_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=state.quick_template == "",
      localized(state.locale, "Select a template", "选择模板"),
    ),
  ]
  for template in state.catalog_templates {
    template_options.push(
      @html.option(
        value="\{template.template_id}@\{template.version}",
        selected=state.quick_template ==
          "\{template.template_id}@\{template.version}",
        "\{template.display_name} · \{template.version}",
      ),
    )
  }
  let service_name_present = state.quick_deployment_id.trim() != ""
  let service_name_valid = quick_service_name_valid(state.quick_deployment_id)
  @html.section(attrs=@html.Attrs::build().aria_labelledby("catalog-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="catalog-title",
          localized(state.locale, "Model service catalog", "模型服务目录"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Deploy an approved, immutable model-service template through one governed intent.",
            "通过一个受治理的意图部署已批准且不可变的模型服务模板。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.catalog_templates.length()} templates",
          "\{state.catalog_templates.length()} 个模板",
        ),
      ),
    ]),
    @html.div(class="operation-panel", [
      @html.div(class="operation-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(state.locale, "Governed deployment", "受治理的部署"),
          ),
          @html.h3(
            localized(
              state.locale,
              "One-click model service",
              "一键模型服务",
            ),
          ),
        ]),
        @html.span(
          class="status status-pending",
          localized(state.locale, "Preflight enforced", "强制预检"),
        ),
      ]),
      @html.p(
        class="section-copy",
        localized(
          state.locale,
          "License, verification, evaluation, alias, secret, data-class and capacity blockers are checked before any assignment is published.",
          "发布任何分配前都会检查许可证、验证、评测、别名、密钥引用、数据分类与容量阻塞项。",
        ),
      ),
      @html.ol(class="deployment-steps", [
        @html.li([
          @html.span("1"),
          @html.strong(
            localized(
              state.locale,
              "Select approved template",
              "选择已批准模板",
            ),
          ),
        ]),
        @html.li([
          @html.span("2"),
          @html.strong(
            localized(state.locale, "Name the service", "命名服务"),
          ),
        ]),
        @html.li([
          @html.span("3"),
          @html.strong(
            localized(state.locale, "Preflight and deploy", "预检并部署"),
          ),
        ]),
      ]),
      @html.div(class="operation-form", [
        @html.div(class="field-group", [
          @html.label(
            for_="quick-deployment-id",
            localized(state.locale, "Service name", "服务名称"),
          ),
          @html.input(
            input_type=Text,
            id="quick-deployment-id",
            maxlength=128,
            attrs=@html.Attrs::build()
              .aria_describedby("quick-deployment-id-help")
              .aria_invalid(
                if service_name_present && !service_name_valid {
                  "true"
                } else {
                  "false"
                },
              ),
            placeholder="text-service",
            value=state.quick_deployment_id,
            on_input=text_command(emit, value => QuickDeploymentIdChanged(value)),
          ),
          @html.p(
            id="quick-deployment-id-help",
            class=if service_name_present && !service_name_valid {
              "field-help field-error"
            } else {
              "field-help"
            },
            localized(
              state.locale,
              "Use 1–128 letters, numbers, hyphens, underscores, dots, or colons.",
              "使用 1–128 个字母、数字、连字符、下划线、点或冒号。",
            ),
          ),
        ]),
        @html.div(class="field-group", [
          @html.label(
            for_="quick-template",
            localized(state.locale, "Approved template", "已批准模板"),
          ),
          @html.select(
            id="quick-template",
            on_change=text_command(emit, value => QuickTemplateChanged(value)),
            template_options,
          ),
        ]),
        @html.div(class="fixed-capacity", [
          @html.div(class="fixed-capacity-mark", "1"),
          @html.div([
            @html.strong(
              localized(
                state.locale,
                "One service · one assigned machine",
                "一个服务 · 一台分配机器",
              ),
            ),
            @html.p(
              localized(
                state.locale,
                "Capacity is fixed. LunaNexa selects one eligible DGX after preflight; replicas, batch scheduling, and autoscaling are unavailable.",
                "容量固定。LunaNexa 在预检后选择一台符合条件的 DGX；不提供副本、批处理调度或自动扩缩容。",
              ),
            ),
          ]),
        ]),
      ]),
      @html.div(class="operation-actions", [
        @html.span(
          class="secondary",
          localized(
            state.locale,
            "Creates one durable idempotent operation",
            "创建一个持久且幂等的操作",
          ),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=state.loading ||
            !service_name_valid ||
            state.quick_template == "",
          on_click=command(emit, SubmitQuickDeployment),
          localized(state.locale, "Deploy model service", "部署模型服务"),
        ),
      ]),
    ]),
    if state.catalog_templates.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No approved model-service templates are registered.",
          "尚未注册已批准的模型服务模板。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Approved model-service templates",
              "已批准的模型服务模板",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Template", "模板")),
              @html.th(
                scope=Col,
                localized(state.locale, "Model selector", "模型选择器"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Runtime", "运行时"),
              ),
              @html.th(scope=Col, localized(state.locale, "Policy", "策略")),
            ]),
          ),
          @html.tbody(
            [
              for template in state.catalog_templates => {
                @html.tr([
                  @html.td([
                    @html.strong(template.display_name),
                    @html.span(
                      class="mono secondary",
                      "\{template.template_id}@\{template.version}",
                    ),
                  ]),
                  @html.td(class="mono", template.model_selector),
                  @html.td(
                    "\{template.runtime.name} · \{template.architecture}",
                  ),
                  @html.td(
                    if template.rollout.automatic_promotion {
                      localized(
                        state.locale,
                        "Auto-promote allowed",
                        "允许自动提升",
                      )
                    } else {
                      localized(
                        state.locale,
                        "Explicit promotion",
                        "显式提升",
                      )
                    },
                  ),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(localized(state.locale, "Service operations", "服务操作")),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Restart-safe progress, endpoint and audit evidence for every model service.",
            "查看每个模型服务的重启安全进度、端点与审计证据。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.service_deployments.length()} operations",
          "\{state.service_deployments.length()} 个操作",
        ),
      ),
    ]),
    if state.service_deployments.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No model-service operations yet.",
          "尚无模型服务操作。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Model-service operations",
              "模型服务操作",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Service", "服务")),
              @html.th(scope=Col, localized(state.locale, "State", "状态")),
              @html.th(scope=Col, localized(state.locale, "Endpoint", "端点")),
              @html.th(scope=Col, localized(state.locale, "Evidence", "证据")),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for operation in state.service_deployments => {
                @html.tr([
                  @html.td([
                    @html.strong(operation.deployment_id),
                    @html.span(class="mono secondary", operation.operation_id),
                  ]),
                  @html.td(
                    service_operation_state_badge(state.locale, operation.state),
                  ),
                  @html.td(
                    class="mono",
                    operation.endpoint
                    .map(value => {
                      "\{value.canonical_path} · \{value.model_selector}"
                    })
                    .unwrap_or("—"),
                  ),
                  @html.td(class="mono secondary", operation.audit_receipt),
                  @html.td(
                    @html.div(class="row-actions", [
                      @html.button(
                        type_="button",
                        disabled=operation.state != Ready,
                        on_click=command(
                          emit,
                          PromoteServiceDeployment(operation.deployment_id),
                        ),
                        localized(state.locale, "Promote", "提升"),
                      ),
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=operation.state == Deleted ||
                          operation.state == RolledBack,
                        on_click=command(
                          emit,
                          BeginRollbackServiceDeployment(
                            operation.deployment_id,
                          ),
                        ),
                        localized(state.locale, "Roll back…", "回滚…"),
                      ),
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=operation.state == Deleted,
                        on_click=command(
                          emit,
                          BeginDeleteServiceDeployment(operation.deployment_id),
                        ),
                        localized(state.locale, "Delete…", "删除…"),
                      ),
                    ]),
                  ),
                ])
              }
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn deployments_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("deployments-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="deployments-title",
            localized(state.locale, "Deployments", "部署"),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Compare desired and observed runtime state with each placement decision.",
              "对比每项放置决策的期望状态与实际运行时状态。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.deployments.length()} assignments",
            "\{state.deployments.length()} 项分配",
          ),
        ),
      ]),
      if state.deployments.length() == 0 {
        @html.div(class="empty-state empty-state-action", [
          @html.strong(
            localized(
              state.locale,
              "No deployments are currently assigned",
              "当前没有已分配的部署",
            ),
          ),
          @html.p(
            localized(
              state.locale,
              "Choose an approved model-service template. Preflight will select exactly one eligible machine.",
              "请选择已批准的模型服务模板。预检将只选择一台符合条件的机器。",
            ),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            on_click=command(emit, Navigate(Catalog)),
            localized(
              state.locale,
              "Open one-click deployment",
              "打开一键部署",
            ),
          ),
        ])
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(state.locale, "Model deployments", "模型部署"),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Deployment", "部署"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Desired", "期望状态"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Observed", "实际状态"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Placement rationale", "调度依据"),
                ),
                @html.th(scope=Col, localized(state.locale, "Action", "操作")),
              ]),
            ),
            @html.tbody(
              [
                for deployment in state.deployments => {
                  deployment_item(state.locale, deployment, emit)
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn deployment_item(
  locale : @i18n.Locale,
  deployment : DeploymentRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.tr([
    @html.td([
      @html.strong(deployment.deployment_id),
      @html.span(class="mono secondary", deployment.assignment_id),
    ]),
    @html.td(deployment_state_badge(locale, deployment.desired)),
    @html.td(deployment_state_badge(locale, deployment.observed)),
    @html.td(deployment.placement_reason),
    @html.td(
      @html.button(
        type_="button",
        class="danger-secondary",
        on_click=command(emit, BeginStopDeployment(deployment.assignment_id)),
        localized(locale, "Stop…", "停止…"),
      ),
    ),
  ])
}

///|
fn requests_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("requests-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="requests-title",
          localized(state.locale, "Request operations", "请求监控"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Observe throughput and failures without exposing prompt or output content.",
            "在不公开提示词或输出内容的前提下观察吞吐量和失败情况。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.requests.count} audited",
          "已审计 \{state.requests.count} 项",
        ),
      ),
    ]),
    @html.dl(class="stats request-stats", [
      stat(
        localized(state.locale, "Audited events", "已审计事件"),
        state.requests.count.to_string(),
        localized(state.locale, "Bounded receipts", "范围受限的回执"),
        "neutral",
      ),
      stat(
        localized(state.locale, "Benchmark p95", "基准测试 p95"),
        "\{state.requests.p95_ms} ms",
        localized(state.locale, "Latest evidence", "最新证据"),
        "neutral",
      ),
      stat(
        localized(state.locale, "Throughput", "吞吐量"),
        "\{state.requests.throughput_per_second}/s",
        localized(state.locale, "Observed rate", "观测速率"),
        "ok",
      ),
      stat(
        localized(state.locale, "Failures", "失败"),
        state.requests.errors.to_string(),
        if state.requests.errors == 0 {
          localized(state.locale, "No failures", "无失败")
        } else {
          localized(state.locale, "Review receipts", "检查回执")
        },
        if state.requests.errors == 0 {
          "ok"
        } else {
          "danger"
        },
      ),
    ]),
    @html.p(
      class="privacy-note",
      localized(
        state.locale,
        "Request detail is bounded and excludes raw payloads.",
        "请求详情受边界限制，且不包含原始载荷。",
      ),
    ),
    if state.request_details.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No request receipts are available yet.",
          "暂无请求回执。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Bounded workload request receipts",
              "有边界的工作负载请求回执",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Timestamp", "时间戳"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
              @html.th(
                scope=Col,
                localized(state.locale, "Model selector", "模型选择器"),
              ),
              @html.th(scope=Col, localized(state.locale, "Result", "结果")),
              @html.th(scope=Col, localized(state.locale, "Receipt", "回执")),
            ]),
          ),
          @html.tbody(
            [
              for detail in state.request_details => {
                @html.tr([
                  @html.td(
                    class="mono secondary",
                    detail.timestamp_unix_ms.to_string(),
                  ),
                  @html.td(detail.action),
                  @html.td(class="mono", detail.model_selector),
                  @html.td(
                    status_badge(
                      result_label(state.locale, detail.result),
                      "ok",
                    ),
                  ),
                  @html.td(class="mono secondary", detail.receipt),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.div(class="subsection-heading", [
      @html.h3(localized(state.locale, "Latest live stream", "最新实时流")),
      @html.span(
        class="resource-count",
        localized(state.locale, "Browser session", "浏览器会话"),
      ),
    ]),
    @html.div(class="stream-panel", [
      if state.stream_events.length() == 0 {
        @html.p(
          class="empty-state compact",
          localized(
            state.locale,
            "No live stream has been run in this browser session.",
            "此浏览器会话尚未运行实时流。",
          ),
        )
      } else {
        @html.ol(
          class="stream-list",
          [
            for event in state.stream_events => {
              @html.li([
                @html.div(class="stream-meta", [
                  @html.span(
                    class="stream-sequence",
                    event.sequence.to_string(),
                  ),
                  @html.strong(stream_kind_label(state.locale, event.kind)),
                  if event.receipt == "" {
                    @html.nothing
                  } else {
                    @html.span(class="mono secondary", event.receipt)
                  },
                ]),
                if event.text == "" {
                  @html.nothing
                } else {
                  @html.pre(class="stream-output", event.text)
                },
              ])
            }
          ],
        )
      },
    ]),
  ])
}

///|
fn benchmarks_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("benchmarks-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="benchmarks-title",
            localized(state.locale, "Benchmark evidence", "基准测试证据"),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Versioned runtime measurements used for placement and promotion decisions.",
              "用于放置与提升决策的版本化运行时测量数据。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.benchmark_evidence.length()} profiles",
            "\{state.benchmark_evidence.length()} 个配置",
          ),
        ),
      ]),
      if state.benchmark_evidence.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No benchmark evidence has been recorded.",
            "尚未记录基准测试证据。",
          ),
        )
      } else {
        @html.ul(
          class="evidence-list",
          [
            for evidence in state.benchmark_evidence => {
              @html.li([
                @html.span(
                  class="evidence-mark",
                  attrs=@html.Attrs::build().aria_hidden("true"),
                  "",
                ),
                @html.div([
                  @html.strong(benchmark_evidence_label(state.locale, evidence)),
                  @html.span(
                    class="secondary",
                    localized(
                      state.locale,
                      "Recorded performance profile",
                      "已记录的性能配置",
                    ),
                  ),
                ]),
              ])
            }
          ],
        )
      },
    ],
  )
}

///|
fn retention_label(
  locale : @i18n.Locale,
  retention : @contracts.RetentionPolicy,
) -> String {
  match retention {
    Ephemeral => localized(locale, "Ephemeral", "临时（不保留）")
    EvaluationCapture(consent_receipt=_) =>
      localized(locale, "Evaluation capture", "评测采集")
    RetainUntil(expiry) =>
      localized(locale, "Retain until \{expiry}", "保留至 \{expiry}")
  }
}

///|
fn policies_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("policies-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="policies-title",
          localized(state.locale, "Policy & operations", "策略与运维"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Review effective controls and submit validated changes through the canonical API.",
            "检查生效的控制项，并通过规范 API 提交已验证的变更。",
          ),
        ),
      ]),
    ]),
    @html.dl(class="policy-summary", [
      @html.div([
        @html.dt(localized(state.locale, "Quotas", "配额")),
        @html.dd(state.policies.quota_count.to_string()),
      ]),
      @html.div([
        @html.dt(localized(state.locale, "Data classes", "数据分类")),
        @html.dd(state.policies.data_class_count.to_string()),
      ]),
      @html.div([
        @html.dt(
          localized(state.locale, "Default retention", "默认保留策略"),
        ),
        @html.dd(
          retention_label(state.locale, state.policies.default_retention),
        ),
      ]),
      @html.div([
        @html.dt(
          localized(state.locale, "Allowed runtimes", "允许的运行时"),
        ),
        @html.dd(
          if state.policies.allowed_runtimes.length() == 0 {
            localized(state.locale, "None configured", "未配置")
          } else {
            state.policies.allowed_runtimes.join(", ")
          },
        ),
      ]),
    ]),
    @html.div(class="operation-panel", [
      @html.div(class="operation-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(
              state.locale,
              "Validated control path",
              "已验证的控制路径",
            ),
          ),
          @html.h3(
            localized(
              state.locale,
              "Typed operator operation",
              "类型化运维操作",
            ),
          ),
        ]),
        @html.span(
          class="status status-pending",
          localized(state.locale, "Canonical JSON", "规范 JSON"),
        ),
      ]),
      @html.p(
        class="section-copy",
        localized(
          state.locale,
          "Submit canonical JSON to the same validated API used by automation. Secret values remain in browser memory and must not be pasted into model or assignment metadata.",
          "向自动化所使用的同一已验证 API 提交规范 JSON。机密值仅保留在浏览器内存中，不得粘贴到模型或分配元数据中。",
        ),
      ),
      @html.div(class="operation-form", [
        @html.div(class="field-group", [
          @html.label(
            for_="operation-name",
            localized(state.locale, "Operation", "操作"),
          ),
          @html.select(
            id="operation-name",
            on_change=text_command(emit, value => OperationChanged(value)),
            [
              @html.option(
                value="issue-enrollment-token",
                selected=state.operation_name == "issue-enrollment-token",
                localized(
                  state.locale,
                  "Issue enrollment token",
                  "签发注册令牌",
                ),
              ),
              @html.option(
                value="register-runtime",
                selected=state.operation_name == "register-runtime",
                localized(state.locale, "Register runtime", "注册运行时"),
              ),
              @html.option(
                value="register-model",
                selected=state.operation_name == "register-model",
                localized(state.locale, "Register model", "注册模型"),
              ),
              @html.option(
                value="register-template",
                selected=state.operation_name == "register-template",
                localized(
                  state.locale,
                  "Register model-service template",
                  "注册模型服务模板",
                ),
              ),
              @html.option(
                value="plan-deployment",
                selected=state.operation_name == "plan-deployment",
                localized(
                  state.locale,
                  "Preflight deployment intent",
                  "预检部署意图",
                ),
              ),
              @html.option(
                value="deploy-service",
                selected=state.operation_name == "deploy-service",
                localized(
                  state.locale,
                  "Deploy model service",
                  "部署模型服务",
                ),
              ),
              @html.option(
                value="record-license",
                selected=state.operation_name == "record-license",
                localized(state.locale, "Record license", "记录许可证"),
              ),
              @html.option(
                value="record-verification",
                selected=state.operation_name == "record-verification",
                localized(state.locale, "Record verification", "记录验证"),
              ),
              @html.option(
                value="record-evaluation",
                selected=state.operation_name == "record-evaluation",
                localized(state.locale, "Record evaluation", "记录评测"),
              ),
              @html.option(
                value="approve-model",
                selected=state.operation_name == "approve-model",
                localized(state.locale, "Approve model", "批准模型"),
              ),
              @html.option(
                value="promote-alias",
                selected=state.operation_name == "promote-alias",
                localized(state.locale, "Promote alias", "提升模型别名"),
              ),
              @html.option(
                value="set-quota",
                selected=state.operation_name == "set-quota",
                localized(state.locale, "Set quota", "设置配额"),
              ),
              @html.option(
                value="create-organization",
                selected=state.operation_name == "create-organization",
                localized(state.locale, "Create organization", "创建组织"),
              ),
              @html.option(
                value="create-cost-center",
                selected=state.operation_name == "create-cost-center",
                localized(
                  state.locale,
                  "Create cost center",
                  "创建成本中心",
                ),
              ),
              @html.option(
                value="create-project",
                selected=state.operation_name == "create-project",
                localized(
                  state.locale,
                  "Create commercial project",
                  "创建商业项目",
                ),
              ),
              @html.option(
                value="record-commercial-usage",
                selected=state.operation_name == "record-commercial-usage",
                localized(
                  state.locale,
                  "Record commercial usage",
                  "记录商业用量",
                ),
              ),
              @html.option(
                value="rate-commercial-usage",
                selected=state.operation_name == "rate-commercial-usage",
                localized(
                  state.locale,
                  "Rate commercial usage",
                  "计费商业用量",
                ),
              ),
              @html.option(
                value="create-commercial-budget",
                selected=state.operation_name == "create-commercial-budget",
                localized(
                  state.locale,
                  "Create commercial budget",
                  "创建商业预算",
                ),
              ),
              @html.option(
                value="create-commercial-quota",
                selected=state.operation_name == "create-commercial-quota",
                localized(
                  state.locale,
                  "Create commercial quota",
                  "创建商业配额",
                ),
              ),
              @html.option(
                value="register-agreement-template",
                selected=state.operation_name == "register-agreement-template",
                localized(
                  state.locale,
                  "Register agreement template",
                  "注册协议模板",
                ),
              ),
              @html.option(
                value="create-agreement",
                selected=state.operation_name == "create-agreement",
                localized(
                  state.locale,
                  "Create digital agreement",
                  "创建数字协议",
                ),
              ),
              @html.option(
                value="create-enterprise-membership",
                selected=state.operation_name == "create-enterprise-membership",
                localized(
                  state.locale,
                  "Create enterprise membership",
                  "创建企业成员关系",
                ),
              ),
              @html.option(
                value="publish-portal-agreement",
                selected=state.operation_name == "publish-portal-agreement",
                localized(
                  state.locale,
                  "Publish portal agreement",
                  "发布企业门户协议",
                ),
              ),
              @html.option(
                value="register-external-record",
                selected=state.operation_name == "register-external-record",
                localized(
                  state.locale,
                  "Register external evidence",
                  "登记外部证据",
                ),
              ),
              @html.option(
                value="decide-backpressure",
                selected=state.operation_name == "decide-backpressure",
                localized(state.locale, "Evaluate backpressure", "评估背压"),
              ),
              @html.option(
                value="validate-transfer-grant",
                selected=state.operation_name == "validate-transfer-grant",
                localized(
                  state.locale,
                  "Validate transfer grant",
                  "验证传输授权",
                ),
              ),
              @html.option(
                value="invite-user",
                selected=state.operation_name == "invite-user",
                localized(state.locale, "Invite user", "邀请用户"),
              ),
              @html.option(
                value="grant-access",
                selected=state.operation_name == "grant-access",
                localized(
                  state.locale,
                  "Grant scoped access",
                  "授予限定范围的访问权限",
                ),
              ),
              @html.option(
                value="create-compute-lease",
                selected=state.operation_name == "create-compute-lease",
                localized(
                  state.locale,
                  "Create workspace lease",
                  "创建工作区租约",
                ),
              ),
              @html.option(
                value="publish-assignment",
                selected=state.operation_name == "publish-assignment",
                localized(
                  state.locale,
                  "Publish assignment for controller signing",
                  "发布分配以供控制器签名",
                ),
              ),
              @html.option(
                value="invoke-workload",
                selected=state.operation_name == "invoke-workload",
                localized(state.locale, "Invoke workload", "调用工作负载"),
              ),
              @html.option(
                value="record-benchmark",
                selected=state.operation_name == "record-benchmark",
                localized(
                  state.locale,
                  "Record benchmark evidence",
                  "记录基准测试证据",
                ),
              ),
            ],
          ),
        ]),
        @html.div(class="field-group operation-body", [
          @html.label(
            for_="operation-body",
            localized(state.locale, "Canonical JSON body", "规范 JSON 正文"),
          ),
          @html.textarea(
            id="operation-body",
            rows=12,
            maxlength=1048576,
            value=state.operation_body,
            on_input=text_command(emit, value => OperationBodyChanged(value)),
            "",
          ),
        ]),
      ]),
      @html.div(class="operation-actions", [
        @html.span(
          class="secondary",
          localized(
            state.locale,
            "Validated by the same contract used by automation",
            "使用与自动化相同的契约进行验证",
          ),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=state.operation_body.trim() == "" || state.loading,
          on_click=command(emit, SubmitOperation),
          localized(state.locale, "Validate and submit", "验证并提交"),
        ),
      ]),
    ]),
  ])
}

///|
fn cost_centers_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("cost-centers-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="cost-centers-title",
            localized(
              state.locale,
              "Cost center governance",
              "成本中心治理",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Allocate metered model usage to a tenant hierarchy before rating, budget admission, and ledger finalization.",
              "在计费、预算准入和账本结算前，将模型用量分配至租户层级。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.cost_centers.length()} cost centers",
            "\{state.cost_centers.length()} 个成本中心",
          ),
        ),
      ]),
      @html.p(
        class="privacy-note",
        localized(
          state.locale,
          "Financial exports are tenant-scoped, formula-safe, and contain immutable ledger snapshots—not prompts or model payloads.",
          "财务导出限定租户范围、防公式注入，并仅包含不可变账本快照，不含提示词或模型载荷。",
        ),
      ),
      if state.cost_centers.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No cost centers are loaded. Create the organization hierarchy through the commercial API, then refresh.",
            "尚未加载成本中心。请通过商业管理 API 创建组织层级后刷新。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(
                state.locale,
                "Cost center financial posture",
                "成本中心财务状态",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Cost center", "成本中心"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Organization", "组织"),
                ),
                @html.th(scope=Col, localized(state.locale, "Parent", "上级")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Projects", "项目"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Provisional spend", "暂计支出"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Budget posture", "预算状态"),
                ),
              ]),
            ),
            @html.tbody(
              [
                for center in state.cost_centers => {
                  @html.tr([
                    @html.td([
                      @html.strong(center.display_name),
                      @html.span(class="mono secondary", center.cost_center_id),
                    ]),
                    @html.td(class="mono", center.organization_id),
                    @html.td(
                      class="mono secondary",
                      center.parent_cost_center_id,
                    ),
                    @html.td(center.project_count.to_string()),
                    @html.td(class="mono", center.provisional_spend),
                    @html.td(
                      status_badge(
                        center.budget_posture,
                        if center.budget_posture.contains("Within") {
                          "ok"
                        } else {
                          "warning"
                        },
                      ),
                    ),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn agreements_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("agreements-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="agreements-title",
            localized(
              state.locale,
              "Digital agreement lifecycle",
              "数字协议生命周期",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Track immutable template versions, clickwrap acceptance, signature callbacks, and separation-of-duties evidence.",
              "跟踪不可变模板版本、点击接受、签名回调与职责分离证据。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.agreements.length()} agreements",
            "\{state.agreements.length()} 份协议",
          ),
        ),
      ]),
      if state.agreements.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No agreement evidence is loaded.",
            "尚未加载协议证据。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(
                state.locale,
                "Digital agreement evidence",
                "数字协议证据",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Agreement", "协议"),
                ),
                @html.th(scope=Col, localized(state.locale, "Type", "类型")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Template", "模板"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Organization", "组织"),
                ),
                @html.th(scope=Col, localized(state.locale, "State", "状态")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Evidence receipt", "证据回执"),
                ),
              ]),
            ),
            @html.tbody(
              [
                for agreement in state.agreements => {
                  @html.tr([
                    @html.td(class="mono", agreement.agreement_id),
                    @html.td(agreement.agreement_type),
                    @html.td(class="mono", agreement.template_version),
                    @html.td(class="mono", agreement.organization_id),
                    @html.td(
                      status_badge(
                        agreement.state,
                        if agreement.state == "Executed" {
                          "ok"
                        } else {
                          "pending"
                        },
                      ),
                    ),
                    @html.td(class="mono secondary", agreement.evidence_receipt),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
      @html.div(class="section-heading enterprise-request-heading", [
        @html.div([
          @html.h2(
            localized(
              state.locale,
              "Enterprise lease requests",
              "企业租用申请",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Select one eligible node, then approve the tenant request into the exclusive-node lease authority.",
              "选择一个符合条件的节点，然后将租户申请批准到独占节点租约权限中。",
            ),
          ),
        ]),
        @html.div(class="portal-node-picker", [
          @html.label(
            for_="portal-node-id",
            localized(state.locale, "Assigned node", "分配节点"),
          ),
          @html.input(
            id="portal-node-id",
            value=state.portal_node_id,
            maxlength=128,
            placeholder="dgx-spark-01",
            on_input=text_command(emit, value => PortalNodeChanged(value)),
          ),
        ]),
      ]),
      if state.enterprise_lease_requests.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No enterprise lease requests are waiting.",
            "没有待处理的企业租用申请。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.thead(
              @html.tr([
                @html.th(localized(state.locale, "Request", "申请")),
                @html.th(localized(state.locale, "Organization", "组织")),
                @html.th(
                  localized(state.locale, "Project / user", "项目 / 用户"),
                ),
                @html.th(localized(state.locale, "Models", "模型")),
                @html.th(localized(state.locale, "State", "状态")),
                @html.th(localized(state.locale, "Decision", "决策")),
              ]),
            ),
            @html.tbody(
              [
                for request in state.enterprise_lease_requests => {
                  @html.tr([
                    @html.td(class="mono", request.request_id),
                    @html.td([
                      @html.strong(request.organization_id),
                      @html.span(class="mono secondary", request.subject_ref),
                    ]),
                    @html.td([
                      @html.strong(request.project_id),
                      @html.span(class="mono secondary", request.unix_username),
                    ]),
                    @html.td(request.requested_models),
                    @html.td(
                      status_badge(
                        request.state,
                        if request.state == "Submitted" {
                          "pending"
                        } else {
                          "ok"
                        },
                      ),
                    ),
                    @html.td(
                      if request.state == "Submitted" {
                        @html.div(class="table-actions", [
                          @html.button(
                            type_="button",
                            class="action-button primary",
                            disabled=state.loading ||
                              state.portal_node_id.trim() == "",
                            on_click=command(
                              emit,
                              ApproveEnterpriseLease(
                                request.request_id,
                                request.generation,
                              ),
                            ),
                            localized(state.locale, "Approve", "批准"),
                          ),
                          @html.button(
                            type_="button",
                            class="action-button",
                            disabled=state.loading,
                            on_click=command(
                              emit,
                              RejectEnterpriseLease(
                                request.request_id,
                                request.generation,
                              ),
                            ),
                            localized(state.locale, "Reject", "拒绝"),
                          ),
                        ])
                      } else {
                        @html.span(
                          class="mono secondary",
                          request.assigned_node_id,
                        )
                      },
                    ),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn qualified_services_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("qualified-services-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="qualified-services-title",
            localized(
              state.locale,
              "Qualified service adapters",
              "资质服务适配器",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Inspect normalized provider capabilities and callback evidence without exposing provider references or credentials.",
              "查看规范化供应商能力与回调证据，不暴露供应商引用或凭据。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.qualified_services.length()} adapters",
            "\{state.qualified_services.length()} 个适配器",
          ),
        ),
      ]),
      @html.p(
        class="privacy-note",
        localized(
          state.locale,
          "LunaFide is a deterministic test simulator only. It is not a qualified trust service, payment processor, tax platform, or production security boundary.",
          "LunaFide 仅为确定性测试模拟器，不是合格信任服务、支付处理器、税务平台或生产安全边界。",
        ),
      ),
      if state.qualified_services.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No provider adapters are loaded.",
            "尚未加载供应商适配器。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(
                state.locale,
                "Qualified service adapter posture",
                "资质服务适配器状态",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Provider", "供应商"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Capability", "能力"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Environment", "环境"),
                ),
                @html.th(scope=Col, localized(state.locale, "State", "状态")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Evidence policy", "证据策略"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Production", "生产"),
                ),
              ]),
            ),
            @html.tbody(
              [
                for service in state.qualified_services => {
                  @html.tr([
                    @html.td(@html.strong(service.provider)),
                    @html.td(service.capability),
                    @html.td(status_badge(service.environment, "warning")),
                    @html.td(status_badge(service.state, "ok")),
                    @html.td(service.evidence_policy),
                    @html.td(
                      status_badge(
                        if service.production_ready {
                          localized(state.locale, "Ready", "就绪")
                        } else {
                          localized(state.locale, "Not ready", "未就绪")
                        },
                        if service.production_ready {
                          "ok"
                        } else {
                          "danger"
                        },
                      ),
                    ),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn audit_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("audit-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="audit-title",
          localized(state.locale, "Audit evidence", "审计证据"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Trace consequential changes from actor and evidence through result and receipt.",
            "从操作者和证据追踪重要变更，直至结果与回执。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.audit.length()} events",
          "\{state.audit.length()} 个事件",
        ),
      ),
    ]),
    if state.audit.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No audit events are available.",
          "暂无审计事件。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Immutable operator audit evidence",
              "不可变的运维审计证据",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Actor", "操作者")),
              @html.th(scope=Col, localized(state.locale, "Decision", "决策")),
              @html.th(scope=Col, localized(state.locale, "Evidence", "证据")),
              @html.th(scope=Col, localized(state.locale, "Result", "结果")),
              @html.th(scope=Col, localized(state.locale, "Receipt", "回执")),
            ]),
          ),
          @html.tbody(
            [
              for event in state.audit => audit_item(state.locale, event)
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn audit_item(locale : @i18n.Locale, event : AuditRow) -> @rabbita.Html {
  @html.tr([
    @html.td(event.actor),
    @html.td(event.decision),
    @html.td(event.evidence),
    @html.td(status_badge(result_label(locale, event.result), "ok")),
    @html.td(class="mono secondary", event.receipt),
  ])
}

///|
fn confirmation_copy(
  locale : @i18n.Locale,
  action : DestructiveAction,
) -> String {
  match action {
    SuspendUser(_) =>
      localized(
        locale, "Suspending this identity immediately blocks new workspace authorization. Existing records remain available for audit and later reactivation.",
        "暂停此身份会立即阻止新的工作区授权。现有记录仍可用于审计和后续重新激活。",
      )
    RevokeUser(_) =>
      localized(
        locale, "Revoking this identity is terminal and blocks new workspace authorization. Confirm the principal before continuing.",
        "撤销此身份是终止性操作，并会阻止新的工作区授权。继续前请确认主体。",
      )
    RevokeAccessGrant(_) =>
      localized(
        locale, "Revoking this grant removes its scoped access. Confirm only after checking the principal and scope.",
        "撤销此授权会移除其限定范围的访问权限。请在核对主体和范围后确认。",
      )
    EndComputeLease(_) =>
      localized(
        locale, "Ending this lease revokes its inference capacity and workspace access. Running work may be interrupted.",
        "结束此租约会撤销其推理容量和工作区访问权限，正在运行的工作可能中断。",
      )
    TerminateExclusiveNodeLease(_, _) =>
      localized(
        locale, "This immediately revokes the leased user's access and interrupts all tenant processes. The DGX stays unavailable until container, account, credential, process, volume and lease-data checks pass; any failure quarantines it.",
        "此操作会立即撤销租用用户的访问权限并中断全部租户进程。只有容器、账户、凭据、进程、卷和租约数据检查全部通过后，DGX 才会恢复可用；任何失败都会使其进入隔离状态。",
      )
    CordonNode(_) =>
      localized(
        locale, "Cordoning prevents new assignments on this node.", "封锁调度会阻止此节点接收新的分配。",
      )
    DrainNode(_) =>
      localized(
        locale, "Draining prevents new assignments and moves eligible subsequent work.",
        "排空会阻止新的分配，并将后续符合条件的工作迁移出去。",
      )
    StopDeployment(_) =>
      localized(
        locale, "Stopping ends the selected deployment assignment.", "停止操作会结束所选部署分配。",
      )
    RollbackAlias(_) =>
      localized(
        locale, "Rolling back changes the model version selected by this alias.",
        "回滚会更改此模型别名所选择的模型版本。",
      )
    RollbackServiceDeployment(_) =>
      localized(
        locale, "Rolling back removes only the signed assignments owned by this model service.",
        "回滚只会移除此模型服务拥有的已签名分配。",
      )
    DeleteServiceDeployment(_) =>
      localized(
        locale, "Deleting stops this model service and retains its immutable operation and audit evidence.",
        "删除会停止此模型服务，并保留其不可变操作与审计证据。",
      )
  }
}

///|
fn confirmation_view(
  locale : @i18n.Locale,
  confirmation : Confirmation?,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  match confirmation {
    None => @html.nothing
    Some(value) =>
      @html.aside(
        class="confirmation-panel",
        attrs=@html.Attrs::build()
          .role("alertdialog")
          .aria_labelledby("confirmation-title")
          .aria_describedby("confirmation-description"),
        [
          @html.p(
            class="eyebrow danger-copy",
            localized(locale, "Destructive operation", "破坏性操作"),
          ),
          @html.h2(
            id="confirmation-title",
            localized(
              locale, "Confirm destructive operation", "确认破坏性操作",
            ),
          ),
          @html.p(
            id="confirmation-description",
            confirmation_copy(locale, value.action),
          ),
          @html.dl(class="confirmation-scope", [
            @html.div([
              @html.dt(localized(locale, "Scope", "范围")),
              @html.dd(value.scope),
            ]),
            @html.div([
              @html.dt(
                localized(locale, "Confirmation receipt", "确认回执"),
              ),
              @html.dd(class="mono", value.receipt),
            ]),
          ]),
          @html.div(class="confirmation-actions", [
            @html.button(
              type_="button",
              on_click=command(emit, DismissConfirmation),
              localized(locale, "Cancel", "取消"),
            ),
            @html.button(
              type_="button",
              class="danger-button",
              disabled=value.confirmed,
              on_click=command(emit, ConfirmAction(value.action)),
              localized(locale, "Confirm operation", "确认操作"),
            ),
          ]),
        ],
      )
  }
}

///|
fn console_styles() -> String {
  (
    #|:root {
    #|  color-scheme: light dark;
    #|  --bg: #f3f6fa;
    #|  --surface: #ffffff;
    #|  --surface-subtle: #f8fafc;
    #|  --surface-hover: #f1f5f9;
    #|  --ink: #101828;
    #|  --muted: #667085;
    #|  --muted-strong: #475467;
    #|  --line: #dce3ec;
    #|  --line-strong: #c8d2df;
    #|  --accent: #2f6fed;
    #|  --accent-hover: #245dcc;
    #|  --accent-soft: #edf4ff;
    #|  --success: #087a55;
    #|  --success-soft: #ecfdf3;
    #|  --warning: #a15c07;
    #|  --warning-soft: #fff8e7;
    #|  --danger: #b42318;
    #|  --danger-soft: #fff1f0;
    #|  --sidebar: #0b1220;
    #|  --sidebar-ink: #e8eef8;
    #|  --sidebar-muted: #91a0b8;
    #|  --sidebar-active: #16243a;
    #|  --shadow-sm: 0 1px 2px rgba(16, 24, 40, .05);
    #|  --shadow-lg: 0 18px 48px rgba(15, 23, 42, .18);
    #|}
    #|@media (prefers-color-scheme: dark) {
    #|  :root {
    #|    --bg: #0f1521;
    #|    --surface: #171e2b;
    #|    --surface-subtle: #1b2433;
    #|    --surface-hover: #202b3d;
    #|    --ink: #edf2f9;
    #|    --muted: #9aa9bd;
    #|    --muted-strong: #c1ccda;
    #|    --line: #2a3546;
    #|    --line-strong: #3a475b;
    #|    --accent: #79a7ff;
    #|    --accent-hover: #9abbff;
    #|    --accent-soft: #182a49;
    #|    --success: #6ce9b2;
    #|    --success-soft: #14372c;
    #|    --warning: #fec84b;
    #|    --warning-soft: #392d15;
    #|    --danger: #fda29b;
    #|    --danger-soft: #40201f;
    #|    --sidebar: #080d16;
    #|    --sidebar-active: #152238;
    #|    --shadow-lg: 0 18px 48px rgba(0, 0, 0, .38);
    #|  }
    #|}
    #|* { box-sizing: border-box; }
    #|html { min-width: 20rem; background: var(--bg); }
    #|body {
    #|  margin: 0;
    #|  background: var(--bg);
    #|  color: var(--ink);
    #|  font-family: Inter, "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    #|  font-size: .875rem;
    #|  line-height: 1.5;
    #|  text-rendering: optimizeLegibility;
    #|}
    #|html[lang^="zh"] body {
    #|  font-family: "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", Inter, ui-sans-serif, system-ui, sans-serif;
    #|}
    #|html[lang^="zh"] .page-eyebrow,
    #|html[lang^="zh"] .eyebrow,
    #|html[lang^="zh"] .nav-group-label,
    #|html[lang^="zh"] .resource-table th,
    #|html[lang^="zh"] .confirmation-scope dt {
    #|  letter-spacing: .02em;
    #|  text-transform: none;
    #|}
    #|button, input, select, textarea { font: inherit; }
    #|button, select, input { min-height: 2.75rem; }
    #|button {
    #|  margin: 0;
    #|  padding: .55rem .8rem;
    #|  border: 1px solid var(--line-strong);
    #|  border-radius: .45rem;
    #|  background: var(--surface);
    #|  color: var(--ink);
    #|  font-weight: 650;
    #|  cursor: pointer;
    #|  transition: background-color 120ms ease, border-color 120ms ease, color 120ms ease;
    #|}
    #|button:hover:not(:disabled) { background: var(--surface-hover); border-color: var(--muted); }
    #|button:disabled { cursor: not-allowed; opacity: .5; }
    #|button:focus-visible, input:focus-visible, select:focus-visible, textarea:focus-visible, summary:focus-visible, a:focus-visible {
    #|  outline: 3px solid var(--accent);
    #|  outline-offset: 2px;
    #|}
    #|.primary-button { border-color: var(--accent); background: var(--accent); color: #fff; }
    #|.primary-button:hover:not(:disabled) { border-color: var(--accent-hover); background: var(--accent-hover); }
    #|.danger-secondary { border-color: color-mix(in srgb, var(--danger) 55%, var(--line)); color: var(--danger); background: transparent; }
    #|.danger-secondary:hover:not(:disabled) { border-color: var(--danger); background: var(--danger-soft); }
    #|.danger-button { border-color: var(--danger); background: var(--danger); color: #fff; }
    #|.danger-button:hover:not(:disabled) { border-color: var(--danger); background: #8f1c13; }
    #|.console-root {
    #|  display: grid;
    #|  grid-template-columns: 14rem minmax(0, 1fr);
    #|  grid-template-rows: auto minmax(0, 1fr);
    #|  min-height: 100vh;
    #|  background: var(--bg);
    #|}
    #|.app-shell { display: contents; }
    #|.skip-link, .sr-only { position: absolute; left: -9999px; }
    #|.skip-link:focus {
    #|  left: 15rem;
    #|  top: .75rem;
    #|  z-index: 60;
    #|  padding: .65rem .9rem;
    #|  border-radius: .4rem;
    #|  background: var(--surface);
    #|  color: var(--ink);
    #|  box-shadow: var(--shadow-lg);
    #|}
    #|.sidebar {
    #|  grid-column: 1;
    #|  grid-row: 1 / 3;
    #|  position: sticky;
    #|  top: 0;
    #|  height: 100vh;
    #|  display: flex;
    #|  flex-direction: column;
    #|  overflow-y: auto;
    #|  padding: 1.15rem .75rem 1rem;
    #|  background: var(--sidebar);
    #|  color: var(--sidebar-ink);
    #|}
    #|.brand {
    #|  display: flex;
    #|  align-items: center;
    #|  gap: .7rem;
    #|  min-height: 3.25rem;
    #|  margin: 0 .35rem 1.1rem;
    #|  padding-bottom: 1rem;
    #|  border-bottom: 1px solid rgba(255, 255, 255, .1);
    #|}
    #|.brand-mark {
    #|  display: grid;
    #|  place-items: center;
    #|  width: 2.1rem;
    #|  height: 2.1rem;
    #|  flex: none;
    #|  border: 1px solid rgba(255, 255, 255, .24);
    #|  border-radius: .55rem;
    #|  background: #f8fafc;
    #|  color: #0b1220;
    #|  font-size: .72rem;
    #|  font-weight: 800;
    #|  letter-spacing: .05em;
    #|}
    #|.brand-copy { min-width: 0; }
    #|.brand-name { display: block; font-size: .96rem; font-weight: 760; letter-spacing: -.01em; }
    #|.brand-product { display: block; color: var(--sidebar-muted); font-size: .72rem; }
    #|.sidebar nav { display: flex; flex-direction: column; gap: .15rem; }
    #|.nav-group-label {
    #|  margin: 1rem .65rem .35rem;
    #|  color: var(--sidebar-muted);
    #|  font-size: .65rem;
    #|  font-weight: 750;
    #|  letter-spacing: .11em;
    #|  text-transform: uppercase;
    #|}
    #|.nav-group-label:first-child { margin-top: 0; }
    #|.nav-link {
    #|  position: relative;
    #|  width: 100%;
    #|  display: flex;
    #|  align-items: center;
    #|  gap: .65rem;
    #|  padding: .55rem .65rem;
    #|  border-color: transparent;
    #|  background: transparent;
    #|  color: var(--sidebar-muted);
    #|  text-align: left;
    #|  font-weight: 600;
    #|}
    #|.nav-link:hover:not(:disabled) { border-color: transparent; background: rgba(255, 255, 255, .055); color: var(--sidebar-ink); }
    #|.nav-link.active { background: var(--sidebar-active); color: #fff; }
    #|.nav-indicator { width: .3rem; height: .3rem; flex: none; border-radius: 999px; background: currentColor; opacity: .45; }
    #|.nav-link.active .nav-indicator { width: .38rem; height: 1.2rem; border-radius: .3rem; background: var(--accent); opacity: 1; }
    #|.sidebar-footer {
    #|  margin: auto .4rem 0;
    #|  padding-top: 1rem;
    #|  border-top: 1px solid rgba(255, 255, 255, .1);
    #|  color: var(--sidebar-muted);
    #|  font-size: .72rem;
    #|}
    #|.sidebar-footer strong { display: block; margin-bottom: .2rem; color: var(--sidebar-ink); font-size: .75rem; }
    #|.connection-panel {
    #|  grid-column: 2;
    #|  grid-row: 1;
    #|  position: sticky;
    #|  top: 0;
    #|  z-index: 30;
    #|  min-height: 3.65rem;
    #|  padding: .45rem 1.75rem;
    #|  border-bottom: 1px solid var(--line);
    #|  background: color-mix(in srgb, var(--surface) 94%, transparent);
    #|  box-shadow: var(--shadow-sm);
    #|  backdrop-filter: blur(12px);
    #|}
    #|.connection-panel summary {
    #|  min-height: 44px;
    #|  display: flex;
    #|  align-items: center;
    #|  justify-content: flex-end;
    #|  gap: .65rem;
    #|  color: var(--muted-strong);
    #|  cursor: pointer;
    #|  list-style: none;
    #|}
    #|.connection-panel summary::-webkit-details-marker { display: none; }
    #|.connection-panel summary::after { content: "+"; color: var(--muted); font-size: 1rem; }
    #|.connection-panel[open] summary::after { content: "–"; }
    #|.connection-summary-label { font-weight: 700; color: var(--ink); }
    #|.connection-endpoint { max-width: 22rem; overflow: hidden; color: var(--muted); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .72rem; text-overflow: ellipsis; white-space: nowrap; }
    #|.connection-state { display: inline-flex; align-items: center; gap: .4rem; font-size: .75rem; }
    #|.connection-state::before { width: .45rem; height: .45rem; border-radius: 999px; background: currentColor; content: ""; }
    #|.connection-state-ready { color: var(--success); }
    #|.connection-state-needed { color: var(--warning); }
    #|.demo-banner {
    #|  display: flex;
    #|  align-items: center;
    #|  gap: .6rem;
    #|  margin: 0 2rem;
    #|  padding: .65rem .8rem;
    #|  border: 1px solid color-mix(in srgb, var(--accent) 35%, var(--line));
    #|  border-radius: .55rem;
    #|  background: var(--accent-soft);
    #|  color: var(--muted-strong);
    #|  font-size: .76rem;
    #|}
    #|.demo-banner-mark {
    #|  padding: .2rem .38rem;
    #|  border-radius: .3rem;
    #|  background: var(--accent);
    #|  color: white;
    #|  font-size: .62rem;
    #|  font-weight: 800;
    #|  letter-spacing: .08em;
    #|}
    #|.demo-banner strong { color: var(--ink); }
    #|.connection-form {
    #|  display: grid;
    #|  grid-template-columns: repeat(2, minmax(13rem, 1fr));
    #|  gap: .8rem 1rem;
    #|  max-width: 60rem;
    #|  margin: .45rem 0 .85rem auto;
    #|  padding: 1rem;
    #|  border: 1px solid var(--line);
    #|  border-radius: .65rem;
    #|  background: var(--surface-subtle);
    #|}
    #|.connection-field label, .field-group label { display: block; margin-bottom: .35rem; color: var(--muted-strong); font-size: .75rem; font-weight: 700; }
    #|.connection-field input, .field-group input, .field-group select, .field-group textarea {
    #|  width: 100%;
    #|  border: 1px solid var(--line-strong);
    #|  border-radius: .4rem;
    #|  background: var(--surface);
    #|  color: var(--ink);
    #|}
    #|.connection-field input, .field-group input { padding: .55rem .65rem; }
    #|.field-group input[aria-invalid="true"] { border-color: var(--danger); box-shadow: 0 0 0 1px var(--danger-soft); }
    #|.field-help { margin: .35rem 0 0; color: var(--muted); font-size: .7rem; line-height: 1.4; }
    #|.field-error { color: var(--danger); }
    #|.connection-help { display: block; margin-top: .35rem; color: var(--muted); font-size: .7rem; line-height: 1.4; }
    #|.connection-actions { display: flex; align-items: end; justify-content: space-between; gap: 1rem; grid-column: 1 / -1; }
    #|.connection-actions .secondary { max-width: 34rem; }
    #|.workspace { grid-column: 2; grid-row: 2; min-width: 0; }
    #|.workspace-topbar {
    #|  display: flex;
    #|  align-items: flex-start;
    #|  justify-content: space-between;
    #|  gap: 1.5rem;
    #|  padding: 1.55rem 2rem 1.2rem;
    #|  border-bottom: 1px solid var(--line);
    #|}
    #|.page-eyebrow, .eyebrow { margin: 0 0 .25rem; color: var(--muted); font-size: .68rem; font-weight: 780; letter-spacing: .1em; text-transform: uppercase; }
    #|.page-heading h1 { margin: 0; font-size: 1.55rem; line-height: 1.2; letter-spacing: -.025em; }
    #|.page-description { max-width: 46rem; margin: .35rem 0 0; color: var(--muted); }
    #|.topbar-actions { display: flex; align-items: center; gap: .6rem; flex: none; }
    #|.locale-control { display: flex; align-items: center; gap: .4rem; min-height: 44px; }
    #|.locale-control label { color: var(--muted); font-size: .72rem; font-weight: 700; }
    #|.locale-select { min-width: 8rem; min-height: 44px; padding: .5rem 1.8rem .5rem .65rem; border: 1px solid var(--line-strong); border-radius: .45rem; background: var(--surface); color: var(--ink); font-weight: 650; }
    #|.alert-summary { display: inline-flex; align-items: center; gap: .45rem; min-height: 2.25rem; padding: .35rem .65rem; border: 1px solid var(--line); border-radius: 999px; background: var(--surface); color: var(--muted-strong); font-size: .75rem; font-weight: 650; }
    #|.alert-summary::before { width: .45rem; height: .45rem; border-radius: 999px; background: var(--success); content: ""; }
    #|.alert-summary.awaiting-telemetry::before { background: var(--muted); }
    #|.alert-summary.has-alerts { border-color: color-mix(in srgb, var(--warning) 40%, var(--line)); background: var(--warning-soft); color: var(--warning); }
    #|.alert-summary.has-alerts::before { background: var(--warning); }
    #|.workspace-main { width: 100%; max-width: 100rem; margin: 0 auto; padding: 1.45rem 2rem 3rem; }
    #|h2, h3 { letter-spacing: -.015em; }
    #|h2 { margin: 0; font-size: 1.16rem; line-height: 1.35; }
    #|h3 { margin: 1.5rem 0 .65rem; font-size: .96rem; }
    #|.overview-grid { display: grid; grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr); gap: 1rem; }
    #|.health-panel, .activity-panel, .stat, .operation-panel, .stream-panel, .evidence-list {
    #|  border: 1px solid var(--line);
    #|  border-radius: .65rem;
    #|  background: var(--surface);
    #|  box-shadow: var(--shadow-sm);
    #|}
    #|.health-panel { position: relative; overflow: hidden; padding: 1.4rem 1.5rem; }
    #|.health-panel::before { position: absolute; inset: 0 auto 0 0; width: .25rem; background: var(--success); content: ""; }
    #|.health-panel-unknown::before { background: var(--line-strong); }
    #|.health-panel-warning::before { background: var(--warning); }
    #|.health-title { display: flex; align-items: center; gap: .65rem; }
    #|.health-title h2 { font-size: 1.35rem; }
    #|.health-dot { width: .7rem; height: .7rem; flex: none; border: .18rem solid color-mix(in srgb, var(--success) 20%, transparent); border-radius: 999px; background: var(--success); box-shadow: 0 0 0 .2rem var(--success-soft); }
    #|.health-panel-unknown .health-dot { background: var(--muted); box-shadow: 0 0 0 .2rem var(--surface-hover); }
    #|.health-panel-warning .health-dot { background: var(--warning); box-shadow: 0 0 0 .2rem var(--warning-soft); }
    #|.health-copy { max-width: 43rem; margin: .55rem 0 1.15rem 1.35rem; color: var(--muted); }
    #|.health-facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .75rem; margin: 0; }
    #|.health-facts > div { padding: .7rem .8rem; border-left: 1px solid var(--line); }
    #|.health-facts dt { color: var(--muted); font-size: .7rem; }
    #|.health-facts dd { margin: .15rem 0 0; font-size: 1rem; font-weight: 750; }
    #|.activity-panel { padding: 1.25rem 1.35rem; background: linear-gradient(145deg, var(--surface), var(--surface-subtle)); }
    #|.activity-value { margin: .1rem 0 0; font-size: 2.6rem; font-weight: 780; line-height: 1; letter-spacing: -.05em; }
    #|.activity-label { margin: .35rem 0 0; color: var(--muted); }
    #|.activity-divider { height: 1px; margin: 1.15rem 0; background: var(--line); }
    #|.activity-note { display: grid; gap: .15rem; margin: 0; }
    #|.activity-note span { color: var(--muted); font-size: .75rem; }
    #|.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .75rem; margin: .8rem 0 0; }
    #|.stat { position: relative; min-height: 7rem; padding: .95rem 1rem; overflow: hidden; }
    #|.stat::before { position: absolute; inset: 0 0 auto; height: .16rem; background: var(--line-strong); content: ""; }
    #|.stat-ok::before { background: var(--success); }
    #|.stat-warning::before { background: var(--warning); }
    #|.stat-danger::before { background: var(--danger); }
    #|.stat dt { color: var(--muted); font-size: .72rem; font-weight: 650; }
    #|.stat dd { margin: .3rem 0 .15rem; font-size: 1.6rem; font-weight: 780; line-height: 1.15; letter-spacing: -.035em; }
    #|.stat-detail { color: var(--muted); font-size: .7rem; }
    #|.readiness-panel { display: grid; grid-template-columns: minmax(18rem, .85fr) minmax(24rem, 1.15fr); gap: 1.5rem; margin-top: 1rem; padding: 1.25rem 1.35rem; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.readiness-copy h2 { margin-bottom: .35rem; }
    #|.readiness-action { margin-top: 1rem; }
    #|.readiness-list { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .6rem; margin: 0; padding: 0; list-style: none; }
    #|.readiness-item { display: flex; align-items: flex-start; gap: .65rem; min-width: 0; padding: .75rem; border: 1px solid color-mix(in srgb, var(--warning) 35%, var(--line)); border-radius: .5rem; background: var(--warning-soft); }
    #|.readiness-item.ready { border-color: color-mix(in srgb, var(--success) 28%, var(--line)); background: var(--success-soft); }
    #|.readiness-mark { display: grid; place-items: center; width: 1.35rem; height: 1.35rem; flex: none; border-radius: 999px; background: var(--warning); color: white; font-size: .72rem; font-weight: 800; }
    #|.readiness-item.ready .readiness-mark { background: var(--success); }
    #|.readiness-item div { display: grid; gap: .15rem; min-width: 0; }
    #|.section-heading, .subsection-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; margin-bottom: 1rem; }
    #|.section-heading h2 { margin-bottom: .2rem; }
    #|.enterprise-request-heading { margin-top: 2rem; padding-top: 1.5rem; border-top: 1px solid var(--line); }
    #|.portal-node-picker { min-width: 16rem; }
    #|.portal-node-picker label { display: block; margin-bottom: .3rem; color: var(--muted); font-size: .68rem; font-weight: 700; }
    #|.portal-node-picker input { width: 100%; min-height: 2.5rem; padding: .55rem .65rem; border: 1px solid var(--line-strong); border-radius: .45rem; background: var(--panel-strong); color: var(--text); }
    #|.table-actions { display: flex; flex-wrap: wrap; gap: .4rem; }
    #|.action-button { min-height: 2.25rem; padding: .4rem .65rem; border: 1px solid var(--line-strong); border-radius: .4rem; background: var(--panel-strong); color: var(--text); font: inherit; font-weight: 750; cursor: pointer; }
    #|.action-button.primary { border-color: var(--accent); color: var(--accent); }
    #|.action-button:disabled { opacity: .45; cursor: not-allowed; }
    #|.section-copy { max-width: 52rem; margin: 0; color: var(--muted); }
    #|.resource-count { flex: none; margin-top: .15rem; color: var(--muted); font-size: .75rem; }
    #|.subsection-heading { align-items: center; margin: 1.6rem 0 .65rem; }
    #|.subsection-heading h3 { margin: 0; }
    #|.lease-cleanup-policy { margin: .9rem 0 1.15rem; padding: .85rem 1rem; border: 1px solid color-mix(in srgb, var(--warning) 38%, var(--line)); border-left: 4px solid var(--warning); border-radius: .55rem; background: color-mix(in srgb, var(--warning-soft) 68%, var(--surface)); }
    #|.lease-cleanup-policy p { margin: .25rem 0 0; color: var(--muted); font-size: .78rem; }
    #|.table-scroll { max-width: 100%; overflow-x: auto; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.resource-table { width: 100%; min-width: 48rem; border-collapse: collapse; font-size: .8rem; }
    #|.resource-table th, .resource-table td { padding: .65rem .8rem; text-align: left; vertical-align: middle; border-bottom: 1px solid var(--line); }
    #|.resource-table th { height: 2.4rem; background: var(--surface-subtle); color: var(--muted); font-size: .66rem; font-weight: 760; letter-spacing: .07em; text-transform: uppercase; }
    #|.resource-table tbody tr:last-child td { border-bottom: 0; }
    #|.resource-table tbody tr:hover { background: var(--surface-hover); }
    #|.resource-table td > span, .resource-table td > strong { display: block; }
    #|.row-actions { white-space: nowrap; }
    #|.row-actions button { min-width: 5rem; margin-right: .35rem; }
    #|.row-actions button:last-child { margin-right: 0; }
    #|.row-actions .secondary { padding: .65rem 0; }
    #|.secondary { color: var(--muted); font-size: .74rem; }
    #|.mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; overflow-wrap: anywhere; }
    #|.status { display: inline-flex !important; align-items: center; gap: .35rem; width: max-content; padding: .2rem .5rem; border: 1px solid var(--line); border-radius: 999px; background: var(--surface-subtle); color: var(--muted-strong); font-size: .7rem; font-weight: 720; line-height: 1.2; }
    #|.status::before { width: .38rem; height: .38rem; border-radius: 999px; background: currentColor; content: ""; }
    #|.status-ok { border-color: color-mix(in srgb, var(--success) 30%, var(--line)); background: var(--success-soft); color: var(--success); }
    #|.status-pending { border-color: color-mix(in srgb, var(--accent) 30%, var(--line)); background: var(--accent-soft); color: var(--accent); }
    #|.status-warning { border-color: color-mix(in srgb, var(--warning) 35%, var(--line)); background: var(--warning-soft); color: var(--warning); }
    #|.status-danger { border-color: color-mix(in srgb, var(--danger) 35%, var(--line)); background: var(--danger-soft); color: var(--danger); }
    #|.status-muted { color: var(--muted); }
    #|.loading-state, .error-state, .success-state { margin: 0 0 1rem; padding: .8rem 1rem; border: 1px solid var(--line); border-left-width: .25rem; border-radius: .45rem; background: var(--surface); }
    #|.loading-state { border-left-color: var(--accent); }
    #|.error-state { border-left-color: var(--danger); background: var(--danger-soft); }
    #|.success-state { border-left-color: var(--success); background: var(--success-soft); }
    #|.empty-state { margin: 0; padding: 2.2rem; border: 1px dashed var(--line-strong); border-radius: .6rem; background: var(--surface-subtle); color: var(--muted); text-align: center; }
    #|.empty-state.compact { padding: 1rem; }
    #|.empty-state-action { display: grid; justify-items: center; gap: .55rem; }
    #|.empty-state-action strong { color: var(--ink); font-size: .95rem; }
    #|.empty-state-action p { max-width: 36rem; margin: 0; }
    #|.node-list { display: grid; gap: .65rem; }
    #|.node-record { overflow: hidden; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.node-record[open] { border-color: color-mix(in srgb, var(--accent) 32%, var(--line)); }
    #|.node-summary { display: grid; grid-template-columns: minmax(11rem, 1.25fr) minmax(7rem, .65fr) minmax(8rem, .75fr) minmax(7rem, .65fr) minmax(11rem, 1fr) auto; align-items: center; gap: 1rem; min-height: 4.6rem; padding: .75rem 1rem; cursor: pointer; list-style: none; }
    #|.node-summary::-webkit-details-marker { display: none; }
    #|.node-summary:hover { background: var(--surface-hover); }
    #|.node-identity, .node-summary-cell { display: grid; gap: .2rem; min-width: 0; }
    #|.node-identity > strong { font-size: .86rem; }
    #|.node-summary-cell > span { color: var(--muted); font-size: .67rem; font-weight: 680; }
    #|.node-summary-cell > strong { overflow: hidden; color: var(--ink); font-size: .78rem; text-overflow: ellipsis; white-space: nowrap; }
    #|.node-summary-cell > small { color: var(--muted); font-size: .66rem; }
    #|.node-expand-cue { display: inline-flex; align-items: center; gap: .35rem; color: var(--accent); font-size: .72rem; font-weight: 750; }
    #|.node-expand-cue::after { content: "⌄"; font-size: .9rem; transition: transform .16s ease; }
    #|.node-record[open] .node-expand-cue::after { transform: rotate(180deg); }
    #|.node-detail { padding: 1rem; border-top: 1px solid var(--line); background: var(--surface-subtle); }
    #|.node-detail-heading { display: flex; align-items: flex-end; justify-content: space-between; gap: 1rem; margin-bottom: .75rem; }
    #|.node-detail-heading h3 { margin: 0; }
    #|.node-metrics { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .65rem; }
    #|.node-metric { display: grid; gap: .35rem; min-height: 7.2rem; padding: .8rem; border: 1px solid var(--line); border-radius: .5rem; background: var(--surface); }
    #|.node-metric > span { color: var(--muted); font-size: .68rem; font-weight: 680; }
    #|.node-metric > strong { font-size: 1.35rem; letter-spacing: -.035em; }
    #|.node-metric > small { color: var(--muted); font-size: .66rem; }
    #|.node-metric progress { width: 100%; height: .4rem; overflow: hidden; border: 0; border-radius: 999px; background: var(--line); accent-color: var(--accent); }
    #|.node-metric progress::-webkit-progress-bar { border-radius: 999px; background: var(--line); }
    #|.node-metric progress::-webkit-progress-value { border-radius: 999px; background: var(--accent); }
    #|.node-facts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); margin: .7rem 0 0; border: 1px solid var(--line); border-radius: .5rem; background: var(--surface); }
    #|.node-facts > div { min-width: 0; padding: .7rem .8rem; border-right: 1px solid var(--line); }
    #|.node-facts > div:last-child { border-right: 0; }
    #|.node-facts dt { color: var(--muted); font-size: .66rem; font-weight: 680; }
    #|.node-facts dd { margin: .2rem 0 0; overflow-wrap: anywhere; font-size: .76rem; font-weight: 680; }
    #|.node-detail-actions { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-top: .7rem; }
    #|.node-detail-actions p { max-width: 44rem; margin: 0; color: var(--muted); font-size: .7rem; }
    #|.privacy-note { margin: .8rem 0; padding: .55rem .75rem; border-left: .2rem solid var(--accent); background: var(--accent-soft); color: var(--muted-strong); font-size: .75rem; }
    #|.request-stats { margin-bottom: 1rem; }
    #|.stream-panel { padding: .7rem; }
    #|.stream-list { display: grid; gap: .5rem; margin: 0; padding: 0; list-style: none; }
    #|.stream-list li { padding: .75rem; border: 1px solid var(--line); border-radius: .45rem; background: var(--surface-subtle); }
    #|.stream-meta { display: flex; align-items: center; gap: .55rem; }
    #|.stream-sequence { display: grid; place-items: center; width: 1.5rem; height: 1.5rem; border-radius: 999px; background: var(--accent-soft); color: var(--accent); font-size: .68rem; font-weight: 760; }
    #|.stream-output { margin: .6rem 0 0 2.05rem; padding: .65rem; overflow: auto; border-radius: .35rem; background: var(--sidebar); color: var(--sidebar-ink); font: .76rem/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|.evidence-list { display: grid; gap: 0; margin: 0; padding: 0; list-style: none; }
    #|.evidence-list li { display: flex; align-items: center; gap: .75rem; min-height: 3.75rem; padding: .65rem 1rem; border-bottom: 1px solid var(--line); }
    #|.evidence-list li:last-child { border-bottom: 0; }
    #|.evidence-list li span { display: block; }
    #|.evidence-mark { width: .55rem; height: .55rem; flex: none; border: .15rem solid var(--accent-soft); border-radius: 999px; background: var(--accent); }
    #|.policy-summary { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); margin: 0 0 1rem; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.policy-summary > div { min-width: 0; padding: .8rem 1rem; border-right: 1px solid var(--line); }
    #|.policy-summary > div:last-child { border-right: 0; }
    #|.policy-summary dt { color: var(--muted); font-size: .7rem; }
    #|.policy-summary dd { margin: .2rem 0 0; font-weight: 720; overflow-wrap: anywhere; }
    #|.operation-panel { padding: 1.1rem; }
    #|.operation-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; }
    #|.operation-heading h3 { margin: 0; font-size: 1.05rem; }
    #|.operation-form { display: grid; grid-template-columns: minmax(13rem, .72fr) minmax(20rem, 1.6fr); gap: 1rem; margin-top: 1rem; }
    #|.fixed-capacity { display: flex; align-items: center; gap: .75rem; grid-column: 1 / -1; min-height: 4.5rem; padding: .75rem .85rem; border: 1px solid color-mix(in srgb, var(--success) 28%, var(--line)); border-radius: .5rem; background: var(--success-soft); }
    #|.fixed-capacity-mark { display: grid; place-items: center; width: 2.25rem; height: 2.25rem; flex: none; border-radius: .5rem; background: var(--success); color: white; font-weight: 850; }
    #|.fixed-capacity strong { display: block; color: var(--ink); font-size: .78rem; }
    #|.fixed-capacity p { margin: .22rem 0 0; color: var(--muted-strong); font-size: .7rem; line-height: 1.45; }
    #|.deployment-steps { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .6rem; margin: 1rem 0 0; padding: 0; list-style: none; }
    #|.deployment-steps li { display: flex; align-items: center; gap: .5rem; color: var(--muted-strong); font-size: .74rem; }
    #|.deployment-steps li > span { display: grid; place-items: center; width: 1.45rem; height: 1.45rem; flex: none; border-radius: 999px; background: var(--accent-soft); color: var(--accent); font-weight: 800; }
    #|.field-group select { padding: .55rem .65rem; }
    #|.field-group textarea { display: block; min-height: 15rem; padding: .7rem; resize: vertical; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; line-height: 1.55; }
    #|.operation-actions { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-top: .8rem; padding-top: .8rem; border-top: 1px solid var(--line); }
    #|.confirmation-panel { position: fixed; right: 1.5rem; bottom: 1.5rem; z-index: 50; width: min(31rem, calc(100vw - 3rem)); padding: 1.25rem; border: 1px solid color-mix(in srgb, var(--danger) 40%, var(--line)); border-top: .25rem solid var(--danger); border-radius: .7rem; background: var(--surface); box-shadow: var(--shadow-lg); }
    #|.confirmation-panel h2 { margin-bottom: .45rem; }
    #|.confirmation-panel > p:not(.eyebrow) { margin: 0 0 1rem; color: var(--muted-strong); }
    #|.danger-copy { color: var(--danger); }
    #|.confirmation-scope { display: grid; gap: .55rem; margin: 0; padding: .75rem; border-radius: .45rem; background: var(--surface-subtle); }
    #|.confirmation-scope dt { color: var(--muted); font-size: .68rem; font-weight: 700; text-transform: uppercase; }
    #|.confirmation-scope dd { margin: .1rem 0 0; overflow-wrap: anywhere; }
    #|.confirmation-actions { display: flex; justify-content: flex-end; gap: .5rem; margin-top: 1rem; }
    #|@media (max-width: 72rem) {
    #|  .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .operation-form { grid-template-columns: 1fr; }
    #|  .policy-summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .readiness-panel { grid-template-columns: 1fr; }
    #|  .node-summary { grid-template-columns: minmax(11rem, 1.3fr) repeat(3, minmax(7rem, .7fr)) auto; }
    #|  .node-lease-summary { display: none; }
    #|  .node-metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .node-facts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .node-facts > div:nth-child(2) { border-right: 0; }
    #|  .node-facts > div:nth-child(-n+2) { border-bottom: 1px solid var(--line); }
    #|  .policy-summary > div:nth-child(2) { border-right: 0; }
    #|  .policy-summary > div:nth-child(-n+2) { border-bottom: 1px solid var(--line); }
    #|}
    #|@media (max-width: 56rem) {
    #|  .console-root { display: flex; flex-direction: column; }
    #|  .connection-panel { order: 2; position: sticky; width: 100%; padding-inline: 1rem; }
    #|  .connection-panel summary { justify-content: flex-start; }
    #|  .sidebar { order: 1; position: static; width: 100%; height: auto; overflow: visible; padding: .75rem; }
    #|  .brand { margin-bottom: .65rem; padding-bottom: .65rem; }
    #|  .sidebar nav { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .25rem; }
    #|  .nav-group-label { grid-column: 1 / -1; margin-top: .65rem; }
    #|  .sidebar-footer { display: none; }
    #|  .workspace { order: 3; width: 100%; }
    #|  .workspace-topbar { padding: 1.25rem 1rem 1rem; }
    #|  .workspace-main { padding: 1rem 1rem 2.5rem; }
    #|  .skip-link:focus { left: 1rem; }
    #|  .overview-grid { grid-template-columns: 1fr; }
    #|  .connection-form { grid-template-columns: 1fr; margin-left: 0; }
    #|  .connection-actions { display: grid; }
    #|  .node-summary { grid-template-columns: minmax(10rem, 1.4fr) minmax(7rem, .7fr) minmax(7rem, .7fr) auto; }
    #|  .node-memory-summary { display: none; }
    #|}
    #|@media (max-width: 40rem) {
    #|  .connection-endpoint { display: none; }
    #|  .demo-banner { align-items: flex-start; flex-direction: column; margin: 0 .75rem; }
    #|  .nav-group-label { display: none; }
    #|  .workspace-topbar, .section-heading, .operation-heading { flex-direction: column; }
    #|  .topbar-actions { width: 100%; flex-wrap: wrap; justify-content: space-between; }
    #|  .locale-control { flex: 1; }
    #|  .locale-select { width: 100%; }
    #|  .health-facts { grid-template-columns: 1fr; }
    #|  .health-facts > div { border-left: 0; border-top: 1px solid var(--line); }
    #|  .stats, .policy-summary { grid-template-columns: 1fr; }
    #|  .readiness-list, .deployment-steps { grid-template-columns: 1fr; }
    #|  .policy-summary > div { border-right: 0; border-bottom: 1px solid var(--line); }
    #|  .policy-summary > div:last-child { border-bottom: 0; }
    #|  .operation-actions { align-items: stretch; flex-direction: column; }
    #|  .operation-actions button { width: 100%; }
    #|  .node-summary { grid-template-columns: minmax(0, 1fr) auto; gap: .65rem; }
    #|  .node-summary-cell { display: none; }
    #|  .node-detail-heading, .node-detail-actions { align-items: stretch; flex-direction: column; }
    #|  .node-metrics, .node-facts { grid-template-columns: 1fr; }
    #|  .node-facts > div { border-right: 0; border-bottom: 1px solid var(--line); }
    #|  .node-facts > div:last-child { border-bottom: 0; }
    #|  .confirmation-panel { right: .75rem; bottom: .75rem; width: calc(100vw - 1.5rem); }
    #|}
    #|@media (prefers-reduced-motion: reduce) {
    #|  * { scroll-behavior: auto !important; transition: none !important; }
    #|}
  )
}

///|
fn console_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let content = match state.route {
    Overview => overview_view(state, emit)
    Users => users_view(state, emit)
    Leases => leases_view(state, emit)
    CostCenters => cost_centers_view(state)
    Agreements => agreements_view(state, emit)
    QualifiedServices => qualified_services_view(state)
    Nodes => nodes_view(state, emit)
    Models => models_view(state, emit)
    Catalog => catalog_view(state, emit)
    Deployments => deployments_view(state, emit)
    Requests => requests_view(state)
    Benchmarks => benchmarks_view(state)
    Policies => policies_view(state, emit)
    Audit => audit_view(state)
  }
  @html.div(class="app-shell", [
    @html.style_tag(console_styles()),
    @html.a(
      href="#main",
      class="skip-link",
      localized(state.locale, "Skip to content", "跳转到主要内容"),
    ),
    @html.aside(class="sidebar", [
      @html.div(
        class="brand",
        attrs=@html.Attrs::build().aria_label(
          localized(
            state.locale,
            "LunaNexa Cluster Operations",
            "LunaNexa 集群运维",
          ),
        ),
        [
          @html.span(class="brand-mark", "LN"),
          @html.div(class="brand-copy", [
            @html.span(class="brand-name", "LunaNexa"),
            @html.span(
              class="brand-product",
              localized(state.locale, "Cluster operations", "集群运维"),
            ),
          ]),
        ],
      ),
      navigation(state.locale, state.route, emit),
      @html.p(class="sidebar-footer", [
        @html.strong(localized(state.locale, "Control plane", "控制平面")),
        @html.span(
          localized(
            state.locale,
            "Managed nodes remain isolated from application state.",
            "受管节点始终与应用状态隔离。",
          ),
        ),
      ]),
    ]),
    @html.div(class="workspace", [
      @html.header(class="workspace-topbar", [
        @html.div(class="page-heading", [
          @html.p(
            class="page-eyebrow",
            localized(state.locale, "Private DGX cluster", "私有 DGX 集群"),
          ),
          @html.h1(route_label(state.locale, state.route)),
          @html.p(
            class="page-description",
            route_description(state.locale, state.route),
          ),
        ]),
        @html.div(class="topbar-actions", [
          @html.div(class="locale-control", [
            @html.label(
              for_="console-locale",
              localized(state.locale, "Language", "语言"),
            ),
            @html.select(
              id="console-locale",
              class="locale-select",
              on_change=text_command(emit, value => {
                LocaleChanged(@i18n.parse_locale(value))
              }),
              [
                @html.option(
                  value=@i18n.English.storage_value(),
                  selected=state.locale == English,
                  @i18n.English.label(),
                ),
                @html.option(
                  value=@i18n.ChineseSimplified.storage_value(),
                  selected=state.locale == ChineseSimplified,
                  @i18n.ChineseSimplified.label(),
                ),
              ],
            ),
          ]),
          @html.span(
            class=if state.overview.total_nodes == 0 {
              "alert-summary awaiting-telemetry"
            } else if state.overview.alerts == 0 {
              "alert-summary"
            } else {
              "alert-summary has-alerts"
            },
            if state.overview.total_nodes == 0 {
              localized(state.locale, "Awaiting telemetry", "等待遥测")
            } else if state.overview.alerts == 0 {
              localized(state.locale, "No open alerts", "无未解决告警")
            } else {
              localized(
                state.locale,
                "\{state.overview.alerts} open alerts",
                "\{state.overview.alerts} 个未解决告警",
              )
            },
          ),
          @html.button(
            type_="button",
            disabled=state.loading,
            on_click=command(emit, Refresh),
            localized(state.locale, "Refresh", "刷新"),
          ),
        ]),
      ]),
      @html.main_(id="main", class="workspace-main", [
        if state.loading {
          @html.p(
            class="loading-state",
            attrs=@html.Attrs::build()
              .role("status")
              .aria_live("polite")
              .aria_busy("true"),
            localized(
              state.locale,
              "Loading current cluster state…",
              "正在加载当前集群状态…",
            ),
          )
        } else {
          @html.nothing
        },
        match state.error_message {
          Some(message) =>
            @html.div(
              attrs=@html.Attrs::build().role("alert"),
              class="error-state",
              localized(
                state.locale,
                "Unable to complete the operation: \{message}",
                "无法完成此操作：\{message}",
              ),
            )
          None => @html.nothing
        },
        match state.success_message {
          Some(message) =>
            @html.div(
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              class="success-state",
              message,
            )
          None => @html.nothing
        },
        content,
        confirmation_view(state.locale, state.confirmation, emit),
      ]),
    ]),
  ])
}

///|
pub fn view(state : ConsoleState) -> @rabbita.Html {
  console_view(state, None)
}

///|
pub fn interactive_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage],
) -> @rabbita.Html {
  console_view(state, Some(emit))
}

///|
#warnings("-alert_unstable")
pub fn render(state : ConsoleState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
