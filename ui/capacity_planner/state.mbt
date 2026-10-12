///|
pub(all) enum Field {
  Profile
  ModelDigest
  RuntimeDigest
  HardwareProfile
  WorkloadRef
  OutputUnit
  Kind
  MinimumConcurrency
  MaximumP95
  MinimumThroughput
  MaximumFailures
} derive(Eq)

///|
pub extend Field with Eq::{not_equal, equal}

///|
pub(all) struct Draft {
  profile : String
  model_digest : String
  runtime_digest : String
  hardware_profile : String
  workload_ref : String
  output_unit : String
  kind : String
  minimum_concurrency : String
  maximum_p95 : String
  minimum_throughput : String
  maximum_failures : String
} derive(Eq)

///|
pub extend Draft with Eq::{not_equal, equal}

///|
pub(all) struct State {
  revision : Int
  refresh_sequence : Int
  refreshing : Bool
  reading_file : Bool
  recorded_runs : Array[@benchmark.BenchmarkRun]
  recorded_loaded : Bool
  recorded_snapshot : String
  refresh_error : String?
  recordings : Array[Recording]
  pending_recording : Recording?
  import_text : String
  reopen_text : String
  sources : Array[@planning.Evidence]
  selected : Array[String]
  draft : Draft
  packet : @planning.Packet?
  explorer : Explorer
  change_analysis : ChangeState
  csv : CsvState
  error : String?
} derive(Eq)

///|
pub extend State with Eq::{not_equal, equal}

///|
pub(all) enum Message {
  RefreshRecorded
  RecordedLoaded(Int, Result[ConsoleTelemetrySnapshot, String])
  ReadFile(Bool)
  FileRead(Int, Bool, Result[String, String])
  SelectRecorded(String)
  EditMetadata(MetadataField, String)
  AddRecorded
  CancelRecorded
  ImportEvidenceFile(String)
  ReopenPacketFile(String)
  ImportTextChanged(String)
  ImportEvidence
  ToggleRun(String)
  Edit(Field, String)
  Prepare
  ReopenTextChanged(String)
  ReopenPacket
  ExploreRun(String)
  ExploreFailures(Bool)
  ExploreOrder(@planning.SampleOrder)
  ExplorePage(Int)
  ExportSamples
  ChangeSelectRun(String)
  ChangeCaptureBaseline
  ChangeCompare
  ChangeClear
  ReadCsvFile
  CsvFileRead(Int, Result[String, String])
  CsvTextChanged(String)
  CsvPreview
  CsvMap(Int, String)
  EditCsv(CsvField, String)
  EditCsvMetadata(MetadataField, String)
  AddCsv
  ClearCsv
  Reset
} derive(Eq)

///|
pub extend Message with Eq::{not_equal, equal}

///|
pub fn initial() -> State {
  {
    revision: 0,
    refresh_sequence: 0,
    refreshing: false,
    reading_file: false,
    recorded_runs: [],
    recorded_loaded: false,
    recorded_snapshot: "",
    refresh_error: None,
    recordings: [],
    pending_recording: None,
    import_text: "",
    reopen_text: "",
    sources: [],
    selected: [],
    packet: None,
    explorer: empty_explorer(),
    change_analysis: empty_change_state(),
    csv: empty_csv(),
    error: None,
    draft: {
      profile: "",
      model_digest: "",
      runtime_digest: "",
      hardware_profile: "",
      workload_ref: "",
      output_unit: "",
      kind: "Concurrency",
      minimum_concurrency: "",
      maximum_p95: "",
      minimum_throughput: "",
      maximum_failures: "",
    },
  }
}

///|
fn parse_number(value : String, label : String) -> Int raise {
  @string.parse_int(value) catch {
    _ => fail("\{label}: enter a whole number")
  }
}

///|
fn parse_kind(value : String) -> @benchmark.BenchmarkKind raise {
  match value {
    "Concurrency" => Concurrency
    "Saturation" => Saturation
    "ColdStart" => ColdStart
    "LongStream" => LongStream
    "MixedWorkload" => MixedWorkload
    _ => fail("select a supported benchmark kind")
  }
}

///|
pub fn input(state : State) -> @planning.Input raise {
  let d = state.draft
  {
    schema_version: 1,
    workload: {
      profile: d.profile,
      model_digest: d.model_digest,
      runtime_digest: d.runtime_digest,
      hardware_profile: d.hardware_profile,
      workload_ref: d.workload_ref,
      output_unit: d.output_unit,
      kind: parse_kind(d.kind),
      minimum_tested_concurrency: parse_number(
        d.minimum_concurrency,
        "minimum tested concurrency",
      ),
    },
    objective: {
      profile: d.profile,
      maximum_p95_ms: parse_number(d.maximum_p95, "maximum p95 ms"),
      minimum_throughput_units_per_second: parse_number(
        d.minimum_throughput,
        "minimum throughput",
      ),
      maximum_failure_per_mille: parse_number(
        d.maximum_failures,
        "maximum failures per mille",
      ),
    },
    evidence: state.sources.filter(source => {
      state.selected.contains(source.run.run_id)
    }),
  }
}

///|
fn edit(draft : Draft, field : Field, value : String) -> Draft {
  match field {
    Profile => { ..draft, profile: value, }
    ModelDigest => { ..draft, model_digest: value, }
    RuntimeDigest => { ..draft, runtime_digest: value, }
    HardwareProfile => { ..draft, hardware_profile: value, }
    WorkloadRef => { ..draft, workload_ref: value, }
    OutputUnit => { ..draft, output_unit: value, }
    Kind => { ..draft, kind: value, }
    MinimumConcurrency => { ..draft, minimum_concurrency: value, }
    MaximumP95 => { ..draft, maximum_p95: value, }
    MinimumThroughput => { ..draft, minimum_throughput: value, }
    MaximumFailures => { ..draft, maximum_failures: value, }
  }
}

///|
/// Pure state transitions; the console owns read-only telemetry/file effects.
pub fn update(state : State, message : Message) -> State {
  match message {
    RecordedLoaded(sequence, _) if sequence != state.refresh_sequence ||
      !state.refreshing => return state
    FileRead(revision, _, _) if revision != state.revision ||
      !state.reading_file => return state
    CsvFileRead(revision, _) if revision != state.revision ||
      !state.reading_file => return state
    _ => ()
  }
  let next = update_inner(state, message)
  let next = if next.sources != state.sources {
    { ..next, explorer: { ..next.explorer, export_csv: None, page: 0, }, }
  } else {
    next
  }
  let next = if next.packet != state.packet {
    {
      ..next,
      change_analysis: { ..next.change_analysis, report: None, error: None, },
    }
  } else {
    next
  }
  {
    ..next,
    revision: state.revision + 1,
    reading_file: match message {
      ReadFile(_) | ReadCsvFile => true
      _ => false
    },
  }
}

///|
fn update_inner(state : State, message : Message) -> State {
  match message {
    ReadCsvFile
    | CsvFileRead(_, _)
    | CsvTextChanged(_)
    | CsvPreview
    | CsvMap(_, _)
    | EditCsv(_, _)
    | EditCsvMetadata(_, _)
    | AddCsv
    | ClearCsv => update_csv(state, message)
    ExploreRun(_)
    | ExploreFailures(_)
    | ExploreOrder(_)
    | ExplorePage(_)
    | ExportSamples => update_explorer(state, message)
    ChangeSelectRun(_) | ChangeCaptureBaseline | ChangeCompare | ChangeClear =>
      update_change(state, message)
    RefreshRecorded =>
      {
        ..state,
        refresh_sequence: state.refresh_sequence + 1,
        refreshing: true,
        refresh_error: None,
      }
    RecordedLoaded(_, Ok(snapshot)) =>
      { ..refresh_telemetry(state, snapshot), refreshing: false, }
    RecordedLoaded(_, Err(error)) =>
      { ..state, refreshing: false, refresh_error: Some(error), }
    ReadFile(_) => { ..state, error: None, }
    FileRead(_, reopen, Ok(text)) =>
      update_inner(
        state,
        if reopen {
          ReopenPacketFile(text)
        } else {
          ImportEvidenceFile(text)
        },
      )
    FileRead(_, _, Err(error)) => { ..state, error: Some(error), }
    SelectRecorded(id) => choose_recorded(state, id)
    EditMetadata(field, value) =>
      match state.pending_recording {
        Some(recording) =>
          {
            ..state,
            pending_recording: Some({
              ..recording,
              metadata: edit_metadata(recording.metadata, field, value),
            }),
            packet: None,
            error: None,
          }
        None => { ..state, error: Some("Select a recorded run first"), }
      }
    AddRecorded => add_recorded(state)
    CancelRecorded => { ..state, pending_recording: None, error: None, }
    ImportEvidenceFile(text) =>
      update_inner({ ..state, import_text: text, }, ImportEvidence)
    ReopenPacketFile(text) =>
      update_inner({ ..state, reopen_text: text, }, ReopenPacket)
    Reset =>
      {
        ..initial(),
        recorded_runs: state.recorded_runs,
        recorded_loaded: state.recorded_loaded,
        recorded_snapshot: state.recorded_snapshot,
        refresh_sequence: state.refresh_sequence + 1,
      }
    ImportTextChanged(value) => { ..state, import_text: value, error: None, }
    ReopenTextChanged(value) => { ..state, reopen_text: value, error: None, }
    Edit(field, value) =>
      {
        ..state,
        draft: edit(state.draft, field, value),
        packet: None,
        error: None,
      }
    ToggleRun(id) => {
      if !state.sources.any(source => source.run.run_id == id) {
        return { ..state, packet: None, error: Some("unknown evidence run"), }
      }
      {
        ..state,
        selected: if state.selected.contains(id) {
          state.selected.filter(selected => selected != id)
        } else {
          state.selected + [id]
        },
        packet: None,
        error: None,
      }
    }
    ImportEvidence =>
      try @planning.import_evidence(state.import_text) catch {
        error => { ..state, error: Some("\{Repr(error)}"), }
      } noraise {
        sources => {
          let first = sources[0]
          {
            ..state,
            sources,
            explorer: { ..empty_explorer(), run_id: first.run.run_id, },
            recordings: [],
            pending_recording: None,
            selected: [first.run.run_id],
            packet: None,
            error: None,
            draft: {
              ..state.draft,
              profile: first.run.profile,
              model_digest: first.run.model_digest,
              runtime_digest: first.run.runtime_digest,
              hardware_profile: first.run.hardware_profile,
              workload_ref: first.workload_ref,
              output_unit: first.output_unit,
              kind: "\{Repr(first.run.kind)}",
            },
          }
        }
      }
    Prepare =>
      try @planning.prepare(input(state)) catch {
        error => { ..state, packet: None, error: Some("\{Repr(error)}"), }
      } noraise {
        packet => { ..state, packet: Some(packet), error: None, }
      }
    ReopenPacket =>
      try @planning.reopen(state.reopen_text) catch {
        error => { ..state, error: Some("\{Repr(error)}"), }
      } noraise {
        packet => {
          let w = packet.input.workload
          let o = packet.input.objective
          {
            ..state,
            sources: packet.input.evidence,
            explorer: {
              ..empty_explorer(),
              run_id: packet.input.evidence[0].run.run_id,
            },
            recordings: [],
            pending_recording: None,
            selected: packet.input.evidence.map(e => e.run.run_id),
            import_text: ToJson::to_json(packet.input.evidence).stringify(
              indent=2,
            ),
            draft: {
              profile: w.profile,
              model_digest: w.model_digest,
              runtime_digest: w.runtime_digest,
              hardware_profile: w.hardware_profile,
              workload_ref: w.workload_ref,
              output_unit: w.output_unit,
              kind: "\{Repr(w.kind)}",
              minimum_concurrency: "\{w.minimum_tested_concurrency}",
              maximum_p95: "\{o.maximum_p95_ms}",
              minimum_throughput: "\{o.minimum_throughput_units_per_second}",
              maximum_failures: "\{o.maximum_failure_per_mille}",
            },
            packet: Some(packet),
            error: None,
          }
        }
      }
  }
}
