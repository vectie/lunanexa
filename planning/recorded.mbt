///|
/// Missing measurement context must be explicitly declared, never inferred from
/// a telemetry summary, node counters, run name or apparent hardware identity.
pub(all) struct RecordedMetadata {
  origin : Origin
  source_ref : String
  workload_ref : String
  output_unit : String
  memory_total_mib : Int
  memory_peak_mib : Int
} derive(Eq, ToJson, FromJson)

///|
pub extend RecordedMetadata with Eq::{equal, not_equal}

///|
pub extend RecordedMetadata with ToJson::{to_json}

///|
pub extend RecordedMetadata with FromJson::{from_json}

///|
pub fn observation_digest(run : @benchmark.BenchmarkRun) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode(ToJson::to_json(run).stringify()).to_fixedarray(),
    ),
  )
}

///|
pub fn snapshot_digest(runs : Array[@benchmark.BenchmarkRun]) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode(ToJson::to_json(runs).stringify()).to_fixedarray(),
    ),
  )
}

///|
fn valid_digest(text : String) -> Bool {
  text.length() == 64 &&
  text.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
}

///|
fn validate_recorded_reference(evidence : Evidence) -> Unit raise PlanningError {
  let source = evidence.source_ref
  if !source.has_prefix("recorded-v1:sha256:") {
    return
  }
  let prefix = "recorded-v1:sha256:" +
    observation_digest(evidence.run) +
    ":snapshot:"
  if !source.has_prefix(prefix) || source.length() <= prefix.length() + 72 {
    raise InvalidInput(
      "recorded source reference does not match the exact raw run",
    )
  }
  let tail = source[prefix.length():].to_owned()
  if !valid_digest(tail[:64].to_owned()) ||
    tail[64:72] != ":source:" ||
    tail[72:].trim().is_empty() {
    raise InvalidInput("invalid recorded snapshot or source reference")
  }
}

///|
/// Preserve both the canonical raw-run and observed raw-run-list identities in
/// the existing v1 packet source reference. The full selected raw run remains
/// in Evidence. These content hashes are reproducibility checks, not signatures.
pub fn recorded_evidence(
  run : @benchmark.BenchmarkRun,
  observed_snapshot_digest : String,
  metadata : RecordedMetadata,
) -> Evidence raise PlanningError {
  require_text(metadata.source_ref, "operator source reference")
  if !valid_digest(observed_snapshot_digest) {
    raise InvalidInput("invalid observed benchmark snapshot digest")
  }
  let evidence : Evidence = {
    run,
    origin: metadata.origin,
    source_ref: "recorded-v1:sha256:" +
    observation_digest(run) +
    ":snapshot:" +
    observed_snapshot_digest +
    ":source:" +
    metadata.source_ref,
    workload_ref: metadata.workload_ref,
    output_unit: metadata.output_unit,
    memory_total_mib: metadata.memory_total_mib,
    memory_peak_mib: metadata.memory_peak_mib,
  }
  validate_evidence(evidence)
  // Use the ordinary strict evidence importer to isolate mutable sample arrays.
  import_evidence(ToJson::to_json([evidence]).stringify())[0]
}
