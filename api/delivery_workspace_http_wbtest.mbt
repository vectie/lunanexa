///|
test "workspace callback identity separates client and delivery within the same user project" {
  let authority : @access.ApiAuthorization = {
    key_id: "key-a",
    tenant_ref: "tenant-a",
    subject_ref: "subject-a",
    organization_id: "org-a",
    project_id: "project-a",
  }
  let first = delivery_workspace_id(authority, "comfyui", "delivery-a")
  assert_eq(
    first,
    delivery_workspace_id(
      { ..authority, key_id: "rotated-key", },
      "comfyui",
      "delivery-a",
    ),
  )
  assert_true(
    first != delivery_workspace_id(authority, "terminal", "delivery-a"),
  )
  assert_true(
    first != delivery_workspace_id(authority, "comfyui", "delivery-b"),
  )
}

///|
async test "gateway stop observation clears only its workspace claim and retains node reservation" {
  let root = @fs.tmpdir(prefix="workspace-delivery-observation-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let scheduler = @scheduler.FileScheduler::open("\{root}/scheduler.json", 4)
  let deliveries = @delivery.DeliveryStore::open("\{root}/deliveries.json")
  let directory = @directory.FileWorkspaceDirectory::open(
    "\{root}/directory.json",
    now_unix_ms=now,
  )
  let handoffs = @client_handoff_store.ClientHandoffStore::open(
    "\{root}/handoffs.json",
    "workspace-test-signing-secret-at-least-32-bytes",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "",
    "v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let base = ApiService::new(
    @store.FileStore::open("\{root}/state.json"),
    runtime,
    "op",
    "infer",
    "node",
    "test",
  )
  let service = {
    ..base,
    scheduler: Some(scheduler),
    workspace_directory: Some(directory),
    client_handoff_store: Some(handoffs),
  }.with_delivery_store(
    deliveries,
    gateway_observation_token="gateway-test-observation",
  )
  ignore(
    scheduler.reserve_nodes(
      {
        reservation_id: "reservation-a",
        idempotency_key: "reserve-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        authority_ref: "grant-a",
        lease_id: "lease-a",
        node_ids: ["node-a"],
        starts_unix_ms: now - 1L,
        expires_unix_ms: now + 60000L,
        memory_mib_per_node: 10000,
        gpu_memory_mib_per_node: 8000,
        max_concurrency_per_node: 4,
      },
      ["node-a"],
      now,
    ),
  )
  let operation = deliveries.create(
    {
      tenant_id: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      authorization_ref: "grant-a",
      lease_id: "lease-a",
      idempotency_key: "delivery-a",
      kind: GpuContainer,
      template_id: "terminal",
      template_version: "v1",
      model_digest: None,
      node_count: 1,
      expires_at_ms: now + 60000L,
    },
    now,
  )
  let operation = deliveries.observe(
    operation.operation_id,
    operation.generation,
    Reserved(reservation_id="reservation-a", node_ids=["node-a"]),
    now,
  )
  let operation = deliveries.observe(
    operation.operation_id,
    operation.generation,
    WorkspaceStarting(workspace_id="workspace-a"),
    now,
  )
  ignore(deliveries.stop(operation.operation_id, operation.generation, now))
  for service_id in ["\{operation.operation_id}-workspace", "other-service"] {
    ignore(
      scheduler.claim_node_service(
        "reservation-a",
        "tenant-a",
        {
          service_id,
          node_id: "node-a",
          memory_mib: 512,
          gpu_memory_mib: 0,
          concurrency: 1,
        },
        now,
      ),
    )
  }
  let body = ({ "workspace_id": "workspace-a" } : Json).stringify()
  let denied = service.handle_workspace_delivery(
    Post,
    "/v1/workspace-delivery/stopped",
    {},
    body,
  )
  assert_eq(denied.status, 403)
  assert_eq(
    scheduler.node_reservation("reservation-a").unwrap().services.length(),
    2,
  )
  let accepted = service.handle_workspace_delivery(
    Post,
    "/v1/workspace-delivery/stopped",
    { "x-lunanexa-gateway-token": "gateway-test-observation" },
    body,
  )
  assert_eq(accepted.status, 200)
  let held = scheduler.node_reservation("reservation-a").unwrap()
  assert_eq(held.services.length(), 1)
  assert_eq(held.services[0].service_id, "other-service")
  assert_eq(held.state, Reserved)
  assert_eq(
    deliveries.operation(operation.operation_id).unwrap().workspace_id,
    None,
  )
  assert_eq(
    deliveries.operation(operation.operation_id).unwrap().stage,
    Stopping,
  )
}
