///|
async fn invoke(args : Array[String]) -> (Int, String, String) {
  let executable = @env.get_env_var("DEPLOYMENT_REPORT_EXE").unwrap_or("")
  if executable == "" {
    fail(
      "Set DEPLOYMENT_REPORT_EXE to the built native deployment-report executable",
    )
  }
  let (code, out, err) = @process.collect_output(executable, args)
  (code, out.text(), err.text())
}

///|
async test "actual native saved-file workflow exports filters deterministic results and atomic failures" {
  let fixtures = @env.get_env_var("DEPLOYMENT_REPORT_FIXTURES").unwrap_or("")
  let evidence = @env.get_env_var("DEPLOYMENT_REPORT_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence == "" {
    fail("Set DEPLOYMENT_REPORT_FIXTURES and DEPLOYMENT_REPORT_EVIDENCE")
  }
  let operations = fixtures + "/deployment-operations.synthetic.json"
  let nodes = fixtures + "/deployment-nodes.synthetic.json"
  let query = fixtures + "/deployment-query.synthetic.json"
  let originals = [
    @fs.read_file(operations).text(),
    @fs.read_file(nodes).text(),
    @fs.read_file(query).text(),
  ]
  for mode in ["deployments", "placements", "json"] {
    let (code, output, error) = invoke([mode, operations, nodes, query])
    assert_eq(code, 0)
    assert_eq(error, "")
    let suffix = if mode == "json" { ".json" } else { ".csv" }
    let path = evidence + "/" + mode + suffix
    save(path, output)
    assert_eq(@fs.read_file(path).text(), output)
    let (_, repeated, _) = invoke([mode, operations, nodes, query])
    assert_eq(output, repeated)
    if mode == "json" {
      guard @json.parse(output)
        is { "deployments": Array(ds), "placements": Array(ps), .. } else {
        fail("report shape")
      }
      assert_eq(ds.length(), 2)
      assert_eq(ps.length(), 5)
      guard ds[0]
        is {
          "generation": "9007199254740993",
          "model_id": "synthetic-model",
          "runtime_name": "synthetic-runtime",
          "planned_replicas": 5,
          ..
        } else {
        fail("identity projection")
      }
      guard ds[1] is Object(fields) else { fail("overview object") }
      assert_false(fields.contains("model_id"))
      guard ps[0]
        is { "node_deployment_membership": "listed", "freshness": "fresh", .. } else {
        fail("threshold")
      }
      guard ps[1] is { "node_deployment_membership": "listed", .. } else {
        fail("shared node")
      }
      guard ps[2]
        is {
          "node_deployment_membership": "not-listed",
          "freshness": "stale",
          ..
        } else {
        fail("stale absence")
      }
      guard ps[3] is { "freshness": "future", .. } else { fail("future") }
      guard ps[4] is Object(missing) else { fail("missing node") }
      assert_false(missing.contains("observed_node_state"))
      assert_false(missing.contains("observed_unix_ms"))
      assert_false(output.contains("excluded"))
    } else {
      assert_true(output.has_suffix("\r\n"))
    }
  }
  let selected = evidence + "/selected-query.json"
  save(
    selected,
    originals[2].replace_all(old="\"node_id\":\"\"", new="\"node_id\":\"a\""),
  )
  let (selected_code, selected_output, _) = invoke([
    "json", operations, nodes, selected,
  ])
  assert_eq(selected_code, 0)
  guard @json.parse(selected_output)
    is { "deployments": Array(ds), "placements": Array(ps), .. } else {
    fail("selected shape")
  }
  assert_eq(ds.length(), 1)
  assert_eq(ps.length(), 2)
  guard ds[0] is { "planned_replicas": 5, "selected_placements": 2, .. } else {
    fail("whole operation totals")
  }
  save(evidence + "/selected.json", selected_output)
  let empty = evidence + "/empty-query.json"
  save(
    empty,
    originals[2].replace_all(
      old="\"node_id\":\"\"",
      new="\"node_id\":\"absent\"",
    ),
  )
  let (empty_code, empty_output, _) = invoke([
    "placements", operations, nodes, empty,
  ])
  assert_eq(empty_code, 0)
  assert_eq(empty_output.split("\r\n").count(), 2)
  save(evidence + "/empty.csv", empty_output)
  let malformed = evidence + "/malformed.json"
  save(malformed, "{")
  let invalid_utf8 = evidence + "/invalid-utf8.json"
  save(invalid_utf8, b"\xff")
  let unknown = evidence + "/unknown-query.json"
  save(unknown, originals[2].replace_all(old="model_id", new="typo"))
  let duplicate = evidence + "/duplicate-nodes.json"
  save(duplicate, originals[1].replace_all(old="\"b\"", new="\"a\""))
  let cases = [
    ["apply", operations, nodes, query],
    ["json", malformed, nodes, query],
    ["json", operations, malformed, query],
    ["json", operations, nodes, malformed],
    ["json", invalid_utf8, nodes, query],
    ["json", operations, nodes, unknown],
    ["json", operations, duplicate, query],
    ["json", evidence + "/does-not-exist.json", nodes, query],
  ]
  for i, args in cases {
    let (code, output, error) = invoke(args)
    assert_true(code != 0)
    assert_eq(output, "")
    assert_true(error.contains("lunanexa-deployment-report:"))
    save(evidence + "/invalid-" + i.to_string() + ".stderr", error)
  }
  assert_eq(@fs.read_file(operations).text(), originals[0])
  assert_eq(@fs.read_file(nodes).text(), originals[1])
  assert_eq(@fs.read_file(query).text(), originals[2])
  save(
    evidence + "/CLI_WORKFLOW.json",
    (
      {
        "passed": true,
        "synthetic_only": true,
        "operations": 2,
        "placements": 5,
        "shared_node_membership_not_replica_readiness": true,
        "selected_placements": 2,
        "whole_operation_total": 5,
        "invalid_cases": 8,
        "failure_stdout_empty": true,
        "deterministic": true,
        "sources_unchanged": true,
        "live_fetch": false,
      } : Json).stringify(indent=2),
  )
}

///|
async fn save(path : String, data : &@io.Data) -> Unit {
  @fs.write_file(path, data, create_mode=CreateOrTruncate)
}
