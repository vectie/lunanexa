///|
test "legacy summary-only snapshots keep observations absent and planner unavailable" {
  for
    wire in [
      ({ "samples": [], "benchmark_summaries": [] } : Json),
      {
        "schema_version": "lunanexa.telemetry.v1",
        "samples": [],
        "benchmark_summaries": [],
      },
    ] {
    let snapshot = @capacity_planner.decode_telemetry(wire)
    assert_true(snapshot.benchmark_runs is None)
    if wire is { "schema_version": _, .. } {
      assert_eq(snapshot.schema_version, Some("lunanexa.telemetry.v1"))
    } else {
      assert_true(snapshot.schema_version is None)
    }
    let initial = @capacity_planner.refresh_telemetry(
      @capacity_planner.initial(),
      snapshot,
    )
    assert_false(initial.recorded_loaded)
    assert_true(initial.recorded_runs.is_empty())
    assert_true(render(initial).contains("legacy summary-only"))
    let prepared = @capacity_planner.update(recorded_authored(), Prepare)
    let pending = @capacity_planner.update(prepared, RefreshRecorded)
    let unavailable = @capacity_planner.update(
      pending,
      RecordedLoaded(pending.refresh_sequence, Ok(snapshot)),
    )
    assert_false(unavailable.refreshing)
    assert_eq(unavailable.packet, prepared.packet)
    assert_eq(unavailable.sources, prepared.sources)
    assert_eq(unavailable.recorded_runs, prepared.recorded_runs)
    assert_true(unavailable.refresh_error is Some(_))
  }
}

///|
test "legacy compatibility does not weaken unknown version or malformed raw observation checks" {
  for
    wire in [
      (
        {
          "schema_version": "lunanexa.telemetry.v2",
          "samples": [],
          "benchmark_summaries": [],
        } : Json),
      { "schema_version": null, "samples": [], "benchmark_summaries": [] },
      { "samples": [], "benchmark_summaries": [], "benchmark_runs": [] },
      {
        "schema_version": "lunanexa.telemetry.v1",
        "samples": [],
        "benchmark_summaries": [],
        "benchmark_runs": null,
      },
      {
        "schema_version": "lunanexa.telemetry.v1",
        "samples": [],
        "benchmark_summaries": [],
        "benchmark_runs": "summary text",
      },
    ] {
    try @capacity_planner.decode_telemetry(wire) catch {
      _ => ()
    } noraise {
      _ => fail("invalid telemetry accepted")
    }
  }
}
