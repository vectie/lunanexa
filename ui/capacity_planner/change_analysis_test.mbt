///|
fn candidate_packet(baseline : @planning.Packet) -> @planning.Packet raise {
  let old = baseline.input
  @planning.prepare({
    ..old,
    workload: { ..old.workload, runtime_digest: "sha256:fixture-candidate-v2", },
    objective: { ..old.objective, minimum_throughput_units_per_second: 400, },
    evidence: old.evidence.map(e => {
      ..e,
      memory_peak_mib: 9000,
      run: {
        ..e.run,
        run_id: "candidate-" + e.run.run_id,
        runtime_digest: "sha256:fixture-candidate-v2",
        samples: e.run.samples.map(s => {
          ..s,
          duration_ms: 200,
          latency_ms: 10,
        }),
      },
    }),
  })
}

///|
test "capture baseline reopen candidate inspect tradeoffs and export both exact runs" {
  let baseline = @capacity_planner.update(authored(), Prepare)
  let captured = @capacity_planner.update(baseline, ChangeCaptureBaseline)
  assert_eq(captured.change_analysis.baseline_run_id, "fixture-run-4")
  let candidate = candidate_packet(baseline.packet.unwrap())
  let reopened = @capacity_planner.update(
    captured,
    ReopenPacketFile(candidate.export_json()),
  )
  assert_true(
    reopened.change_analysis.baseline_packet ==
    captured.change_analysis.baseline_packet,
  )
  let analyzed = @capacity_planner.update(reopened, ChangeCompare)
  let report = analyzed.change_analysis.report.unwrap()
  assert_eq(
    report.input.candidate.run.runtime_digest,
    "sha256:fixture-candidate-v2",
  )
  assert_true(report.baseline_meets_objective)
  assert_false(report.candidate_meets_objective)
  assert_eq(report.input.objective.minimum_throughput_units_per_second, 900)
  assert_true(@planning.reopen_change(report.export_json()) == report)
  let html = render(analyzed)
  for
    text in [
      "Compare a baseline with a candidate", "Captured baseline: fixture-run-4",
      "candidate-fixture-run-4", "sha256:fixture-candidate-v2", "Fixed objective met",
      "Download reproducible change analysis JSON", "Download readable change report",
      "500", "3000",
    ] {
    assert_true(html.contains(text))
  }
}

///|
test "selecting another run clears report and baseline survives candidate edits and history refresh" {
  let baseline = @capacity_planner.update(
    @capacity_planner.update(authored(), ToggleRun("fixture-run-8")),
    Prepare,
  )
  let selected = @capacity_planner.update(
    baseline,
    ChangeSelectRun("fixture-run-8"),
  )
  let captured = @capacity_planner.update(selected, ChangeCaptureBaseline)
  assert_eq(captured.change_analysis.baseline_run_id, "fixture-run-8")
  let compared = @capacity_planner.update(captured, ChangeCompare)
  assert_true(compared.change_analysis.report is Some(_))
  let reselected = @capacity_planner.update(
    compared,
    ChangeSelectRun("fixture-run-4"),
  )
  assert_true(reselected.change_analysis.report is None)
  assert_eq(reselected.change_analysis.baseline_run_id, "fixture-run-8")
  let edited = @capacity_planner.update(compared, Edit(MaximumP95, "40"))
  assert_true(edited.change_analysis.report is None)
  assert_true(edited.packet is None)
  assert_true(edited.change_analysis.baseline_packet is Some(_))
  let refreshed = @capacity_planner.update(compared, RefreshRecorded)
  assert_true(
    refreshed.change_analysis.report == compared.change_analysis.report,
  )
  let replaced = @capacity_planner.update(
    compared,
    ReopenPacketFile(candidate_packet(baseline.packet.unwrap()).export_json()),
  )
  assert_true(replaced.change_analysis.report is None)
  assert_eq(replaced.change_analysis.baseline_run_id, "fixture-run-8")
}

///|
test "failed reopen preserves the baseline and previous result while clear and reset remove them" {
  let captured = @capacity_planner.update(
    @capacity_planner.update(authored(), Prepare),
    ChangeCaptureBaseline,
  )
  let compared = @capacity_planner.update(captured, ChangeCompare)
  let invalid = @capacity_planner.update(compared, ReopenPacketFile("not JSON"))
  assert_true(invalid.change_analysis == compared.change_analysis)
  assert_true(invalid.error is Some(_))
  let cleared = @capacity_planner.update(compared, ChangeClear)
  assert_true(cleared.change_analysis.baseline_packet is None)
  assert_true(cleared.change_analysis.report is None)
  assert_true(cleared.packet == compared.packet)
  let reset = @capacity_planner.update(compared, Reset)
  assert_true(reset.change_analysis.baseline_packet is None)
  assert_true(reset.change_analysis.report is None)
}

///|
test "incompatible candidate has useful error and does not discard captured baseline" {
  let baseline = @capacity_planner.update(authored(), Prepare)
  let captured = @capacity_planner.update(baseline, ChangeCaptureBaseline)
  let input = baseline.packet.unwrap().input
  let mismatch = @planning.prepare({
    ..input,
    workload: { ..input.workload, workload_ref: "another-fixture-dataset", },
    evidence: input.evidence.map(e => {
      ..e,
      workload_ref: "another-fixture-dataset",
    }),
  })
  let compared = @capacity_planner.update(
    @capacity_planner.update(captured, ReopenPacketFile(mismatch.export_json())),
    ChangeCompare,
  )
  assert_true(compared.change_analysis.report is None)
  assert_true(
    compared.change_analysis.error.unwrap().contains("workload revision"),
  )
  assert_true(
    compared.change_analysis.baseline_packet ==
    captured.change_analysis.baseline_packet,
  )
}

///|
test "analysis actions explain missing packet or baseline without changing authoring input" {
  let state = authored()
  assert_true(
    @capacity_planner.update(state, ChangeCaptureBaseline).change_analysis.error
    is Some(_),
  )
  let prepared = @capacity_planner.update(state, Prepare)
  let attempted = @capacity_planner.update(prepared, ChangeCompare)
  assert_true(attempted.change_analysis.error is Some(_))
  assert_true(attempted.packet == prepared.packet)
}
