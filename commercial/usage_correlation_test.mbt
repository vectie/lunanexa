///|
fn correlation_manifest() -> @commercial.UsageCorrelationManifest {
  {
    schema_version: "lunanexa.usage-correlation-manifest.v1",
    organization_id: "org-a",
    links: [
      {
        external_ref: "invoice:2026-10",
        project_id: "project-a",
        event_id: "usage-one",
      },
      {
        external_ref: "invoice:2026-10",
        project_id: "project-a",
        event_id: "usage-unpriced",
      },
      {
        external_ref: "task:awaited",
        project_id: "project-a",
        event_id: "usage-pending",
      },
    ],
  }
}

///|
test "correlation groups many events with credits and unresolved evidence without mutation" {
  let source = report_snapshot()
  let before = source.to_json().stringify()
  let manifest = correlation_manifest()
  let report = @commercial.correlate_usage(source, report_query(), manifest)
  assert_eq(report.references.length(), 2)
  let invoice = report.references[0]
  assert_eq(invoice.external_ref, "invoice:2026-10")
  assert_eq(invoice.report.rows.length(), 3)
  assert_eq(invoice.report.groups.length(), 2)
  assert_eq(
    invoice.report.groups.filter(g => g.amount is Some(_))[0].amount,
    Some(@commercial.money(4L, "CNY", 2)),
  )
  assert_eq(invoice.links[0].source_row_ids, [
    "ledger:charge-one", "ledger:credit-one",
  ])
  assert_eq(report.references[1].links[0].status, "not_observed_in_selection")
  assert_eq(report.references[1].report.rows.length(), 0)
  assert_eq(report.references[1].report.groups.length(), 0)
  assert_eq(report.unassigned.rows.length(), 0)
  assert_eq(before, source.to_json().stringify())
  assert_true(report.json_text().contains("\"amount\": null"))
  assert_true(
    report
    .rows_csv()
    .contains("assigned,\"invoice:2026-10\",\"project-a\",\"usage-one\""),
  )
  assert_true(
    report.rows_csv().contains("not_observed_in_selection,\"task:awaited\""),
  )
  assert_false(report.json_text().contains("dgx-1"))
}

///|
test "correlation preserves unmatched rows and follows out of window original charge" {
  let source = report_snapshot()
  let manifest = {
    ..correlation_manifest(),
    links: [correlation_manifest().links[0]],
  }
  let report = @commercial.correlate_usage(source, report_query(), manifest)
  assert_eq(report.unassigned.rows.length(), 1)
  assert_eq(report.unassigned.rows[0].kind, "unpriced_usage")
  let credit = @commercial.correlate_usage(
    source,
    { ..report_query(), started_unix_ms: 4100L, ended_unix_ms: 4101L, },
    manifest,
  )
  assert_eq(credit.references[0].report.rows.length(), 1)
  assert_eq(credit.references[0].report.rows[0].kind, "credit")
  assert_eq(credit.references[0].links[0].source_row_ids, ["ledger:credit-one"])
  let empty = @commercial.correlate_usage(
    source,
    { ..report_query(), meter: "unobserved", },
    manifest,
  )
  assert_eq(empty.references[0].links[0].status, "not_observed_in_selection")
  assert_eq(empty.references[0].report.groups.length(), 0)
  let redacted = @commercial.correlate_usage(
    { ..source, usage_observations: [], },
    report_query(),
    manifest,
  )
  assert_eq(
    redacted.references[0].report.groups[0].missing_observation_count,
    1,
  )
  assert_eq(
    redacted.references[0].report.groups[0].amount,
    Some(@commercial.money(4L, "CNY", 2)),
  )
}

///|
test "replayed identical links deduplicate and reordered input is deterministic" {
  let source = report_snapshot()
  let manifest = correlation_manifest()
  let replay = { ..manifest, links: manifest.links + [manifest.links[0]], }
  let report = @commercial.correlate_usage(source, report_query(), replay)
  assert_eq(report.duplicate_link_count, 1)
  assert_eq(report.references[0].report.rows.length(), 3)
  let reordered = @commercial.correlate_usage(
    {
      ..source,
      usage_observations: source.usage_observations.rev(),
      ledger_entries: source.ledger_entries.rev(),
    },
    report_query(),
    { ..replay, links: replay.links.rev(), },
  )
  assert_eq(reordered, report)
  assert_eq(reordered.json_text(), report.json_text())
  assert_eq(reordered.rows_csv(), report.rows_csv())
}

///|
test "correlation keeps currencies scales meters and genuine zero separate" {
  let source = report_snapshot()
  let charge = source.ledger_entries[0]
  let extra = [
    {
      ..charge,
      entry_id: "zero",
      source_event_id: "zero",
      amount: @commercial.money(0L, "CNY", 2),
    },
    {
      ..charge,
      entry_id: "usd",
      source_event_id: "usd",
      amount: @commercial.money(5L, "USD", 2),
    },
    {
      ..charge,
      entry_id: "scale",
      source_event_id: "scale",
      amount: @commercial.money(5L, "CNY", 3),
    },
    {
      ..charge,
      entry_id: "meter",
      source_event_id: "meter",
      meter: "different",
    },
  ]
  let manifest = correlation_manifest()
  let report = @commercial.correlate_usage(
    { ..source, ledger_entries: source.ledger_entries + extra, },
    report_query(),
    {
      ..manifest,
      links: manifest.links +
      extra.map(e => {
        external_ref: "invoice:2026-10",
        project_id: e.project_id,
        event_id: e.source_event_id,
      }),
    },
  )
  assert_eq(report.references[0].report.groups.length(), 5)
  assert_true(report.rows_csv().contains(",3,0,\"CNY\",2,"))
  assert_true(report.summary_csv().contains("\"USD\",2,"))
  assert_true(report.summary_csv().contains("\"CNY\",3,"))
}

///|
test "correlation rejects ambiguous project organization and manifest authority fields" {
  let source = report_snapshot()
  let manifest = correlation_manifest()
  for
    invalid in [
      { ..manifest, organization_id: "org-other", },
      { ..manifest, schema_version: "future", },
      {
        ..manifest,
        links: manifest.links +
        [{ ..manifest.links[0], external_ref: "conflict", }],
      },
      { ..manifest, links: [{ ..manifest.links[0], project_id: "missing", }], },
      {
        ..manifest,
        links: [
          {
            ..manifest.links[0],
            event_id: source.ledger_entries[1].source_event_id,
          },
        ],
      },
      { ..manifest, links: [{ ..manifest.links[0], external_ref: "", }], },
    ] {
    try @commercial.correlate_usage(source, report_query(), invalid) catch {
      InvalidInput(_) => ()
      _ => fail("unexpected commercial error")
    } noraise {
      _ => fail("expected invalid manifest")
    }
  }
  assert_eq(
    @commercial.import_usage_correlation_manifest(
      manifest.to_json().stringify(),
    ),
    manifest,
  )
  let json = manifest.to_json()
  if json is Object(fields) {
    fields["placement_authority"] = "node-admin"
  }
  try @commercial.import_usage_correlation_manifest(json.stringify()) catch {
    InvalidInput(_) => ()
    _ => fail("unexpected commercial error")
  } noraise {
    _ => fail("unexpected field accepted")
  }
}

///|
test "correlation requires matching project and never reads other tenant evidence" {
  let source = report_snapshot()
  let extra_project = { ..source.projects[0], project_id: "project-b", }
  let link = { ..correlation_manifest().links[0], project_id: "project-b", }
  try
    @commercial.correlate_usage(
      { ..source, projects: source.projects + [extra_project], },
      report_query(),
      { ..correlation_manifest(), links: [link], },
    )
  catch {
    InvalidInput(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("cross-project association accepted")
  }
  let private = {
    ..source.usage_observations[0],
    organization_id: "org-private",
    project_id: "private-project",
    event_id: "private-event",
    workload_id: "private-workload",
  }
  let manifest = {
    ..correlation_manifest(),
    links: [
      {
        ..correlation_manifest().links[0],
        event_id: "private-event",
        external_ref: "@pending",
      },
    ],
  }
  let report = @commercial.correlate_usage(
    { ..source, usage_observations: source.usage_observations + [private], },
    report_query(),
    manifest,
  )
  assert_eq(report.references[0].links[0].status, "not_observed_in_selection")
  assert_eq(report.unassigned.rows.length(), 3)
  assert_false(report.json_text().contains("private-workload"))
  assert_true(report.rows_csv().contains("\"'@pending\""))
}
