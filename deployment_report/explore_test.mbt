///|
fn template() -> @deployment.ModelServiceTemplate {
  {
    template_id: "text-small",
    version: "v1",
    display_name: "Text small",
    description: "Approved text service",
    model_selector: "text.default",
    model_id: "model.text",
    model_version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.text/v1",
      size_bytes: 1L,
      signature_ref: "s3://models/model.text/v1.sig",
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
      accelerator_memory_mib: 1000,
      cpu_millis: 1000,
      memory_mib: 2000,
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
    signature: "signed",
  }
}

///|
fn intent() -> @deployment.ModelServiceIntent {
  {
    version: @contracts.contract_version,
    idempotency_key: "deploy-text-small",
    deployment_id: "text-small-service",
    template: { template_id: "text-small", version: "v1", },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 60000L,
    promote_when_ready: false,
    topology_profile: None,
  }
}

///|
fn query() -> @deployment_report.Query {
  {
    now_unix_ms: 1000L,
    maximum_age_ms: 100L,
    deployment_id: "",
    model_id: "",
    operation_state: "",
    node_id: "",
  }
}

///|
fn operation() -> @deployment.DeploymentOperation {
  {
    operation_id: "operation-a",
    deployment_id: "text-small-service",
    generation: 9007199254740993L,
    state: Ready,
    plan: {
      plan_id: "plan",
      intent: { ..intent(), replicas: 5, },
      template: Some(template()),
      replicas: [
        { replica_id: "r1", node_id: "a", devices: ["z", "a"], group: None, },
        { replica_id: "r2", node_id: "a", devices: [], group: None, },
        { replica_id: "r3", node_id: "b", devices: ["b"], group: None, },
        { replica_id: "r4", node_id: "c", devices: [], group: None, },
        { replica_id: "r5", node_id: "missing", devices: [], group: None, },
      ],
      findings: [],
      executable: true,
      endpoint: None,
    },
    assignment_ids: [],
    endpoint: None,
    message: "HIDDEN",
    audit_receipt: "HIDDEN",
    created_unix_ms: 1L,
    updated_unix_ms: 2L,
  }
}

///|
fn node(id : String, timestamp : Int64) -> @contracts.NodeHeartbeat {
  {
    node_id: id,
    state: Active,
    observed_generation: 0L,
    controller_epoch: 0L,
    inventory: {
      node_id: id,
      agent_version: "synthetic",
      os_release: "HIDDEN",
      runtime_names: [],
      accelerators: [],
      labels: Map([]),
      taints: [],
    },
    running_deployments: ["text-small-service"],
    runtime_endpoints: None,
    timestamp_unix_ms: timestamp,
    signature: "HIDDEN",
  }
}

///|
fn nodes() -> Array[@contracts.NodeHeartbeat] {
  [
    node("a", 900L),
    { ..node("b", 899L), running_deployments: [], },
    node("c", 1001L),
  ]
}

///|
test "exact operation model runtime placement associations and node-only membership" {
  let op = operation()
  let blank = {
    ..op,
    operation_id: "operation-b",
    state: Blocked,
    plan: { ..op.plan, template: None, replicas: [], },
  }
  let before = [op, blank].to_json().stringify()
  let report = @deployment_report.explore(
    @deployment_report.import_operations(before),
    @deployment_report.import_nodes(nodes().to_json().stringify()),
    query(),
  )
  assert_eq(report.deployments.length(), 2)
  assert_eq(report.placements.length(), 5)
  assert_eq(report.deployments[0].generation, 9007199254740993L)
  assert_eq(report.deployments[0].model_id, Some("model.text"))
  assert_eq(report.deployments[0].runtime_name, Some("text-runtime"))
  assert_eq(report.deployments[1].model_id, None)
  assert_eq(report.deployments[1].planned_replicas, 0)
  assert_eq(report.placements[0].planned_device_ids, ["a", "z"])
  assert_eq(report.placements[0].node_deployment_membership, "listed")
  assert_eq(report.placements[1].node_deployment_membership, "listed")
  assert_eq(report.placements[2].node_deployment_membership, "not-listed")
  assert_eq(report.placements[0].freshness, "fresh")
  assert_eq(report.placements[2].freshness, "stale")
  assert_eq(report.placements[3].freshness, "future")
  assert_eq(report.placements[3].age_ms, None)
  assert_eq(report.placements[4].node_deployment_membership, "missing-node")
  assert_eq(report.placements[4].observed_node_state, None)
  assert_eq(
    report.json_text(),
    @deployment_report.explore(
      [blank, { ..op, plan: { ..op.plan, replicas: op.plan.replicas.rev(), }, }],
      nodes().rev(),
      query(),
    ).json_text(),
  )
  assert_eq(before, [op, blank].to_json().stringify())
  let json = report.json_text()
  for
    hidden in [
      "HIDDEN", "secret_refs", "signature", "readiness", "ready_replicas", "approval_receipt",
      "s3://",
    ] {
    assert_false(json.contains(hidden))
  }
  assert_true(json.contains("9007199254740993"))
}

///|
test "AND filters retain operation totals and zero replica overview" {
  let op = operation()
  let report = @deployment_report.explore([op], nodes(), {
    ..query(),
    node_id: "a",
    deployment_id: op.deployment_id,
    model_id: "model.text",
    operation_state: "Ready",
  })
  assert_eq(report.deployments[0].planned_replicas, 5)
  assert_eq(report.deployments[0].selected_placements, 2)
  assert_eq(report.placements.length(), 2)
  for
    q in [
      { ..query(), model_id: "absent", },
      { ..query(), deployment_id: "absent", },
      { ..query(), operation_state: "Blocked", },
      { ..query(), node_id: "absent", },
    ] {
    assert_eq(
      @deployment_report.explore([op], nodes(), q).deployments.length(),
      0,
    )
  }
  let zero = { ..op, plan: { ..op.plan, replicas: [], template: None, }, }
  assert_eq(
    @deployment_report.explore([zero], [], query()).deployments.length(),
    1,
  )
  assert_eq(
    @deployment_report.explore([zero], [], { ..query(), node_id: "a", }).deployments.length(),
    0,
  )
}

///|
test "ambiguous joins and mismatched associations rejected before filtering" {
  let op = operation()
  for
    ops in [
      [op, op],
      [
        {
          ..op,
          plan: {
            ..op.plan,
            intent: { ..op.plan.intent, deployment_id: "other", },
          },
        },
      ],
      [
        {
          ..op,
          plan: {
            ..op.plan,
            template: Some({ ..template(), version: "other", }),
          },
        },
      ],
      [
        {
          ..op,
          plan: {
            ..op.plan,
            replicas: [op.plan.replicas[0], op.plan.replicas[0]],
          },
        },
      ],
    ] {
    assert_true(
      try {
        let _ = @deployment_report.explore(ops, [], {
          ..query(),
          deployment_id: "absent",
        })
        false
      } catch {
        _ => true
      },
    )
  }
  for
    ns in [
      [node("a", 1L), node("a", 2L)],
      [{ ..node("a", 1L), inventory: node("b", 1L).inventory, }],
      [node("a", -1L)],
    ] {
    assert_true(
      try {
        let _ = @deployment_report.explore([], ns, query())
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "strict query malformed source and collection bounds" {
  assert_eq(
    @deployment_report.import_query(query().to_json().stringify())
    .to_json()
    .stringify(),
    query().to_json().stringify(),
  )
  for
    wire in [
      "{}",
      "[]",
      "{",
      query().to_json().stringify().replace_all(old="model_id", new="typo"),
      query().to_json().stringify().replace_all(old="1000", new="-1"),
    ] {
    assert_true(
      try {
        let _ = @deployment_report.import_query(wire)
        false
      } catch {
        _ => true
      },
    )
  }
  for wire in ["{}", "{", "[{}]"] {
    assert_true(
      try {
        let _ = @deployment_report.import_operations(wire)
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      let _ = @deployment_report.explore(
        Array::make(1001, operation()),
        [],
        query(),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @deployment_report.explore(
        [],
        Array::make(10001, node("a", 1L)),
        query(),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "CSV quoting unicode formula text missing values and empty headers" {
  let op = { ..operation(), operation_id: "=SUM(1,2)\n\"你好\"", }
  let report = @deployment_report.explore([op], [], query())
  assert_true(
    report.deployments_csv().contains("\"'=SUM(1,2)\n\"\"你好\"\"\""),
  )
  assert_true(report.placements_csv().contains("missing-node"))
  assert_eq(
    @deployment_report.explore([], [], query())
    .placements_csv()
    .split("\r\n")
    .count(),
    2,
  )
  assert_eq(
    @deployment_report.explore([], [], query())
    .deployments_csv()
    .split("\r\n")
    .count(),
    2,
  )
}

///|
test "bounded replica device membership and identity allocations" {
  let op = operation()
  let r = op.plan.replicas[0]
  for
    bad in [
      { ..op, plan: { ..op.plan, replicas: Array::make(5001, r), }, },
      {
        ..op,
        plan: {
          ..op.plan,
          replicas: [{ ..r, devices: Array::make(20001, "device"), }],
        },
      },
      {
        ..op,
        plan: { ..op.plan, replicas: [{ ..r, devices: ["same", "same"], }], },
      },
      { ..op, operation_id: Array::make(513, "x").join(""), },
    ] {
    assert_true(
      try {
        let _ = @deployment_report.explore([bad], [], query())
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      let _ = @deployment_report.explore(
        [],
        [{ ..node("a", 1L), running_deployments: Array::make(20001, "x"), }],
        query(),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @deployment_report.import_query(Array::make(16385, " ").join(""))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @deployment_report.explore([], [], {
        ..query(),
        maximum_age_ms: -1L,
      })
      false
    } catch {
      _ => true
    },
  )
}

///|
test "exact upper timestamp boundary and missing JSON properties" {
  let max = 9007199254740991L
  let report = @deployment_report.explore([operation()], [node("a", max)], {
    ..query(),
    now_unix_ms: max,
    maximum_age_ms: 0L,
  })
  assert_eq(report.placements[0].age_ms, Some(0L))
  assert_eq(report.placements[0].freshness, "fresh")
  assert_true(report.json_text().contains("9007199254740991"))
  guard @json.parse(report.json_text()) is { "placements": Array(rows), .. } else {
    fail("shape")
  }
  guard rows[4] is Object(fields) else { fail("row") }
  assert_false(fields.contains("observed_unix_ms"))
  assert_false(fields.contains("age_ms"))
  assert_true(
    try {
      let _ = @deployment_report.explore([], [node("a", max + 1L)], query())
      false
    } catch {
      _ => true
    },
  )
}
