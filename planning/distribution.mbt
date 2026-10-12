///|
/// Every selected metric is a required, validated integer in milliseconds.
pub(all) enum DistributionMetric {
  LatencyMs
  QueueMs
  FirstOutputMs
  LoadMs
  DurationMs
} derive(Eq, ToJson, FromJson)

///|
pub extend DistributionMetric with Eq::{equal, not_equal}

///|
pub extend DistributionMetric with ToJson::{to_json}

///|
pub extend DistributionMetric with FromJson::{from_json}

///|
/// Inclusive upper bounds; an overflow bucket is always added.
pub(all) struct DistributionPlan {
  schema_version : Int
  metric : DistributionMetric
  upper_bounds_ms : Array[Int]
} derive(Eq, ToJson, FromJson)

///|
pub extend DistributionPlan with Eq::{equal, not_equal}

///|
pub extend DistributionPlan with ToJson::{to_json}

///|
pub extend DistributionPlan with FromJson::{from_json}

///|
pub(all) struct DistributionBucket {
  lower_exclusive_ms : Int?
  upper_inclusive_ms : Int?
  sample_count : Int
  succeeded_count : Int
  failed_count : Int
  cumulative_sample_count : Int
  cumulative_succeeded_count : Int
  cumulative_failed_count : Int
} derive(Eq)

///|
pub extend DistributionBucket with Eq::{equal, not_equal}

///|
pub extend DistributionBucket with ToJson::{to_json}

///|
pub impl ToJson for DistributionBucket with fn to_json(
  self : DistributionBucket,
) -> Json {
  {
    "lower_exclusive_ms": match self.lower_exclusive_ms {
      Some(n) => n.to_json()
      None => Json::null()
    },
    "upper_inclusive_ms": match self.upper_inclusive_ms {
      Some(n) => n.to_json()
      None => Json::null()
    },
    "sample_count": self.sample_count.to_json(),
    "succeeded_count": self.succeeded_count.to_json(),
    "failed_count": self.failed_count.to_json(),
    "cumulative_sample_count": self.cumulative_sample_count.to_json(),
    "cumulative_succeeded_count": self.cumulative_succeeded_count.to_json(),
    "cumulative_failed_count": self.cumulative_failed_count.to_json(),
  }
}

///|
/// Derived exploration output; the original packet remains the reopenable evidence.
pub(all) struct DistributionReport {
  schema_version : Int
  packet_id : String
  run_id : String
  observation_sha256 : String
  origin : Origin
  source_ref : String
  workload_ref : String
  profile : String
  model_digest : String
  runtime_digest : String
  hardware_profile : String
  kind : @benchmark.BenchmarkKind
  tested_concurrency : Int
  metric : DistributionMetric
  unit : String
  upper_bounds_ms : Array[Int]
  sample_count : Int
  succeeded_count : Int
  failed_count : Int
  buckets : Array[DistributionBucket]
} derive(ToJson)

///|
pub extend DistributionReport with ToJson::{to_json}

///|
fn validate_distribution_plan(
  plan : DistributionPlan,
) -> Unit raise PlanningError {
  if plan.schema_version != 1 ||
    plan.upper_bounds_ms.is_empty() ||
    plan.upper_bounds_ms.length() > 32 {
    raise InvalidInput(
      "distribution plan v1 requires 1..32 inclusive upper bounds in milliseconds",
    )
  }
  let mut previous = -1
  for bound in plan.upper_bounds_ms {
    if bound < 0 || bound <= previous {
      raise InvalidInput(
        "upper_bounds_ms must be nonnegative, unique and strictly increasing",
      )
    }
    previous = bound
  }
}

///|
pub fn import_distribution_plan(
  text : String,
) -> DistributionPlan raise PlanningError {
  if @utf8.encode(text).length() > 65536 {
    raise InvalidInput("distribution plan exceeds 64 KiB")
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidInput("invalid distribution plan JSON")
  }
  let plan : DistributionPlan = @json.from_json(json) catch {
    _ =>
      raise InvalidInput(
        "expected distribution plan schema_version, metric and upper_bounds_ms",
      )
  }
  if ToJson::to_json(plan) != json {
    raise InvalidInput(
      "distribution plan contains unsupported fields or inexact integers",
    )
  }
  validate_distribution_plan(plan)
  plan
}

///|
fn sample_metric(
  sample : @benchmark.BenchmarkSample,
  metric : DistributionMetric,
) -> Int {
  match metric {
    LatencyMs => sample.latency_ms
    QueueMs => sample.queue_ms
    FirstOutputMs => sample.first_output_ms
    LoadMs => sample.load_ms
    DurationMs => sample.duration_ms
  }
}

///|
/// Bins one exact run, without pooling runs, dropping failures, or editing samples.
pub fn explore_distribution(
  packet : Packet,
  run_id : String,
  plan : DistributionPlan,
) -> DistributionReport raise PlanningError {
  validate_distribution_plan(plan)
  if prepare(packet.input) != packet {
    raise InvalidInput("distribution requires a verified planning packet")
  }
  guard packet.input.evidence.iter().find_first(e => e.run.run_id == run_id)
    is Some(e) else {
    raise InvalidInput("selected run is absent from the verified packet")
  }
  let counts = Array::make(plan.upper_bounds_ms.length() + 1, 0)
  let failures = Array::make(counts.length(), 0)
  for sample in e.run.samples {
    let value = sample_metric(sample, plan.metric)
    let mut index = 0
    while index < plan.upper_bounds_ms.length() &&
          value > plan.upper_bounds_ms[index] {
      index += 1
    }
    counts[index] += 1
    if sample.failed {
      failures[index] += 1
    }
  }
  let buckets : Array[DistributionBucket] = []
  let mut cumulative = 0
  let mut failed = 0
  for index, count in counts {
    cumulative += count
    failed += failures[index]
    buckets.push({
      lower_exclusive_ms: if index == 0 {
        None
      } else {
        Some(plan.upper_bounds_ms[index - 1])
      },
      upper_inclusive_ms: plan.upper_bounds_ms.get(index),
      sample_count: count,
      succeeded_count: count - failures[index],
      failed_count: failures[index],
      cumulative_sample_count: cumulative,
      cumulative_succeeded_count: cumulative - failed,
      cumulative_failed_count: failed,
    })
  }
  {
    schema_version: 1,
    packet_id: packet.packet_id,
    run_id,
    observation_sha256: observation_digest(e.run),
    origin: e.origin,
    source_ref: e.source_ref,
    workload_ref: e.workload_ref,
    profile: e.run.profile,
    model_digest: e.run.model_digest,
    runtime_digest: e.run.runtime_digest,
    hardware_profile: e.run.hardware_profile,
    kind: e.run.kind,
    tested_concurrency: e.run.concurrency,
    metric: plan.metric,
    unit: "milliseconds",
    upper_bounds_ms: plan.upper_bounds_ms.copy(),
    sample_count: cumulative,
    succeeded_count: cumulative - failed,
    failed_count: failed,
    buckets,
  }
}

///|
/// Spreadsheet presentation with explicit open bounds and unchanged provenance.
pub fn distribution_csv(
  packet : Packet,
  run_id : String,
  plan : DistributionPlan,
) -> String raise PlanningError {
  let report = explore_distribution(packet, run_id, plan)
  let lines = [
    "packet_id,run_id,observation_sha256,origin,source_ref,workload_ref,profile,model_digest,runtime_digest,hardware_profile,kind,tested_concurrency,metric,unit,lower_exclusive_ms,upper_inclusive_ms,sample_count,succeeded_count,failed_count,cumulative_sample_count,cumulative_succeeded_count,cumulative_failed_count,run_sample_count,run_succeeded_count,run_failed_count",
  ]
  let identity = [
    csv_text(report.packet_id),
    csv_text(report.run_id),
    csv_text(report.observation_sha256),
    csv_text("\{Repr(report.origin)}"),
    csv_text(report.source_ref),
    csv_text(report.workload_ref),
    csv_text(report.profile),
    csv_text(report.model_digest),
    csv_text(report.runtime_digest),
    csv_text(report.hardware_profile),
    csv_text("\{Repr(report.kind)}"),
    report.tested_concurrency.to_string(),
    csv_text(
      match report.metric {
        LatencyMs => "LatencyMs"
        QueueMs => "QueueMs"
        FirstOutputMs => "FirstOutputMs"
        LoadMs => "LoadMs"
        DurationMs => "DurationMs"
      },
    ),
    "milliseconds",
  ].join(",")
  for b in report.buckets {
    let lower = match b.lower_exclusive_ms {
      Some(n) => n.to_string()
      None => ""
    }
    let upper = match b.upper_inclusive_ms {
      Some(n) => n.to_string()
      None => ""
    }
    lines.push(
      identity +
      ",\{lower},\{upper},\{b.sample_count},\{b.succeeded_count},\{b.failed_count},\{b.cumulative_sample_count},\{b.cumulative_succeeded_count},\{b.cumulative_failed_count},\{report.sample_count},\{report.succeeded_count},\{report.failed_count}",
    )
  }
  lines.join("\r\n") + "\r\n"
}
