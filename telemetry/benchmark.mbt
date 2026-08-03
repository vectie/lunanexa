///|
pub(all) enum BenchmarkKind {
  Concurrency
  Saturation
  ColdStart
  LongStream
  MixedWorkload
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BenchmarkSample {
  latency_ms : Int
  queue_ms : Int
  load_ms : Int
  first_output_ms : Int
  output_units : Int
  duration_ms : Int
  utilization_per_mille : Int
  failed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BenchmarkRun {
  run_id : String
  profile : String
  model_digest : String
  runtime_digest : String
  hardware_profile : String
  kind : BenchmarkKind
  concurrency : Int
  samples : Array[BenchmarkSample]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BenchmarkSummary {
  run_id : String
  profile : String
  sample_count : Int
  latency_p50_ms : Int
  latency_p95_ms : Int
  latency_p99_ms : Int
  queue_p95_ms : Int
  first_output_p95_ms : Int
  throughput_units_per_second : Int
  failure_per_mille : Int
  peak_utilization_per_mille : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror BenchmarkError {
  EmptyRun
  InvalidDuration
  InvalidEvidence(String)
} derive(Debug, Eq)

///|
fn percentile(values : Array[Int], percentage : Int) -> Int {
  let sorted = values.copy()
  sorted.sort()
  let index = ((sorted.length() - 1) * percentage + 99) / 100
  sorted[index]
}

///|
pub fn summarize(run : BenchmarkRun) -> BenchmarkSummary raise BenchmarkError {
  if run.samples.length() == 0 {
    raise EmptyRun
  }
  let latencies = [ for sample in run.samples => sample.latency_ms ]
  let queues = [ for sample in run.samples => sample.queue_ms ]
  let first_outputs = [ for sample in run.samples => sample.first_output_ms ]
  let mut total_units = 0
  let mut total_duration = 0
  let mut failures = 0
  let mut peak_utilization = 0
  for sample in run.samples {
    if sample.duration_ms <= 0 {
      raise InvalidDuration
    }
    total_units += sample.output_units
    total_duration += sample.duration_ms
    if sample.failed {
      failures += 1
    }
    peak_utilization = peak_utilization.max(sample.utilization_per_mille)
  }
  {
    run_id: run.run_id,
    profile: run.profile,
    sample_count: run.samples.length(),
    latency_p50_ms: percentile(latencies, 50),
    latency_p95_ms: percentile(latencies, 95),
    latency_p99_ms: percentile(latencies, 99),
    queue_p95_ms: percentile(queues, 95),
    first_output_p95_ms: percentile(first_outputs, 95),
    throughput_units_per_second: total_units * 1000 / total_duration,
    failure_per_mille: failures * 1000 / run.samples.length(),
    peak_utilization_per_mille: peak_utilization,
  }
}

///|
pub(all) struct ServiceObjective {
  profile : String
  maximum_p95_ms : Int
  minimum_throughput_units_per_second : Int
  maximum_failure_per_mille : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn meets_objective(
  summary : BenchmarkSummary,
  objective : ServiceObjective,
) -> Bool {
  summary.profile == objective.profile &&
  summary.latency_p95_ms <= objective.maximum_p95_ms &&
  summary.throughput_units_per_second >=
  objective.minimum_throughput_units_per_second &&
  summary.failure_per_mille <= objective.maximum_failure_per_mille
}

///|
pub(all) struct CapacityRecommendation {
  profile : String
  recommended_concurrency : Int
  memory_headroom_mib : Int
  evidence_run_id : String
  statement : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn recommend_capacity(
  summary : BenchmarkSummary,
  tested_concurrency : Int,
  memory_total_mib : Int,
  memory_peak_mib : Int,
) -> CapacityRecommendation {
  {
    profile: summary.profile,
    recommended_concurrency: if summary.failure_per_mille == 0 {
      tested_concurrency
    } else {
      (tested_concurrency - 1).max(1)
    },
    memory_headroom_mib: (memory_total_mib - memory_peak_mib).max(0),
    evidence_run_id: summary.run_id,
    statement: "Evidence from \{summary.run_id}; remeasure after model, runtime, driver, or hardware changes.",
  }
}

///|
pub(all) struct EvidenceBundle {
  release_version : String
  benchmark_summaries : Array[BenchmarkSummary]
  scenario_passed : Bool
  isolation_scan_passed : Bool
  security_report_ref : String
  operations_report_ref : String
  license_report_ref : String
  accepted_by : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceBundleInput {
  release_version : String
  scenario_passed : Bool
  isolation_scan_passed : Bool
  security_report_ref : String
  operations_report_ref : String
  license_report_ref : String
  accepted_by : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn build_evidence_bundle(
  summaries : Array[BenchmarkSummary],
  input : EvidenceBundleInput,
) -> EvidenceBundle {
  {
    release_version: input.release_version,
    benchmark_summaries: summaries,
    scenario_passed: input.scenario_passed,
    isolation_scan_passed: input.isolation_scan_passed,
    security_report_ref: input.security_report_ref,
    operations_report_ref: input.operations_report_ref,
    license_report_ref: input.license_report_ref,
    accepted_by: input.accepted_by,
  }
}

///|
pub(all) struct RecommendationInput {
  run_id : String
  objective : ServiceObjective
  tested_concurrency : Int
  memory_total_mib : Int
  memory_peak_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RecommendationEvidence {
  summary : BenchmarkSummary
  objective : ServiceObjective
  objective_met : Bool
  capacity : CapacityRecommendation
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn build_recommendation(
  summaries : Array[BenchmarkSummary],
  input : RecommendationInput,
) -> RecommendationEvidence raise BenchmarkError {
  let mut selected : BenchmarkSummary? = None
  for summary in summaries {
    if summary.run_id == input.run_id {
      selected = Some(summary)
    }
  }
  guard selected is Some(summary) else {
    raise InvalidEvidence("benchmark run was not found")
  }
  if input.tested_concurrency <= 0 ||
    input.memory_total_mib <= 0 ||
    input.memory_peak_mib <= 0 ||
    input.memory_peak_mib > input.memory_total_mib {
    raise InvalidEvidence("capacity inputs are invalid")
  }
  {
    summary,
    objective: input.objective,
    objective_met: meets_objective(summary, input.objective),
    capacity: recommend_capacity(
      summary,
      input.tested_concurrency,
      input.memory_total_mib,
      input.memory_peak_mib,
    ),
  }
}

///|
pub fn EvidenceBundle::release_ready(self : EvidenceBundle) -> Bool {
  self.benchmark_summaries.length() > 0 &&
  self.scenario_passed &&
  self.isolation_scan_passed &&
  self.security_report_ref != "" &&
  self.operations_report_ref != "" &&
  self.license_report_ref != "" &&
  self.accepted_by is Some(name) &&
  name != ""
}

///|
pub fn EvidenceBundle::export_json(self : EvidenceBundle) -> String {
  self.to_json().stringify(indent=2)
}
