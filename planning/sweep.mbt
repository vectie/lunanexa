///|
/// An explicit coverage target, not an instruction to execute a benchmark.
pub(all) struct SweepTarget {
  tested_concurrency : Int
  memory_total_mib : Int
  expected_repeats : Int
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct SweepPlan {
  schema_version : Int
  targets : Array[SweepTarget]
} derive(Eq, ToJson, FromJson)

///|
/// Range of independently computed per-run statistics, never pooled percentiles.
pub(all) struct SweepRange {
  metric : String
  unit : String
  minimum : Int
  maximum : Int
} derive(Eq, ToJson)

///|
pub(all) struct SweepRun {
  run_id : String
  source_ref : String
  observation_sha256 : String
  summary : @benchmark.BenchmarkSummary
  failed_count : Int
  memory_peak_mib : Int
  exact_count_objective_met : Bool
  meets_declared_envelope : Bool
} derive(Eq, ToJson)

///|
/// Empty runs/ranges mean no observation, never zero latency or zero failures.
pub(all) struct SweepGroup {
  tested_concurrency : Int
  memory_total_mib : Int
  expected_repeats : Int?
  observed_repeats : Int
  missing_repeats : Int?
  coverage : String
  objective_met_runs : Int
  envelope_met_runs : Int
  sample_count : Int
  failed_count : Int
  ranges : Array[SweepRange]
  runs : Array[SweepRun]
} derive(Eq, ToJson)

///|
/// Read-only projection; keep the packet and plan for raw samples and reproduction.
pub(all) struct SweepReport {
  schema_version : String
  packet_id : String
  plan : SweepPlan
  origin : Origin
  workload : Workload
  objective : @benchmark.ServiceObjective
  interpretation : String
  groups : Array[SweepGroup]
} derive(Eq, ToJson)

///|
fn validate_sweep_plan(plan : SweepPlan) -> Unit raise PlanningError {
  if plan.schema_version != 1 || plan.targets.length() > 8 {
    raise InvalidInput("sweep plan requires version 1 and at most 8 targets")
  }
  let seen : Map[String, Bool] = Map([])
  for target in plan.targets {
    if target.tested_concurrency < 1 ||
      target.tested_concurrency > 1024 ||
      target.memory_total_mib <= 0 ||
      target.expected_repeats < 1 ||
      target.expected_repeats > 8 {
      raise InvalidInput(
        "sweep targets require concurrency 1..1024, positive total memory and expected repeats 1..8",
      )
    }
    let key = "\{target.tested_concurrency}:\{target.memory_total_mib}"
    if seen.contains(key) {
      raise InvalidInput(
        "duplicate sweep target concurrency and total-memory pair",
      )
    }
    seen[key] = true
  }
}

///|
pub fn import_sweep_plan(text : String) -> SweepPlan raise PlanningError {
  if text.length() > 65536 {
    raise InvalidInput("sweep plan exceeds the 64 Ki-character limit")
  }
  let parsed = @json.parse(text) catch {
    _ => raise InvalidInput("invalid sweep plan JSON")
  }
  let plan : SweepPlan = @json.from_json(parsed) catch {
    _ => raise InvalidInput("invalid sweep plan JSON")
  }
  if ToJson::to_json(plan) != parsed {
    raise InvalidInput("sweep plan contains unsupported fields")
  }
  validate_sweep_plan(plan)
  plan
}

///|
fn sweep_ranges(runs : Array[SweepRun]) -> Array[SweepRange] {
  if runs.is_empty() {
    return []
  }
  let fields : Array[(String, String, (SweepRun) -> Int)] = [
    ("latency_p50_ms", "ms", r => r.summary.latency_p50_ms),
    ("latency_p95_ms", "ms", r => r.summary.latency_p95_ms),
    ("latency_p99_ms", "ms", r => r.summary.latency_p99_ms),
    ("queue_p95_ms", "ms", r => r.summary.queue_p95_ms),
    ("first_output_p95_ms", "ms", r => r.summary.first_output_p95_ms),
    (
      "throughput_units_per_second",
      "output_units/s",
      r => r.summary.throughput_units_per_second,
    ),
    ("memory_peak_mib", "MiB", r => r.memory_peak_mib),
  ]
  fields.map(field => {
    let (metric, unit, value) = field
    let minimum = runs.fold(init=value(runs[0]), (n, r) => n.min(value(r)))
    let maximum = runs.fold(init=value(runs[0]), (n, r) => n.max(value(r)))
    { metric, unit, minimum, maximum, }
  })
}

///|
/// Account for every planned level and every observation. The existing packet
/// verifier enforces exact workload/model/runtime/hardware/kind/unit/origin.
/// A total-memory change forms another group, even with the same hardware label.
pub fn explore_sweep(
  packet : Packet,
  plan : SweepPlan,
) -> SweepReport raise PlanningError {
  validate_sweep_plan(plan)
  let packet = reopen(packet.export_json())
  // Copy targets to avoid sharing the caller's mutable array with the report.
  let plan = import_sweep_plan(ToJson::to_json(plan).stringify())
  let keys : Array[(Int, Int)] = plan.targets.map(t => {
    (t.tested_concurrency, t.memory_total_mib)
  })
  for evidence in packet.input.evidence {
    let key = (evidence.run.concurrency, evidence.memory_total_mib)
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  keys.sort_by((a, b) => {
    let concurrency = a.0.compare(b.0)
    if concurrency == 0 {
      a.1.compare(b.1)
    } else {
      concurrency
    }
  })
  let groups : Array[SweepGroup] = []
  for (tested_concurrency, memory_total_mib) in keys {
    let target = plan.targets
      .iter()
      .find_first(t => {
        t.tested_concurrency == tested_concurrency &&
        t.memory_total_mib == memory_total_mib
      })
    let expected_repeats = target.map(t => t.expected_repeats)
    let runs : Array[SweepRun] = []
    for i, evidence in packet.input.evidence {
      if evidence.run.concurrency == tested_concurrency &&
        evidence.memory_total_mib == memory_total_mib {
        let choice = packet.choices[i]
        runs.push({
          run_id: evidence.run.run_id,
          source_ref: evidence.source_ref,
          observation_sha256: observation_digest(evidence.run),
          summary: choice.recommendation.summary,
          failed_count: observed_failure_count(evidence),
          memory_peak_mib: evidence.memory_peak_mib,
          exact_count_objective_met: observed_objective_met(
            evidence,
            choice.recommendation,
          ),
          meets_declared_envelope: choice.meets_declared_envelope,
        })
      }
    }
    runs.sort_by((a, b) => a.run_id.compare(b.run_id))
    let observed_repeats = runs.length()
    let missing_repeats = expected_repeats.map(n => {
      (n - observed_repeats).max(0)
    })
    let coverage = match expected_repeats {
      None => if plan.targets.is_empty() { "unspecified" } else { "unplanned" }
      Some(_) if observed_repeats == 0 => "missing"
      Some(n) if observed_repeats < n => "incomplete"
      Some(_) => "complete"
    }
    groups.push({
      tested_concurrency,
      memory_total_mib,
      expected_repeats,
      observed_repeats,
      missing_repeats,
      coverage,
      objective_met_runs: runs.filter(r => r.exact_count_objective_met).length(),
      envelope_met_runs: runs.filter(r => r.meets_declared_envelope).length(),
      sample_count: runs.fold(init=0, (n, r) => n + r.summary.sample_count),
      failed_count: runs.fold(init=0, (n, r) => n + r.failed_count),
      ranges: sweep_ranges(runs),
      runs,
    })
  }
  {
    schema_version: "lunanexa.benchmark-sweep.v1",
    packet_id: packet.packet_id,
    plan,
    origin: packet.input.evidence[0].origin,
    workload: packet.input.workload,
    objective: packet.input.objective,
    interpretation: "Observed independent runs only. Ranges describe per-run statistics, not pooled percentiles or confidence intervals. Throughput is sum(output units)/sum(sample durations) within each run, not fleet throughput. Complete means the declared repeat count was reached, not that objectives passed. Missing observations have no metric ranges. No production capacity, SLA, model quality, causal attribution or measurement authentication is established.",
    groups,
  }
}

///|
/// One row per planned/observed group. Missing metrics are empty, never zero.
/// JSON arrays in the final columns preserve unambiguous per-run traceability.
pub fn sweep_csv(
  packet : Packet,
  plan : SweepPlan,
) -> String raise PlanningError {
  let report = explore_sweep(packet, plan)
  let w = report.workload
  let o = report.objective
  let lines = [
    "packet_id,origin,profile,model_digest,runtime_digest,hardware_profile,kind,workload_ref,output_unit,maximum_p95_ms,minimum_throughput_units_per_second,maximum_failure_per_mille,minimum_tested_concurrency,tested_concurrency,memory_total_mib,expected_repeats,observed_repeats,missing_repeats,coverage,objective_met_runs,envelope_met_runs,sample_count,failed_count,latency_p50_ms_min,latency_p50_ms_max,latency_p95_ms_min,latency_p95_ms_max,latency_p99_ms_min,latency_p99_ms_max,queue_p95_ms_min,queue_p95_ms_max,first_output_p95_ms_min,first_output_p95_ms_max,throughput_units_per_second_min,throughput_units_per_second_max,memory_peak_mib_min,memory_peak_mib_max,run_ids_json,source_refs_json,observation_hashes_json",
  ]
  for group in report.groups {
    let row = [
      csv_text(report.packet_id),
      csv_text("\{Repr(report.origin)}"),
      csv_text(w.profile),
      csv_text(w.model_digest),
      csv_text(w.runtime_digest),
      csv_text(w.hardware_profile),
      csv_text("\{Repr(w.kind)}"),
      csv_text(w.workload_ref),
      csv_text(w.output_unit),
      "\{o.maximum_p95_ms}",
      "\{o.minimum_throughput_units_per_second}",
      "\{o.maximum_failure_per_mille}",
      "\{w.minimum_tested_concurrency}",
      "\{group.tested_concurrency}",
      "\{group.memory_total_mib}",
      group.expected_repeats.map(n => n.to_string()).unwrap_or(""),
      "\{group.observed_repeats}",
      group.missing_repeats.map(n => n.to_string()).unwrap_or(""),
      csv_text(group.coverage),
      "\{group.objective_met_runs}",
      "\{group.envelope_met_runs}",
      "\{group.sample_count}",
      "\{group.failed_count}",
    ]
    if group.ranges.is_empty() {
      for _ in 0..<14 {
        row.push("")
      }
    } else {
      for range in group.ranges {
        row.push("\{range.minimum}")
        row.push("\{range.maximum}")
      }
    }
    row.push(
      csv_text(ToJson::to_json(group.runs.map(r => r.run_id)).stringify()),
    )
    row.push(
      csv_text(ToJson::to_json(group.runs.map(r => r.source_ref)).stringify()),
    )
    row.push(
      csv_text(
        ToJson::to_json(group.runs.map(r => r.observation_sha256)).stringify(),
      ),
    )
    lines.push(row.join(","))
  }
  lines.join("\r\n") + "\r\n"
}

///|
pub extend SweepTarget with Eq::{equal, not_equal}

///|
pub extend SweepTarget with ToJson::{to_json}

///|
pub extend SweepTarget with FromJson::{from_json}

///|
pub extend SweepPlan with Eq::{equal, not_equal}

///|
pub extend SweepPlan with ToJson::{to_json}

///|
pub extend SweepPlan with FromJson::{from_json}

///|
pub extend SweepRange with Eq::{equal, not_equal}

///|
pub extend SweepRange with ToJson::{to_json}

///|
pub extend SweepRun with Eq::{equal, not_equal}

///|
pub extend SweepRun with ToJson::{to_json}

///|
pub extend SweepGroup with Eq::{equal, not_equal}

///|
pub extend SweepGroup with ToJson::{to_json}

///|
pub extend SweepReport with Eq::{equal, not_equal}

///|
pub extend SweepReport with ToJson::{to_json}
