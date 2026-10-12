///|
async test "combine actual capture files exports once with traceable provenance and atomic failures" {
  let fixtures = @env.get_env_var("USAGE_REPORT_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("USAGE_REPORT_EVIDENCE").unwrap_or("")
  guard fixtures != "" && evidence != "" else {
    fail("fixture and evidence directories required")
  }
  let observations = fixtures + "/usage-capture-observations.synthetic.json"
  let ledger = fixtures + "/usage-capture-ledger.synthetic.json"
  let full = fixtures + "/usage-snapshot.synthetic.json"
  let query = fixtures + "/usage-query.synthetic.json"
  let originals = [
    @fs.read_file(observations).text(),
    @fs.read_file(ledger).text(),
  ]
  let args = ["combine-json", query, observations, ledger, ledger]
  let (code, output, error) = invoke(args)
  assert_eq(code, 0)
  assert_eq(error, "")
  guard @json.parse(output)
    is {
      "schema_version": "lunanexa.usage-consolidation.v1",
      "unique_usage_count": 3,
      "unique_ledger_count": 4,
      "duplicate_usage_count": 0,
      "duplicate_ledger_count": 4,
      "sources": Array(sources),
      "row_sources": Array(provenance),
      "report": { "rows": Array(rows), "groups": Array(groups), .. },
      ..
    } else {
    fail("consolidation shape and counts")
  }
  assert_eq(sources.length(), 3)
  assert_eq(rows.length(), 5)
  assert_eq(groups.length(), 3)
  guard provenance[0]
    is {
      "event_id": "usage-one",
      "observation_sources": [1],
      "ledger_sources": [2, 3],
      ..
    } else {
    fail("split-source provenance")
  }
  save(evidence + "/combine.json", output)
  let (repeat_code, repeated, _) = invoke(args)
  assert_eq(repeat_code, 0)
  assert_eq(repeated, output)
  let (summary_code, summary, _) = invoke([
    "combine-summary", query, observations, ledger, ledger,
  ])
  let (original_code, original_summary, _) = invoke(["summary", full, query])
  assert_eq(summary_code, 0)
  assert_eq(original_code, 0)
  assert_eq(summary, original_summary)
  save(evidence + "/combine-summary.csv", summary)
  let (csv_code, csv, _) = invoke([
    "combine-rows", query, observations, ledger, ledger,
  ])
  assert_eq(csv_code, 0)
  assert_eq(csv.split("\n").count(), 7)
  assert_true(csv.contains("\"[2,3]\""))
  save(evidence + "/combine-rows.csv", csv)
  let conflict = evidence + "/combine-conflict.json"
  save(
    conflict,
    originals[1].replace_all(
      old="\"minor_units\":\"12000\"",
      new="\"minor_units\":\"13000\"",
    ),
  )
  let invalid = evidence + "/combine-invalid.json"
  save(invalid, "{")
  let wrong_org = evidence + "/combine-wrong-org-query.json"
  save(
    wrong_org,
    @fs.read_file(query).text().replace_all(old="org-example", new="absent-org"),
  )
  let too_many = ["combine-json", query]
  for index = 0; index < 9; index = index + 1 {
    too_many.push(ledger)
  }
  for
    index, rejected in [
      ["combine-json", query, ledger, conflict],
      ["combine-summary", query, observations, invalid],
      ["combine-rows", invalid, observations],
      ["combine-json", wrong_org, ledger],
      ["combine-json", query],
      ["combine-json", query, evidence + "/missing-capture.json"],
      too_many,
    ] {
    let (status, out, err) = invoke(rejected)
    assert_true(status != 0)
    assert_eq(out, "")
    assert_true(err.contains("lunanexa-usage-report:"))
    save(evidence + "/combine-rejection-\{index + 1}.txt", err)
  }
  assert_eq(@fs.read_file(observations).text(), originals[0])
  assert_eq(@fs.read_file(ledger).text(), originals[1])
  assert_false(output.contains("synthetic-node"))
  assert_false(output.contains("synthetic-actor"))
  assert_false(output.contains(fixtures))
}
