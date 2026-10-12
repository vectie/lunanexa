///|
/// Operator-declared evidence origin, never a production qualification claim.
pub(all) enum Origin {
  SyntheticFixture
  LocalObservation
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Evidence {
  run : @benchmark.BenchmarkRun
  origin : Origin
  source_ref : String
  workload_ref : String
  output_unit : String
  memory_total_mib : Int
  memory_peak_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Matching is exact, including workload and unit. No unrelated runs are pooled.
pub(all) struct Workload {
  profile : String
  model_digest : String
  runtime_digest : String
  hardware_profile : String
  kind : @benchmark.BenchmarkKind
  workload_ref : String
  output_unit : String
  minimum_tested_concurrency : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Input {
  schema_version : Int
  workload : Workload
  objective : @benchmark.ServiceObjective
  evidence : Array[Evidence]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Choice {
  run_id : String
  tested_concurrency : Int
  origin : Origin
  source_ref : String
  recommendation : @benchmark.RecommendationEvidence
  meets_declared_envelope : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// This is a reproducible decision-support artifact, never an allocation.
pub(all) struct Packet {
  schema_version : Int
  packet_id : String
  input : Input
  choices : Array[Choice]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror PlanningError {
  InvalidInput(String)
} derive(Debug, Eq)

///|
fn require_text(value : String, field : String) -> Unit raise PlanningError {
  if value.trim().is_empty() || value.length() > 512 {
    raise InvalidInput(
      "\{field} is required and must be at most 512 characters",
    )
  }
}

///|
/// Validate bounds before calling the historical Int-based summary algorithm.
pub fn validate_evidence(evidence : Evidence) -> Unit raise PlanningError {
  let run = evidence.run
  validate_recorded_reference(evidence)
  for
    (label, value) in [
      ("run_id", run.run_id),
      ("profile", run.profile),
      ("model_digest", run.model_digest),
      ("runtime_digest", run.runtime_digest),
      ("hardware_profile", run.hardware_profile),
      ("source_ref", evidence.source_ref),
      ("workload_ref", evidence.workload_ref),
      ("output_unit", evidence.output_unit),
    ] {
    require_text(value, label)
  }
  if run.concurrency <= 0 || run.concurrency > 1024 {
    raise InvalidInput("tested concurrency must be between 1 and 1024")
  }
  if run.samples.is_empty() || run.samples.length() > 10000 {
    raise InvalidInput("a run requires between 1 and 10000 samples")
  }
  if evidence.memory_total_mib <= 0 ||
    evidence.memory_peak_mib <= 0 ||
    evidence.memory_peak_mib > evidence.memory_total_mib {
    raise InvalidInput(
      "measured memory must be positive and peak must not exceed total",
    )
  }
  let mut units = 0L
  let mut duration = 0L
  for sample in run.samples {
    if sample.duration_ms <= 0 {
      raise InvalidInput("sample duration_ms must be positive")
    }
    if sample.latency_ms < 0 ||
      sample.queue_ms < 0 ||
      sample.load_ms < 0 ||
      sample.first_output_ms < 0 ||
      sample.output_units < 0 ||
      sample.utilization_per_mille < 0 ||
      sample.utilization_per_mille > 1000 {
      raise InvalidInput(
        "sample metrics must be nonnegative; utilization must be 0..1000",
      )
    }
    units += sample.output_units.to_int64()
    duration += sample.duration_ms.to_int64()
  }
  if units * 1000L > 2147483647L || duration > 2147483647L {
    raise InvalidInput(
      "run exceeds the existing summary arithmetic bounds; split the run",
    )
  }
}

///|
pub fn compatible(evidence : Evidence, workload : Workload) -> Bool {
  let run = evidence.run
  run.profile == workload.profile &&
  run.model_digest == workload.model_digest &&
  run.runtime_digest == workload.runtime_digest &&
  run.hardware_profile == workload.hardware_profile &&
  run.kind == workload.kind &&
  evidence.workload_ref == workload.workload_ref &&
  evidence.output_unit == workload.output_unit
}

///|
/// Actual failed sample count, before the legacy per-mille integer rounding.
pub fn observed_failure_count(evidence : Evidence) -> Int {
  evidence.run.samples.filter(sample => sample.failed).length()
}

///|
/// The new planner checks the declared failure threshold using exact counts.
/// Historical summary/recommendation fields remain unchanged in the packet.
pub fn observed_objective_met(
  evidence : Evidence,
  recommendation : @benchmark.RecommendationEvidence,
) -> Bool {
  recommendation.objective_met &&
  observed_failure_count(evidence).to_int64() * 1000L <=
  recommendation.objective.maximum_failure_per_mille.to_int64() *
  evidence.run.samples.length().to_int64()
}

///|
/// Exact canonical inputs are hashed; no timestamps, randomness, prices or SLA.
pub fn prepare(input : Input) -> Packet raise PlanningError {
  if input.schema_version != 1 {
    raise InvalidInput("unsupported planning input version")
  }
  let w = input.workload
  for
    (label, value) in [
      ("profile", w.profile),
      ("model_digest", w.model_digest),
      ("runtime_digest", w.runtime_digest),
      ("hardware_profile", w.hardware_profile),
      ("workload_ref", w.workload_ref),
      ("output_unit", w.output_unit),
    ] {
    require_text(value, label)
  }
  if w.minimum_tested_concurrency <= 0 || w.minimum_tested_concurrency > 1024 {
    raise InvalidInput("minimum tested concurrency must be between 1 and 1024")
  }
  let objective = input.objective
  if objective.profile != w.profile ||
    objective.maximum_p95_ms <= 0 ||
    objective.minimum_throughput_units_per_second <= 0 ||
    objective.maximum_failure_per_mille < 0 ||
    objective.maximum_failure_per_mille > 1000 {
    raise InvalidInput(
      "enter a matching objective: positive p95 and throughput; failures 0..1000",
    )
  }
  if input.evidence.is_empty() || input.evidence.length() > 8 {
    raise InvalidInput("select between 1 and 8 evidence runs")
  }
  let seen : Map[String, Bool] = Map([])
  let choices : Array[Choice] = []
  for evidence in input.evidence {
    validate_evidence(evidence)
    if seen.contains(evidence.run.run_id) {
      raise InvalidInput("duplicate evidence run_id")
    }
    seen[evidence.run.run_id] = true
    if evidence.origin != input.evidence[0].origin {
      raise InvalidInput(
        "compare synthetic and local-observation runs in separate packets",
      )
    }
    if !compatible(evidence, w) {
      raise InvalidInput(
        "incompatible run \{evidence.run.run_id}: profile/model/runtime/hardware/kind/workload/unit must match",
      )
    }
    let recommendation = @benchmark.build_recommendation(
      [@benchmark.summarize(evidence.run)],
      {
        run_id: evidence.run.run_id,
        objective,
        tested_concurrency: evidence.run.concurrency,
        memory_total_mib: evidence.memory_total_mib,
        memory_peak_mib: evidence.memory_peak_mib,
      },
    ) catch {
      _ => raise InvalidInput("benchmark summary or recommendation failed")
    }
    choices.push({
      run_id: evidence.run.run_id,
      tested_concurrency: evidence.run.concurrency,
      origin: evidence.origin,
      source_ref: evidence.source_ref,
      recommendation,
      meets_declared_envelope: observed_objective_met(evidence, recommendation) &&
      evidence.run.concurrency >= w.minimum_tested_concurrency,
    })
  }
  let canonical = ToJson::to_json(input).stringify()
  // JSON reconstruction isolates mutable sample arrays from the author's draft.
  let frozen : Input = @json.from_json(@json.parse(canonical)) catch {
    _ => raise InvalidInput("could not freeze planning inputs")
  }
  let packet = {
    schema_version: 1,
    packet_id: "capacity-v1:sha256:" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(canonical).to_fixedarray()),
    ),
    input: frozen,
    choices,
  }
  if packet.export_json().length() > 4194304 {
    raise InvalidInput(
      "prepared packet exceeds the 4 Mi-character reopen limit; select fewer runs",
    )
  }
  packet
}

///|
pub fn Packet::export_json(self : Packet) -> String {
  ToJson::to_json(self).stringify(indent=2)
}

///|
/// Reject altered results and unsupported versions instead of trusting exports.
pub fn reopen(text : String) -> Packet raise PlanningError {
  if text.length() > 4194304 {
    raise InvalidInput(
      "planning packet exceeds the 4 Mi-character import limit",
    )
  }
  let parsed = @json.parse(text) catch {
    _ => raise InvalidInput("invalid planning packet JSON")
  }
  let packet : Packet = @json.from_json(parsed) catch {
    _ => raise InvalidInput("invalid planning packet JSON")
  }
  if ToJson::to_json(packet) != parsed {
    raise InvalidInput("planning packet contains unsupported fields")
  }
  if packet.schema_version != 1 {
    raise InvalidInput("unsupported planning packet version")
  }
  let verified = prepare(packet.input)
  if verified != packet {
    raise InvalidInput(
      "packet identity or recommendation differs from its exact inputs",
    )
  }
  verified
}

///|
pub fn import_evidence(text : String) -> Array[Evidence] raise PlanningError {
  if text.length() > 4194304 {
    raise InvalidInput(
      "benchmark import exceeds the 4 Mi-character import limit",
    )
  }
  let parsed = @json.parse(text) catch {
    _ =>
      raise InvalidInput("expected a JSON array of benchmark evidence records")
  }
  let evidence : Array[Evidence] = @json.from_json(parsed) catch {
    _ =>
      raise InvalidInput("expected a JSON array of benchmark evidence records")
  }
  if ToJson::to_json(evidence) != parsed {
    raise InvalidInput("benchmark evidence contains unsupported fields")
  }
  if evidence.is_empty() || evidence.length() > 8 {
    raise InvalidInput("import between 1 and 8 evidence runs")
  }
  let seen : Map[String, Bool] = Map([])
  for item in evidence {
    validate_evidence(item)
    if seen.contains(item.run.run_id) {
      raise InvalidInput("duplicate evidence run_id")
    }
    seen[item.run.run_id] = true
  }
  evidence
}

///|
/// Decode the offline CLI's exact typed input without discarding future fields.
pub fn import_input(text : String) -> Input raise PlanningError {
  if text.length() > 4194304 {
    raise InvalidInput("planning input exceeds the 4 Mi-character import limit")
  }
  let parsed = @json.parse(text) catch {
    _ => raise InvalidInput("invalid planning input JSON")
  }
  let input : Input = @json.from_json(parsed) catch {
    _ => raise InvalidInput("invalid planning input JSON")
  }
  if ToJson::to_json(input) != parsed {
    raise InvalidInput("planning input contains unsupported fields")
  }
  input
}

///|
pub extend Origin with Debug::{to_repr}

///|
pub extend Origin with Eq::{not_equal, equal}

///|
pub extend Origin with ToJson::{to_json}

///|
pub extend Origin with FromJson::{from_json}

///|
pub extend Evidence with Debug::{to_repr}

///|
pub extend Evidence with Eq::{not_equal, equal}

///|
pub extend Evidence with ToJson::{to_json}

///|
pub extend Evidence with FromJson::{from_json}

///|
pub extend Workload with Debug::{to_repr}

///|
pub extend Workload with Eq::{not_equal, equal}

///|
pub extend Workload with ToJson::{to_json}

///|
pub extend Workload with FromJson::{from_json}

///|
pub extend Input with Debug::{to_repr}

///|
pub extend Input with Eq::{not_equal, equal}

///|
pub extend Input with ToJson::{to_json}

///|
pub extend Input with FromJson::{from_json}

///|
pub extend Choice with Debug::{to_repr}

///|
pub extend Choice with Eq::{not_equal, equal}

///|
pub extend Choice with ToJson::{to_json}

///|
pub extend Choice with FromJson::{from_json}

///|
pub extend Packet with Debug::{to_repr}

///|
pub extend Packet with Eq::{not_equal, equal}

///|
pub extend Packet with ToJson::{to_json}

///|
pub extend Packet with FromJson::{from_json}

///|
pub extend PlanningError with Debug::{to_repr}

///|
pub extend PlanningError with Eq::{not_equal, equal}
