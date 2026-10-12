///|
test "operator explores paged samples and exports all matches without changing the packet" {
  let base = fixture_evidence()
  let samples = [
    for index in 0..<61 => {
      {
        ..base.run.samples[0],
        latency_ms: index + 1,
        queue_ms: 61 - index,
        failed: index % 30 == 0,
      }
    }
  ]
  let source = { ..base, run: { ..base.run, samples, }, }
  let mut state = @capacity_planner.update(
    authored(),
    ImportEvidenceFile(ToJson::to_json([source]).stringify()),
  )
  state = @capacity_planner.update(state, Prepare)
  let packet = state.packet.unwrap()
  assert_true(render(state).contains("Showing 1–25 of 61 matching samples"))
  state = @capacity_planner.update(state, ExplorePage(1))
  assert_true(render(state).contains("Showing 26–50 of 61 matching samples"))
  state = @capacity_planner.update(state, ExplorePage(2))
  assert_true(render(state).contains("Showing 51–61 of 61 matching samples"))
  state = @capacity_planner.update(state, ExploreOrder(SlowestLatency))
  assert_eq(state.explorer.page, 0)
  state = @capacity_planner.update(state, ExploreFailures(true))
  state = @capacity_planner.update(state, ExportSamples)
  let csv = state.explorer.export_csv.unwrap()
  assert_eq(csv, @planning.samples_csv(source, true, SlowestLatency))
  assert_eq(csv.split("\r\n").collect().length(), 5)
  let html = render(state)
  assert_true(
    html.contains(
      "Showing 1–3 of 3 matching samples (61 in the complete run)",
    ),
  )
  assert_true(html.contains("Download all matching samples CSV"))
  assert_true(html.contains("Download comparison summary CSV"))
  assert_true(html.contains("data:text/csv;charset=utf-8;base64,"))
  assert_eq(state.packet, Some(packet))
  state = @capacity_planner.update(state, ExploreFailures(false))
  assert_true(state.explorer.export_csv is None)
  assert_eq(state.packet, Some(packet))
}

///|
test "sample explorer handles empty filters repeated controls and replaced evidence" {
  let mut state = @capacity_planner.update(authored(), Prepare)
  state = @capacity_planner.update(state, ExploreRun("fixture-run-4"))
  state = @capacity_planner.update(state, ExploreFailures(true))
  assert_true(render(state).contains("No samples match this filter"))
  state = @capacity_planner.update(state, ExportSamples)
  assert_true(state.explorer.export_csv is Some(_))
  state = @capacity_planner.update(state, ExportSamples)
  let exported = state.explorer.export_csv
  let unchanged = @capacity_planner.update(
    state,
    ImportEvidenceFile("not JSON"),
  )
  assert_eq(unchanged.explorer.export_csv, exported)
  let replaced = @capacity_planner.update(
    state,
    ImportEvidenceFile(ToJson::to_json([fixture_evidence()]).stringify()),
  )
  assert_true(replaced.explorer.export_csv is None)
  assert_false(replaced.explorer.failed_only)
  assert_eq(replaced.explorer.page, 0)
  let switched = @capacity_planner.update(state, ExploreRun("fixture-run-8"))
  assert_eq(switched.explorer.run_id, "fixture-run-8")
  assert_true(switched.explorer.export_csv is None)
  assert_false(switched.explorer.failed_only)
  assert_true(@capacity_planner.update(switched, Reset).sources.is_empty())
}
