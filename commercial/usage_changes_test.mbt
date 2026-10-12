///|
test "snapshot changes pair unpriced and charged usage with no invented zero" {
  let candidate = report_snapshot()
  let baseline = { ..candidate, ledger_entries: [], }
  let original = baseline.to_json().stringify()
  let result = @commercial.compare_usage_snapshots(
    baseline,
    candidate,
    report_query(),
  )
  assert_eq(result.baseline_row_count, 2)
  assert_eq(result.candidate_row_count, 3)
  assert_eq(result.unchanged_count, 1)
  assert_eq(result.changes.length(), 2)
  let rated = result.changes[0]
  assert_eq(rated.identity_kind, "event")
  assert_eq(rated.identity, "usage-one")
  assert_eq(rated.status, "changed")
  assert_eq(rated.before.unwrap().kind, "unpriced_usage")
  assert_eq(rated.before.unwrap().amount, None)
  assert_eq(rated.after.unwrap().amount, Some(@commercial.money(6L, "CNY", 2)))
  assert_eq(result.changes[1].status, "added")
  assert_eq(result.changes[1].identity_kind, "ledger")
  assert_eq(
    result.changes[1].after.unwrap().amount,
    Some(@commercial.money(-2L, "CNY", 2)),
  )
  assert_true(result.json_text().contains("\"amount\": null"))
  assert_true(result.json_text().contains("\"before\": null"))
  assert_true(result.rows_csv().contains("\"unpriced_usage\",\"\",,,,"))
  assert_eq(baseline.to_json().stringify(), original)
  let reverse = @commercial.compare_usage_snapshots(
    candidate,
    baseline,
    report_query(),
  )
  assert_eq(reverse.changes[0].after.unwrap().amount, None)
  assert_eq(reverse.changes[1].status, "removed")
}

///|
test "snapshot changes detect source bindings labels money and observation availability" {
  let source = report_snapshot()
  let charge = source.ledger_entries[0]
  let changed = {
    ..source,
    ledger_entries: [
      {
        ..charge,
        entry_id: "replacement-charge",
        project_name_snapshot: "=new,\"name\"",
        amount: @commercial.money(0L, "USD", 3),
      },
    ],
    usage_observations: [],
  }
  let report = @commercial.compare_usage_snapshots(
    source,
    changed,
    report_query(),
  )
  assert_eq(report.changes.length(), 3)
  let paired = report.changes.filter(c => c.identity == "usage-one")[0]
  assert_eq(paired.status, "changed")
  assert_eq(paired.before.unwrap().entry_id, "charge-one")
  assert_eq(paired.after.unwrap().entry_id, "replacement-charge")
  assert_eq(paired.after.unwrap().amount, Some(@commercial.money(0L, "USD", 3)))
  assert_false(paired.after.unwrap().observation_available)
  assert_true(report.rows_csv().contains("\"USD\",3,"))
  let rebound = {
    ..source,
    ledger_entries: [{ ..charge, source_event_id: "different-event", }],
  }
  let report = @commercial.compare_usage_snapshots(
    source,
    rebound,
    report_query(),
  )
  assert_true(
    report.changes.any(c => {
      c.identity == "different-event" && c.status == "added"
    }),
  )
  assert_true(
    report.changes.any(c => {
      c.identity == "usage-one" && c.after.unwrap().kind == "unpriced_usage"
    }),
  )
}

///|
test "snapshot change output is deterministic scoped and detects visible changes only" {
  let source = report_snapshot()
  let reordered = {
    ..source,
    ledger_entries: source.ledger_entries.rev(),
    usage_observations: source.usage_observations.rev(),
  }
  let report = @commercial.compare_usage_snapshots(
    source,
    reordered,
    report_query(),
  )
  assert_eq(report.unchanged_count, 3)
  assert_eq(report.changes.length(), 0)
  assert_eq(report.rows_csv().split("\n").count(), 2)
  let other = {
    ..source,
    ledger_entries: source.ledger_entries +
    [
      {
        ..source.ledger_entries[0],
        organization_id: "private-org",
        project_name_snapshot: "secret-tenant",
      },
    ],
  }
  assert_eq(
    @commercial.compare_usage_snapshots(source, other, report_query()).json_text(),
    report.json_text(),
  )
  let empty = @commercial.compare_usage_snapshots(source, reordered, {
    ..report_query(),
    meter: "absent",
  })
  assert_eq(empty.baseline_row_count, 0)
  assert_eq(empty.changes.length(), 0)
  let gone = { ..source, ledger_entries: [], usage_observations: [], }
  assert_eq(
    @commercial.compare_usage_snapshots(source, gone, report_query()).json_text(),
    @commercial.compare_usage_snapshots(reordered, gone, report_query()).json_text(),
  )
}

///|
test "both snapshots must independently pass usage validation before comparison" {
  let source = report_snapshot()
  let invalid = {
    ..source,
    ledger_entries: source.ledger_entries + [source.ledger_entries[0]],
  }
  for (before, after) in [(source, invalid), (invalid, source)] {
    try
      @commercial.compare_usage_snapshots(before, after, report_query())
    catch {
      @commercial.InvalidInput(_) => ()
      _ => fail("unexpected error")
    } noraise {
      _ => fail("expected duplicate rejection")
    }
  }
}

///|
test "event and ledger namespaces stay separate and window moves are view removals" {
  let source = report_snapshot()
  let credit = { ..source.ledger_entries[1], entry_id: "usage-one", }
  let before = { ..source, ledger_entries: [source.ledger_entries[0]], }
  let after = { ..source, ledger_entries: [source.ledger_entries[0], credit], }
  let report = @commercial.compare_usage_snapshots(
    before,
    after,
    report_query(),
  )
  assert_eq(report.changes.length(), 1)
  assert_eq(report.changes[0].identity_kind, "ledger")
  assert_eq(report.changes[0].identity, "usage-one")
  assert_eq(report.changes[0].status, "added")
  assert_eq(report.unchanged_count, 2)
  let observation = source.usage_observations.filter(o => {
      o.event_id == "usage-unpriced"
    })[0]
  let moved = {
    ..source,
    usage_observations: source.usage_observations.filter(o => {
      o.event_id != "usage-unpriced"
    }) +
    [{ ..observation, started_unix_ms: 6000L, ended_unix_ms: 7000L, }],
  }
  let moved_report = @commercial.compare_usage_snapshots(
    source,
    moved,
    report_query(),
  )
  assert_eq(moved_report.changes.length(), 1)
  assert_eq(moved_report.changes[0].status, "removed")
  assert_eq(moved_report.changes[0].identity, "usage-unpriced")
}
