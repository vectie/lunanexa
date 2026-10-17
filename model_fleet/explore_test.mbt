///|
fn query() -> @model_fleet.Query {
  {
    schema_version: "lunanexa.model-fleet.query.v1",
    now_unix_ms: 1000L,
    maximum_age_ms: 100L,
    memory_reserve_mib: 1024,
    model_id: "",
    version: "",
    node_id: "",
  }
}

///|
fn model(id : String, memory : Int) -> @contracts.ModelRecord {
  {
    model_id: id,
    version: "v1",
    artifact: {
      digest: "sha256:" + "a".repeat(64),
      uri: "modelstore://synthetic",
      size_bytes: 1L,
      signature_ref: "excluded-signature",
    },
    license_id: "excluded-license",
    provenance: "excluded synthetic metadata",
    compatible_architectures: ["fixture-arch"],
    minimum_memory_mib: memory,
    state: Candidate,
  }
}

///|
fn node(
  id : String,
  state : @contracts.NodeState,
  time : Int64,
  devices : Array[@contracts.AcceleratorInventory],
) -> @contracts.NodeHeartbeat {
  {
    node_id: id,
    state,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: id,
      agent_version: "fixture",
      os_release: "excluded-os",
      runtime_names: ["excluded-runtime"],
      accelerators: devices,
      labels: { "excluded": "excluded" },
      taints: [],
    },
    running_deployments: ["excluded-deployment"],
    timestamp_unix_ms: time,
    signature: "excluded-signature",
    runtime_endpoints: None,
  }
}

///|
fn device(
  id : String,
  architecture : String,
  free : Int,
  healthy : Bool,
) -> @contracts.AcceleratorInventory {
  {
    device_id: id,
    architecture,
    memory_total_mib: 16384,
    memory_free_mib: free,
    healthy,
  }
}

///|
test "single-device declarations retain health approval freshness and zero-device caveats" {
  let models = [model("small", 4096), model("large", 8192)]
  let nodes = [
    node("a", Active, 900L, [
      device("0", "fixture-arch", 5120, true),
      device("1", "fixture-arch", 8192, false),
    ]),
    node("b", Cordoned, 899L, [device("0", "other-arch", 16384, true)]),
    node("cpu", Active, 1001L, []),
  ]
  let before = (models.to_json(), nodes.to_json())
  let report = @model_fleet.explore(models, nodes, query())
  assert_eq(report.rows.length(), 8)
  assert_eq(report.models[0].model_id, "large")
  assert_eq(report.models[0].devices_matching_declarations, 0)
  assert_eq(report.models[1].devices_matching_declarations, 2)
  assert_eq(report.models[1].nodes_without_devices, 1)
  let row = report.rows[4]
  assert_eq(row.memory_margin_mib, Some(0L))
  assert_eq(row.declaration_comparison, "matches-declarations")
  assert_eq(row.freshness, "fresh")
  assert_eq(row.cautions, ["model-not-recorded-approved"])
  assert_eq(report.rows[5].declaration_comparison, "matches-declarations")
  assert_true(report.rows[5].cautions.contains("device-recorded-unhealthy"))
  assert_eq(report.rows[6].declaration_comparison, "architecture-mismatch")
  assert_true(report.rows[6].cautions.contains("stale-heartbeat"))
  assert_true(report.rows[6].cautions.contains("node-not-recorded-active"))
  let absent = report.rows[7]
  assert_eq(absent.device_id, None)
  assert_eq(absent.memory_matches, None)
  assert_eq(absent.memory_margin_mib, None)
  assert_eq(absent.freshness, "future")
  assert_eq(absent.declaration_comparison, "no-device-observation")
  assert_false(report.json_text().contains("excluded"))
  assert_eq(before, (models.to_json(), nodes.to_json()))
}

///|
test "reserves are editable do not pool device memory and use exact 64-bit arithmetic" {
  let nodes = [
    node("a", Active, 900L, [
      device("0", "fixture-arch", 8192, true),
      device("1", "fixture-arch", 8192, true),
    ]),
  ]
  let models = [model("m", 8192)]
  let without = @model_fleet.explore(models, nodes, {
    ..query(),
    memory_reserve_mib: 0,
  })
  assert_eq(without.models[0].devices_matching_declarations, 2)
  let reserved = @model_fleet.explore(models, nodes, query())
  assert_eq(reserved.models[0].devices_matching_declarations, 0)
  assert_eq(reserved.rows[0].memory_margin_mib, Some(-1024L))
  let huge = @model_fleet.explore([model("huge", 2147483647)], nodes, {
    ..query(),
    memory_reserve_mib: 2147483647,
  })
  assert_eq(huge.rows[0].required_with_reserve_mib, 4294967294L)
  assert_eq(huge.rows[0].memory_margin_mib, Some(-4294959102L))
  assert_true(
    @model_fleet.explore(models, nodes, { ..query(), memory_reserve_mib: 0, }) ==
    without,
  )
}

///|
test "exact filters deterministic ordering empty selections and unmutated arrays" {
  let models = [model("z", 1), model("a", 1)]
  let nodes = [
    node("z", Active, 900L, []),
    node("a", Active, 900L, [
      device("z", "fixture-arch", 8192, true),
      device("a", "fixture-arch", 8192, true),
    ]),
  ]
  let all = @model_fleet.explore(models, nodes, query())
  let reversed_models = [models[1], models[0]]
  let reversed_nodes = [nodes[1], nodes[0]]
  assert_true(
    all == @model_fleet.explore(reversed_models, reversed_nodes, query()),
  )
  assert_eq(all.rows[0].node_id, "a")
  assert_eq(all.rows[0].device_id, Some("a"))
  let selected = @model_fleet.explore(models, nodes, {
    ..query(),
    model_id: "a",
    version: "v1",
    node_id: "z",
  })
  assert_eq(selected.rows.length(), 1)
  assert_eq(selected.selected_model_count, 1)
  assert_eq(selected.source_model_count, 2)
  let empty = @model_fleet.explore(models, nodes, {
    ..query(),
    node_id: "absent",
  })
  assert_eq(empty.rows.length(), 0)
  assert_eq(empty.models.length(), 2)
  assert_eq(empty.matrix_csv().split("\r\n").count(), 2)
  assert_eq(
    @model_fleet.explore(models, nodes, { ..query(), version: "V1", }).selected_model_count,
    0,
  )
}

///|
test "missing invalid and duplicated data fail before filters and do not imply compatibility" {
  let m = model("m", 1)
  let n = node("a", Active, 900L, [device("0", "fixture-arch", 8192, true)])
  for
    models in [
      [m, m],
      [{ ..m, minimum_memory_mib: 0, }],
      [{ ..m, compatible_architectures: [], }],
      [{ ..m, compatible_architectures: ["fixture-arch", "fixture-arch"], }],
      [{ ..m, artifact: { ..m.artifact, digest: "sha256:short", }, }],
    ] {
    try
      @model_fleet.explore(models, [n], { ..query(), model_id: "absent", })
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid model accepted")
    }
  }
  for
    nodes in [
      [n, n],
      [node("bad", Active, -1L, [])],
      [node("bad", Active, 900L, [device("0", "", 8192, true)])],
      [node("bad", Active, 900L, [device("0", "a", 20000, true)])],
      [
        node("bad", Active, 900L, [
          device("0", "a", 1, true),
          device("0", "a", 1, true),
        ]),
      ],
    ] {
    try
      @model_fleet.explore([m], nodes, { ..query(), node_id: "absent", })
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid node accepted")
    }
  }
  try
    @model_fleet.explore([m], [n], { ..query(), memory_reserve_mib: -1, })
  catch {
    _ => ()
  } noraise {
    _ => fail("negative reserve accepted")
  }
}

///|
test "registry and Candidate drafts preserve version identity and reject incomplete declarations" {
  let m = model("m", 1)
  let registry = (
    {
      "schema_version": "lunanexa.registry.v1",
      "models": [m.to_json()],
      "unrelated": true,
    } : Json).stringify()
  assert_eq(@model_fleet.import_models(registry, "registry"), [m])
  let draft = ({ "schema_version": 1, "models": [m.to_json()] } : Json).stringify()
  assert_eq(@model_fleet.import_models(draft, "draft"), [m])
  for
    invalid in [
      draft.replace_all(old="\"Candidate\"", new="\"Approved\""),
      draft.replace_all(old="\"minimum_memory_mib\":1,", new=""),
      draft.replace_all(
        old="\"minimum_memory_mib\":1",
        new="\"minimum_memory_mib\":0",
      ),
      draft.replace_all(
        old="\"schema_version\":1",
        new="\"schema_version\":1,\"typo\":true",
      ),
    ] {
    try @model_fleet.import_models(invalid, "draft") catch {
      _ => ()
    } noraise {
      _ => fail("invalid draft accepted")
    }
  }
  let wire = query().to_json().stringify()
  assert_true(@model_fleet.import_query(wire) == query())
  try
    @model_fleet.import_query(
      wire.replace_all(
        old="\"version\":\"\"",
        new="\"version\":\"\",\"typo\":true",
      ),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("unknown query accepted")
  }
}

///|
test "CSV quotes formula-like Unicode text and distinguishes numeric negative margin" {
  let report = @model_fleet.explore(
    [model(" =SUM(1,2)\n雪", 8192)],
    [
      node("@node", Active, 900L, [
        device("\"device\"", "fixture-arch", 4096, true),
      ]),
    ],
    query(),
  )
  let csv = report.matrix_csv()
  assert_true(csv.contains("\"' =SUM(1,2)\n雪\""))
  assert_true(csv.contains("\"'@node\""))
  assert_true(csv.contains("\"\"\"device\"\"\""))
  assert_true(csv.contains(",-5120,"))
  assert_true(csv.has_suffix("\r\n"))
}

///|
test "comparison row bound rejects explosion before report allocation" {
  let models = Array::makei(501, i => model("m" + i.to_string(), 1))
  let nodes = Array::makei(100, i => node("n" + i.to_string(), Active, 900L, []))
  try @model_fleet.explore(models, nodes, query()) catch {
    _ => ()
  } noraise {
    _ => fail("row bound ignored")
  }
  assert_eq(
    @model_fleet.explore(models, nodes, { ..query(), model_id: "m0", }).rows.length(),
    100,
  )
}
