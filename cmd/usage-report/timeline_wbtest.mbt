///|
async test "timeline file workflow exports daily rows and drilldown with honest empty buckets" {
  let fixtures = @env.get_env_var("USAGE_REPORT_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("USAGE_REPORT_EVIDENCE").unwrap_or("")
  guard fixtures != "" && evidence != "" else {
    fail("fixture and evidence directories required")
  }
  let snapshot = fixtures + "/usage-snapshot.synthetic.json"
  let query = fixtures + "/usage-query.synthetic.json"
  let original = @fs.read_file(snapshot).text()
  let (code, output, error) = invoke([
    "timeline-json", snapshot, query, "86400000",
  ])
  assert_eq(code, 0)
  assert_eq(error, "")
  guard @json.parse(output)
    is {
      "schema_version": "lunanexa.usage-timeline.v1",
      "buckets": Array(buckets),
      ..
    } else {
    fail("timeline JSON")
  }
  assert_eq(buckets.length(), 7)
  guard buckets[0]
    is {
      "crossing_bucket_count": 1,
      "report": { "rows": [{ "entry_id": "charge-one", .. }], .. },
      ..
    } else {
    fail("prewindow charge assigned once")
  }
  guard buckets[1] is { "report": { "rows": Array(rows), .. }, .. } else {
    fail("daily rows")
  }
  assert_eq(rows.length(), 2)
  guard buckets[2]
    is {
      "report": { "groups": [{ "amount": Null, "quantity": "300", .. }], .. },
      ..
    } else {
    fail("unknown cost")
  }
  guard buckets[3]
    is {
      "report": {
        "groups": [{ "amount": { "minor_units": "-2000", .. }, .. }],
        ..
      },
      ..
    } else {
    fail("credit by service interval")
  }
  guard buckets[6] is { "report": { "rows": [], "groups": [], .. }, .. } else {
    fail("empty day")
  }
  let (csv_code, csv, csv_error) = invoke([
    "timeline-summary", snapshot, query, "86400000",
  ])
  assert_eq(csv_code, 0)
  assert_eq(csv_error, "")
  assert_eq(csv.split("\n").count(), 10)
  assert_true(csv.contains(",50,0,\"CNY\",2,"))
  assert_true(csv.contains(",300,,,,1,0,1,0,0"))
  assert_false(output.contains("synthetic-node"))
  assert_false(output.contains("synthetic-actor"))
  let (repeat_code, repeat_output, _) = invoke([
    "timeline-json", snapshot, query, "86400000",
  ])
  assert_eq(repeat_code, 0)
  assert_eq(repeat_output, output)
  save(evidence + "/timeline.json", output)
  save(evidence + "/timeline.csv", csv)
  for
    index, args in [
      ["timeline-json", snapshot, query, "0"],
      ["timeline-summary", snapshot, query, "1"],
      ["timeline-json", snapshot, query, "nope"],
      ["timeline-json", snapshot, query],
      ["timeline-json", snapshot + ".absent", query, "86400000"],
    ] {
    let (status, out, err) = invoke(args)
    assert_true(status != 0)
    assert_eq(out, "")
    assert_true(err.contains("lunanexa-usage-report:"))
    save(evidence + "/timeline-rejection-\{index}.txt", err)
  }
  assert_eq(@fs.read_file(snapshot).text(), original)
}
