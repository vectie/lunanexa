///|
/// Context for one exact group. Samples and metrics come only from CSV rows.
pub(all) struct CsvRunContext {
  run_id : String
  profile : String
  model_digest : String
  runtime_digest : String
  hardware_profile : String
  kind : @benchmark.BenchmarkKind
  concurrency : Int
  metadata : RecordedMetadata
} derive(Eq, ToJson, FromJson)

///|
/// A shared metric mapping and explicit context for every run-ID group.
pub(all) struct GroupedCsvImportSpec {
  schema_version : Int
  run_id_column : String
  columns : CsvColumns
  runs : Array[CsvRunContext]
} derive(Eq, ToJson, FromJson)

///|
pub fn import_grouped_csv_spec(
  text : String,
) -> GroupedCsvImportSpec raise PlanningError {
  if text.length() > 65536 {
    raise InvalidInput("grouped CSV mapping exceeds 64 Ki characters")
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidInput("invalid grouped CSV mapping JSON")
  }
  let spec : GroupedCsvImportSpec = @json.from_json(json) catch {
    _ => raise InvalidInput("invalid grouped CSV mapping JSON")
  }
  if spec.schema_version != 1 || ToJson::to_json(spec) != json {
    raise InvalidInput(
      "grouped CSV mapping has an unsupported version or fields",
    )
  }
  spec
}

///|
/// Import all rows atomically, retaining each group's original sample order.
/// Runs are returned in mapping order. Group keys are exact, not trimmed.
/// The file has the existing 10000-record bound, shared across all groups.
pub fn import_grouped_csv(
  text : String,
  spec : GroupedCsvImportSpec,
) -> Array[Evidence] raise PlanningError {
  if spec.schema_version != 1 {
    raise InvalidInput("unsupported grouped CSV mapping version")
  }
  if spec.runs.is_empty() || spec.runs.length() > 8 {
    raise InvalidInput("grouped CSV requires context for 1..8 runs")
  }
  let by_id : Map[String, Int] = Map([])
  let samples : Array[Array[@benchmark.BenchmarkSample]] = []
  for index, run in spec.runs {
    require_text(run.run_id, "grouped CSV run_id")
    if run.run_id.trim() != run.run_id {
      raise InvalidInput(
        "grouped CSV run_id cannot have surrounding whitespace",
      )
    }
    if by_id.contains(run.run_id) {
      raise InvalidInput("duplicate grouped CSV run_id context: \{run.run_id}")
    }
    by_id[run.run_id] = index
    samples.push([])
  }
  let rows = csv_rows(text)
  let headers = rows[0]
  let names = csv_column_names(spec.columns)
  let indices = csv_metric_indices(headers, spec.columns)
  if names.contains(spec.run_id_column) {
    raise InvalidInput("run ID must map to a different column from all metrics")
  }
  let mut group_index = -1
  for index, header in headers {
    if header == spec.run_id_column {
      group_index = index
    }
  }
  if group_index < 0 {
    raise InvalidInput(
      "map run ID to an existing CSV header: \{spec.run_id_column}",
    )
  }
  for index = 1; index < rows.length(); index = index + 1 {
    let row = rows[index]
    let key = row[group_index]
    guard by_id.get(key) is Some(run_index) else {
      raise InvalidInput(
        "CSV record \{index + 1}, column \{spec.run_id_column}: no exact run context for \{key}",
      )
    }
    samples[run_index].push(csv_sample(row, index + 1, names, indices))
  }
  let result : Array[Evidence] = []
  for index, run in spec.runs {
    if samples[index].is_empty() {
      raise InvalidInput(
        "grouped CSV context has no observations: \{run.run_id}",
      )
    }
    let single : CsvImportSpec = {
      schema_version: 1,
      run_id: run.run_id,
      profile: run.profile,
      model_digest: run.model_digest,
      runtime_digest: run.runtime_digest,
      hardware_profile: run.hardware_profile,
      kind: run.kind,
      concurrency: run.concurrency,
      metadata: run.metadata,
      columns: spec.columns,
    }
    result.push(csv_evidence(single, samples[index]))
  }
  // Reuse the existing evidence contract, bounds and deep-copy boundary.
  import_evidence(ToJson::to_json(result).stringify())
}

///|
pub extend CsvRunContext with Eq::{equal, not_equal}

///|
pub extend CsvRunContext with ToJson::{to_json}

///|
pub extend CsvRunContext with FromJson::{from_json}

///|
pub extend GroupedCsvImportSpec with Eq::{equal, not_equal}

///|
pub extend GroupedCsvImportSpec with ToJson::{to_json}

///|
pub extend GroupedCsvImportSpec with FromJson::{from_json}
