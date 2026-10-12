///|
async fn grouped_invoke(args : Array[String]) -> (Int, String, String) {
  let executable = @env.get_env_var("CAPACITY_PLAN_EXE").unwrap_or("")
  if executable == "" {
    fail("Set CAPACITY_PLAN_EXE to the built native capacity-plan executable")
  }
  let (code, out, err) = @process.collect_output(executable, args)
  (code, out.text(), err.text())
}

///|
async fn grouped_save(path : String, data : &@io.Data) -> Unit {
  @fs.write_file(path, data, create_mode=CreateOrTruncate)
}

///|
async test "actual grouped CSV import edit prepare reopen and independent CSV summaries" {
  let fixtures = @env.get_env_var("CAPACITY_PLAN_FIXTURES").unwrap_or("")
  let evidence_dir = @env.get_env_var("CAPACITY_PLAN_EVIDENCE").unwrap_or("")
  if fixtures == "" || evidence_dir == "" {
    fail("Set CAPACITY_PLAN_FIXTURES and CAPACITY_PLAN_EVIDENCE")
  }
  let csv = fixtures + "/benchmark-grouped.synthetic.csv"
  let mapping = fixtures + "/benchmark-grouped-mapping.v1.json"
  let template = fixtures + "/benchmark-grouped-plan-template.v1.json"
  let originals = [
    @fs.read_file(csv).text(),
    @fs.read_file(mapping).text(),
    @fs.read_file(template).text(),
  ]
  let (code, imported, err) = grouped_invoke([
    "import-grouped-csv", csv, mapping,
  ])
  assert_eq(code, 0)
  assert_eq(err, "")
  grouped_save(evidence_dir + "/grouped-evidence.json", imported)
  let runs = @planning.import_evidence(
    @fs.read_file(evidence_dir + "/grouped-evidence.json").text(),
  )
  assert_eq(runs.map(e => e.run.concurrency), [4, 8])
  assert_eq(runs.map(e => e.run.samples.length()), [3, 3])
  assert_eq(runs[0].run.samples.map(s => s.latency_ms), [200, 240, 280])
  assert_eq(runs[1].run.samples.map(s => s.latency_ms), [300, 360, 420])
  let (again_code, again, _) = grouped_invoke([
    "import-grouped-csv", csv, mapping,
  ])
  assert_eq(again_code, 0)
  assert_eq(again, imported)
  let skeleton : @planning.Input = @json.from_json(@json.parse(originals[2]))
  let input = { ..skeleton, evidence: runs, }
  let input_path = evidence_dir + "/planning-input.json"
  grouped_save(input_path, ToJson::to_json(input).stringify(indent=2))
  let (prepare_code, prepared, prepare_error) = grouped_invoke([
    "prepare", input_path,
  ])
  assert_eq(prepare_code, 0)
  assert_eq(prepare_error, "")
  let packet_path = evidence_dir + "/planning-packet.json"
  grouped_save(packet_path, prepared)
  let packet = @planning.reopen(@fs.read_file(packet_path).text())
  assert_eq(packet.choices.length(), 2)
  assert_true(packet.choices[0].meets_declared_envelope)
  assert_false(packet.choices[1].meets_declared_envelope)
  let (reopen_code, reopened, reopen_error) = grouped_invoke([
    "reopen", packet_path,
  ])
  assert_eq(reopen_code, 0)
  assert_eq(reopen_error, "")
  assert_eq(reopened, prepared)
  grouped_save(evidence_dir + "/reopened-packet.json", reopened)
  let (summary_code, summary, summary_error) = grouped_invoke([
    "summary", packet_path,
  ])
  assert_eq(summary_code, 0)
  assert_eq(summary_error, "")
  assert_eq(summary, packet.summary_csv())
  grouped_save(evidence_dir + "/comparison.csv", summary)
  let (samples_code, samples, _) = grouped_invoke([
    "samples", packet_path, "synthetic-csv-concurrency-8", "failed", "latency",
  ])
  assert_eq(samples_code, 0)
  assert_eq(samples, @planning.samples_csv(runs[1], true, SlowestLatency))
  grouped_save(evidence_dir + "/failed-samples.csv", samples)
  // Editing one run never changes the other run's observations.
  let edited_csv = evidence_dir + "/edited-observations.csv"
  grouped_save(edited_csv, originals[0].replace(old=",420,", new=",390,"))
  let (edit_code, edited, _) = grouped_invoke([
    "import-grouped-csv", edited_csv, mapping,
  ])
  assert_eq(edit_code, 0)
  let changed = @planning.import_evidence(edited)
  assert_eq(changed[0], runs[0])
  assert_eq(changed[1].run.samples[2].latency_ms, 390)
  grouped_save(evidence_dir + "/edited-evidence.json", edited)
  let bad_csv = evidence_dir + "/invalid-observations.csv"
  let unknown_csv = evidence_dir + "/unknown-group.csv"
  let bad_mapping = evidence_dir + "/unused-context.json"
  let invalid_utf8 = evidence_dir + "/invalid-utf8.csv"
  grouped_save(bad_csv, originals[0].replace(old=",420,", new=",420.5,"))
  grouped_save(
    unknown_csv,
    originals[0].replace(old="synthetic-csv-concurrency-8", new="unmapped"),
  )
  grouped_save(
    bad_mapping,
    originals[1].replace(old="synthetic-csv-concurrency-8", new="unused"),
  )
  grouped_save(invalid_utf8, b"\xff")
  for
    args in [
      ["import-grouped-csv", bad_csv, mapping],
      ["import-grouped-csv", unknown_csv, mapping],
      ["import-grouped-csv", csv, bad_mapping],
      ["import-grouped-csv", csv],
      ["import-grouped-csv", csv, mapping, "extra"],
      ["import-grouped-csv", evidence_dir + "/missing.csv", mapping],
      ["import-grouped-csv", invalid_utf8, mapping],
    ] {
    let (bad_code, out, error) = grouped_invoke(args)
    assert_true(bad_code != 0)
    assert_eq(out, "")
    assert_true(error.length() > 0)
  }
  assert_eq(@fs.read_file(csv).text(), originals[0])
  assert_eq(@fs.read_file(mapping).text(), originals[1])
  assert_eq(@fs.read_file(template).text(), originals[2])
  grouped_save(
    evidence_dir + "/CLI_WORKFLOW.json",
    (
      {
        "grouped_run_count": 2,
        "samples_per_run": [3, 3],
        "objective_results": [true, false],
        "prepare_reopen_byte_identical": true,
        "repeat_import_byte_identical": true,
        "edit_only_one_group": true,
        "negative_commands_checked": 7,
        "original_inputs_unchanged": true,
        "synthetic_only": true,
      } : Json).stringify(indent=2),
  )
}
