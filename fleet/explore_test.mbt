///|
fn query() -> @fleet.Query {
  {
    now_unix_ms: 1000L,
    maximum_age_ms: 100L,
    node_id: "",
    state: "",
    architecture: "",
    runtime: "",
    freshness: "all",
    health: "all",
  }
}

///|
fn node(id : String, timestamp : Int64) -> @contracts.NodeHeartbeat {
  {
    node_id: id,
    state: Active,
    observed_generation: 1L,
    controller_epoch: 1L,
    inventory: {
      node_id: id,
      agent_version: "fixture-v1",
      os_release: "synthetic",
      runtime_names: ["fixture-runtime"],
      accelerators: [
        {
          device_id: "device-1",
          architecture: "synthetic-arch",
          memory_total_mib: 16000,
          memory_free_mib: 8000,
          healthy: true,
        },
      ],
      labels: { "private": "must-not-export" },
      taints: [],
    },
    running_deployments: ["private-deployment"],
    runtime_endpoints: None,
    timestamp_unix_ms: timestamp,
    signature: "private-signature",
  }
}

///|
test "imports existing heartbeat wire; deterministic exploration and private-field omission" {
  let input = [node("b", 900L), node("a", 901L)]
  let wire = input.to_json().stringify()
  let report = @fleet.explore(@fleet.import_nodes(wire), query())
  assert_eq(report.nodes[0].node_id, "a")
  assert_eq(report.devices.length(), 2)
  assert_eq(report.groups.length(), 1)
  assert_eq(report.groups[0].summed_device_free_mib, 16000L)
  assert_true(report == @fleet.explore(input.rev(), query()))
  assert_eq(input.to_json().stringify(), wire)
  for
    hidden in [
      "must-not-export", "private-deployment", "private-signature", "labels", "runtime_endpoints",
    ] {
    assert_false(report.json_text().contains(hidden))
  }
}

///|
test "fresh boundary stale and future timestamps remain distinct" {
  let report = @fleet.explore(
    [node("exact", 900L), node("old", 899L), node("future", 1001L)],
    query(),
  )
  assert_eq(
    report.nodes.iter().find_first(r => r.node_id == "exact").unwrap().freshness,
    "fresh",
  )
  assert_eq(
    report.nodes.iter().find_first(r => r.node_id == "future").unwrap().freshness,
    "future",
  )
  assert_eq(
    report.nodes.iter().find_first(r => r.node_id == "future").unwrap().age_ms,
    None,
  )
  assert_eq(
    report.nodes.iter().find_first(r => r.node_id == "old").unwrap().freshness,
    "stale",
  )
  assert_eq(
    @fleet.explore([node("zero", 1000L)], { ..query(), maximum_age_ms: 0L, }).nodes[0].freshness,
    "fresh",
  )
  assert_eq(
    @fleet.explore([node("old", 899L)], { ..query(), freshness: "fresh", }).nodes.length(),
    0,
  )
}

///|
test "node runtime state and same-device health architecture filters" {
  let n = node("a", 1000L)
  let mixed = {
    ..n,
    state: Cordoned,
    inventory: {
      ..n.inventory,
      accelerators: [
        n.inventory.accelerators[0],
        {
          ..n.inventory.accelerators[0],
          device_id: "bad",
          architecture: "other",
          healthy: false,
        },
      ],
    },
  }
  let selected = @fleet.explore([mixed], {
    ..query(),
    architecture: "other",
    health: "unhealthy",
    state: "Cordoned",
    runtime: "fixture-runtime",
    node_id: "a",
  })
  assert_eq(selected.nodes[0].reported_devices, 2)
  assert_eq(selected.nodes[0].matching_devices, 1)
  assert_eq(selected.devices[0].device_id, "bad")
  assert_eq(
    @fleet.explore([mixed], {
      ..query(),
      architecture: "other",
      health: "healthy",
    }).nodes.length(),
    0,
  )
  assert_eq(
    @fleet.explore([mixed], { ..query(), runtime: "missing", }).nodes.length(),
    0,
  )
  assert_eq(
    @fleet.explore([mixed], { ..query(), state: "Active", }).nodes.length(),
    0,
  )
  assert_eq(
    @fleet.explore([mixed], { ..query(), node_id: "missing", }).nodes.length(),
    0,
  )
}

///|
test "CPU-only nodes and zero matches produce honest empty reports" {
  let n = node("cpu", 1000L)
  let cpu = { ..n, inventory: { ..n.inventory, accelerators: [], }, }
  let report = @fleet.explore([cpu], query())
  assert_eq(report.nodes.length(), 1)
  assert_eq(report.groups.length(), 0)
  assert_eq(report.devices.length(), 0)
  assert_eq(
    @fleet.explore([cpu], { ..query(), health: "healthy", }).nodes.length(),
    0,
  )
  assert_eq(@fleet.explore([], query()).summary_csv().split("\r\n").count(), 2)
}

///|
test "validates entire source even when invalid record is filtered out" {
  let n = node("a", 1000L)
  assert_true(
    try {
      let _ = @fleet.explore([n, n], { ..query(), node_id: "missing", })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @fleet.explore(
        [{ ..n, inventory: { ..n.inventory, node_id: "wrong", }, }],
        query(),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @fleet.explore([{ ..n, timestamp_unix_ms: -1L, }], query())
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @fleet.explore(
        [
          {
            ..n,
            inventory: {
              ..n.inventory,
              accelerators: [
                n.inventory.accelerators[0],
                n.inventory.accelerators[0],
              ],
            },
          },
        ],
        query(),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @fleet.explore(
        [
          {
            ..n,
            inventory: {
              ..n.inventory,
              accelerators: [
                { ..n.inventory.accelerators[0], memory_free_mib: 16001, },
              ],
            },
          },
        ],
        query(),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @fleet.explore([n], { ..query(), health: "yes", })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      let _ = @fleet.explore([n], { ..query(), maximum_age_ms: -1L, })
      false
    } catch {
      _ => true
    },
  )
}

///|
test "query typo rejection and precise JSON times" {
  let text = query().to_json().stringify()
  assert_true(@fleet.import_query(text) == query())
  assert_true(
    try {
      let _ = @fleet.import_query(
        text.replace(old="maximum_age_ms", new="maximum_age"),
      )
      false
    } catch {
      _ => true
    },
  )
  let report = @fleet.explore([node("a", 9007199254740991L)], {
    ..query(),
    now_unix_ms: 9007199254740991L,
  })
  assert_true(report.json_text().contains("\"9007199254740991\""))
  assert_eq(report.nodes[0].age_ms, Some(0L))
}

///|
test "CSV quotes Unicode delimiters newlines and formula-like identifiers" {
  let report = @fleet.explore(
    [node("=synthetic,\"设备\"\nnext", 1000L)],
    query(),
  )
  assert_true(
    report.nodes_csv().contains("\"'=synthetic,\"\"设备\"\"\nnext\""),
  )
  assert_true(report.nodes_csv().has_suffix("\r\n"))
  assert_true(report.devices_csv().contains(",true,16000,8000\r\n"))
  assert_true(report.summary_csv().contains(",true,1,16000,8000\r\n"))
}

///|
test "sum uses 64-bit and groups remain separated by freshness state and health" {
  let n = node("a", 1000L)
  let huge = {
    ..n,
    inventory: {
      ..n.inventory,
      accelerators: [
        {
          ..n.inventory.accelerators[0],
          memory_total_mib: 2147483647,
          memory_free_mib: 2147483647,
        },
        {
          ..n.inventory.accelerators[0],
          device_id: "two",
          memory_total_mib: 2147483647,
          memory_free_mib: 2147483647,
        },
      ],
    },
  }
  assert_eq(
    @fleet.explore([huge], query()).groups[0].summed_device_total_mib,
    4294967294L,
  )
  assert_eq(
    @fleet.explore(
      [n, node("b", 1L), { ..node("c", 1000L), state: Retired, }],
      query(),
    ).groups.length(),
    3,
  )
}
