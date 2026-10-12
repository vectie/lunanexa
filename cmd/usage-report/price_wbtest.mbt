///|
async fn invoke(args : Array[String]) -> (Int, String, String) {
  let executable = @env.get_env_var("USAGE_REPORT_EXE").unwrap_or("")
  if executable == "" {
    fail("Set USAGE_REPORT_EXE to the built native usage-report executable")
  }
  let (code, out, err) = @process.collect_output(executable, args)
  (code, out.text(), err.text())
}

///|
async fn save(path : String, data : &@io.Data) -> Unit {
  @fs.write_file(path, data, create_mode=CreateOrTruncate)
}

///|
async test "actual usage price files support edit reopen allocation and atomic failures" {
  let fixtures = @env.get_env_var("USAGE_REPORT_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("USAGE_REPORT_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence == "" {
    fail("Set USAGE_REPORT_FIXTURES and USAGE_REPORT_EVIDENCE")
  }
  let snapshot = fixtures + "/usage-snapshot.synthetic.json"
  let query = fixtures + "/usage-query.synthetic.json"
  let scenario = fixtures + "/usage-price-scenario.synthetic.json"
  let originals = [
    @fs.read_file(snapshot).text(),
    @fs.read_file(query).text(),
    @fs.read_file(scenario).text(),
  ]
  for
    mode in [
      "summary", "rows", "json", "price-summary", "price-rows", "price-json",
    ] {
    let args = [mode, snapshot, query]
    if mode.has_prefix("price-") {
      args.push(scenario)
    }
    let (code, output, error) = invoke(args)
    assert_eq(code, 0)
    assert_eq(error, "")
    let suffix = if mode.has_suffix("json") { ".json" } else { ".csv" }
    let path = evidence + "/" + mode + suffix
    save(path, output)
    assert_eq(@fs.read_file(path).text(), output)
    let (repeat_code, repeated, _) = invoke(args)
    assert_eq(repeat_code, 0)
    assert_eq(repeated, output)
    if mode == "price-json" {
      guard @json.parse(output)
        is {
          "analysis_mode": "hypothetical-not-ledger",
          "rows": Array(rows),
          "groups": Array(groups),
          ..
        } else {
        fail("price report shape")
      }
      assert_eq(rows.length(), 5)
      assert_eq(groups.length(), 5)
      guard rows[0]
        is {
          "status": "Compared",
          "hypothetical_amount": { "minor_units": "2400", .. },
          "delta": { "minor_units": "-9600", .. },
          ..
        } else {
        fail("first charge comparison")
      }
      guard rows[1]
        is {
          "status": "Compared",
          "hypothetical_amount": { "minor_units": "4000", .. },
          "delta": { "minor_units": "-2000", .. },
          ..
        } else {
        fail("second charge comparison")
      }
      guard rows[2]
        is {
          "status": "MissingObservation",
          "hypothetical_amount": Null,
          "delta": Null,
          ..
        } else {
        fail("missing observation must not be estimated")
      }
      guard rows[3]
        is {
          "status": "EstimatedUnpriced",
          "hypothetical_amount": { "minor_units": "6000", .. },
          "delta": Null,
          ..
        } else {
        fail("unpriced estimate")
      }
      guard rows[4]
        is {
          "status": "RecordedAdjustment",
          "recorded": { "amount": { "minor_units": "-2000", .. }, .. },
          "hypothetical_amount": Null,
          ..
        } else {
        fail("credit preserved")
      }
      assert_false(output.contains("synthetic-node"))
      assert_false(output.contains("synthetic-actor"))
    }
  }
  let edited = evidence + "/edited-scenario.json"
  save(
    edited,
    originals[2].replace_all(
      old="\"minor_units\": \"20\"",
      new="\"minor_units\": \"30\"",
    ),
  )
  let (edit_code, changed, _) = invoke(["price-json", snapshot, query, edited])
  assert_eq(edit_code, 0)
  guard @json.parse(changed) is { "rows": Array(changed_rows), .. } else {
    fail("edited report")
  }
  guard changed_rows[0]
    is {
      "hypothetical_amount": { "minor_units": "3600", .. },
      "delta": { "minor_units": "-8400", .. },
      "recorded": { "amount": { "minor_units": "12000", .. }, .. },
      ..
    } else {
    fail("edit changes only hypothetical amount")
  }
  save(evidence + "/edited-report.json", changed)
  let (_, reopened, _) = invoke(["price-json", snapshot, query, edited])
  assert_eq(reopened, changed)
  let filtered_query = evidence + "/filtered-query.json"
  save(
    filtered_query,
    originals[1].replace_all(
      old="\"project_id\": \"\"",
      new="\"project_id\": \"project-inference\"",
    ),
  )
  let (filtered_code, filtered, _) = invoke([
    "price-json", snapshot, filtered_query, scenario,
  ])
  assert_eq(filtered_code, 0)
  guard @json.parse(filtered) is { "rows": Array(filtered_rows), .. } else {
    fail("filtered report")
  }
  assert_eq(filtered_rows.length(), 3)
  assert_false(filtered.contains("workload-two"))
  save(evidence + "/filtered-report.json", filtered)
  let empty_query = evidence + "/empty-query.json"
  save(
    empty_query,
    originals[1].replace_all(old="\"meter\": \"\"", new="\"meter\": \"absent\""),
  )
  let (empty_code, empty, _) = invoke([
    "price-summary", snapshot, empty_query, scenario,
  ])
  assert_eq(empty_code, 0)
  assert_eq(empty.split("\n").count(), 2)
  save(evidence + "/empty.csv", empty)
  let malformed = evidence + "/malformed.json"
  save(malformed, "{")
  let unknown = evidence + "/unknown-scenario.json"
  save(
    unknown,
    originals[2].replace_all(
      old="\"meter\":",
      new="\"extra\": true, \"meter\":",
    ),
  )
  let invalid_utf8 = evidence + "/invalid-utf8.json"
  save(invalid_utf8, b"\xff")
  let overflow = evidence + "/overflow.json"
  save(
    overflow,
    originals[2].replace_all(
      old="\"minor_units\": \"20\"",
      new="\"minor_units\": \"9223372036854775807\"",
    ),
  )
  let cases = [
    ["price-json", snapshot, query],
    ["json", snapshot, query, scenario],
    ["price-json", snapshot, query, malformed],
    ["price-json", malformed, query, scenario],
    ["price-json", snapshot, malformed, scenario],
    ["price-json", snapshot, query, unknown],
    ["price-json", snapshot, query, invalid_utf8],
    ["price-json", snapshot, query, overflow],
    ["price-json", snapshot, query, evidence + "/does-not-exist.json"],
  ]
  for i, args in cases {
    let (code, output, error) = invoke(args)
    assert_true(code != 0)
    assert_eq(output, "")
    assert_true(error.contains("lunanexa-usage-report:"))
    save(evidence + "/invalid-" + i.to_string() + ".stderr", error)
  }
  assert_eq(@fs.read_file(snapshot).text(), originals[0])
  assert_eq(@fs.read_file(query).text(), originals[1])
  assert_eq(@fs.read_file(scenario).text(), originals[2])
  save(
    evidence + "/CLI_WORKFLOW.json",
    (
      {
        "passed": true,
        "synthetic_only": true,
        "existing_and_new_modes": 6,
        "repeated_byte_identical": true,
        "candidate_file_edited_and_reopened": true,
        "recorded_charges_unchanged": true,
        "invalid_cases": 9,
        "failure_stdout_empty": true,
        "sources_unchanged": true,
        "live_fetch": false,
        "ledger_mutation": false,
      } : Json).stringify(indent=2),
  )
}
