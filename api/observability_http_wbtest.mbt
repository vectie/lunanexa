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
      false,
    )
  }
  let alerts = notifications.records_for_operators(@async.now())
  assert_eq(alerts.length(), 1)
  assert_eq(alerts[0].event.code, "WorkloadAdmissionRejected")
  assert_eq(alerts[0].event.parameters["count"], "5")
  ignore(service.reconcile_notifications(@async.now() + 300001L))
  assert_eq(
    notifications.records_for_operators(@async.now() + 300002L)[0].lifecycle,
    Resolved,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "operational tenant hash is resolved from trusted portal membership" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-tenant-")
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "member-observability",
      tenant_ref: "tenant-authoritative",
      organization_id: "org-observability",
      subject_ref: "subject-observability",
      roles: [Developer],
      active: true,
      created_unix_ms: @async.now(),
    }),
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
  ).with_portal_store(portal)
  let trusted = service.trusted_operational_tenant_hash(
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-observability",
      "X-LunaNexa-Tenant": "attacker-tenant",
    },
    true,
  )
  assert_eq(trusted, Some("sha256:\{digest_hex("tenant-authoritative")}"))
  assert_false(trusted == Some("sha256:\{digest_hex("attacker-tenant")}"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "external collector proof is bounded fresh and durable" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-proof-api-")
  let operational = @observability.ObservabilityStore::open(
    "\{directory}/operational.json",
    emit_json_lines=true,
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
  ).with_observability_store(operational)
  let weak_service = ApiService::new(
      @store.FileStore::open("\{directory}/weak-state.json"),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_observability_store(operational)
    .with_external_export_proof_token("weak")
  assert_eq(
    weak_service.handle(
      Post,
      "/v1/observability/export-proof",
      { "Authorization": "Bearer weak" },
      "{\"proof_receipt\":\"weak-proof\",\"exported_unix_ms\":\"1000\"}",
    ).status,
    401,
  )
  ignore(
    service.record_external_export_proof(
      { proof_receipt: "collector-proof-api", exported_unix_ms: 1000L },
      1001L,
    ),
  )
  assert_eq(
    operational.readiness(external_collector_configured=true, now_unix_ms=1002L).state,
    LocalJsonReady,
  )
  try
    service.record_external_export_proof(
      { proof_receipt: "collector-proof-stale", exported_unix_ms: 1000L },
      400001L,
    )
  catch {
    @observability.ObservabilityError::InvalidEvent(_) => ()
    error => fail("unexpected proof error: \{Repr(error)}")
  } noraise {
    _ => fail("stale collector proof was accepted")
  }
  @fs.rmdir(directory, recursive=true)
}
