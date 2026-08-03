///|
fn node_snapshot(
  id : String,
  state : @contracts.NodeState,
  architecture : String,
  memory : Int,
  warm : Bool,
  queue : Int,
  licensed? : Bool = true,
) -> @scheduler.NodeSnapshot {
  {
    node_id: id,
    state,
    architecture,
    memory_free_mib: memory,
    runtimes: ["text-runtime"],
    licensed_models: if licensed {
      ["model.text@v1"]
    } else {
      []
    },
    ready_models: if licensed {
      ["model.text@v1"]
    } else {
      []
    },
    allowed_data_classes: [Confidential],
    warm_models: if warm {
      ["model.text@v1"]
    } else {
      []
    },
    queue_depth: queue,
    reliability_per_mille: 990,
    accelerator_utilization_per_mille: 300,
  }
}

///|
fn requirements(memory? : Int = 4000) -> @scheduler.PlacementRequirements {
  {
    workload_id: "workload-1",
    model_key: "model.text@v1",
    architecture: "nvidia-gb10",
    memory_mib: memory,
    runtime: "text-runtime",
    data_class: Confidential,
    deadline_unix_ms: 10000L,
    now_unix_ms: 1000L,
    estimated_runtime_ms: 100L,
    multi_node: false,
    topology_profile: None,
  }
}

///|
fn score_policy() -> @scheduler.ScorePolicy {
  {
    version: "placement-v1",
    warm_model_weight: 10000,
    headroom_weight: 1,
    queue_weight: 2,
    reliability_weight: 1,
    utilization_weight: 1,
    validated_topology_profiles: [],
  }
}

///|
test "four-node placement is deterministic with typed explanations" {
  let nodes = [
    node_snapshot("node-a", Active, "nvidia-gb10", 8000, true, 20),
    node_snapshot("node-b", Active, "nvidia-gb10", 12000, false, 0),
    node_snapshot("node-c", Active, "other", 16000, false, 0),
    node_snapshot(
      "node-d",
      Active,
      "nvidia-gb10",
      16000,
      false,
      0,
      licensed=false,
    ),
  ]
  let first = @scheduler.place(nodes, requirements(), score_policy())
  let second = @scheduler.place(nodes, requirements(), score_policy())
  assert_eq(first, second)
  assert_eq(first.selected_node_id, Some("node-a"))
  assert_eq(first.rejected.length(), 2)
  assert_eq(first.policy_version, "placement-v1")
}

///|
test "drain prevents new work and impossible workloads reject before launch" {
  let nodes = [
    node_snapshot("node-a", Draining, "nvidia-gb10", 8000, true, 0),
    node_snapshot("node-b", Active, "nvidia-gb10", 12000, false, 0),
  ]
  let after_drain = @scheduler.place(nodes, requirements(), score_policy())
  assert_eq(after_drain.selected_node_id, Some("node-b"))
  let impossible = @scheduler.place(
    nodes,
    requirements(memory=1000000),
    score_policy(),
  )
  assert_eq(impossible.selected_node_id, None)
  assert_true(
    impossible.rejected.all(item => {
      item.reasons.any(reason => reason == InsufficientMemory)
    }),
  )
}

///|
test "licensed inventory without a ready assigned runtime fails the hard filter" {
  let node = node_snapshot("node-a", Active, "nvidia-gb10", 12000, true, 0)
  let decision = @scheduler.place(
    [{ ..node, ready_models: [] }],
    requirements(),
    score_policy(),
  )
  assert_eq(decision.selected_node_id, None)
  assert_true(
    decision.rejected[0].reasons.any(reason => reason == RuntimeNotReady),
  )
}

///|
fn request() -> @contracts.WorkloadEnvelope {
  {
    version: @contracts.contract_version,
    idempotency_key: "idem",
    workload_id: "workload",
    tenant_ref: "tenant",
    credential_scope: "inference",
    capability: TextGenerate,
    model_selector: "text.default",
    payload: Json::empty_object(),
    data_policy: {
      classification: Confidential,
      retention: Ephemeral,
      allow_cache: false,
      allow_training_reuse: false,
    },
    deadline_unix_ms: 10000L,
    priority: Interactive,
    latency_class: Realtime,
    resource_ceiling: {
      max_input_units: 10,
      max_output_units: 10,
      max_runtime_ms: 100L,
      max_accelerator_memory_mib: 1000,
    },
    stream: true,
    output_format: "text",
    trace_token: "trace",
  }
}

///|
test "admission enforces quotas cancellation capacity and bounded retry" {
  let admission = @scheduler.AdmissionController::new(1)
  admission.set_quota({
    tenant_ref: "tenant",
    max_inflight: 1,
    max_accelerator_ms: 1000L,
    window_ms: 60000L,
  })
  assert_eq(admission.admit(request(), 1L), Accepted(queue_position=0))
  assert_eq(admission.admit(request(), 1L), Rejected(reason=QuotaExceeded))
  admission.set_quota({
    tenant_ref: "tenant-2",
    max_inflight: 1,
    max_accelerator_ms: 1000L,
    window_ms: 60000L,
  })
  assert_eq(
    admission.admit(
      {
        ..request(),
        tenant_ref: "tenant-2",
        workload_id: "workload-2",
        idempotency_key: "idem-2",
      },
      1L,
    ),
    Rejected(reason=AdmissionCapacityExceeded),
  )
  admission.cancel("workload")
  assert_true(admission.is_cancelled("workload"))
  admission.complete("tenant", 100L)
  assert_true(@scheduler.retry_allowed("idem", 1, 2, true))
  assert_false(@scheduler.retry_allowed("idem", 2, 2, true))
  assert_false(@scheduler.retry_allowed("idem", 1, 2, false))
}

///|
test "priority policy reserves bounded capacity for interactive work" {
  assert_eq(@scheduler.priority_capacity_limit(100, Background), 75)
  assert_eq(@scheduler.priority_capacity_limit(100, Normal), 90)
  assert_eq(@scheduler.priority_capacity_limit(100, Interactive), 100)
  assert_eq(@scheduler.priority_capacity_limit(100, Critical), 100)
}

///|
async test "durable scheduler preserves quotas usage and placement receipts" {
  let directory = @fs.tmpdir(prefix="lunanexa-scheduler-")
  let path = "\{directory}/scheduler.json"
  let scheduler = @scheduler.FileScheduler::open(path, 2)
  scheduler.set_quota({
    tenant_ref: "tenant",
    max_inflight: 1,
    max_accelerator_ms: 1000L,
    window_ms: 60000L,
  })
  assert_eq(scheduler.admit(request(), 1L), Accepted(queue_position=0))
  assert_eq(
    scheduler.admit(request(), 1L),
    Rejected(reason=WorkloadAlreadyActive),
  )
  let decision = scheduler.place(
    [node_snapshot("node-a", Active, "nvidia-gb10", 8000, true, 0)],
    requirements(),
    score_policy(),
  )
  assert_eq(decision.selected_node_id, Some("node-a"))
  scheduler.complete("workload", 125L)
  assert_eq(
    scheduler.admit(
      {
        ..request(),
        workload_id: "expired-after-crash",
        idempotency_key: "expired-after-crash",
        deadline_unix_ms: 2L,
      },
      1L,
    ),
    Accepted(queue_position=0),
  )
  let restored = @scheduler.FileScheduler::open(path, 99)
  let snapshot = restored.snapshot()
  assert_eq(snapshot.schema_version, "lunanexa.scheduler.v2")
  assert_eq(snapshot.capacity, 2)
  assert_eq(snapshot.quotas.length(), 1)
  assert_eq(snapshot.active.length(), 0)
  assert_eq(snapshot.usage[0].accelerator_ms, 125L)
  assert_eq(snapshot.decisions.length(), 1)
  @fs.rmdir(directory, recursive=true)
}
