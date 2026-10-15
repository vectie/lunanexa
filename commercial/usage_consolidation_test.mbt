///|
test "combine overlapping captures once with separate observation and ledger provenance" {
  let source = report_snapshot()
  let original = source.to_json().stringify()
  let observations = { ..source, ledger_entries: [], }
  let customer = { ..source, usage_observations: [], }
  let result = @commercial.consolidate_usage(
    [observations, customer, customer],
    report_query(),
  )
  assert_eq(result.report, @commercial.explore_usage(source, report_query()))
  assert_eq(result.unique_usage_count, 2)
  assert_eq(result.unique_ledger_count, 2)
  assert_eq(result.duplicate_usage_count, 0)
  assert_eq(result.duplicate_ledger_count, 2)
  assert_eq(result.row_sources[0].observation_sources, [1])
  assert_eq(result.row_sources[0].ledger_sources, [2, 3])
  assert_eq(result.row_sources[1].observation_sources, [])
  assert_eq(result.row_sources[1].ledger_sources, [2, 3])
  assert_eq(result.row_sources[2].observation_sources, [1])
  assert_eq(result.row_sources[2].ledger_sources, [])
  assert_eq(result.sources[0].selected_row_count, 2)
  assert_eq(result.sources[1].selected_row_count, 2)
  assert_eq(
    result.sources[1].snapshot_sha256,
    result.sources[2].snapshot_sha256,
  )
  assert_true(result.sources[0].snapshot_sha256.has_prefix("sha256:"))
  assert_eq(result.sources[0].snapshot_sha256.length(), 71)
  assert_eq(source.to_json().stringify(), original)
  assert_true(result.json_text().contains("\"amount\": null"))
  assert_false(result.json_text().contains("dgx-1"))
  assert_false(result.rows_csv().contains("actor-a"))
  assert_eq(result.summary_csv(), result.report.summary_csv())
}

///|
test "combined allocations do not depend on capture order or duplicate copies" {
  let source = report_snapshot()
  let first = { ..source, ledger_entries: [], }
  let second = { ..source, usage_observations: [], }
  let a = @commercial.consolidate_usage([first, second], report_query())
  let b = @commercial.consolidate_usage([second, first], report_query())
  assert_eq(a.report, b.report)
  assert_eq(a.summary_csv(), b.summary_csv())
  assert_eq(a.row_sources[0].ledger_sources, [2])
  assert_eq(b.row_sources[0].ledger_sources, [1])
  assert_eq(a.sources[0].snapshot_sha256, b.sources[1].snapshot_sha256)
  let duplicate = @commercial.consolidate_usage(
    [source, source],
    report_query(),
  )
  assert_eq(duplicate.report, a.report)
  assert_eq(duplicate.duplicate_usage_count, 2)
  assert_eq(duplicate.duplicate_ledger_count, 2)
  assert_eq(duplicate.row_sources[0].observation_sources, [1, 2])
  assert_eq(duplicate.row_sources[0].ledger_sources, [1, 2])
}

///|
fn combine_rejects(
  snapshots : Array[@commercial.CommercialSnapshot],
  expected : String,
) -> Unit raise {
  try @commercial.consolidate_usage(snapshots, report_query()) catch {
    InvalidInput(message) => assert_true(message.contains(expected))
    ArithmeticOverflow => assert_eq(expected, "overflow")
    _ => fail("unexpected commercial error")
  } noraise {
    _ => fail("expected rejected consolidation: \{expected}")
  }
}

///|
test "combine conflicts include exact record identity with no source precedence" {
  let source = report_snapshot()
  let charge = source.ledger_entries[0]
  combine_rejects(
    [
      source,
      {
        ..source,
        ledger_entries: [{ ..charge, amount: @commercial.money(8L, "CNY", 2), }],
      },
    ],
    "conflicting ledger entry identity charge-one in source 2",
  )
  combine_rejects(
    [
      source,
      {
        ..source,
        usage_observations: [
          { ..source.usage_observations[0], node_id: "changed-node", },
        ],
      },
    ],
    "conflicting usage event identity usage-one",
  )
  combine_rejects(
    [
      source,
      {
        ..source,
        projects: [{ ..source.projects[0], display_name: "Renamed", }],
      },
    ],
    "conflicting project identity",
  )
  combine_rejects(
    [
      source,
      {
        ..source,
        cost_centers: [{ ..source.cost_centers[0], display_name: "Renamed", }],
      },
    ],
    "conflicting cost center identity",
  )
  // Different entry IDs still cannot charge the same event twice.
  combine_rejects(
    [
      source,
      { ..source, ledger_entries: [{ ..charge, entry_id: "another-charge", }], },
    ],
    "ambiguous charge for usage event",
  )
}

///|
test "combine revalidates cross-capture joins and rejects invalid individual sources" {
  let source = report_snapshot()
  let observations = { ..source, ledger_entries: [], }
  let customer = { ..source, usage_observations: [], }
  let wrong_charge = {
    ..customer,
    ledger_entries: [{ ..customer.ledger_entries[0], quantity: 99L, }],
  }
  combine_rejects(
    [observations, wrong_charge],
    "charge does not match its usage observation",
  )
  combine_rejects([source, { ..source, organizations: [], }], "source 2:")
  combine_rejects(
    [
      source,
      {
        ..source,
        usage_observations: source.usage_observations +
        [source.usage_observations[0]],
      },
    ],
    "source 2: duplicate or invalid usage observation",
  )
  // A dangling credit is not silently repaired with another source's charge.
  combine_rejects(
    [source, { ..source, ledger_entries: [source.ledger_entries[1]], }],
    "source 2: adjustment requires",
  )
}

///|
test "combine retains money dimensions exact zero unknown and union overflow checks" {
  let source = report_snapshot()
  let zero = {
    ..source,
    usage_observations: [],
    ledger_entries: [
      {
        ..source.ledger_entries[0],
        entry_id: "usd-zero",
        source_event_id: "usd-event",
        amount: @commercial.money(0L, "USD", 3),
      },
    ],
  }
  let result = @commercial.consolidate_usage([source, zero], report_query())
  assert_eq(result.report.rows.length(), 4)
  assert_eq(result.report.groups.length(), 3)
  assert_eq(result.report.groups.filter(g => g.amount is None).length(), 1)
  assert_true(
    result.report.groups.any(g => {
      g.amount == Some(@commercial.money(0L, "USD", 3))
    }),
  )
  let huge = {
    ..zero,
    ledger_entries: [
      {
        ..zero.ledger_entries[0],
        amount: @commercial.money(9223372036854775807L, "CNY", 2),
      },
    ],
  }
  combine_rejects([source, huge], "overflow")
}

///|
test "combine supports empty windows and organization scope without inventing completeness" {
  let source = report_snapshot()
  let foreign = {
    ..source,
    usage_observations: source.usage_observations +
    [
      {
        ..source.usage_observations[0],
        organization_id: "other-org",
        node_id: "private-other-node",
      },
    ],
  }
  let result = @commercial.consolidate_usage([source, foreign], report_query())
  assert_eq(result.unique_usage_count, 2)
  assert_eq(result.duplicate_usage_count, 2)
  assert_false(result.json_text().contains("private-other-node"))
  let empty = @commercial.consolidate_usage([source], {
    ..report_query(),
    started_unix_ms: 6000L,
    ended_unix_ms: 7000L,
  })
  assert_eq(empty.report.rows.length(), 0)
  assert_eq(empty.row_sources.length(), 0)
  assert_eq(empty.rows_csv().split("\n").count(), 2)
  assert_eq(empty.unique_usage_count, 2)
  // Out-of-window source conflicts are still conflicts in the supplied union.
  try
    @commercial.consolidate_usage(
      [
        source,
        {
          ..source,
          ledger_entries: [{ ..source.ledger_entries[0], reason: "Changed", }],
        },
      ],
      { ..report_query(), started_unix_ms: 6000L, ended_unix_ms: 7000L, },
    )
  catch {
    InvalidInput(_) => ()
    _ => fail("unexpected commercial error")
  } noraise {
    _ => fail("out-of-window conflict was ignored")
  }
}

///|
test "combine bounds reject missing and excessive captures" {
  combine_rejects([], "1 to 8")
  combine_rejects(Array::make(9, report_snapshot()), "1 to 8")
}
