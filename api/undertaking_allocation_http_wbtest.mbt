///|
async test "undertaking allocation requires exact live signed approval and full prepayment" {
  let root = @fs.tmpdir(prefix="undertaking-allocation-policy-")
  defer @fs.rmdir(root, recursive=true)
  let snapshot = undertaking_test_snapshot("\{root}/offline.json")
  let order = undertaking_test_order()
  let packet = undertaking_test_packet()
  let signed = snapshot.artifacts[0]
  let effective = {
    ..packet,
    state: Effective,
    execution: Some({
      evidence_sha256: signed.sha256,
      signed_on: "2026-09-16",
      registered_by: "manager-a",
      registered_unix_ms: 4000L,
    }),
  }
  let now = @contractdoc.calendar_date_days("2026-09-16").unwrap() * 86400000L
  assert_true(
    undertaking_allocation_packet(order, [effective], snapshot, now) is Some(_),
  )
  assert_true(
    undertaking_allocation_packet(order, [packet], snapshot, now) is None,
  )
  assert_true(
    undertaking_allocation_packet(
      order,
      [effective, { ..effective, packet_id: "duplicate", }],
      snapshot,
      now,
    )
    is None,
  )
  assert_true(
    undertaking_allocation_packet(
      order,
      [effective],
      { ..snapshot, reviews: [], },
      now,
    )
    is None,
  )
  assert_true(
    undertaking_allocation_packet(
      { ..order, organization_id: "other-org", },
      [effective],
      snapshot,
      now,
    )
    is None,
  )
  assert_eq(
    undertaking_allocation_expiry(order, effective, now),
    Some(now + 86400000L),
  )
  assert_eq(
    undertaking_allocation_expiry(order, effective, now + 86400000L),
    None,
  )
}

///|
async test "undertaking node preflight rejects live host-native memory pressure" {
  let root = @fs.tmpdir(prefix="undertaking-node-preflight-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let durable = @store.FileStore::open("\{root}/state.json")
  let scheduler = @scheduler.FileScheduler::open("\{root}/scheduler.json", 4)
  let telemetry = @telemetry.FileTelemetry::open("\{root}/telemetry.json")
  let baseline = customer_machine_test_heartbeat(now)
  let heartbeat : @contracts.NodeHeartbeat = {
    ..baseline,
    inventory: {
      ..baseline.inventory,
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
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let base = ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
  let service = {
    ..base,
    scheduler: Some(scheduler),
    telemetry: Some(telemetry),
  }
  telemetry.record_sample({
    node_id: heartbeat.node_id,
    deployment_id: "",
    metric: "host_memory_available_mib",
    value: 8192.0,
    timestamp_unix_ms: now,
  })
  assert_eq(service.undertaking_idle_capacity([heartbeat.node_id], now), None)
  telemetry.record_sample({
    node_id: heartbeat.node_id,
    deployment_id: "",
    metric: "host_memory_available_mib",
    value: 120000.0,
    timestamp_unix_ms: now + 1L,
  })
  assert_true(
    service.undertaking_idle_capacity([heartbeat.node_id], now + 1L) is Some(_),
  )
}

///|
async test "ordinary resource deliveries keep exact personal lease binding" {
  let root = @fs.tmpdir(prefix="delivery-resource-binding-")
  defer @fs.rmdir(root, recursive=true)
  let durable = @store.FileStore::open("\{root}/state.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  )
  let now = @async.now()
  let reservation : @scheduler.NodeReservation = {
    request: {
      reservation_id: "personal-reservation",
      idempotency_key: "personal-reservation",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      authority_ref: "grant-owner",
      lease_id: "lease-owner",
      node_ids: ["node-a"],
      starts_unix_ms: now - 1000L,
      expires_unix_ms: now + 60000L,
      memory_mib_per_node: 32768,
      gpu_memory_mib_per_node: 32768,
      max_concurrency_per_node: 1,
    },
    state: Reserved,
    generation: 1L,
    updated_unix_ms: now,
    services: [],
  }
  assert_true(
    service.delivery_reservation_authorized(
      reservation, "tenant-a", "org-a", "lease-owner", "grant-owner", now,
    ),
  )
  assert_false(
    service.delivery_reservation_authorized(
      reservation, "tenant-a", "org-a", "lease-colleague", "grant-colleague", now,
    ),
  )
  assert_false(
    service.delivery_reservation_authorized(
      reservation, "tenant-a", "other-org", "lease-owner", "grant-owner", now,
    ),
  )
}

///|
async test "company machine access does not reuse a colleague's text-only lease" {
  let root = @fs.tmpdir(prefix="undertaking-member-workspace-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let empty = @directory.FileWorkspaceDirectory::open("\{root}/workspace.json").snapshot(
    now,
  )
  let text_limit : @workspace.CapabilityLimit = {
    capability: TextGenerate,
    max_concurrent_requests: 2,
    max_requests_per_hour: 100,
    max_input_units_per_request: 65536,
    max_output_units_per_request: 8192,
  }
  let user : @workspace.WorkspaceUser = {
    version: @workspace.contract_version,
    user_id: "colleague-user",
    subject_ref: "colleague-a",
    display_name: "Colleague A",
    email: "colleague@example.com",
    state: UserActive,
    created_unix_ms: now - 1000L,
    last_active_unix_ms: None,
    identity_receipt: "verified-colleague",
  }
  let grant : @workspace.WorkspaceAccessGrant = {
    version: @workspace.contract_version,
    grant_id: "colleague-grant",
    user_id: user.user_id,
    tenant_ref: "tenant-a",
    access: Developer,
    starts_unix_ms: now - 1000L,
    expires_unix_ms: now + 86400000L,
    state: GrantActive,
    policy_receipt: "company-grant",
  }
  let lease : @workspace.WorkspaceLease = {
    version: @workspace.contract_version,
    lease_id: "member-lease",
    tenant_ref: "tenant-a",
    subject_ref: "colleague-a",
    access: Developer,
    limits: {
      max_active_sessions: 2,
      max_session_duration_ms: 3600000L,
      capabilities: [text_limit],
    },
    starts_unix_ms: now - 1000L,
    expires_unix_ms: now + 86400000L,
    state: Active,
    policy_receipt: "member-grant",
  }
  assert_false(
    undertaking_member_has_gpu_workspace(
      { ..empty, users: [user], access_grants: [grant], leases: [lease], },
      "colleague-a",
      "tenant-a",
      now,
    ),
  )
  let full = {
    ..lease,
    limits: {
      ..lease.limits,
      capabilities: [
        text_limit,
        { ..text_limit, capability: EmbeddingCreate, },
        { ..text_limit, capability: ImageGenerate, },
        { ..text_limit, capability: VideoGenerate, },
        { ..text_limit, capability: AudioGenerate, },
      ],
    },
  }
  assert_true(
    undertaking_member_has_gpu_workspace(
      { ..empty, users: [user], access_grants: [grant], leases: [full], },
      "colleague-a",
      "tenant-a",
      now,
    ),
  )
  assert_false(
    undertaking_member_has_gpu_workspace(
      { ..empty, users: [user], access_grants: [grant], leases: [full], },
      "other-subject",
      "tenant-a",
      now,
    ),
  )
  assert_false(
    undertaking_member_has_gpu_workspace(
      {
        ..empty,
        users: [user],
        access_grants: [{ ..grant, state: GrantRevoked, }],
        leases: [full],
      },
      "colleague-a",
      "tenant-a",
      now,
    ),
  )
}
