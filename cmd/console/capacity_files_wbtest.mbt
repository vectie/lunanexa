///|
extern "js" fn mock_capacity_file(
  text : String,
  invalid_utf8 : Bool,
  too_large : Bool,
) -> Unit =
  #|(text, invalid, large) => {
  #|  const bytes = invalid ? new Uint8Array([0xff]) : new TextEncoder().encode(text);
  #|  globalThis.document = {getElementById: () => ({files: [{size: large ? 16777217 : bytes.length, arrayBuffer: () => Promise.resolve(bytes.buffer)}]})};
  #|}

///|
extern "js" fn clear_capacity_mock() -> Unit =
  #|() => { delete globalThis.document; }

///|
async test "production file reader preserves unicode rejects invalid UTF8 and bounds file bytes" {
  defer clear_capacity_mock()
  mock_capacity_file("[\"观察😀\"]", false, false)
  let text : String = capacity_file_text(false).wait().cast()
  assert_eq(text, "[\"观察😀\"]")
  for (invalid, large) in [(true, false), (false, true)] {
    mock_capacity_file("[]", invalid, large)
    try ignore(capacity_file_text(false).wait()) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid or oversized file")
    }
  }
}

///|
extern "js" fn mock_csv_file_picker() -> Unit =
  #|() => {
  #|  const input = {value:'selected', files:[{size:7, arrayBuffer:() => Promise.resolve(new TextEncoder().encode('a,b\n1,2').buffer)}]};
  #|  globalThis.document = {getElementById: id => {if (id !== 'capacity-csv-file') throw new Error('wrong CSV picker'); return input;}};
  #|}

///|
extern "js" fn csv_picker_was_reset() -> Bool =
  #|() => document.getElementById('capacity-csv-file').value === ''

///|
extern "js" fn replace_csv_picker_selection() -> Unit =
  #|() => { document.getElementById('capacity-csv-file').files = []; }

///|
async test "CSV reader uses its own picker captures the selected file and permits repeat selection" {
  defer clear_capacity_mock()
  mock_csv_file_picker()
  let pending = capacity_named_file_text("capacity-csv-file")
  assert_true(csv_picker_was_reset())
  replace_csv_picker_selection()
  let text : String = pending.wait().cast()
  assert_eq(text, "a,b\n1,2")
  try ignore(capacity_named_file_text("capacity-csv-file").wait()) catch {
    _ => ()
  } noraise {
    _ => fail("missing selection accepted")
  }
  for (invalid, large) in [(true, false), (false, true)] {
    mock_capacity_file("a,b\n1,2", invalid, large)
    try ignore(capacity_named_file_text("capacity-csv-file").wait()) catch {
      _ => ()
    } noraise {
      _ => fail("invalid CSV file bytes accepted")
    }
  }
}

///|
test "recorded reply is bound to operator session endpoint and latest planner request" {
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let initial = deferred_read_test_model(Benchmarks)
  let state = @capacity_planner.update(
    initial.console.capacity_planner,
    RefreshRecorded,
  )
  let model = {
    ..initial,
    console: {
      ..initial.console,
      operator_authenticated: true,
      capacity_planner: state,
    },
  }
  let snapshot = @capacity_planner.decode_telemetry({
    "schema_version": "lunanexa.telemetry.v1",
    "samples": [],
    "benchmark_runs": [],
    "benchmark_summaries": [],
  })
  let message = RecordedBenchmarksLoaded(
    model.endpoint,
    model.credential,
    model.cluster_poll_generation,
    state.refresh_sequence,
    Ok(snapshot),
  )
  let (accepted, _) = update(model, Outcome(message), emit)
  assert_true(accepted.console.capacity_planner.recorded_loaded)
  assert_false(accepted.console.capacity_planner.refreshing)
  for
    changed in [
      { ..model, endpoint: "http://other.invalid", },
      { ..model, credential: "changed", },
      { ..model, cluster_poll_generation: model.cluster_poll_generation + 1L, },
      { ..model, console: { ..model.console, operator_authenticated: false, }, },
    ] {
    let (ignored, _) = update(changed, Outcome(message), emit)
    assert_true(
      ignored.console.capacity_planner == changed.console.capacity_planner,
    )
  }
}

///|
test "initial duplicate-history error is visible and unauthenticated refresh never stays pending" {
  let current = @ui.default_state()
  let loaded = {
    ..current,
    capacity_planner: {
      ..current.capacity_planner,
      refresh_error: Some(
        "Duplicate recorded run ID; previous observations retained",
      ),
    },
  }
  let merged = merge_loaded_console(current, loaded)
  assert_true(merged.capacity_planner.refresh_error is Some(_))
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let base = deferred_read_test_model(Benchmarks)
  let model = {
    ..base,
    console: { ..base.console, operator_authenticated: false, },
  }
  let (next, _) = update(model, Console(CapacityPlanner(RefreshRecorded)), emit)
  assert_false(next.console.capacity_planner.refreshing)
  assert_true(next.console.capacity_planner.refresh_error is Some(_))
}

///|
test "legacy console telemetry keeps node metrics and old benchmark summaries available" {
  let samples = [
    node_row_sample("node-1", "host_memory_total_mib", 32000.0),
    node_row_sample("node-1", "host_memory_used_mib", 12000.0),
  ]
  let snapshot = @capacity_planner.decode_telemetry({
    "samples": ToJson::to_json(samples),
    "benchmark_summaries": [
      {
        "run_id": "legacy-summary",
        "profile": "text-short",
        "latency_p95_ms": 31,
        "throughput_units_per_second": 90,
        "failure_per_mille": 2,
      },
    ],
  })
  assert_eq(snapshot.benchmark_summaries[0].run_id, "legacy-summary")
  assert_eq(snapshot.benchmark_summaries[0].latency_p95_ms, 31)
  let rows = build_node_rows(
    [node_row_heartbeat("node-1", declared_memory_mib=1000)],
    snapshot,
    None,
    English,
  )
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].total_memory_mib, 32000)
  assert_eq(rows[0].used_memory_mib, 12000)
  let loaded = {
    ..@ui.default_state(),
    capacity_planner: @capacity_planner.refresh_telemetry(
      @capacity_planner.initial(),
      snapshot,
    ),
  }
  let merged = merge_loaded_console(@ui.default_state(), loaded)
  assert_true(merged.capacity_planner.refresh_error is Some(_))
  assert_false(merged.capacity_planner.recorded_loaded)
}
