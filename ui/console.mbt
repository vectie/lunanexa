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
pub(all) enum DestructiveAction {
  CordonNode(String)
  DrainNode(String)
  StopDeployment(String)
  RollbackAlias(String)
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
  route : OperatorRoute
  overview : OverviewMetrics
  nodes : Array[NodeRow]
  models : Array[ModelRow]
  deployments : Array[DeploymentRow]
  requests : RequestMetrics
  request_details : Array[RequestDetail]
  stream_events : Array[StreamEventView]
  benchmark_evidence : Array[String]
  policies : PolicySummary
  audit : Array[AuditRow]
  confirmation : Confirmation?
  error_message : String?
  success_message : String?
  loading : Bool
  operation_name : String
  operation_body : String
} derive(Eq)

///|
pub(all) enum ConsoleMessage {
  Navigate(OperatorRoute)
  BeginCordon(String)
  BeginDrain(String)
  BeginRollback(String)
  BeginStopDeployment(String)
  DismissConfirmation
  ConfirmAction(DestructiveAction)
  Refresh
  OperationChanged(String)
  OperationBodyChanged(String)
  SubmitOperation
} derive(Eq)

///|
pub fn confirmation_receipt(
  action : DestructiveAction,
  scope : String,
) -> Confirmation {
  {
    action,
    scope,
    receipt: "confirm:\{scope}:\{to_repr(action)}",
    confirmed: false,
  }
}

///|
pub fn default_state() -> ConsoleState {
  {
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
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operation_name: "register-model",
    operation_body: "",
  }
}

///|
fn route_label(route : OperatorRoute) -> String {
  match route {
    Overview => "Overview"
    Nodes => "Nodes"
    Models => "Models"
    Deployments => "Deployments"
    Requests => "Requests"
    Benchmarks => "Benchmarks"
    Policies => "Policies"
    Audit => "Audit"
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
    None => @cmd.Emit(_ => @rabbita.none)
  }
}

///|
fn navigation(
  current : OperatorRoute,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.nav(
    attrs=@html.Attrs::build().aria_label("Primary"),
    [
      for route in all_routes() => nav_link(route, current, emit)
    ],
  )
}

///|
fn nav_link(
  route : OperatorRoute,
  current : OperatorRoute,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let label = route_label(route)
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
    label,
  )
}

///|
fn stat(label : String, value : String) -> @rabbita.Html {
  @html.div(class="stat", [@html.dt(label), @html.dd(value)])
}

///|
fn overview_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("overview-title"), [
    @html.h2(id="overview-title", "Cluster overview"),
    @html.dl(class="stats", [
      stat(
        "Nodes",
        "\{state.overview.active_nodes}/\{state.overview.total_nodes}",
      ),
      stat("Active models", state.overview.active_models.to_string()),
      stat("Queue", state.overview.queue_depth.to_string()),
      stat("Alerts", state.overview.alerts.to_string()),
      stat("Recent changes", state.overview.recent_changes.to_string()),
    ]),
  ])
}

///|
fn nodes_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("nodes-title"), [
    @html.h2(id="nodes-title", "Nodes"),
    if state.nodes.length() == 0 {
      @html.p(
        class="empty-state",
        "No nodes enrolled. Create a short-lived enrollment token to begin.",
      )
    } else {
      @html.ul([ for node in state.nodes => node_item(node, emit) ])
    },
  ])
}

///|
fn node_item(
  node : NodeRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.li([
    @html.strong(node.node_id),
    @html.span(" · \{to_repr(node.state)} · \{node.architecture}"),
    @html.span(
      " · \{node.free_memory_mib} MiB free · \{node.workloads} workloads",
    ),
    @html.button(
      type_="button",
      title="Cordon \{node.node_id}",
      on_click=command(emit, BeginCordon(node.node_id)),
      "Cordon…",
    ),
    @html.button(
      type_="button",
      title="Drain \{node.node_id}",
      on_click=command(emit, BeginDrain(node.node_id)),
      "Drain…",
    ),
  ])
}

///|
fn models_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("models-title"), [
    @html.h2(id="models-title", "Models"),
    if state.models.length() == 0 {
      @html.p(class="empty-state", "No model artifacts registered.")
    } else {
      @html.ul([ for model in state.models => model_item(model, emit) ])
    },
  ])
}

///|
fn model_item(
  model : ModelRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.li([
    @html.span(
      "\{model.model_id}@\{model.version} · \{to_repr(model.state)} · license \{model.license_status} · evaluation \{model.evaluation_status} · \{model.compatibility} · \{model.alias_name}",
    ),
    if model.alias_name == "—" {
      @html.nothing
    } else {
      @html.button(
        type_="button",
        on_click=command(emit, BeginRollback(model.alias_name)),
        "Roll back alias…",
      )
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
      @html.h2(id="deployments-title", "Deployments"),
      @html.ul(
        [
          for deployment in state.deployments => {
            deployment_item(deployment, emit)
          }
        ],
      ),
    ],
  )
}

///|
fn deployment_item(
  deployment : DeploymentRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.li([
    @html.strong(deployment.deployment_id),
    @html.span(
      " · desired \{to_repr(deployment.desired)} · observed \{to_repr(deployment.observed)} · \{deployment.placement_reason}",
    ),
    @html.button(
      type_="button",
      on_click=command(emit, BeginStopDeployment(deployment.assignment_id)),
      "Stop…",
    ),
  ])
}

///|
fn requests_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("requests-title"), [
    @html.h2(id="requests-title", "Requests"),
    @html.p(
      "\{state.requests.count} audited request events · latest benchmark p95 \{state.requests.p95_ms} ms · \{state.requests.throughput_per_second}/s · \{state.requests.errors} failures",
    ),
    @html.p("Request detail is bounded and excludes raw payloads."),
    if state.request_details.length() == 0 {
      @html.p(class="empty-state", "No request receipts are available yet.")
    } else {
      @html.ul(
        [
          for detail in state.request_details => {
            @html.li(
              "\{detail.timestamp_unix_ms} · \{detail.action} · \{detail.model_selector} · \{detail.result} · \{detail.receipt}",
            )
          }
        ],
      )
    },
    @html.h3("Latest live stream"),
    if state.stream_events.length() == 0 {
      @html.p(
        class="empty-state",
        "No live stream has been run in this browser session.",
      )
    } else {
      @html.ol(
        [
          for event in state.stream_events => {
            @html.li([
              @html.strong("\{event.sequence} · \{event.kind}"),
              if event.text == "" {
                @html.nothing
              } else {
                @html.pre(event.text)
              },
              if event.receipt == "" {
                @html.nothing
              } else {
                @html.span("Receipt: \{event.receipt}")
              },
            ])
          }
        ],
      )
    },
  ])
}

///|
fn benchmarks_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("benchmarks-title"),
    [
      @html.h2(id="benchmarks-title", "Benchmarks"),
      @html.ul(
        [
          for evidence in state.benchmark_evidence => @html.li(evidence)
        ],
      ),
    ],
  )
}

///|
fn policies_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("policies-title"), [
    @html.h2(id="policies-title", "Policies"),
    @html.p(
      "\{state.policies.quota_count} quotas · \{state.policies.data_class_count} data classes · retention \{to_repr(state.policies.default_retention)}",
    ),
    @html.p("Allowed runtimes: \{state.policies.allowed_runtimes.join(", ")}"),
    @html.h3("Typed operator operation"),
    @html.p(
      "Submit canonical JSON to the same validated API used by automation. Secret values remain in browser memory and must not be pasted into model or assignment metadata.",
    ),
    @html.label(for_="operation-name", "Operation"),
    @html.select(
      id="operation-name",
      on_change=text_command(emit, value => OperationChanged(value)),
      [
        @html.option(
          value="issue-enrollment-token",
          selected=state.operation_name == "issue-enrollment-token",
          "Issue enrollment token",
        ),
        @html.option(
          value="register-runtime",
          selected=state.operation_name == "register-runtime",
          "Register runtime",
        ),
        @html.option(
          value="register-model",
          selected=state.operation_name == "register-model",
          "Register model",
        ),
        @html.option(
          value="record-license",
          selected=state.operation_name == "record-license",
          "Record license",
        ),
        @html.option(
          value="record-verification",
          selected=state.operation_name == "record-verification",
          "Record verification",
        ),
        @html.option(
          value="record-evaluation",
          selected=state.operation_name == "record-evaluation",
          "Record evaluation",
        ),
        @html.option(
          value="approve-model",
          selected=state.operation_name == "approve-model",
          "Approve model",
        ),
        @html.option(
          value="promote-alias",
          selected=state.operation_name == "promote-alias",
          "Promote alias",
        ),
        @html.option(
          value="set-quota",
          selected=state.operation_name == "set-quota",
          "Set quota",
        ),
        @html.option(
          value="publish-assignment",
          selected=state.operation_name == "publish-assignment",
          "Publish assignment for controller signing",
        ),
        @html.option(
          value="invoke-workload",
          selected=state.operation_name == "invoke-workload",
          "Invoke workload",
        ),
        @html.option(
          value="record-benchmark",
          selected=state.operation_name == "record-benchmark",
          "Record benchmark evidence",
        ),
      ],
    ),
    @html.label(for_="operation-body", "Canonical JSON body"),
    @html.textarea(
      id="operation-body",
      rows=12,
      maxlength=1048576,
      value=state.operation_body,
      on_input=text_command(emit, value => OperationBodyChanged(value)),
      "",
    ),
    @html.button(
      type_="button",
      disabled=state.operation_body.trim() == "" || state.loading,
      on_click=command(emit, SubmitOperation),
      "Validate and submit",
    ),
  ])
}

///|
fn audit_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("audit-title"), [
    @html.h2(id="audit-title", "Audit"),
    @html.ul([ for event in state.audit => audit_item(event) ]),
  ])
}

///|
fn audit_item(event : AuditRow) -> @rabbita.Html {
  @html.li(
    "\{event.actor} · \{event.decision} · \{event.evidence} · \{event.result} · \{event.receipt}",
  )
}

///|
fn confirmation_view(
  confirmation : Confirmation?,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  match confirmation {
    None => @html.nothing
    Some(value) =>
      @html.aside(attrs=@html.Attrs::build().aria_label("Confirmation"), [
        @html.h2("Confirm destructive operation"),
        @html.p("Scope: \{value.scope}"),
        @html.p("Receipt: \{value.receipt}"),
        @html.button(
          type_="button",
          disabled=value.confirmed,
          on_click=command(emit, ConfirmAction(value.action)),
          "Confirm",
        ),
        @html.button(
          type_="button",
          on_click=command(emit, DismissConfirmation),
          "Cancel",
        ),
      ])
  }
}

///|
fn console_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let content = match state.route {
    Overview => overview_view(state)
    Nodes => nodes_view(state, emit)
    Models => models_view(state, emit)
    Deployments => deployments_view(state, emit)
    Requests => requests_view(state)
    Benchmarks => benchmarks_view(state)
    Policies => policies_view(state, emit)
    Audit => audit_view(state)
  }
  @html.div(class="app-shell", [
    @html.style_tag(
      (
        #|:root{color-scheme:light dark;--bg:#f5f7fb;--surface:#fff;--ink:#152033;--muted:#526078;--line:#d8dfeb;--accent:#175cd3;--danger:#b42318}@media(prefers-color-scheme:dark){:root{--bg:#0f1726;--surface:#172235;--ink:#f3f6fb;--muted:#b4bfd0;--line:#34445d;--accent:#84adff;--danger:#fda29b}}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:ui-sans-serif,system-ui,sans-serif}.connection-panel{max-width:80rem;margin:0 auto;padding:.75rem 1rem;display:flex;align-items:center;justify-content:flex-end;gap:.5rem;border-bottom:1px solid var(--line);background:var(--surface)}.connection-panel input{min-height:2.75rem;max-width:18rem}.skip-link{position:absolute;left:-9999px}.skip-link:focus{left:1rem;top:1rem;z-index:10;background:var(--surface);padding:.75rem}.app-shell{max-width:80rem;margin:auto;padding:1rem}.app-shell>header{display:flex;align-items:center;justify-content:space-between;gap:1rem;border-bottom:1px solid var(--line)}.nav-link{display:inline-block;min-height:2.75rem;padding:.7rem;border:0;background:transparent;color:var(--muted)}.nav-link.active{color:var(--accent);border-bottom:3px solid var(--accent)}.nav-link:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible{outline:3px solid var(--accent);outline-offset:2px}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(10rem,1fr));gap:1rem}.stat{padding:1rem;border:1px solid var(--line);border-radius:.5rem;background:var(--surface)}.error-state,.success-state,.loading-state{padding:1rem;margin:1rem 0;background:var(--surface)}.error-state{border-left:.3rem solid var(--danger)}.success-state{border-left:.3rem solid #079455}.empty-state{padding:2rem;border:1px dashed var(--line);background:var(--surface)}select,textarea{display:block;width:100%;max-width:60rem;margin:.5rem 0;padding:.6rem;background:var(--surface);color:var(--ink);border:1px solid var(--line)}button,select{min-height:2.75rem}button{margin:.25rem;padding:.5rem .75rem}li{line-height:1.6;margin:.5rem 0}@media(max-width:48rem){.connection-panel{align-items:stretch;flex-direction:column}.connection-panel input{max-width:none;width:100%}.app-shell{padding:.5rem}.app-shell>header{align-items:flex-start;flex-direction:column}.nav-link{margin:0 .1rem}.stats{grid-template-columns:1fr}li{margin-bottom:1rem}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important}}
      ),
    ),
    @html.a(href="#main", class="skip-link", "Skip to content"),
    @html.header([
      @html.h1("LunaNexa Operations"),
      navigation(state.route, emit),
    ]),
    @html.main_(id="main", [
      if state.loading {
        @html.p(
          class="loading-state",
          attrs=@html.Attrs::build()
            .role("status")
            .aria_live("polite")
            .aria_busy("true"),
          "Loading current cluster state…",
        )
      } else {
        @html.nothing
      },
      match state.error_message {
        Some(message) =>
          @html.div(
            attrs=@html.Attrs::build().role("alert"),
            class="error-state",
            "Unable to load this view: \{message}",
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
      confirmation_view(state.confirmation, emit),
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
