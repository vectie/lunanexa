///|
fn recorded_snapshot(
  runs : Array[@benchmark.BenchmarkRun],
) -> @capacity_planner.ConsoleTelemetrySnapshot {
  @capacity_planner.decode_telemetry({
    "schema_version": "lunanexa.telemetry.v1",
    "samples": [],
    "benchmark_runs": ToJson::to_json(runs),
    "benchmark_summaries": [],
  }) catch {
    _ => abort("invalid fixture")
  }
}

///|
fn fill_recorded(
  state : @capacity_planner.State,
  id : String,
) -> @capacity_planner.State {
  let mut state = @capacity_planner.update(state, SelectRecorded(id))
  for
    (field, value) in [
      (@capacity_planner.MetadataField::Origin, "SyntheticFixture"),
      (SourceRef, "fixture:recorded-source-观察"),
      (WorkloadRef, "fixture:workload-revision-1"),
      (OutputUnit, "tokens"),
      (MemoryTotal, "16000"),
      (MemoryPeak, "12000"),
    ] {
    state = @capacity_planner.update(state, EditMetadata(field, value))
  }
  @capacity_planner.update(state, AddRecorded)
}

///|
fn recorded_authored() -> @capacity_planner.State {
  let run = fixture_evidence().run
  let mut state = fill_recorded(
    @capacity_planner.refresh_recorded(@capacity_planner.initial(), [run]),
    run.run_id,
  )
  for
    (field, value) in [
      (@capacity_planner.Field::MinimumConcurrency, "4"),
      (MaximumP95, "30"),
      (MinimumThroughput, "900"),
      (MaximumFailures, "0"),
    ] {
    state = @capacity_planner.update(state, Edit(field, value))
  }
  state
}

///|
test "recorded observation is copied from exact API raw runs with explicit metadata and reopened" {
  let run = fixture_evidence().run
  let wire = recorded_snapshot([run]).to_json()
  let decoded = @capacity_planner.decode_telemetry(wire)
  assert_eq(decoded.benchmark_runs, Some([run]))
  let prepared = @capacity_planner.update(recorded_authored(), Prepare)
  let packet = prepared.packet.unwrap()
  assert_eq(packet.input.evidence[0].run, run)
  assert_true(
    packet.input.evidence[0].source_ref.contains(
      @planning.observation_digest(run),
    ),
  )
  assert_true(
    packet.input.evidence[0].source_ref.contains(
      @planning.snapshot_digest([run]),
    ),
  )
  let reopened = @capacity_planner.update(
    @capacity_planner.initial(),
    ReopenPacketFile(packet.export_json()),
  )
  assert_eq(reopened.packet, prepared.packet)
  assert_eq(@capacity_planner.update(reopened, Prepare).packet, prepared.packet)
  let restored = @capacity_planner.refresh_recorded(reopened, [run])
  let editing = @capacity_planner.update(restored, SelectRecorded(run.run_id))
  assert_eq(
    editing.pending_recording.unwrap().metadata.origin,
    "SyntheticFixture",
  )
  assert_eq(
    editing.pending_recording.unwrap().metadata.source_ref,
    "fixture:recorded-source-观察",
  )
  assert_eq(editing.pending_recording.unwrap().metadata.memory_peak, "12000")
  let html = render(prepared)
  for
    required in [
      "Select recorded run", "Refresh recorded runs", "Benchmark evidence file",
      "Saved planning packet file", "<details>", "SYNTHETIC FIXTURE",
    ] {
    assert_true(html.contains(required), msg=required)
  }
}

///|
test "missing provenance and memory never become fabricated genuine evidence" {
  let run = fixture_evidence().run
  let state = @capacity_planner.refresh_recorded(@capacity_planner.initial(), [
    run,
  ])
  let state = @capacity_planner.update(state, SelectRecorded(run.run_id))
  assert_eq(state.pending_recording.unwrap().metadata.origin, "")
  assert_eq(state.pending_recording.unwrap().metadata.memory_total, "")
  assert_true(@capacity_planner.update(state, AddRecorded).sources.is_empty())
  let state = @capacity_planner.update(
    state,
    EditMetadata(Origin, "LocalObservation"),
  )
  assert_true(@capacity_planner.update(state, AddRecorded).sources.is_empty())
  assert_true(render(state).contains("unverified"))
}

///|
test "metadata changes replace the same run once and preserve prior immutable packet" {
  let prepared = @capacity_planner.update(recorded_authored(), Prepare)
  let bytes = prepared.packet.unwrap().export_json()
  let state = @capacity_planner.update(
    prepared,
    SelectRecorded("fixture-run-4"),
  )
  assert_eq(state.pending_recording.unwrap().metadata.memory_peak, "12000")
  let state = @capacity_planner.update(state, EditMetadata(MemoryPeak, "11000"))
  let state = @capacity_planner.update(state, AddRecorded)
  assert_eq(state.sources.length(), 1)
  assert_eq(state.selected, ["fixture-run-4"])
  assert_eq(state.sources[0].memory_peak_mib, 11000)
  assert_true(state.packet is None)
  assert_eq(prepared.packet.unwrap().export_json(), bytes)
  assert_not_eq(
    @capacity_planner.update(state, Prepare).packet.unwrap().packet_id,
    prepared.packet.unwrap().packet_id,
  )
}

///|
test "refresh flags changed disappeared observations without erasing source metadata packet or pending edit" {
  let state = @capacity_planner.update(recorded_authored(), Prepare)
  let state = @capacity_planner.update(state, SelectRecorded("fixture-run-4"))
  let captured = state.pending_recording.unwrap()
  let changed = @capacity_planner.refresh_recorded(state, [
    { ..captured.run, concurrency: 8, },
  ])
  assert_true(@capacity_planner.recording_changed(changed, captured))
  assert_eq(changed.packet, state.packet)
  assert_eq(changed.sources, state.sources)
  assert_true(changed.pending_recording == state.pending_recording)
  assert_true(@capacity_planner.update(changed, AddRecorded).error is Some(_))
  let missing = @capacity_planner.refresh_recorded(changed, [])
  assert_true(render(missing).contains("changed or disappeared"))
  let reopened = @capacity_planner.update(
    missing,
    ReopenPacketFile(state.packet.unwrap().export_json()),
  )
  assert_true(@capacity_planner.captured_changed(reopened, reopened.sources[0]))
  assert_eq(reopened.packet, state.packet)
}

///|
test "refresh generation rejects stale success failure and duplicates while retaining draft" {
  let state = @capacity_planner.update(recorded_authored(), Prepare)
  let first = @capacity_planner.update(state, RefreshRecorded)
  let second = @capacity_planner.update(first, RefreshRecorded)
  let stale = @capacity_planner.update(
    second,
    RecordedLoaded(first.refresh_sequence, Ok(recorded_snapshot([]))),
  )
  assert_true(stale == second)
  let failed = @capacity_planner.update(
    second,
    RecordedLoaded(second.refresh_sequence, Err("offline")),
  )
  assert_eq(failed.packet, state.packet)
  assert_eq(failed.sources, state.sources)
  assert_true(failed.refresh_error is Some(_))
  let run = fixture_evidence().run
  let duplicate = @capacity_planner.refresh_recorded(failed, [run, run])
  assert_eq(duplicate.recorded_runs, failed.recorded_runs)
  assert_eq(duplicate.packet, state.packet)
  assert_true(duplicate.refresh_error is Some(_))
  let reset = @capacity_planner.update(second, Reset)
  assert_true(
    @capacity_planner.update(
      reset,
      RecordedLoaded(second.refresh_sequence, Ok(recorded_snapshot([]))),
    ) ==
    reset,
  )
}

///|
test "file callbacks are fenced by later read edit and reset and invalid files retain packet" {
  let state = @capacity_planner.update(recorded_authored(), Prepare)
  let first = @capacity_planner.update(state, ReadFile(false))
  let second = @capacity_planner.update(first, ReadFile(true))
  assert_true(
    @capacity_planner.update(second, FileRead(first.revision, false, Ok("[]"))) ==
    second,
  )
  let edited = @capacity_planner.update(second, Edit(MaximumP95, "77"))
  assert_true(
    @capacity_planner.update(
      edited,
      FileRead(second.revision, true, Ok(state.packet.unwrap().export_json())),
    ) ==
    edited,
  )
  let reset = @capacity_planner.update(second, Reset)
  assert_true(
    @capacity_planner.update(reset, FileRead(second.revision, false, Ok("[]"))) ==
    reset,
  )
  let invalid = @capacity_planner.update(
    second,
    FileRead(second.revision, true, Ok("{}")),
  )
  assert_eq(invalid.packet, state.packet)
  assert_eq(invalid.sources, state.sources)
  assert_true(invalid.error is Some(_))
}

///|
test "incompatible runs malformed observations unknown selection and one failure in 1001 are truthful" {
  let first = fixture_evidence().run
  let second = { ..first, run_id: "other", hardware_profile: "other-hardware", }
  let state = @capacity_planner.refresh_recorded(recorded_authored(), [
    first, second,
  ])
  let state = fill_recorded(state, "other")
  assert_eq(state.sources.length(), 2)
  assert_true(@capacity_planner.update(state, Prepare).error is Some(_))
  let invalid = @capacity_planner.update(state, SelectRecorded("missing"))
  assert_true(invalid.error is Some(_))
  assert_eq(invalid.sources, state.sources)
  let malformed = {
    ..first,
    samples: [{ ..first.samples[0], duration_ms: 0, }],
  }
  let state = fill_recorded(
    @capacity_planner.refresh_recorded(@capacity_planner.initial(), [malformed]),
    first.run_id,
  )
  assert_true(state.error is Some(_))
  assert_true(state.sources.is_empty())
  let samples = [
    for index in 0..<1001 => { ..first.samples[0], failed: index == 0, }
  ]
  let run = { ..first, samples, }
  let state = fill_recorded(
    @capacity_planner.refresh_recorded(recorded_authored(), [run]),
    run.run_id,
  )
  let state = @capacity_planner.update(state, Prepare)
  assert_true(state.packet is Some(_))
  assert_false(state.packet.unwrap().choices[0].meets_declared_envelope)
  assert_true(render(state).contains("1/1001 · 0‰ (rounded down)"))
  assert_true(render(state).contains("Objective not met"))
}

///|
test "recorded binding rejects edited samples and decoder rejects dropped raw fields" {
  let state = recorded_authored()
  let source = state.sources[0]
  let altered = { ..source, run: { ..source.run, concurrency: 7, }, }
  try @planning.import_evidence(ToJson::to_json([altered]).stringify()) catch {
    _ => ()
  } noraise {
    _ => fail("accepted changed raw observation with unchanged identity")
  }
  let raw = source.run.to_json()
  guard raw is Object(fields) else { fail("expected object") }
  fields["new_sample_semantics"] = true
  try
    @capacity_planner.decode_telemetry({
      "schema_version": "lunanexa.telemetry.v1",
      "samples": [],
      "benchmark_runs": [raw],
      "benchmark_summaries": [],
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("discarded unknown raw fields")
  }
}
