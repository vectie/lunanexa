///|
/// A baseline objective is held fixed while two complete observations are compared.
/// Runtime, model, hardware and concurrency may differ; all changes are disclosed.
pub(all) struct ChangeInput {
  baseline : Evidence
  candidate : Evidence
  objective : @benchmark.ServiceObjective
  minimum_tested_concurrency : Int
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct MetricChange {
  metric : String
  unit : String
  baseline : Int
  candidate : Int
  delta : Int
  relative_per_mille : Int64?
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct ConfigurationChange {
  field : String
  baseline : String
  candidate : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct ChangeReport {
  schema_version : Int
  analysis_id : String
  input : ChangeInput
  baseline_summary : @benchmark.BenchmarkSummary
  candidate_summary : @benchmark.BenchmarkSummary
  baseline_failures : Int
  candidate_failures : Int
  failure_rate_direction : String
  baseline_meets_objective : Bool
  candidate_meets_objective : Bool
  baseline_meets_envelope : Bool
  candidate_meets_envelope : Bool
  configuration_changes : Array[ConfigurationChange]
  metrics : Array[MetricChange]
} derive(Eq, ToJson, FromJson)

///|
fn change_metric(
  metric : String,
  unit : String,
  baseline : Int,
  candidate : Int,
) -> MetricChange {
  {
    metric,
    unit,
    baseline,
    candidate,
    delta: candidate - baseline,
    relative_per_mille: if baseline == 0 {
      None
    } else {
      Some(
        (candidate.to_int64() - baseline.to_int64()) *
        1000L /
        baseline.to_int64(),
      )
    },
  }
}

///|
fn change_choice(
  evidence : Evidence,
  input : ChangeInput,
) -> Choice raise PlanningError {
  prepare({
    schema_version: 1,
    workload: {
      profile: evidence.run.profile,
      model_digest: evidence.run.model_digest,
      runtime_digest: evidence.run.runtime_digest,
      hardware_profile: evidence.run.hardware_profile,
      kind: evidence.run.kind,
      workload_ref: evidence.workload_ref,
      output_unit: evidence.output_unit,
      minimum_tested_concurrency: input.minimum_tested_concurrency,
    },
    objective: input.objective,
    evidence: [evidence],
  }).choices[0]
}

///|
pub fn analyze_change(input : ChangeInput) -> ChangeReport raise PlanningError {
  let b = input.baseline
  let c = input.candidate
  if b.origin != c.origin ||
    b.run.profile != c.run.profile ||
    b.run.kind != c.run.kind ||
    b.workload_ref != c.workload_ref ||
    b.output_unit != c.output_unit {
    raise InvalidInput(
      "change analysis requires the same origin, profile, benchmark kind, workload revision and output unit",
    )
  }
  let bc = change_choice(b, input)
  let cc = change_choice(c, input)
  let bs = bc.recommendation.summary
  let cs = cc.recommendation.summary
  let bf = observed_failure_count(b)
  let cf = observed_failure_count(c)
  let failure_difference = cf.to_int64() * bs.sample_count.to_int64() -
    bf.to_int64() * cs.sample_count.to_int64()
  let configuration_changes : Array[ConfigurationChange] = []
  for
    (field, baseline, candidate) in [
      ("model_digest", b.run.model_digest, c.run.model_digest),
      ("runtime_digest", b.run.runtime_digest, c.run.runtime_digest),
      ("hardware_profile", b.run.hardware_profile, c.run.hardware_profile),
      (
        "tested_concurrency",
        b.run.concurrency.to_string(),
        c.run.concurrency.to_string(),
      ),
      (
        "memory_total_mib",
        b.memory_total_mib.to_string(),
        c.memory_total_mib.to_string(),
      ),
    ] {
    if baseline != candidate {
      configuration_changes.push({ field, baseline, candidate, })
    }
  }
  let canonical = ToJson::to_json(input).stringify()
  let frozen : ChangeInput = @json.from_json(@json.parse(canonical)) catch {
    _ => raise InvalidInput("could not freeze change-analysis inputs")
  }
  let report : ChangeReport = {
    schema_version: 1,
    analysis_id: "benchmark-change-v1:sha256:" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(canonical).to_fixedarray()),
    ),
    input: frozen,
    baseline_summary: bs,
    candidate_summary: cs,
    baseline_failures: bf,
    candidate_failures: cf,
    failure_rate_direction: if failure_difference < 0L {
      "lower"
    } else if failure_difference > 0L {
      "higher"
    } else {
      "unchanged"
    },
    baseline_meets_objective: observed_objective_met(b, bc.recommendation),
    candidate_meets_objective: observed_objective_met(c, cc.recommendation),
    baseline_meets_envelope: bc.meets_declared_envelope,
    candidate_meets_envelope: cc.meets_declared_envelope,
    configuration_changes,
    metrics: [
      change_metric("latency_p50", "ms", bs.latency_p50_ms, cs.latency_p50_ms),
      change_metric("latency_p95", "ms", bs.latency_p95_ms, cs.latency_p95_ms),
      change_metric("latency_p99", "ms", bs.latency_p99_ms, cs.latency_p99_ms),
      change_metric("queue_p95", "ms", bs.queue_p95_ms, cs.queue_p95_ms),
      change_metric(
        "first_output_p95",
        "ms",
        bs.first_output_p95_ms,
        cs.first_output_p95_ms,
      ),
      change_metric(
        "throughput",
        b.output_unit + "/s",
        bs.throughput_units_per_second,
        cs.throughput_units_per_second,
      ),
      change_metric("memory_peak", "MiB", b.memory_peak_mib, c.memory_peak_mib),
      change_metric(
        "memory_headroom",
        "MiB",
        b.memory_total_mib - b.memory_peak_mib,
        c.memory_total_mib - c.memory_peak_mib,
      ),
    ],
  }
  if report.export_json().length() > 8388608 {
    raise InvalidInput(
      "change analysis exceeds the 8 Mi-character reopen limit",
    )
  }
  report
}

///|
/// Verify both saved packets before extracting their selected observations.
/// The candidate packet's objective never silently changes the comparison bar.
pub fn compare_packet_runs(
  baseline : Packet,
  baseline_id : String,
  candidate : Packet,
  candidate_id : String,
) -> ChangeReport raise PlanningError {
  let baseline = reopen(baseline.export_json())
  let candidate = reopen(candidate.export_json())
  guard baseline.input.evidence
    .iter()
    .find_first(e => e.run.run_id == baseline_id)
    is Some(b) else {
    raise InvalidInput("baseline run is absent from its packet")
  }
  guard candidate.input.evidence
    .iter()
    .find_first(e => e.run.run_id == candidate_id)
    is Some(c) else {
    raise InvalidInput("candidate run is absent from its packet")
  }
  analyze_change({
    baseline: b,
    candidate: c,
    objective: baseline.input.objective,
    minimum_tested_concurrency: baseline.input.workload.minimum_tested_concurrency,
  })
}

///|
pub fn ChangeReport::export_json(self : ChangeReport) -> String {
  ToJson::to_json(self).stringify(indent=2)
}

///|
pub fn reopen_change(text : String) -> ChangeReport raise PlanningError {
  if text.length() > 8388608 {
    raise InvalidInput(
      "change analysis exceeds the 8 Mi-character reopen limit",
    )
  }
  let parsed = @json.parse(text) catch {
    _ => raise InvalidInput("invalid change-analysis JSON")
  }
  let report : ChangeReport = @json.from_json(parsed) catch {
    _ => raise InvalidInput("invalid change-analysis JSON")
  }
  if ToJson::to_json(report) != parsed {
    raise InvalidInput("change analysis contains unsupported fields")
  }
  if report.schema_version != 1 {
    raise InvalidInput("unsupported change-analysis version")
  }
  let verified = analyze_change(report.input)
  if verified != report {
    raise InvalidInput(
      "change-analysis identity or results differ from exact inputs",
    )
  }
  verified
}

///|
pub fn ChangeReport::summary_text(self : ChangeReport) -> String {
  let b = self.input.baseline
  let c = self.input.candidate
  let o = self.input.objective
  let out = StringBuilder()
  out.write_string(
    "LunaNexa benchmark change analysis\n\{self.analysis_id}\n\n",
  )
  out.write_string(
    "Origin: \{Repr(b.origin)}; operator-declared context, no independent measurement authentication.\n",
  )
  out.write_string(
    "Baseline: \{b.run.run_id} (\{self.baseline_summary.sample_count} samples; concurrency \{b.run.concurrency})\n",
  )
  out.write_string(
    "Candidate: \{c.run.run_id} (\{self.candidate_summary.sample_count} samples; concurrency \{c.run.concurrency})\n",
  )
  out.write_string(
    "Workload: \{b.workload_ref}; profile \{b.run.profile}; kind \{Repr(b.run.kind)}; output unit \{b.output_unit}\n",
  )
  out.write_string(
    "Baseline source: \{b.source_ref}\nCandidate source: \{c.source_ref}\n",
  )
  out.write_string(
    "Baseline configuration: model \{b.run.model_digest}; runtime \{b.run.runtime_digest}; hardware \{b.run.hardware_profile}; memory \{b.memory_peak_mib}/\{b.memory_total_mib} MiB peak/total.\n",
  )
  out.write_string(
    "Candidate configuration: model \{c.run.model_digest}; runtime \{c.run.runtime_digest}; hardware \{c.run.hardware_profile}; memory \{c.memory_peak_mib}/\{c.memory_total_mib} MiB peak/total.\n",
  )
  out.write_string(
    "Baseline observation SHA-256: \{observation_digest(b.run)}\nCandidate observation SHA-256: \{observation_digest(c.run)}\n\n",
  )
  out.write_string(
    "Fixed baseline objective: p95 <= \{o.maximum_p95_ms} ms; throughput >= \{o.minimum_throughput_units_per_second} \{b.output_unit}/s; failures <= \{o.maximum_failure_per_mille} per mille; minimum tested concurrency \{self.input.minimum_tested_concurrency}.\n",
  )
  out.write_string(
    "Exact-count objective met: baseline \{self.baseline_meets_objective}; candidate \{self.candidate_meets_objective}\n",
  )
  out.write_string(
    "Objective and concurrency envelope met: baseline \{self.baseline_meets_envelope}; candidate \{self.candidate_meets_envelope}\n\nConfiguration changes:\n",
  )
  if self.configuration_changes.is_empty() {
    out.write_string(
      "  None among model, runtime, hardware, concurrency and total memory.\n",
    )
  }
  for change in self.configuration_changes {
    out.write_string(
      "  \{change.field}: \{change.baseline} -> \{change.candidate}\n",
    )
  }
  out.write_string("\nMeasured changes (candidate minus baseline):\n")
  for metric in self.metrics {
    let relative = match metric.relative_per_mille {
      Some(value) => "\{value} per mille of baseline (truncated toward zero)"
      None => "relative change unavailable: zero baseline"
    }
    out.write_string(
      "  \{metric.metric}: \{metric.baseline} -> \{metric.candidate} \{metric.unit}; delta \{metric.delta}; \{relative}\n",
    )
  }
  out.write_string(
    "  Failures: \{self.baseline_failures}/\{self.baseline_summary.sample_count} -> \{self.candidate_failures}/\{self.candidate_summary.sample_count}; exact failure rate \{self.failure_rate_direction}.\n\n",
  )
  out.write_string(
    "Interpretation: independent unpaired runs; no pooling, confidence interval, significance, causal attribution or automatic winner. Different sample counts/configurations may confound the comparison. Throughput is sum(output units) / sum(sample durations), not fleet throughput. Model output quality is not evaluated. Only observed samples are described; no production qualification, SLA, price, deployment or provider request. Save the JSON to retain both raw runs and recompute this report.\n",
  )
  out.to_string()
}

///|
pub extend ChangeInput with Eq::{equal, not_equal}

///|
pub extend ChangeInput with ToJson::{to_json}

///|
pub extend ChangeInput with FromJson::{from_json}

///|
pub extend MetricChange with Eq::{equal, not_equal}

///|
pub extend MetricChange with ToJson::{to_json}

///|
pub extend MetricChange with FromJson::{from_json}

///|
pub extend ConfigurationChange with Eq::{equal, not_equal}

///|
pub extend ConfigurationChange with ToJson::{to_json}

///|
pub extend ConfigurationChange with FromJson::{from_json}

///|
pub extend ChangeReport with Eq::{equal, not_equal}

///|
pub extend ChangeReport with ToJson::{to_json}

///|
pub extend ChangeReport with FromJson::{from_json}
