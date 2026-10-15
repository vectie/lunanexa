///|
fn report_query() -> @commercial.UsageQuery {
  {
    organization_id: "org-a",
    started_unix_ms: 1500L,
    ended_unix_ms: 6000L,
    project_id: "",
    meter: "",
    group_by: "project",
  }
}

///|
fn report_snapshot() -> @commercial.CommercialSnapshot raise {
  let store = base_store()
  ignore(add_rated_usage(store, "usage-one", "charge-one", 3L))
  ignore(
    store.finalize_period(
      "first", "org-a", 1500L, 4000L, "UTC", "CNY", 2, "finance-a", 4000L,
    ),
  )
  ignore(
    store.append_adjustment(
      "credit-one",
      "org-a",
      "charge-one",
      Credit,
      @commercial.money(2L, "CNY", 2),
      "Partial credit",
      4100L,
    ),
  )
  ignore(
    store.ingest_usage(
      usage("usage-unpriced", 5L, started_unix_ms=4500L, ended_unix_ms=5000L),
    ),
  )
  store.snapshot("org-a")
}

///|
test "usage report joins usage and credits without mutating or pricing missing usage" {
  let source = report_snapshot()
  let before = source.to_json().stringify()
  let report = @commercial.explore_usage(source, report_query())
  assert_eq(report.rows.length(), 3)
  assert_eq(report.groups.length(), 2)
  let priced = report.groups.filter(group => group.amount is Some(_))[0]
  assert_eq(priced.quantity, 3L)
  assert_eq(priced.amount, Some(@commercial.money(4L, "CNY", 2)))
  assert_eq(priced.ledger_entry_count, 2)
  assert_eq(priced.missing_observation_count, 0)
  let unpriced = report.groups.filter(group => group.amount is None)[0]
  assert_eq(unpriced.quantity, 5L)
  assert_eq(unpriced.unpriced_usage_count, 1)
  assert_eq(report.rows[1].linked_entry_id, "charge-one")
  assert_eq(report.rows[0].workload_id, "lease-a")
  assert_eq(report.rows[0].rate_card_id, "lease-rate")
  assert_eq(report.rows[0].rate_card_version, "v1")
  assert_eq(report.rows[0].recorded_unix_ms, 3100L)
  assert_eq(report.rows[1].reason, "Partial credit")
  assert_eq(report.rows[2].rate_card_id, "")
  assert_eq(before, source.to_json().stringify())
  assert_true(report.json_text().contains("\"amount\": null"))
  assert_false(report.json_text().contains("dgx-1"))
  assert_false(report.rows_csv().contains("actor-a"))
}

///|
test "customer snapshots without observations still expose recorded charges honestly" {
  let source = { ..report_snapshot(), usage_observations: [], }
  let report = @commercial.explore_usage(source, report_query())
  assert_eq(report.rows.length(), 2)
  assert_eq(report.groups.length(), 1)
  assert_eq(report.groups[0].missing_observation_count, 1)
  assert_eq(report.groups[0].unpriced_usage_count, 0)
  assert_eq(report.groups[0].amount, Some(@commercial.money(4L, "CNY", 2)))
  assert_eq(report.rows[0].workload_id, "")
}

///|
test "half-open windows include intersecting rows in full and flag crossing records" {
  let source = report_snapshot()
  let full = @commercial.explore_usage(source, {
    ..report_query(),
    started_unix_ms: 2000L,
    ended_unix_ms: 3000L,
  })
  assert_eq(full.rows.length(), 1)
  assert_eq(full.groups[0].crossing_window_count, 0)
  let partial = @commercial.explore_usage(source, {
    ..report_query(),
    started_unix_ms: 2500L,
    ended_unix_ms: 2800L,
  })
  assert_eq(partial.rows.length(), 1)
  assert_eq(partial.groups[0].quantity, 3L)
  assert_eq(partial.groups[0].amount, Some(@commercial.money(6L, "CNY", 2)))
  assert_eq(partial.groups[0].crossing_window_count, 1)
  let empty = @commercial.explore_usage(source, {
    ..report_query(),
    started_unix_ms: 3000L,
    ended_unix_ms: 4100L,
  })
  assert_eq(empty.rows.length(), 0)
  assert_eq(empty.summary_csv().split("\n").count(), 2)
  let credit_only = @commercial.explore_usage(source, {
    ..report_query(),
    started_unix_ms: 4100L,
    ended_unix_ms: 4101L,
  })
  assert_eq(credit_only.rows.length(), 1)
  assert_eq(credit_only.groups[0].quantity, 0L)
  assert_eq(
    credit_only.groups[0].amount,
    Some(@commercial.money(-2L, "CNY", 2)),
  )
}

///|
test "grouping and filters preserve meter currency and scale dimensions" {
  let source = report_snapshot()
  let original = source.ledger_entries[0]
  let second_project = {
    ..source.projects[0],
    project_id: "project-b",
    display_name: "Batch",
  }
  let second_charge = {
    ..original,
    entry_id: "charge-two",
    source_event_id: "usage-two",
    project_id: "project-b",
    project_name_snapshot: "Batch",
  }
  let dollar = {
    ..original,
    entry_id: "charge-usd",
    source_event_id: "usage-usd",
    amount: @commercial.money(12L, "USD", 2),
  }
  let scale = {
    ..original,
    entry_id: "charge-scale",
    source_event_id: "usage-scale",
    amount: @commercial.money(12L, "CNY", 3),
  }
  let meter = {
    ..original,
    entry_id: "charge-meter",
    source_event_id: "usage-meter",
    meter: "accelerator-second",
  }
  let source = {
    ..source,
    projects: source.projects + [second_project],
    ledger_entries: source.ledger_entries +
    [second_charge, dollar, scale, meter],
  }
  let by_project = @commercial.explore_usage(source, report_query())
  assert_eq(by_project.groups.length(), 6)
  let by_center = @commercial.explore_usage(source, {
    ..report_query(),
    group_by: "cost-center",
  })
  assert_eq(by_center.groups.length(), 5)
  let combined = by_center.groups.filter(group => {
    group.meter == "node-second" &&
    group.amount == Some(@commercial.money(10L, "CNY", 2))
  })
  assert_eq(combined.length(), 1)
  assert_eq(combined[0].quantity, 6L)
  let project = @commercial.explore_usage(source, {
    ..report_query(),
    project_id: "project-b",
    meter: "node-second",
  })
  assert_eq(project.rows.length(), 1)
  assert_eq(project.groups[0].amount, Some(@commercial.money(6L, "CNY", 2)))
  let by_meter = @commercial.explore_usage(source, {
    ..report_query(),
    group_by: "meter",
    meter: "accelerator-second",
  })
  assert_eq(by_meter.groups.length(), 1)
  assert_eq(by_meter.groups[0].group_id, "accelerator-second")
}

///|
test "historical ledger labels survive project renames and CSV remains spreadsheet usable" {
  let source = report_snapshot()
  let source = {
    ..source,
    projects: [{ ..source.projects[0], display_name: "Renamed", }],
  }
  let report = @commercial.explore_usage(source, report_query())
  assert_eq(report.rows[0].project_name, "=Serving")
  assert_eq(report.rows[2].project_name, "Renamed")
  assert_true(report.rows_csv().contains("\"'=Serving\""))
  assert_true(report.rows_csv().contains(",0,-2,\"CNY\",2,"))
  assert_true(report.summary_csv().contains(",5,,,,1,0,1,0,0\n"))
  let changed = {
    ..source,
    ledger_entries: [
      {
        ..source.ledger_entries[0],
        project_name_snapshot: "Comma, \"quote\"\nline",
        amount: @commercial.money(0L, "CNY", 2),
      },
    ],
  }
  let zero = @commercial.explore_usage(changed, report_query())
  assert_true(zero.rows_csv().contains("\"Comma, \"\"quote\"\"\nline\""))
  assert_true(zero.summary_csv().contains(",3,0,\"CNY\",2,"))
}

///|
test "usage reports are deterministic and organization scoped" {
  let source = report_snapshot()
  let report = @commercial.explore_usage(source, report_query())
  let reordered = {
    ..source,
    usage_observations: source.usage_observations.rev(),
    ledger_entries: source.ledger_entries.rev(),
  }
  assert_eq(@commercial.explore_usage(reordered, report_query()), report)
  let other = {
    ..source.ledger_entries[0],
    organization_id: "org-secret",
    project_name_snapshot: "Private Other Tenant",
  }
  let mixed = {
    ..source,
    ledger_entries: source.ledger_entries + [other],
    usage_observations: source.usage_observations +
    [{ ..source.usage_observations[0], organization_id: "org-secret", }],
  }
  assert_eq(@commercial.explore_usage(mixed, report_query()), report)
  assert_false(report.json_text().contains("Private Other Tenant"))
}

///|
test "imports accept existing snapshot schema and a plain editable query" {
  let source = report_snapshot()
  let query = report_query()
  assert_eq(
    @commercial.import_usage_snapshot(source.to_json().stringify()),
    source,
  )
  assert_eq(@commercial.import_usage_query(query.to_json().stringify()), query)
  try @commercial.import_usage_query("{}") catch {
    InvalidInput(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("expected invalid query")
  }
  try @commercial.import_usage_snapshot("{}") catch {
    InvalidInput(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("expected invalid snapshot")
  }
  try
    @commercial.explore_usage({ ..source, schema_version: "future", }, query)
  catch {
    InvalidInput(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("expected unsupported schema")
  }
  for
    invalid in [
      { ..query, ended_unix_ms: query.started_unix_ms, },
      { ..query, started_unix_ms: -1L, },
      { ..query, group_by: "day", },
      { ..query, organization_id: "missing", },
      { ..query, project_id: "missing", },
    ] {
    try @commercial.explore_usage(source, invalid) catch {
      InvalidInput(_) => ()
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("expected invalid query")
    }
  }
}

///|
test "ambiguous joins and duplicate source identities cannot double count costs" {
  let source = report_snapshot()
  let charge = source.ledger_entries[0]
  for
    invalid in [
      {
        ..source,
        usage_observations: source.usage_observations +
        [source.usage_observations[0]],
      },
      { ..source, ledger_entries: source.ledger_entries + [charge], },
      {
        ..source,
        ledger_entries: source.ledger_entries +
        [{ ..charge, entry_id: "another", }],
      },
      {
        ..source,
        ledger_entries: [{ ..charge, quantity: charge.quantity + 1L, }],
      },
      {
        ..source,
        ledger_entries: [
          { ..charge, amount: @commercial.money(-1L, "CNY", 2), },
        ],
      },
      { ..source, ledger_entries: [source.ledger_entries[1]], },
      {
        ..source,
        projects: [{ ..source.projects[0], cost_center_id: "missing", }],
      },
    ] {
    try @commercial.explore_usage(invalid, report_query()) catch {
      InvalidInput(_) => ()
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("expected invalid source")
    }
  }
}

///|
test "exact money and quantity overflow are errors rather than wrapped allocations" {
  let source = report_snapshot()
  let charge = source.ledger_entries[0]
  let huge = {
    ..charge,
    amount: @commercial.money(9223372036854775807L, "CNY", 2),
  }
  let more = {
    ..charge,
    entry_id: "more",
    source_event_id: "more",
    amount: @commercial.money(1L, "CNY", 2),
  }
  try
    @commercial.explore_usage(
      { ..source, ledger_entries: [huge, more], },
      report_query(),
    )
  catch {
    ArithmeticOverflow => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("expected money overflow")
  }
  let observations = [
    { ..source.usage_observations[0], quantity: 9223372036854775807L, },
    { ..source.usage_observations[0], event_id: "more", quantity: 1L, },
  ]
  try
    @commercial.explore_usage(
      { ..source, ledger_entries: [], usage_observations: observations, },
      report_query(),
    )
  catch {
    ArithmeticOverflow => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("expected quantity overflow")
  }
}
