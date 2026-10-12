///|
/// Sorting never alters recorded order; ties retain the original sample index.
pub(all) enum SampleOrder {
  RecordedOrder
  SlowestLatency
  LongestQueue
} derive(Eq)

///|
pub extend SampleOrder with Eq::{equal, not_equal}

///|
/// One-based index in the captured run, stable through filtering and sorting.
pub(all) struct IndexedSample {
  sample_index : Int
  sample : @benchmark.BenchmarkSample
} derive(Eq)

///|
pub extend IndexedSample with Eq::{equal, not_equal}

///|
/// Explore one validated captured run without pooling, editing or remeasuring.
/// Results own a separate array, so sorting cannot mutate evidence or packet IDs.
pub fn explore_samples(
  evidence : Evidence,
  failed_only : Bool,
  order : SampleOrder,
) -> Array[IndexedSample] raise PlanningError {
  validate_evidence(evidence)
  let rows : Array[IndexedSample] = []
  for index, sample in evidence.run.samples {
    if !failed_only || sample.failed {
      rows.push({ sample_index: index + 1, sample, })
    }
  }
  rows.sort_by((a, b) => {
    let comparison = match order {
      RecordedOrder => 0
      SlowestLatency => b.sample.latency_ms.compare(a.sample.latency_ms)
      LongestQueue => b.sample.queue_ms.compare(a.sample.queue_ms)
    }
    if comparison == 0 {
      a.sample_index.compare(b.sample_index)
    } else {
      comparison
    }
  })
  rows
}

///|
// CSV is a spreadsheet presentation. Preserve authoritative strings in JSON;
// prefix formula-like text cells with an apostrophe before RFC 4180 quoting.
fn csv_text(value : String) -> String {
  let trimmed = value.trim()
  let safe_text = if trimmed.has_prefix("=") ||
    trimmed.has_prefix("+") ||
    trimmed.has_prefix("-") ||
    trimmed.has_prefix("@") ||
    value.has_prefix("\t") ||
    value.has_prefix("\r") ||
    value.has_prefix("\n") {
    "'" + value
  } else {
    value
  }
  "\"" + safe_text.replace_all(old="\"", new="\"\"") + "\""
}

///|
/// Export every matching sample, with its original index and canonical run hash.
/// The filter affects this CSV only, never the run summary or service objective.
pub fn samples_csv(
  evidence : Evidence,
  failed_only : Bool,
  order : SampleOrder,
) -> String raise PlanningError {
  let rows = explore_samples(evidence, failed_only, order)
  let lines = [
    "run_id,origin,observation_sha256,output_unit,sample_index,latency_ms,queue_ms,load_ms,first_output_ms,output_units,duration_ms,utilization_per_mille,failed",
  ]
  let identity = csv_text(evidence.run.run_id) +
    "," +
    csv_text("\{Repr(evidence.origin)}") +
    "," +
    csv_text(observation_digest(evidence.run)) +
    "," +
    csv_text(evidence.output_unit)
  for row in rows {
    let s = row.sample
    lines.push(
      identity +
      ",\{row.sample_index},\{s.latency_ms},\{s.queue_ms},\{s.load_ms},\{s.first_output_ms},\{s.output_units},\{s.duration_ms},\{s.utilization_per_mille},\{s.failed}",
    )
  }
  lines.join("\r\n") + "\r\n"
}

///|
/// Export one row per verified run, retaining context and exact-count outcomes.
/// This projection is not a reopenable packet or a production qualification.
pub fn Packet::summary_csv(self : Packet) -> String raise PlanningError {
  if prepare(self.input) != self {
    raise InvalidInput("CSV requires a verified planning packet")
  }
  let lines = [
    "packet_id,run_id,origin,source_ref,observation_sha256,profile,model_digest,runtime_digest,hardware_profile,kind,workload_ref,output_unit,sample_count,failed_count,failure_per_mille_rounded,tested_concurrency,suggested_concurrency_untested,latency_p50_ms,latency_p95_ms,latency_p99_ms,queue_p95_ms,first_output_p95_ms,throughput_units_per_second,peak_utilization_per_mille,memory_total_mib,memory_peak_mib,memory_headroom_mib,maximum_p95_ms,minimum_throughput_units_per_second,maximum_failure_per_mille,minimum_tested_concurrency,exact_count_objective_met,meets_declared_envelope",
  ]
  for index, choice in self.choices {
    let e = self.input.evidence[index]
    let r = choice.recommendation
    let s = r.summary
    let row = [
      csv_text(self.packet_id),
      csv_text(e.run.run_id),
      csv_text("\{Repr(e.origin)}"),
      csv_text(e.source_ref),
      csv_text(observation_digest(e.run)),
      csv_text(e.run.profile),
      csv_text(e.run.model_digest),
      csv_text(e.run.runtime_digest),
      csv_text(e.run.hardware_profile),
      csv_text("\{Repr(e.run.kind)}"),
      csv_text(e.workload_ref),
      csv_text(e.output_unit),
      "\{s.sample_count}",
      "\{observed_failure_count(e)}",
      "\{s.failure_per_mille}",
      "\{e.run.concurrency}",
      "\{r.capacity.recommended_concurrency}",
      "\{s.latency_p50_ms}",
      "\{s.latency_p95_ms}",
      "\{s.latency_p99_ms}",
      "\{s.queue_p95_ms}",
      "\{s.first_output_p95_ms}",
      "\{s.throughput_units_per_second}",
      "\{s.peak_utilization_per_mille}",
      "\{e.memory_total_mib}",
      "\{e.memory_peak_mib}",
      "\{r.capacity.memory_headroom_mib}",
      "\{r.objective.maximum_p95_ms}",
      "\{r.objective.minimum_throughput_units_per_second}",
      "\{r.objective.maximum_failure_per_mille}",
      "\{self.input.workload.minimum_tested_concurrency}",
      "\{observed_objective_met(e, r)}",
      "\{choice.meets_declared_envelope}",
    ]
    lines.push(row.join(","))
  }
  lines.join("\r\n") + "\r\n"
}
