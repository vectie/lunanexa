///|
async fn sweep_invoke(args : Array[String]) -> (Int, String, String) {
  let exe = @env.get_env_var("SWEEP_EXE").unwrap_or("")
  if exe == "" {
    fail("Set SWEEP_EXE to the built native capacity-plan executable")
  }
  let (code, out, err) = @process.collect_output(exe, args)
  (code, out.text(), err.text())
}

///|
async fn sweep_save(path : String, data : &@io.Data) -> Unit {
  @fs.write_file(path, data, create_mode=CreateOrTruncate)
}

///|
async test "actual saved packet sweep exposes failed incomplete missing and unplanned repeats" {
  let fixtures = @env.get_env_var("SWEEP_FIXTURES").unwrap_or("")
  let evidence_dir = @env.get_env_var("SWEEP_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence_dir == "" {
    fail("Set SWEEP_FIXTURES and SWEEP_EVIDENCE")
  }
  let input = fixtures + "/benchmark-sweep-input.synthetic.json"
  let plan_path = fixtures + "/benchmark-sweep-plan.v1.json"
  let input_before = @fs.read_file(input).text()
  let plan_before = @fs.read_file(plan_path).text()
  let (code, saved, err) = sweep_invoke(["prepare", input])
  assert_eq(code, 0)
  assert_eq(err, "")
  let packet_path = evidence_dir + "/sweep-packet.json"
  sweep_save(packet_path, saved)
  let packet = @planning.reopen(saved)
  let plan = @planning.import_sweep_plan(plan_before)
  let report = @planning.explore_sweep(packet, plan)
  assert_eq(report.groups.map(g => g.coverage), [
    "incomplete", "complete", "unplanned", "missing",
  ])
  assert_eq(report.groups[1].failed_count, 1)
  assert_eq(report.groups[1].objective_met_runs, 1)
  let (sweep_code, output, sweep_error) = sweep_invoke([
    "sweep", packet_path, plan_path,
  ])
  assert_eq(sweep_code, 0)
  assert_eq(sweep_error, "")
  assert_eq(@json.parse(output), ToJson::to_json(report))
  sweep_save(evidence_dir + "/sweep-report.json", output)
  let (csv_code, csv, csv_error) = sweep_invoke([
    "sweep-csv", packet_path, plan_path,
  ])
  assert_eq(csv_code, 0)
  assert_eq(csv_error, "")
  assert_eq(csv, @planning.sweep_csv(packet, plan))
  sweep_save(evidence_dir + "/sweep.csv", csv)
  let (samples_code, samples, samples_error) = sweep_invoke([
    "samples", packet_path, "synthetic-repeat-b", "failed", "queue",
  ])
  assert_eq(samples_code, 0)
  assert_eq(samples_error, "")
  assert_eq(@planning.preview_csv(samples).sample_count, 1)
  assert_true(samples.contains(",1,90,30,0,4,100,100,500,true\r\n"))
  sweep_save(evidence_dir + "/sweep-failed-samples.csv", samples)
  // Parse the actual CSV back as a table; missing metrics must be empty cells.
  let table = @planning.preview_csv(csv)
  assert_eq(table.headers.length(), 40)
  assert_eq(table.sample_count, 4)
  assert_eq(table.first_rows[1][18], "complete")
  assert_eq(table.first_rows[1][19], "1")
  assert_eq(table.first_rows[1][22], "1")
  assert_eq(table.first_rows[3][18], "missing")
  for i in 23..<37 {
    assert_eq(table.first_rows[3][i], "")
  }
  assert_eq(
    @json.parse(table.first_rows[1][37]),
    (["synthetic-repeat-a", "synthetic-repeat-b"] : Json),
  )
  for command in ["sweep", "sweep-csv"] {
    let (again_code, again, again_err) = sweep_invoke([
      command, packet_path, plan_path,
    ])
    assert_eq(again_code, 0)
    assert_eq(again_err, "")
    assert_eq(again, if command == "sweep" { output } else { csv })
  }
  let (direct_code, direct, direct_err) = sweep_invoke(["sweep", packet_path])
  assert_eq(direct_code, 0)
  assert_eq(direct_err, "")
  let direct_report = @planning.explore_sweep(packet, {
    schema_version: 1,
    targets: [],
  })
  assert_eq(@json.parse(direct), ToJson::to_json(direct_report))
  assert_eq(direct_report.groups.length(), 3)
  assert_true(direct_report.groups.iter().all(g => g.coverage == "unspecified"))
  sweep_save(evidence_dir + "/observed-only.json", direct)
  let (direct_csv_code, direct_csv, _) = sweep_invoke(["sweep-csv", packet_path])
  assert_eq(direct_csv_code, 0)
  assert_eq(@planning.preview_csv(direct_csv).sample_count, 3)
  sweep_save(evidence_dir + "/observed-only.csv", direct_csv)
  let changed_packet = evidence_dir + "/changed-packet.json"
  sweep_save(changed_packet, saved.replace(old=packet.packet_id, new="changed"))
  let bad_plan = evidence_dir + "/bad-plan.json"
  sweep_save(bad_plan, "{\"schema_version\":1,\"targets\":[],\"unknown\":true}")
  let bad_utf8 = evidence_dir + "/invalid-plan.json"
  sweep_save(bad_utf8, b"\xff")
  let missing = evidence_dir + "/absent.json"
  let cases = [
    ["sweep", changed_packet],
    ["sweep-csv", changed_packet],
    ["sweep", packet_path, bad_plan],
    ["sweep-csv", packet_path, bad_plan],
    ["sweep", packet_path, bad_utf8],
    ["sweep", packet_path, missing],
    ["sweep", missing],
    ["sweep"],
    ["sweep-csv"],
    ["sweep", packet_path, plan_path, "extra"],
    ["sweep-csv", packet_path, plan_path, "extra"],
  ]
  for args in cases {
    let (bad_code, out, error) = sweep_invoke(args)
    assert_true(bad_code != 0)
    assert_eq(out, "")
    assert_true(error.length() > 0)
  }
  assert_eq(@fs.read_file(input).text(), input_before)
  assert_eq(@fs.read_file(plan_path).text(), plan_before)
  assert_eq(@fs.read_file(packet_path).text(), saved)
  sweep_save(
    evidence_dir + "/SWEEP_WORKFLOW.json",
    (
      {
        "synthetic_only": true,
        "groups": 4,
        "coverage": ["incomplete", "complete", "unplanned", "missing"],
        "failed_repeats_retained": true,
        "missing_metrics_empty_in_csv": true,
        "optional_plan_supported": true,
        "byte_deterministic": true,
        "input_files_unchanged": true,
        "negative_commands_checked": 11,
      } : Json).stringify(indent=2),
  )
}
