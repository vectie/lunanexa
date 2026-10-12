///|
fn history_query() -> @fleet.HistoryQuery {
  { node_id: "", scope: "all", field: "", }
}

///|
fn capture(
  id : String,
  time : Int64,
  nodes : Array[@contracts.NodeHeartbeat],
) -> @fleet.HistoryCapture {
  { capture_id: id, captured_unix_ms: time, nodes, }
}

///|
test "history compares adjacent captures with exact source associations" {
  let a = node("a", 900L)
  let b = node("b", 900L)
  let changed = {
    ..a,
    state: Cordoned,
    timestamp_unix_ms: 1500L,
    inventory: {
      ..a.inventory,
      agent_version: "fixture-v2",
      accelerators: [
        { ..a.inventory.accelerators[0], healthy: false, memory_free_mib: 0, },
      ],
    },
    running_deployments: [],
  }
  let report = @fleet.explore_history(
    [
      capture("before", 1000L, [a, b]),
      capture("during", 2000L, [changed, node("c", 1900L)]),
      capture("after", 3000L, [changed, b]),
    ],
    history_query(),
  )
  assert_eq(report.captures.length(), 3)
  assert_eq(report.transitions.length(), 2)
  assert_eq(report.transitions[0].newly_observed_nodes, 1)
  assert_eq(report.transitions[0].absent_nodes, 1)
  assert_eq(report.transitions[0].matched_nodes, 1)
  assert_eq(report.transitions[0].total_change_count, 7)
  assert_eq(report.transitions[1].total_change_count, 2)
  assert_eq(report.transitions[1].repeated_heartbeat_nodes, 1)
  assert_eq(report.changes.length(), 9)
  let health = report.changes
    .iter()
    .find_first(c => c.field == "healthy")
    .unwrap()
  assert_eq(health.before, Some("true"))
  assert_eq(health.after, Some("false"))
  assert_eq(health.from_capture, "before")
  assert_eq(health.to_capture, "during")
  assert_eq(health.from_captured_unix_ms, 1000L)
  assert_eq(health.to_captured_unix_ms, 2000L)
  assert_eq(health.before_observed_unix_ms, Some(900L))
  assert_eq(health.after_observed_unix_ms, Some(1500L))
  let absent = report.changes
    .iter()
    .find_first(c => c.node_id == "b" && c.to_capture == "during")
    .unwrap()
  assert_eq(absent.before, Some("observed"))
  assert_eq(absent.after, None)
  assert_eq(absent.after_observed_unix_ms, None)
  let reappeared = report.changes
    .iter()
    .find_first(c => c.node_id == "b" && c.to_capture == "after")
    .unwrap()
  assert_eq(reappeared.before, None)
  assert_eq(reappeared.after, Some("observed"))
  for
    hidden in [
      "private-signature", "private-deployment", "must-not-export", "runtime_endpoints",
      "labels", "path", "os_release",
    ] {
    assert_false(report.json_text().contains(hidden))
  }
}

///|
test "history ignores record device runtime order without mutating sources" {
  let a = node("a", 900L)
  let expanded = {
    ..a,
    inventory: {
      ..a.inventory,
      runtime_names: ["b", "a"],
      accelerators: [
        a.inventory.accelerators[0],
        { ..a.inventory.accelerators[0], device_id: "device-2", },
      ],
    },
  }
  let reversed = {
    ..expanded,
    timestamp_unix_ms: 1900L,
    inventory: {
      ..expanded.inventory,
      runtime_names: expanded.inventory.runtime_names.rev(),
      accelerators: expanded.inventory.accelerators.rev(),
    },
    running_deployments: ["different-private-deployment"],
  }
  let before = [expanded, node("b", 900L)]
  let wire = before.to_json().stringify()
  let captures = [
    capture("one", 1000L, before),
    capture("two", 2000L, [node("b", 1900L), reversed]),
  ]
  let report = @fleet.explore_history(captures, history_query())
  assert_eq(report.changes.length(), 0)
  assert_eq(report.transitions[0].matched_nodes, 2)
  assert_eq(report.transitions[0].repeated_heartbeat_nodes, 0)
  assert_true(
    @fleet.explore_history(
      [capture("one", 1000L, before.rev()), captures[1]],
      history_query(),
    ) ==
    report,
  )
  assert_eq(before.to_json().stringify(), wire)
  assert_eq(report.changes_csv().split("\r\n").count(), 2)
}

///|
test "history identity changes remain separate presence observations" {
  let a = node("a", 900L)
  let device_changed = {
    ..a,
    timestamp_unix_ms: 1900L,
    inventory: {
      ..a.inventory,
      accelerators: [
        { ..a.inventory.accelerators[0], device_id: "device-NEW", },
      ],
    },
  }
  let report = @fleet.explore_history(
    [capture("one", 1000L, [a]), capture("two", 2000L, [device_changed])],
    history_query(),
  )
  assert_eq(report.changes.length(), 2)
  assert_true(
    report.changes.all(c => c.scope == "device" && c.field == "presence"),
  )
  assert_true(
    report.changes.any(c => c.before == None && c.after == Some("observed")),
  )
  assert_true(
    report.changes.any(c => c.before == Some("observed") && c.after == None),
  )
  let nodes = @fleet.explore_history(
    [capture("one", 1000L, [a]), capture("two", 2000L, [node("new-id", 1900L)])],
    history_query(),
  )
  assert_eq(nodes.changes.length(), 2)
  assert_true(nodes.changes.all(c => c.scope == "node"))
}

///|
test "history filters retain full capture and transition counts" {
  let a = node("a", 900L)
  let changed = {
    ..a,
    state: Draining,
    inventory: {
      ..a.inventory,
      accelerators: [{ ..a.inventory.accelerators[0], memory_free_mib: 1234, }],
    },
  }
  let sources = [
    capture("one", 1000L, [a]),
    capture("two", 2000L, [changed, node("b", 1900L)]),
  ]
  let filtered = @fleet.explore_history(sources, {
    node_id: "a",
    scope: "device",
    field: "observed_free_mib",
  })
  assert_eq(filtered.changes.length(), 1)
  assert_eq(filtered.changes[0].before, Some("8000"))
  assert_eq(filtered.changes[0].after, Some("1234"))
  assert_eq(filtered.transitions[0].total_change_count, 3)
  assert_eq(filtered.transitions[0].selected_change_count, 1)
  assert_eq(filtered.captures[1].node_count, 2)
  let empty = @fleet.explore_history(sources, {
    ..history_query(),
    node_id: "absent",
  })
  assert_eq(empty.changes.length(), 0)
  assert_eq(empty.transitions[0].total_change_count, 3)
  assert_eq(empty.transitions[0].selected_change_count, 0)
  assert_eq(empty.changes_csv().split("\r\n").count(), 2)
}

///|
test "history highlights repeated regressed and future observations without inventing changes" {
  let report = @fleet.explore_history(
    [
      capture("one", 1000L, [node("a", 900L), node("b", 900L), node("c", 1001L)]),
      capture("two", 2000L, [node("a", 899L), node("b", 900L), node("c", 2001L)]),
    ],
    history_query(),
  )
  assert_eq(report.captures[0].future_heartbeat_count, 1)
  assert_eq(report.captures[1].future_heartbeat_count, 1)
  assert_eq(report.transitions[0].repeated_heartbeat_nodes, 1)
  assert_eq(report.transitions[0].regressed_heartbeat_nodes, 1)
  assert_eq(report.changes.length(), 0)
}

///|
test "empty captures are allowed but malformed sources are not absence" {
  let empty = @fleet.explore_history(
    [capture("empty-one", 1000L, []), capture("empty-two", 2000L, [])],
    history_query(),
  )
  assert_eq(empty.changes.length(), 0)
  assert_eq(empty.transitions[0].matched_nodes, 0)
  assert_eq(empty.captures[0].node_count, 0)
  let a = node("a", 900L)
  for
    invalid in [
      [a, a],
      [{ ..a, inventory: { ..a.inventory, node_id: "wrong", }, }],
      [
        {
          ..a,
          inventory: {
            ..a.inventory,
            accelerators: [
              { ..a.inventory.accelerators[0], memory_free_mib: -1, },
            ],
          },
        },
      ],
    ] {
    assert_true(
      try {
        let _ = @fleet.explore_history(
          [capture("one", 1000L, []), capture("two", 2000L, invalid)],
          { ..history_query(), node_id: "absent", },
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let missing = a
    .to_json()
    .stringify()
    .replace_all(old="\"state\":\"Active\",", new="")
  assert_true(
    try {
      let _ = @fleet.import_nodes("[" + missing + "]")
      false
    } catch {
      _ => true
    },
  )
}

///|
test "capture count identity time order and bounds are explicit" {
  for
    invalid in [
      [capture("one", 0L, [])],
      [capture("one", 0L, []), capture("one", 1L, [])],
      [capture(" ", 0L, []), capture("two", 1L, [])],
      [capture("one", 1L, []), capture("two", 0L, [])],
      [capture("one", 1L, []), capture("two", 1L, [])],
      [capture("one", -1L, []), capture("two", 1L, [])],
      [capture("one", 0L, []), capture("two", 9007199254740992L, [])],
      Array::makei(17, i => capture(i.to_string(), i.to_int64(), [])),
    ] {
    assert_true(
      try {
        let _ = @fleet.explore_history(invalid, history_query())
        false
      } catch {
        _ => true
      },
    )
  }
  let edge = @fleet.explore_history(
    [
      capture("one", 9007199254740990L, []),
      capture("two", 9007199254740991L, [node("a", 9007199254740991L)]),
    ],
    history_query(),
  )
  assert_true(edge.json_text().contains("\"9007199254740991\""))
  assert_eq(edge.changes[0].to_captured_unix_ms, 9007199254740991L)
}

///|
test "manifest and query reject unknown missing mistyped or invalid fields" {
  let manifest =
    #|{"schema_version":"lunanexa.fleet.history-input.v1","captures":[{"capture_id":"before","captured_unix_ms":"0","path":"before.json"},{"capture_id":"after","captured_unix_ms":"1","path":"after.json"}]}
  let imported = @fleet.import_history_manifest(manifest)
  assert_eq(imported.captures[1].path, "after.json")
  assert_true(
    @fleet.import_history_manifest(imported.to_json().stringify()) == imported,
  )
  for
    invalid in [
      manifest.replace_all(old="history-input.v1", new="history-input.v2"),
      manifest.replace_all(old="\"path\":\"after.json\"", new="\"path\":\"\""),
      manifest.replace_all(
        old="\"path\":\"after.json\"",
        new="\"typo\":\"after.json\"",
      ),
      manifest.replace_all(old="\"after\"", new="\"before\""),
      manifest.replace_all(old="\"1\"", new="\"0\""),
      manifest.replace_all(
        old="\"captures\":",
        new="\"unknown\":true,\"captures\":",
      ),
      manifest.replace_all(old="\"captured_unix_ms\":\"1\",", new=""),
    ] {
    assert_true(
      try {
        let _ = @fleet.import_history_manifest(invalid)
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    @fleet.import_history_query(history_query().to_json().stringify()) ==
    history_query(),
  )
  for
    invalid in [
      "{}", "[]", "{\"node_id\":\"\",\"scope\":\"all\",\"field\":\"\",\"typo\":1}",
      "{\"node_id\":\"\",\"scope\":\"wrong\",\"field\":\"\"}", "{\"node_id\":\"\",\"scope\":\"all\",\"field\":\"signature\"}",
      "{\"node_id\":null,\"scope\":\"all\",\"field\":\"\"}",
    ] {
    assert_true(
      try {
        let _ = @fleet.import_history_query(invalid)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "CSV distinguishes absent from empty quotes and escapes Unicode formula text" {
  let id = "=synthetic,\"节点\"\nname"
  let a = {
    ..node(id, 900L),
    inventory: { ..node(id, 900L).inventory, agent_version: "", },
  }
  let b = { ..a, inventory: { ..a.inventory, agent_version: "@next", }, }
  let report = @fleet.explore_history(
    [capture("=before", 1000L, [a]), capture("after", 2000L, [b])],
    history_query(),
  )
  let csv = report.changes_csv()
  assert_true(csv.contains("\"'=synthetic,\"\"节点\"\"\nname\""))
  assert_true(csv.contains("\"agent_version\",\"\",\"'@next\""))
  assert_true(csv.contains("\"'=before\""))
  assert_true(report.json_text().contains("@next"))
  assert_false(report.json_text().contains("'@next"))
}

///|
test "history bounds cumulative node records before producing output" {
  let n = node("template", 0L)
  let nodes = Array::makei(7500, i => {
    let id = "node-\{i}"
    {
      ..n,
      node_id: id,
      inventory: { ..n.inventory, node_id: id, accelerators: [], },
    }
  })
  assert_true(
    try {
      let _ = @fleet.explore_history(
        [
          capture("one", 0L, nodes),
          capture("two", 1L, nodes),
          capture("three", 2L, nodes),
        ],
        history_query(),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "device identity stays scoped to its node and all scalar fields are compared" {
  let a = node("a", 900L)
  let b = node("b", 900L)
  let revised = {
    ..a,
    inventory: {
      ..a.inventory,
      runtime_names: ["fixture-runtime", "fixture-runtime"],
      accelerators: [
        {
          ..a.inventory.accelerators[0],
          architecture: "revised-arch",
          memory_total_mib: 20000,
        },
      ],
    },
  }
  let report = @fleet.explore_history(
    [capture("one", 1000L, [a, b]), capture("two", 2000L, [b, revised])],
    history_query(),
  )
  assert_eq(report.changes.length(), 3)
  assert_true(report.changes.all(c => c.node_id == "a"))
  assert_true(
    report.changes.any(c => {
      c.field == "architecture" && c.after == Some("revised-arch")
    }),
  )
  assert_true(
    report.changes.any(c => {
      c.field == "observed_total_mib" && c.after == Some("20000")
    }),
  )
  assert_true(
    report.changes.any(c => {
      c.field == "runtime_names" &&
      c.after == Some("[\"fixture-runtime\",\"fixture-runtime\"]")
    }),
  )
}

///|
test "history bounds cumulative device records independently of node count" {
  let n = node("a", 0L)
  let devices = Array::makei(15000, i => {
    ..n.inventory.accelerators[0],
    device_id: "device-\{i}",
  })
  let nodes = [{ ..n, inventory: { ..n.inventory, accelerators: devices, }, }]
  assert_true(
    try {
      let _ = @fleet.explore_history(
        [
          capture("one", 0L, nodes),
          capture("two", 1L, nodes),
          capture("three", 2L, nodes),
        ],
        history_query(),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "history JSON omits absent optional properties instead of emitting null" {
  let report = @fleet.explore_history(
    [
      capture("present", 1000L, [node("a", 900L)]),
      capture("absent", 2000L, []),
      capture("present-again", 3000L, [node("a", 2900L)]),
    ],
    history_query(),
  )
  guard @json.parse(report.json_text()) is { "changes": Array(changes), .. } else {
    fail("missing changes")
  }
  assert_eq(changes.length(), 2)
  guard changes[0] is Object(first) else { fail("missing first change") }
  assert_false(first.contains("after"))
  assert_false(first.contains("after_observed_unix_ms"))
  assert_false(first.contains("device_id"))
  guard changes[0]
    is { "before": "observed", "before_observed_unix_ms": "900", .. } else {
    fail("missing prior observation")
  }
  guard changes[1] is Object(second) else { fail("missing second change") }
  assert_false(second.contains("before"))
  assert_false(second.contains("before_observed_unix_ms"))
  assert_false(second.contains("device_id"))
  guard changes[1]
    is { "after": "observed", "after_observed_unix_ms": "2900", .. } else {
    fail("missing next observation")
  }
}
