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
  free_memory_mib : Int
  workloads : Int
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
  confirmation : Confirmation?
  error_message : String?
  success_message : String?
  loading : Bool
  operation_name : String
  operation_body : String
  quick_deployment_id : String
  quick_template : String
  quick_replicas : String
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
  DismissConfirmation
  ConfirmAction(DestructiveAction)
  Refresh
  OperationChanged(String)
  OperationBodyChanged(String)
  SubmitOperation
  QuickDeploymentIdChanged(String)
  QuickTemplateChanged(String)
  QuickReplicasChanged(String)
  SubmitQuickDeployment
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
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operation_name: "register-model",
    operation_body: "",
    quick_deployment_id: "",
    quick_template: "",
    quick_replicas: "1",
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
        locale, "Time-bounded workspace entitlements and inference capacity.", "管理有时限的工作区权益与推理容量。",
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
      nav_link(locale, Policies, current, emit),
      @html.p(class="nav-group-label", localized(locale, "Evidence", "证据")),
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
fn overview_view(state : ConsoleState) -> @rabbita.Html {
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
          localized(
            state.locale,
            "Compute & workspace leases",
            "计算租约与工作区租约",
          ),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Review who holds each entitlement, its workspace entry point, provider-neutral inference limits, and expiry before taking action.",
            "操作前请检查权益持有者、工作区入口、不绑定特定提供商的推理限制及到期时间。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.compute_leases.count_if(lease => lease.state == Active)} active · \{state.compute_leases.length()} total",
          "\{state.compute_leases.count_if(lease => lease.state == Active)} 项有效 · 共 \{state.compute_leases.length()} 项",
        ),
      ),
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
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No nodes enrolled. Create a short-lived enrollment token to begin.",
          "尚未注册节点。请先创建短期有效的注册令牌。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Managed hardware nodes",
              "受管硬件节点",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Node", "节点")),
              @html.th(scope=Col, localized(state.locale, "Status", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Architecture", "架构"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Free memory", "可用内存"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Workloads", "工作负载"),
              ),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for node in state.nodes => node_item(state.locale, node, emit)
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn node_item(
  locale : @i18n.Locale,
  node : NodeRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.tr([
    @html.td([
      @html.strong(node.node_id),
      @html.span(
        class="secondary",
        localized(locale, "Managed runtime host", "受管运行时主机"),
      ),
    ]),
    @html.td(node_state_badge(locale, node.state)),
    @html.td(class="mono", architecture_label(locale, node.architecture)),
    @html.td("\{node.free_memory_mib} MiB"),
    @html.td(node.workloads.to_string()),
    @html.td(class="row-actions", [
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
            placeholder="text-service",
            value=state.quick_deployment_id,
            on_input=text_command(emit, value => QuickDeploymentIdChanged(value)),
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
        @html.div(class="field-group", [
          @html.label(
            for_="quick-replicas",
            localized(state.locale, "Replicas", "副本数"),
          ),
          @html.input(
            input_type=Number,
            id="quick-replicas",
            min=1,
            max=64,
            value=state.quick_replicas,
            on_input=text_command(emit, value => QuickReplicasChanged(value)),
          ),
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
            state.quick_deployment_id.trim() == "" ||
            state.quick_template == "" ||
            state.quick_replicas.trim() == "",
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
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No deployments are currently assigned.",
            "当前没有已分配的部署。",
          ),
        )
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
    #|.connection-field input, .field-group select, .field-group textarea {
    #|  width: 100%;
    #|  border: 1px solid var(--line-strong);
    #|  border-radius: .4rem;
    #|  background: var(--surface);
    #|  color: var(--ink);
    #|}
    #|.connection-field input { padding: .55rem .65rem; }
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
    #|.section-heading, .subsection-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; margin-bottom: 1rem; }
    #|.section-heading h2 { margin-bottom: .2rem; }
    #|.section-copy { max-width: 52rem; margin: 0; color: var(--muted); }
    #|.resource-count { flex: none; margin-top: .15rem; color: var(--muted); font-size: .75rem; }
    #|.subsection-heading { align-items: center; margin: 1.6rem 0 .65rem; }
    #|.subsection-heading h3 { margin: 0; }
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
    #|}
    #|@media (max-width: 40rem) {
    #|  .connection-endpoint { display: none; }
    #|  .nav-group-label { display: none; }
    #|  .workspace-topbar, .section-heading, .operation-heading { flex-direction: column; }
    #|  .topbar-actions { width: 100%; flex-wrap: wrap; justify-content: space-between; }
    #|  .locale-control { flex: 1; }
    #|  .locale-select { width: 100%; }
    #|  .health-facts { grid-template-columns: 1fr; }
    #|  .health-facts > div { border-left: 0; border-top: 1px solid var(--line); }
    #|  .stats, .policy-summary { grid-template-columns: 1fr; }
    #|  .policy-summary > div { border-right: 0; border-bottom: 1px solid var(--line); }
    #|  .policy-summary > div:last-child { border-bottom: 0; }
    #|  .operation-actions { align-items: stretch; flex-direction: column; }
    #|  .operation-actions button { width: 100%; }
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
    Overview => overview_view(state)
    Users => users_view(state, emit)
    Leases => leases_view(state, emit)
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
