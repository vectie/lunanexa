///|
test "named benchmark evidence computes percentiles throughput and capacity" {
  let run : @telemetry.BenchmarkRun = {
    run_id: "run-text-short-v1",
    profile: "text-short-v1",
    model_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    runtime_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    hardware_profile: "dgx-spark",
    kind: Concurrency,
    concurrency: 4,
    samples: [
      {
        latency_ms: 10,
        queue_ms: 1,
        load_ms: 0,
        first_output_ms: 4,
        output_units: 100,
        duration_ms: 100,
        utilization_per_mille: 500,
        failed: false,
      },
      {
        latency_ms: 20,
        queue_ms: 2,
        load_ms: 0,
        first_output_ms: 6,
        output_units: 100,
        duration_ms: 100,
        utilization_per_mille: 700,
        failed: false,
      },
      {
        latency_ms: 30,
        queue_ms: 3,
        load_ms: 0,
        first_output_ms: 8,
        output_units: 100,
        duration_ms: 100,
        utilization_per_mille: 800,
        failed: false,
      },
    ],
  }
  let summary = @telemetry.summarize(run)
  assert_eq(summary.latency_p50_ms, 20)
  assert_eq(summary.latency_p95_ms, 30)
  assert_eq(summary.throughput_units_per_second, 1000)
  assert_true(
    @telemetry.meets_objective(summary, {
      profile: "text-short-v1",
      maximum_p95_ms: 35,
      minimum_throughput_units_per_second: 900,
      maximum_failure_per_mille: 0,
    }),
  )
  let recommendation = @telemetry.recommend_capacity(summary, 4, 120000, 90000)
  assert_eq(recommendation.memory_headroom_mib, 30000)
}

///|
test "release evidence requires named human acceptance" {
  let summary : @telemetry.BenchmarkSummary = {
    run_id: "run-1",
    profile: "text-short-v1",
    sample_count: 1,
    latency_p50_ms: 1,
    latency_p95_ms: 1,
    latency_p99_ms: 1,
    queue_p95_ms: 0,
    first_output_p95_ms: 1,
    throughput_units_per_second: 1,
    failure_per_mille: 0,
    peak_utilization_per_mille: 1,
  }
  let evidence : @telemetry.EvidenceBundle = {
    release_version: "0.1.0",
    benchmark_summaries: [summary],
    scenario_passed: true,
    isolation_scan_passed: true,
    physical_cluster_passed: true,
    postgres_failover_passed: true,
    object_store_transfer_passed: true,
    inference_billing_passed: true,
    provider_integration_passed: true,
    browser_acceptance_passed: true,
    security_report_ref: "report:security",
    operations_report_ref: "report:operations",
    license_report_ref: "report:license",
    ha_report_ref: "report:ha",
    object_store_report_ref: "report:object-store",
    provider_report_ref: "report:providers",
    sanitization_report_ref: "report:sanitization",
    browser_report_ref: "report:browser",
    accepted_by: None,
  }
  assert_false(evidence.release_ready())
  assert_false(
    {
      ..evidence,
      accepted_by: Some("named-operator"),
      object_store_transfer_passed: false,
    }.release_ready(),
  )
  assert_true(
    { ..evidence, accepted_by: Some("named-operator") }.release_ready(),
  )
  let built = @telemetry.build_evidence_bundle([summary], {
    release_version: "0.1.0",
    scenario_passed: true,
    isolation_scan_passed: true,
    physical_cluster_passed: true,
    postgres_failover_passed: true,
    object_store_transfer_passed: true,
    inference_billing_passed: true,
    provider_integration_passed: true,
    browser_acceptance_passed: true,
    security_report_ref: "report:security",
    operations_report_ref: "report:operations",
    license_report_ref: "report:license",
    ha_report_ref: "report:ha",
    object_store_report_ref: "report:object-store",
    provider_report_ref: "report:providers",
    sanitization_report_ref: "report:sanitization",
    browser_report_ref: "report:browser",
    accepted_by: Some("named-operator"),
  })
  assert_true(built.release_ready())
  let recommendation = @telemetry.build_recommendation([summary], {
    run_id: "run-1",
    objective: {
      profile: "text-short-v1",
      maximum_p95_ms: 2,
      minimum_throughput_units_per_second: 1,
      maximum_failure_per_mille: 0,
    },
    tested_concurrency: 1,
    memory_total_mib: 1000,
    memory_peak_mib: 750,
  })
  assert_true(recommendation.objective_met)
  assert_eq(recommendation.capacity.memory_headroom_mib, 250)
}

///|
test "metric-specific bounds reject skewing node telemetry" {
  let sample : @contracts.TelemetrySample = {
    node_id: "node-1",
    deployment_id: "",
    metric: "accelerator_utilization_per_mille",
    value: 1000.0,
    timestamp_unix_ms: 1L,
  }
  assert_true(@telemetry.bounded_metric(sample))
  assert_false(@telemetry.bounded_metric({ ..sample, value: 1001.0 }))
  assert_false(@telemetry.bounded_metric({ ..sample, node_id: "node\nforged" }))
  let limits = {
    ..@settings.default_global_admin_settings().telemetry_safety,
    maximum_power_watts: 500.0,
  }
  assert_true(
    @telemetry.bounded_metric_with_settings(
      { ..sample, metric: "accelerator_power_watts", value: 499.0 },
      limits,
    ),
  )
  assert_false(
    @telemetry.bounded_metric_with_settings(
      { ..sample, metric: "accelerator_power_watts", value: 501.0 },
      limits,
    ),
  )
}
