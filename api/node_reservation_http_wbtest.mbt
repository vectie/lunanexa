///|
async test "resource reservation API binds live organization grant and rejects busy nodes" {
  let root = @fs.tmpdir(prefix="resource-reservation-api-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let durable = @store.FileStore::open("\{root}/state.json")
  let scheduler = @scheduler.FileScheduler::open("\{root}/scheduler.json", 4)
  let portal = @portal_store.FilePortalStore::open("\{root}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "member-a",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      subject_ref: "subject-a",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
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
  let base = ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_portal_store(portal)
  let legacy = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{root}/legacy-leases.json",
    "resource-test-signing-secret",
  )
  let service = machine_webide_fixture(
    { ..base, scheduler: Some(scheduler), },
    root,
    now,
  ).with_exclusive_lease_store(legacy)
  let original = customer_machine_test_heartbeat(now)
  let heartbeat : @contracts.NodeHeartbeat = {
    ..original,
    inventory: {
      ..original.inventory,
      labels: {
        "lunanexa.io/host-cpu-count": "20",
        "lunanexa.io/host-memory-mib": "131072",
      },
      accelerators: [
        {
          device_id: "gb10",
          architecture: "nvidia-gb10",
          memory_total_mib: 131072,
          memory_free_mib: 100000,
          healthy: true,
        },
      ],
    },
  }
  durable.put_heartbeat(heartbeat)
  let request : @scheduler.NodeReservationRequest = {
    reservation_id: "resource-a",
    idempotency_key: "resource-a",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    authority_ref: "webide-grant-a",
    lease_id: "webide-lease-a",
    node_ids: [heartbeat.node_id],
    starts_unix_ms: now,
    expires_unix_ms: now + 60000L,
    memory_mib_per_node: 100000,
    gpu_memory_mib_per_node: 90000,
    max_concurrency_per_node: 4,
  }
  let headers = { "Authorization": "Bearer operator-token" }
  let body : Json = {
    "request": request.to_json(),
    "readiness_confirmation": "reserve-idle-nodes:resource-a",
  }
  assert_eq(
    service.handle_resource_reservation(
      Post,
      "/v1/resource-reservations",
      Map([]),
      body.stringify(),
    ).status,
    401,
  )
  let wrong_org : Json = {
    "request": { ..request, organization_id: "other-org", }.to_json(),
    "readiness_confirmation": "reserve-idle-nodes:resource-a",
  }
  assert_eq(
    service.handle_resource_reservation(
      Post,
      "/v1/resource-reservations",
      headers,
      wrong_org.stringify(),
    ).status,
    403,
  )
  durable.put_heartbeat({
    ..heartbeat,
    running_deployments: ["existing-model"],
  })
  assert_eq(
    service.handle_resource_reservation(
      Post,
      "/v1/resource-reservations",
      headers,
      body.stringify(),
    ).status,
    409,
  )
  assert_false(scheduler.node_is_reserved(heartbeat.node_id))
  durable.put_heartbeat(heartbeat)
  assert_eq(
    service.handle_resource_reservation(
      Post,
      "/v1/resource-reservations",
      headers,
      body.stringify(),
    ).status,
    201,
  )
  assert_true(scheduler.node_is_reserved(heartbeat.node_id))
  let bare : @nodelease.ExclusiveNodeLeaseIntent = {
    version: @nodelease.contract_version,
    idempotency_key: "bare-request",
    lease_id: "bare-lease",
    node_id: heartbeat.node_id,
    subject_ref: "subject-a",
    unix_username: "tenant_a",
    access_credential_ref: "ssh-cert:bare-lease",
    starts_unix_ms: now,
    expires_unix_ms: now + 60000L,
  }
  assert_eq(
    service.handle_exclusive_lease_management(
      Post,
      "/v1/exclusive-node-leases",
      headers,
      bare.to_json().stringify(),
    ).status,
    409,
  )
  assert_eq(legacy.leases().length(), 0)
  assert_eq(
    service.handle_resource_reservation(
      Post,
      "/v1/resource-reservations",
      headers,
      body.stringify(),
    ).status,
    201,
  )
  assert_eq(
    service.handle_resource_reservation(
      Post,
      "/v1/resource-reservations/resource-a:release",
      headers,
      "{}",
    ).status,
    405,
  )
  assert_true(scheduler.node_is_reserved(heartbeat.node_id))
}
