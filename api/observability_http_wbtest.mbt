///|
async test "repeated authenticated workload admission rejection raises one durable alert" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-alert-")
  let operational = @observability.ObservabilityStore::open(
    "\{directory}/operational.json",
  )
  let notifications = @notification_store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_observability_store(operational)
    .with_notification_store(notifications)
  let headers = { "Authorization": "Bearer inference-token" }
  for index = 0; index < 6; index = index + 1 {
    service.record_operational_request(
      Post,
      "/v1/workloads",
      headers,
      api_error(429, "WorkspaceRateExceeded", "bounded", true),
      @async.now() - 1L,
    )
  }
  let alerts = notifications.records_for_operators(@async.now())
  assert_eq(alerts.length(), 1)
  assert_eq(alerts[0].event.code, "WorkloadAdmissionRejected")
  assert_eq(alerts[0].event.parameters["count"], "5")
  @fs.rmdir(directory, recursive=true)
}
