///|
async test "operational events persist correlation and expose bounded monitoring views" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-api-")
  let operational = @observability.ObservabilityStore::open(
    "\{directory}/operational.json",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = @api.ApiService::new(
      @store.FileStore::open("\{directory}/state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_observability_store(operational)
    .with_role_tokens("audit-token", "monitoring-token")
  assert_eq(
    service.handle(Get, "/health", { "X-Request-Id": "request-health-1" }, "").status,
    200,
  )
  assert_eq(service.handle(Get, "/missing", Map([]), "").status, 404)
  let snapshot = operational.snapshot()
  assert_eq(snapshot.events.length(), 2)
  assert_eq(snapshot.events[0].correlation_id, "request-health-1")
  assert_eq(snapshot.events[0].target_type, "health")
  assert_eq(snapshot.events[1].outcome, "rejected")
  let events = service.handle(
    Get,
    "/v1/observability/events",
    { "Authorization": "Bearer monitoring-token" },
    "",
  )
  assert_eq(events.status, 200)
  assert_true(events.body.contains("request-health-1"))
  assert_false(events.body.contains("runtime-secret"))
  let metrics = service.handle(
    Get,
    "/metrics",
    { "Authorization": "Bearer monitoring-token" },
    "",
  )
  assert_eq(metrics.status, 200)
  assert_true(metrics.body.contains("lunanexa_operational_events_total"))
  assert_true(metrics.body.contains("status_class=\"2xx\""))
  assert_false(metrics.body.contains("request-health-1"))
  assert_eq(
    service.handle(Get, "/v1/observability/events", Map([]), "").status,
    401,
  )
  let reopened = @observability.ObservabilityStore::open(
    "\{directory}/operational.json",
  )
  assert_true(reopened.snapshot().events.length() >= 4)
  @fs.rmdir(directory, recursive=true)
}
