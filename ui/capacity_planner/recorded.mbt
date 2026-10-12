///|
/// The same raw operator API contract is decoded by the production console and
/// fixture tests. Summaries are retained for the legacy dashboard only.
pub(all) struct ConsoleTelemetrySnapshot {
  schema_version : String?
  samples : Array[@contracts.TelemetrySample]
  benchmark_runs : Array[@benchmark.BenchmarkRun]?
  benchmark_summaries : Array[@contracts.BenchmarkReadSummary]
} derive(FromJson, ToJson, Eq)

///|
pub extend ConsoleTelemetrySnapshot with FromJson::{from_json}

///|
pub extend ConsoleTelemetrySnapshot with ToJson::{to_json}

///|
pub extend ConsoleTelemetrySnapshot with Eq::{equal, not_equal}

///|
pub fn decode_telemetry(json : Json) -> ConsoleTelemetrySnapshot raise {
  let snapshot : ConsoleTelemetrySnapshot = @json.from_json(json)
  match snapshot.schema_version {
    Some("lunanexa.telemetry.v1") => ()
    None =>
      // Historical console projections had neither version nor raw runs.
      // Preserve absence; never assign a version or invent observations.
      if json is { "schema_version": _, .. } ||
        snapshot.benchmark_runs is Some(_) {
        fail("unversioned raw telemetry is not supported")
      }
    _ => fail("unsupported telemetry snapshot")
  }
  match snapshot.benchmark_runs {
    Some(runs) => {
      guard json is { "benchmark_runs": raw, .. } &&
        ToJson::to_json(runs) == raw else {
        fail("recorded observations contain unsupported fields")
      }
      if runs.length() > 65536 {
        fail("benchmark history exceeds supported store limit")
      }
    }
    None =>
      if json is { "benchmark_runs": _, .. } {
        fail("invalid raw benchmark observations")
      }
  }
  // Duplicate/empty IDs are a planner-selection error, not a reason to disable
  // unrelated operator console pages. refresh_recorded retains prior evidence.
  snapshot
}

///|
/// Legacy summaries remain usable by existing console views, but cannot supply
/// raw planner evidence. A failed/unavailable refresh retains captured work.
pub fn refresh_telemetry(
  state : State,
  snapshot : ConsoleTelemetrySnapshot,
) -> State {
  match snapshot.benchmark_runs {
    Some(runs) => refresh_recorded(state, runs)
    None =>
      {
        ..state,
        refresh_error: Some(
          "Raw benchmark runs are unavailable in this legacy summary-only snapshot. Summaries cannot supply measurements; import a complete producer evidence file or refresh a current telemetry source.",
        ),
      }
  }
}

///|
pub(all) enum MetadataField {
  Origin
  SourceRef
  WorkloadRef
  OutputUnit
  MemoryTotal
  MemoryPeak
} derive(Eq)

///|
pub extend MetadataField with Eq::{equal, not_equal}

///|
pub(all) struct MetadataDraft {
  origin : String
  source_ref : String
  workload_ref : String
  output_unit : String
  memory_total : String
  memory_peak : String
} derive(Eq)

///|
pub extend MetadataDraft with Eq::{equal, not_equal}

///|
pub(all) struct Recording {
  run : @benchmark.BenchmarkRun
  snapshot_digest : String
  metadata : MetadataDraft
} derive(Eq)

///|
pub extend Recording with Eq::{equal, not_equal}

///|
fn empty_metadata() -> MetadataDraft {
  {
    origin: "",
    source_ref: "",
    workload_ref: "",
    output_unit: "",
    memory_total: "",
    memory_peak: "",
  }
}

///|
fn edit_metadata(
  d : MetadataDraft,
  field : MetadataField,
  value : String,
) -> MetadataDraft {
  match field {
    Origin => { ..d, origin: value, }
    SourceRef => { ..d, source_ref: value, }
    WorkloadRef => { ..d, workload_ref: value, }
    OutputUnit => { ..d, output_unit: value, }
    MemoryTotal => { ..d, memory_total: value, }
    MemoryPeak => { ..d, memory_peak: value, }
  }
}

///|
fn complete_recording(recording : Recording) -> @planning.Evidence raise {
  let d = recording.metadata
  let origin : @planning.Origin = match d.origin {
    "SyntheticFixture" => SyntheticFixture
    "LocalObservation" => LocalObservation
    _ =>
      fail(
        "Declare provenance: synthetic fixture or operator-declared local observation",
      )
  }
  @planning.recorded_evidence(recording.run, recording.snapshot_digest, {
    origin,
    source_ref: d.source_ref,
    workload_ref: d.workload_ref,
    output_unit: d.output_unit,
    memory_total_mib: parse_number(d.memory_total, "measured total memory MiB"),
    memory_peak_mib: parse_number(d.memory_peak, "measured peak memory MiB"),
  })
}

///|
/// Refresh replaces only the available observation list. Captured selections,
/// metadata edits and a prepared/reopened packet remain exact and inspectable.
pub fn refresh_recorded(
  state : State,
  runs : Array[@benchmark.BenchmarkRun],
) -> State {
  let frozen : Array[@benchmark.BenchmarkRun] = @json.from_json(
    @json.parse(ToJson::to_json(runs).stringify()),
  ) catch {
    _ =>
      return {
        ..state,
        refresh_error: Some("Could not decode benchmark observations"),
      }
  }
  let seen : Map[String, Bool] = Map([])
  for run in frozen {
    if run.run_id.trim().is_empty() || seen.contains(run.run_id) {
      return {
        ..state,
        refresh_error: Some(
          "Duplicate or empty recorded run ID; previous observations retained",
        ),
      }
    }
    seen[run.run_id] = true
  }
  {
    ..state,
    recorded_runs: frozen,
    recorded_loaded: true,
    recorded_snapshot: @planning.snapshot_digest(frozen),
    refresh_error: None,
  }
}

///|
pub fn interrupt_refresh(state : State) -> State {
  if !state.refreshing {
    return state
  }
  {
    ..state,
    refreshing: false,
    refresh_sequence: state.refresh_sequence + 1,
    refresh_error: Some(
      "Console session or core read changed during benchmark refresh. Captured evidence is retained; refresh recorded runs again.",
    ),
  }
}

///|
pub fn recording_changed(state : State, recording : Recording) -> Bool {
  state.recorded_loaded && !state.recorded_runs.any(run => run == recording.run)
}

///|
pub fn captured_changed(state : State, evidence : @planning.Evidence) -> Bool {
  evidence.source_ref.has_prefix("recorded-v1:sha256:") &&
  state.recorded_loaded &&
  !state.recorded_runs.any(run => run == evidence.run)
}

///|
fn with_first_source(state : State, evidence : @planning.Evidence) -> State {
  {
    ..state,
    draft: {
      ..state.draft,
      profile: evidence.run.profile,
      model_digest: evidence.run.model_digest,
      runtime_digest: evidence.run.runtime_digest,
      hardware_profile: evidence.run.hardware_profile,
      kind: "\{Repr(evidence.run.kind)}",
      workload_ref: evidence.workload_ref,
      output_unit: evidence.output_unit,
    },
  }
}

///|
fn choose_recorded(state : State, id : String) -> State {
  guard state.recorded_runs.iter().find_first(run => run.run_id == id)
    is Some(run) else {
    return {
      ..state,
      error: Some(
        "Recorded run is no longer available; refresh and select again",
      ),
    }
  }
  let previous = state.recordings.iter().find_first(item => item.run == run)
  let from_evidence = state.sources
    .iter()
    .find_first(e => e.run == run)
    .map(evidence => {
      let prefix = "recorded-v1:sha256:" +
        @planning.observation_digest(run) +
        ":snapshot:"
      let bound = evidence.source_ref.has_prefix(prefix)
      // Evidence has already passed the shared strict importer. Preserve explicit
      // producer/operator metadata, including on packet reopen, rather than ask
      // the operator to retype it or silently invent a new provenance declaration.
      {
        run,
        snapshot_digest: if bound {
          evidence.source_ref[prefix.length():prefix.length() + 64].to_owned()
        } else {
          state.recorded_snapshot
        },
        metadata: {
          origin: "\{Repr(evidence.origin)}",
          source_ref: if bound {
            evidence.source_ref[prefix.length() + 72:].to_owned()
          } else {
            evidence.source_ref
          },
          workload_ref: evidence.workload_ref,
          output_unit: evidence.output_unit,
          memory_total: evidence.memory_total_mib.to_string(),
          memory_peak: evidence.memory_peak_mib.to_string(),
        },
      }
    })
  let recording = previous.unwrap_or(
    from_evidence.unwrap_or({
      run,
      snapshot_digest: state.recorded_snapshot,
      metadata: empty_metadata(),
    }),
  )
  { ..state, pending_recording: Some(recording), error: None, }
}

///|
fn add_recorded(state : State) -> State {
  guard state.pending_recording is Some(recording) else {
    return { ..state, error: Some("Select a recorded run first"), }
  }
  if recording_changed(state, recording) {
    return {
      ..state,
      error: Some(
        "Selected run changed or disappeared; inspect and select the current run before adding",
      ),
    }
  }
  try complete_recording(recording) catch {
    error => { ..state, error: Some("\{Repr(error)}"), }
  } noraise {
    evidence => {
      if state.sources.length() >= 8 &&
        !state.sources.any(e => e.run.run_id == evidence.run.run_id) {
        return { ..state, error: Some("A comparison supports at most 8 runs"), }
      }
      let next = {
        ..state,
        sources: state.sources.filter(e => e.run.run_id != evidence.run.run_id) +
        [evidence],
        selected: state.selected.filter(id => id != evidence.run.run_id) +
        [evidence.run.run_id],
        recordings: state.recordings.filter(r => {
          r.run.run_id != evidence.run.run_id
        }) +
        [recording],
        pending_recording: None,
        packet: None,
        error: None,
      }
      if state.sources.is_empty() ||
        (
          state.sources.length() == 1 &&
          state.sources[0].run.run_id == evidence.run.run_id
        ) {
        with_first_source(next, evidence)
      } else {
        next
      }
    }
  }
}
