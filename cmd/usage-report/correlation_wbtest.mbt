///|
async test "correlation CLI imports edits reopens and exports traceable costs without partial output" {
  let fixtures = @env.get_env_var("USAGE_REPORT_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("USAGE_REPORT_EVIDENCE").unwrap_or("")
  guard fixtures != "" && evidence != "" else {
    fail("fixture and evidence directories required")
  }
  let snapshot = fixtures + "/usage-snapshot.synthetic.json"
  let query = fixtures + "/usage-query.synthetic.json"
  let links = fixtures + "/usage-correlation.synthetic.json"
  let originals = [
    @fs.read_file(snapshot).text(),
    @fs.read_file(query).text(),
    @fs.read_file(links).text(),
  ]
  let (code, output, error) = invoke(["correlate-json", snapshot, query, links])
  assert_eq(code, 0)
  assert_eq(error, "")
  guard @json.parse(output)
    is {
      "schema_version": "lunanexa.usage-correlation-report.v1",
      "duplicate_link_count": 1,
      "references": Array(references),
      "unassigned": {
        "rows": [
          {
            "entry_id": "charge-zero",
            "amount": { "minor_units": "0", .. },
            ..
          },
        ],
        ..
      },
      ..
    } else {
    fail("correlation report shape")
  }
  assert_eq(references.length(), 3)
  guard references[0]
    is {
      "external_ref": "invoice:2026-10-research",
      "report": { "rows": Array(rows), "groups": Array(groups), .. },
      ..
    } else {
    fail("many-event reference")
  }
  assert_eq(rows.length(), 3)
  assert_eq(groups.length(), 2)
  guard references[1]
    is {
      "report": { "groups": [{ "amount": Null, "quantity": "300", .. }], .. },
      ..
    } else {
    fail("unpriced evidence")
  }
  guard references[2]
    is {
      "links": [{ "status": "not_observed_in_selection", "row_count": 0, .. }],
      "report": { "rows": [], "groups": [], .. },
      ..
    } else {
    fail("missing evidence must not become zero")
  }
  save(evidence + "/correlate.json", output)
  for mode in ["correlate-rows", "correlate-summary"] {
    let (status, csv, err) = invoke([mode, snapshot, query, links])
    assert_eq(status, 0)
    assert_eq(err, "")
    assert_true(csv.contains("not_observed_in_selection,\"task:eval-43\""))
    assert_true(csv.contains("unassigned,"))
    assert_true(csv.contains(",0,\"CNY\",2,"))
    let columns = if mode == "correlate-rows" { 30 } else { 19 }
    for line in csv.split("\n") {
      if line != "" {
        assert_eq(line.split(",").count(), columns)
      }
    }
    if mode == "correlate-rows" {
      assert_true(
        csv.contains(
          "assigned,\"invoice:2026-10-research\",\"project-inference\",\"usage-one\"",
        ),
      )
      assert_true(csv.contains("\"adjustment:credit-one\""))
      assert_true(csv.contains("\"charge-one\""))
    }
    save(evidence + "/" + mode + ".csv", csv)
  }
  let manifest = @commercial.import_usage_correlation_manifest(originals[2])
  let edited = {
    ..manifest,
    links: manifest.links +
    [
      {
        external_ref: "invoice:free-trial",
        project_id: "project-inference",
        event_id: "usage-zero-not-in-export",
      },
    ],
  }
  let edited_path = evidence + "/correlation-edited.json"
  save(edited_path, edited.to_json().stringify())
  let (edited_code, edited_output, _) = invoke([
    "correlate-json", snapshot, query, edited_path,
  ])
  assert_eq(edited_code, 0)
  guard @json.parse(edited_output) is { "unassigned": { "rows": [], .. }, .. } else {
    fail("edited manifest must pick up zero charge")
  }
  let (repeat_code, repeated, _) = invoke([
    "correlate-json", snapshot, query, edited_path,
  ])
  assert_eq(repeat_code, 0)
  assert_eq(repeated, edited_output)
  save(evidence + "/correlate-edited.json", edited_output)
  let conflict = {
    ..manifest,
    links: manifest.links +
    [{ ..manifest.links[0], external_ref: "another-invoice", }],
  }
  let conflict_path = evidence + "/correlation-conflict.json"
  save(conflict_path, conflict.to_json().stringify())
  let unsupported_path = evidence + "/correlation-unsupported.json"
  let unsupported = manifest.to_json()
  if unsupported is Object(fields) {
    fields["placement_authority"] = "operator"
  }
  save(unsupported_path, unsupported.stringify())
  for
    index, args in [
      ["correlate-json", snapshot, query, conflict_path],
      ["correlate-rows", snapshot, query, unsupported_path],
      ["correlate-summary", snapshot, query, links + ".missing"],
      ["correlate-json", snapshot, query],
    ] {
    let (status, out, err) = invoke(args)
    assert_true(status != 0)
    assert_eq(out, "")
    assert_true(err.contains("lunanexa-usage-report:"))
    save(evidence + "/correlation-rejected-\{index}.txt", err)
  }
  assert_false(output.contains("synthetic-node"))
  assert_false(output.contains("synthetic-actor"))
  assert_false(output.contains("legal_profile"))
  assert_eq(@fs.read_file(snapshot).text(), originals[0])
  assert_eq(@fs.read_file(query).text(), originals[1])
  assert_eq(@fs.read_file(links).text(), originals[2])
}
