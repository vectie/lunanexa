///|
fn console_state(route : @ui.OperatorRoute) -> @ui.ConsoleState {
  {
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
    confirmation: Some(@ui.confirmation_receipt(DrainNode("node-1"), "node-1")),
    error_message: None,
    success_message: None,
    loading: false,
    operation_name: "register-model",
    operation_body: "{}",
  }
}

///|
test "all operator routes render from the shared typed state" {
  for route in @ui.all_routes() {
    let html = @ui.render(console_state(route))
    assert_true(html.contains("LunaNexa Operations"))
    assert_true(html.contains("Skip to content"))
    assert_true(html.contains("Confirm destructive operation"))
    assert_true(html.contains("aria-label=\"Primary\""))
  }
}

///|
test "empty and error states remain explicit" {
  let state = console_state(Nodes)
  let html = @ui.render({ ..state, nodes: [], error_message: Some("offline") })
  assert_true(html.contains("No nodes enrolled"))
  assert_true(html.contains("Unable to load this view: offline"))
  assert_true(html.contains("max-width:48rem"))
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
