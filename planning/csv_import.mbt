///|
/// Exact header names for all eight observed metrics. Units are never inferred.
pub(all) struct CsvColumns {
  latency_ms : String
  queue_ms : String
  load_ms : String
  first_output_ms : String
  output_units : String
  duration_ms : String
  utilization_per_mille : String
  failed : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct CsvImportSpec {
  schema_version : Int
  run_id : String
  profile : String
  model_digest : String
  runtime_digest : String
  hardware_profile : String
  kind : @benchmark.BenchmarkKind
  concurrency : Int
  metadata : RecordedMetadata
  columns : CsvColumns
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct CsvPreview {
  headers : Array[String]
  sample_count : Int
  first_rows : Array[Array[String]]
} derive(Eq)

///|
fn csv_rows(text : String) -> Array[Array[String]] raise PlanningError {
  if text.length() > 4194304 {
    raise InvalidInput("CSV exceeds the 4 Mi-character limit")
  }
  let chars = text.iter().collect()
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let cell = StringBuilder()
  let mut quoted = false
  let mut closed = false
  let mut started = false
  let mut index = if chars.get(0) == Some('\uFEFF') { 1 } else { 0 }
  while index < chars.length() {
    let ch = chars[index]
    if quoted {
      if ch == '"' {
        if chars.get(index + 1) == Some('"') {
          cell.write_char('"')
          index += 1
        } else {
          quoted = false
          closed = true
        }
      } else {
        cell.write_char(ch)
      }
    } else if ch == ',' || ch == '\n' || ch == '\r' {
      row.push(cell.to_string())
      cell.reset()
      if row.length() > 128 {
        raise InvalidInput("CSV supports at most 128 columns")
      }
      closed = false
      started = false
      if ch != ',' {
        rows.push(row)
        row = []
        if rows.length() > 10001 {
          raise InvalidInput("CSV supports at most 10000 sample records")
        }
        if ch == '\r' && chars.get(index + 1) == Some('\n') {
          index += 1
        }
      }
    } else if ch == '"' && !started && !closed {
      quoted = true
      started = true
    } else {
      if ch == '"' || closed {
        raise InvalidInput("CSV record \{rows.length() + 1}: invalid quote")
      }
      started = true
      cell.write_char(ch)
    }
    index += 1
  }
  if quoted {
    raise InvalidInput("CSV has an unterminated quoted field")
  }
  if started || closed || !row.is_empty() {
    row.push(cell.to_string())
    rows.push(row)
  }
  if rows.length() < 2 || rows.length() > 10001 {
    raise InvalidInput("CSV requires a header and 1..10000 sample records")
  }
  let headers = rows[0].map(s => s.trim().to_owned())
  if headers.length() > 128 {
    raise InvalidInput("CSV supports at most 128 columns")
  }
  let seen : Map[String, Bool] = Map([])
  for header in headers {
    require_text(header, "CSV header")
    if seen.contains(header) {
      raise InvalidInput("CSV headers must be unique")
    }
    seen[header] = true
  }
  rows[0] = headers
  for index = 1; index < rows.length(); index = index + 1 {
    if rows[index].length() != headers.length() {
      raise InvalidInput(
        "CSV record \{index + 1}: column count differs from header",
      )
    }
  }
  rows
}

///|
/// Preview is bounded to five records; import validates every sample record.
pub fn preview_csv(text : String) -> CsvPreview raise PlanningError {
  let rows = csv_rows(text)
  {
    headers: rows[0],
    sample_count: rows.length() - 1,
    first_rows: rows[1:if rows.length() < 6 { rows.length() } else { 6 }].to_owned(),
  }
}

///|
pub fn csv_column_names(columns : CsvColumns) -> Array[String] {
  [
    columns.latency_ms,
    columns.queue_ms,
    columns.load_ms,
    columns.first_output_ms,
    columns.output_units,
    columns.duration_ms,
    columns.utilization_per_mille,
    columns.failed,
  ]
}

///|
fn csv_integer(
  value : String,
  record : Int,
  header : String,
) -> Int raise PlanningError {
  let text = value.trim()
  if text.is_empty() || !text.iter().all(c => c >= '0' && c <= '9') {
    raise InvalidInput(
      "CSV record \{record}, column \{header}: expected nonnegative whole decimal integer",
    )
  }
  @string.parse_int(text, base=10) catch {
    _ =>
      raise InvalidInput(
        "CSV record \{record}, column \{header}: integer exceeds supported range",
      )
  }
}

///|
pub fn import_csv_spec(text : String) -> CsvImportSpec raise PlanningError {
  if text.length() > 65536 {
    raise InvalidInput("CSV mapping exceeds 64 Ki characters")
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidInput("invalid CSV mapping JSON")
  }
  let spec : CsvImportSpec = @json.from_json(json) catch {
    _ => raise InvalidInput("invalid CSV mapping JSON")
  }
  if spec.schema_version != 1 || ToJson::to_json(spec) != json {
    raise InvalidInput("CSV mapping has an unsupported version or fields")
  }
  spec
}

///|
fn csv_metric_indices(
  headers : Array[String],
  columns : CsvColumns,
) -> Array[Int] raise PlanningError {
  let names = csv_column_names(columns)
  let indices : Array[Int] = []
  let used : Map[String, Bool] = Map([])
  for name in names {
    if used.contains(name) {
      raise InvalidInput("each metric must map to a different CSV column")
    }
    used[name] = true
    let mut found = -1
    for index, header in headers {
      if header == name {
        found = index
      }
    }
    if found < 0 {
      raise InvalidInput("map every metric to an existing CSV header: \{name}")
    }
    indices.push(found)
  }
  indices
}

///|
fn csv_sample(
  row : Array[String],
  record : Int,
  names : Array[String],
  indices : Array[Int],
) -> @benchmark.BenchmarkSample raise PlanningError {
  let values : Array[Int] = []
  for metric = 0; metric < 7; metric = metric + 1 {
    values.push(csv_integer(row[indices[metric]], record, names[metric]))
  }
  let failed = match row[indices[7]].trim() {
    "true" | "TRUE" | "1" => true
    "false" | "FALSE" | "0" => false
    _ =>
      raise InvalidInput(
        "CSV record \{record}, column \{names[7]}: expected true/false or 1/0 failure flag",
      )
  }
  if values[5] == 0 || values[6] > 1000 {
    raise InvalidInput(
      "CSV record \{record}: duration must be positive and utilization must be 0..1000 per mille",
    )
  }
  {
    latency_ms: values[0],
    queue_ms: values[1],
    load_ms: values[2],
    first_output_ms: values[3],
    output_units: values[4],
    duration_ms: values[5],
    utilization_per_mille: values[6],
    failed,
  }
}

///|
/// One CSV is one explicitly described run. No rows are skipped, rounded,
/// pooled or interpreted as aggregate statistics. Unmapped columns are omitted.
pub fn import_csv(
  text : String,
  spec : CsvImportSpec,
) -> Evidence raise PlanningError {
  if spec.schema_version != 1 {
    raise InvalidInput("unsupported CSV mapping version")
  }
  let rows = csv_rows(text)
  let headers = rows[0]
  let names = csv_column_names(spec.columns)
  let indices = csv_metric_indices(headers, spec.columns)
  let samples : Array[@benchmark.BenchmarkSample] = []
  for index = 1; index < rows.length(); index = index + 1 {
    samples.push(csv_sample(rows[index], index + 1, names, indices))
  }
  csv_evidence(spec, samples)
}

///|
fn csv_evidence(
  spec : CsvImportSpec,
  samples : Array[@benchmark.BenchmarkSample],
) -> Evidence raise PlanningError {
  let m = spec.metadata
  let evidence : Evidence = {
    run: {
      run_id: spec.run_id,
      profile: spec.profile,
      model_digest: spec.model_digest,
      runtime_digest: spec.runtime_digest,
      hardware_profile: spec.hardware_profile,
      kind: spec.kind,
      concurrency: spec.concurrency,
      samples,
    },
    origin: m.origin,
    source_ref: m.source_ref,
    workload_ref: m.workload_ref,
    output_unit: m.output_unit,
    memory_total_mib: m.memory_total_mib,
    memory_peak_mib: m.memory_peak_mib,
  }
  validate_evidence(evidence)
  evidence
}

///|
pub extend CsvColumns with Eq::{equal, not_equal}

///|
pub extend CsvColumns with ToJson::{to_json}

///|
pub extend CsvColumns with FromJson::{from_json}

///|
pub extend CsvImportSpec with Eq::{equal, not_equal}

///|
pub extend CsvImportSpec with ToJson::{to_json}

///|
pub extend CsvImportSpec with FromJson::{from_json}

///|
pub extend CsvPreview with Eq::{equal, not_equal}
