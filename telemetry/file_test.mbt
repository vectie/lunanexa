///|
async test "failed telemetry persistence restores pruned history and permits retry" {
  let directory = @fs.tmpdir(prefix="lunanexa-telemetry-rollback-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/telemetry.json"
  let store = @telemetry.FileTelemetry::open(
    path,
    sample_history_limit=1,
    benchmark_history_limit=1,
  )
  let sample : @contracts.TelemetrySample = {
    node_id: "fixture-node",
    deployment_id: "fixture-deployment",
    metric: "accelerator_utilization_per_mille",
    value: 100.0,
    timestamp_unix_ms: 1L,
  }
  let run : @telemetry.BenchmarkRun = {
    run_id: "fixture-run",
    profile: "test-only",
    model_digest: "sha256:" + "a".repeat(64),
    runtime_digest: "sha256:" + "b".repeat(64),
    hardware_profile: "test-only-no-hardware",
    kind: Concurrency,
    concurrency: 1,
    samples: [
      {
        latency_ms: 10,
        queue_ms: 0,
        load_ms: 0,
        first_output_ms: 1,
        output_units: 1,
        duration_ms: 10,
        utilization_per_mille: 0,
        failed: false,
      },
    ],
  }
  store.record_sample(sample)
  ignore(store.record_benchmark(run))
  let before = store.snapshot()
  @fs.mkdir(path + ".next")
  try store.record_sample({ ..sample, value: 200.0, }) catch {
    _ => ()
  } noraise {
    _ => fail("expected persistence failure")
  }
  assert_eq(store.snapshot(), before)
  try store.record_benchmark({ ..run, run_id: "fixture-retry", }) catch {
    _ => ()
  } noraise {
    _ => fail("expected benchmark persistence failure")
  }
  assert_eq(store.snapshot(), before)
  assert_eq(@telemetry.FileTelemetry::open(path).snapshot(), before)
  @fs.rmdir(path + ".next")
  store.record_sample({ ..sample, value: 200.0, })
  ignore(store.record_benchmark({ ..run, run_id: "fixture-retry", }))
  let after = store.snapshot()
  assert_eq(after.samples.length(), 1)
  assert_eq(after.samples[0].value, 200.0)
  assert_eq(after.benchmark_runs.length(), 1)
  assert_eq(after.benchmark_runs[0].run_id, "fixture-retry")
  assert_eq(after.benchmark_summaries.length(), 1)
  assert_eq(after.benchmark_summaries[0].run_id, "fixture-retry")
  assert_eq(@telemetry.FileTelemetry::open(path).snapshot(), after)
}

///|
async test "telemetry is bounded durable and rejects payload-shaped metrics" {
  let directory = @fs.tmpdir(prefix="lunanexa-telemetry-")
  let path = "\{directory}/telemetry.json"
  let telemetry = @telemetry.FileTelemetry::open(path)
  telemetry.record_sample({
    node_id: "node-a",
    deployment_id: "deployment-a",
    metric: "accelerator_utilization_per_mille",
    value: 500.0,
    timestamp_unix_ms: 1L,
  })
  try
    telemetry.record_sample({
      node_id: "node-a",
      deployment_id: "deployment-a",
      metric: "prompt",
      value: 1.0,
      timestamp_unix_ms: 2L,
    })
  catch {
    @telemetry.TelemetryError::PayloadMetricRejected => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("payload metric was retained")
  }
  let restored = @telemetry.FileTelemetry::open(path)
  assert_eq(restored.snapshot().samples.length(), 1)
  assert_false(@fs.read_file(path).text().contains("prompt"))
  @fs.rmdir(directory, recursive=true)
}
