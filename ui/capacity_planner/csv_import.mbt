///|
pub(all) enum CsvField {
  RunId
  Profile
  ModelDigest
  RuntimeDigest
  HardwareProfile
  Kind
  Concurrency
} derive(Eq)

///|
pub extend CsvField with Eq::{equal, not_equal}

///|
pub(all) struct CsvState {
  text : String
  preview : @planning.CsvPreview?
  mappings : Array[String]
  run_id : String
  profile : String
  model_digest : String
  runtime_digest : String
  hardware_profile : String
  kind : String
  concurrency : String
  metadata : MetadataDraft
  mapping_json : String?
  notice : String?
  error : String?
} derive(Eq)

///|
pub extend CsvState with Eq::{equal, not_equal}

///|
fn csv_metrics() -> Array[String] {
  [
    "latency_ms", "queue_ms", "load_ms", "first_output_ms", "output_units", "duration_ms",
    "utilization_per_mille", "failed",
  ]
}

///|
fn empty_csv() -> CsvState {
  {
    text: "",
    preview: None,
    mappings: [
      for _ in 0..<8 => ""
    ],
    run_id: "",
    profile: "",
    model_digest: "",
    runtime_digest: "",
    hardware_profile: "",
    kind: "Concurrency",
    concurrency: "",
    metadata: empty_metadata(),
    mapping_json: None,
    notice: None,
    error: None,
  }
}

///|
fn preview_csv(state : State, text : String) -> State {
  try @planning.preview_csv(text) catch {
    error => { ..state, csv: { ..state.csv, error: Some("\{Repr(error)}"), }, }
  } noraise {
    preview => {
      let mappings = csv_metrics().mapi((index, metric) => {
        let previous = state.csv.mappings[index]
        if preview.headers.contains(previous) {
          previous
        } else if preview.headers.contains(metric) {
          metric
        } else {
          ""
        }
      })
      {
        ..state,
        csv: {
          ..state.csv,
          text,
          preview: Some(preview),
          mappings,
          mapping_json: None,
          notice: None,
          error: None,
        },
      }
    }
  }
}

///|
fn csv_spec(csv : CsvState) -> @planning.CsvImportSpec raise {
  let m = csv.metadata
  let origin : @planning.Origin = match m.origin {
    "SyntheticFixture" => SyntheticFixture
    "LocalObservation" => LocalObservation
    _ => fail("Declare CSV provenance before adding observations")
  }
  {
    schema_version: 1,
    run_id: csv.run_id,
    profile: csv.profile,
    model_digest: csv.model_digest,
    runtime_digest: csv.runtime_digest,
    hardware_profile: csv.hardware_profile,
    kind: parse_kind(csv.kind),
    concurrency: parse_number(csv.concurrency, "CSV tested concurrency"),
    metadata: {
      origin,
      source_ref: m.source_ref,
      workload_ref: m.workload_ref,
      output_unit: m.output_unit,
      memory_total_mib: parse_number(
        m.memory_total,
        "CSV measured total memory MiB",
      ),
      memory_peak_mib: parse_number(
        m.memory_peak,
        "CSV measured peak memory MiB",
      ),
    },
    columns: {
      latency_ms: csv.mappings[0],
      queue_ms: csv.mappings[1],
      load_ms: csv.mappings[2],
      first_output_ms: csv.mappings[3],
      output_units: csv.mappings[4],
      duration_ms: csv.mappings[5],
      utilization_per_mille: csv.mappings[6],
      failed: csv.mappings[7],
    },
  }
}

///|
fn add_csv(state : State) -> State {
  try {
    let spec = csv_spec(state.csv)
    let evidence = @planning.import_csv(state.csv.text, spec)
    if state.sources.length() >= 8 &&
      !state.sources.any(e => e.run.run_id == evidence.run.run_id) {
      fail("A comparison supports at most 8 runs")
    }
    (spec, evidence)
  } catch {
    error => { ..state, csv: { ..state.csv, error: Some("\{Repr(error)}"), }, }
  } noraise {
    (spec, evidence) => {
      let next = {
        ..state,
        sources: state.sources.filter(e => e.run.run_id != evidence.run.run_id) +
        [evidence],
        selected: state.selected.filter(id => id != evidence.run.run_id) +
        [evidence.run.run_id],
        recordings: state.recordings.filter(r => {
          r.run.run_id != evidence.run.run_id
        }),
        packet: None,
        error: None,
        csv: {
          ..state.csv,
          mapping_json: Some(ToJson::to_json(spec).stringify(indent=2)),
          notice: Some(
            "Added \{evidence.run.samples.length()} CSV observations as \{evidence.run.run_id}. Review the objective and prepare the comparison packet.",
          ),
          error: None,
        },
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

///|
fn update_csv(state : State, message : Message) -> State {
  let csv = state.csv
  let edited = { ..csv, error: None, notice: None, mapping_json: None, }
  match message {
    CsvTextChanged(text) =>
      { ..state, csv: { ..edited, text, preview: None, }, }
    CsvPreview => preview_csv(state, csv.text)
    ReadCsvFile => { ..state, csv: { ..csv, error: None, }, }
    CsvFileRead(_, Ok(text)) => preview_csv(state, text)
    CsvFileRead(_, Err(error)) =>
      { ..state, csv: { ..csv, error: Some(error), }, }
    CsvMap(index, header) => {
      if index < 0 || index >= 8 {
        return state
      }
      let mappings = csv.mappings.copy()
      mappings[index] = header
      { ..state, csv: { ..edited, mappings, }, }
    }
    EditCsvMetadata(field, value) =>
      {
        ..state,
        csv: { ..edited, metadata: edit_metadata(csv.metadata, field, value), },
      }
    EditCsv(field, value) => {
      let csv = match field {
        RunId => { ..edited, run_id: value, }
        Profile => { ..edited, profile: value, }
        ModelDigest => { ..edited, model_digest: value, }
        RuntimeDigest => { ..edited, runtime_digest: value, }
        HardwareProfile => { ..edited, hardware_profile: value, }
        Kind => { ..edited, kind: value, }
        Concurrency => { ..edited, concurrency: value, }
      }
      { ..state, csv, }
    }
    AddCsv => add_csv(state)
    ClearCsv => { ..state, csv: empty_csv(), }
    _ => state
  }
}
