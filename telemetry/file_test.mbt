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
