///|
async test "saved snapshot changes compare repeat export and fail without partial output" {
  let fixtures = @env.get_env_var("USAGE_REPORT_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("USAGE_REPORT_EVIDENCE").unwrap_or("")
  guard fixtures != "" && evidence != "" else {
    fail("fixture and evidence directories required")
  }
  let snapshot = fixtures + "/usage-snapshot.synthetic.json"
  let query = fixtures + "/usage-query.synthetic.json"
  let original = @fs.read_file(snapshot).text()
  let candidate = evidence + "/changes-candidate.json"
  save(
    candidate,
    original.replace_all(
      old="\"minor_units\":\"12000\"",
      new="\"minor_units\":\"13000\"",
    ),
  )
  let (code, output, error) = invoke([
    "changes-json", snapshot, candidate, query,
  ])
  assert_eq(code, 0)
  assert_eq(error, "")
  guard @json.parse(output)
    is {
      "schema_version": "lunanexa.usage-changes.v1",
      "unchanged_count": 4,
      "changes": Array(changes),
      ..
    } else {
    fail("change shape")
  }
  assert_eq(changes.length(), 1)
  guard changes[0]
    is {
      "status": "changed",
      "identity": "usage-one",
      "before": { "amount": { "minor_units": "12000", .. }, .. },
      "after": { "amount": { "minor_units": "13000", .. }, .. },
      ..
    } else {
    fail("exact before and after")
  }
  save(evidence + "/changes.json", output)
  let (repeat_code, repeated, _) = invoke([
    "changes-json", snapshot, candidate, query,
  ])
  assert_eq(repeat_code, 0)
  assert_eq(repeated, output)
  let (csv_code, csv, _) = invoke(["changes-rows", snapshot, candidate, query])
  assert_eq(csv_code, 0)
  assert_eq(csv.split("\n").count(), 4)
  assert_true(csv.contains("13000"))
  save(evidence + "/changes.csv", csv)
  let malformed = evidence + "/changes-invalid.json"
  save(malformed, "{")
  for
    args in [
      ["changes-json", malformed, candidate, query],
      ["changes-rows", snapshot, malformed, query],
      ["changes-json", snapshot, candidate, malformed],
      ["changes-json", snapshot, candidate],
      ["changes-json", snapshot, candidate, query, "extra"],
    ] {
    let (code, out, err) = invoke(args)
    assert_true(code != 0)
    assert_eq(out, "")
    assert_true(err.contains("lunanexa-usage-report:"))
  }
  assert_eq(@fs.read_file(snapshot).text(), original)
  assert_false(output.contains("synthetic-node"))
  assert_false(output.contains("synthetic-actor"))
}
