///|
async test "configured GPU offering creates a model-free delivery and terminal-only handoff" {
  let root = @fs.tmpdir(prefix="gpu-container-offering-")
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
    "",
    "v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let base = ApiService::new(
    durable, runtime, "operator", "inference", "node", "test",
  ).with_portal_store(portal)
  let fixture = machine_webide_fixture(
    { ..base, scheduler: Some(scheduler), },
    root,
    now,
  )
  let terminal_config = {
    ..fixture.client_launch_config.unwrap(),
    client_id: "gpu-terminal",
    display_name: "GPU terminal",
  }
  let deliveries = @delivery.DeliveryStore::open("\{root}/deliveries.json")
  let service = { ..fixture, client_launch_config: Some(terminal_config), }
    .with_delivery_store(deliveries)
    .with_gpu_container_offering({
      template_id: "gpu-python",
      version: "v1",
      display_name: "Exclusive GPU container",
      client_id: "gpu-terminal",
      image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      cpu_millis: 4000,
      memory_mib: 8192,
    })
  service.commercial_store.add_organization({
    organization_id: "org-a",
    display_name: "Test",
    state: Active,
    verification_ref: None,
    legal_profile: None,
    created_unix_ms: now,
  })
  service.commercial_store.add_cost_center({
    cost_center_id: "cost-a",
    organization_id: "org-a",
    parent_cost_center_id: None,
    display_name: "Default",
    created_unix_ms: now,
  })
  service.commercial_store.add_project({
    project_id: "project-a",
    organization_id: "org-a",
    cost_center_id: "cost-a",
    display_name: "Test",
    created_unix_ms: now,
  })
  ignore(
    scheduler.reserve_nodes(
      {
        reservation_id: "resource-a",
        idempotency_key: "resource-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        authority_ref: "webide-grant-a",
        lease_id: "webide-lease-a",
        node_ids: ["node-a"],
        starts_unix_ms: now,
        expires_unix_ms: now + 3600000L,
        memory_mib_per_node: 100000,
        gpu_memory_mib_per_node: 90000,
        max_concurrency_per_node: 4,
      },
      ["node-a"],
      now,
    ),
  )
  let headers = {
    "Authorization": "Bearer inference",
    "X-LunaNexa-Subject": "subject-a",
    "X-LunaNexa-Organization": "org-a",
  }
  let options = service.handle_delivery(
    Get,
    "/v1/portal/self/delivery-options",
    headers,
    "",
    true,
  )
  assert_eq(options.status, 200)
  assert_true(options.body.contains("GpuContainer"))
  assert_true(options.body.contains("gpu-terminal"))
  assert_false(options.body.contains("image_digest"))
  let request : Json = {
    "project_id": "project-a",
    "idempotency_key": "start-gpu",
    "reservation_id": "resource-a",
    "template_id": "gpu-python",
    "template_version": "v1",
    "kind": "GpuContainer",
  }
  let reply = service.handle_delivery(
    Post,
    "/v1/portal/self/deliveries",
    headers,
    request.stringify(),
    true,
  )
  assert_eq(reply.status, 202)
  let operation = deliveries.operations()[0]
  assert_eq(operation.stage, StartingWorkspace)
  assert_eq(operation.intent.model_digest, None)
  let handoff : Json = {
    "request_id": "terminal-launch",
    "client_id": "gpu-terminal",
    "project_id": "project-a",
    "display_name": "GPU terminal",
    "allowed_models": [],
    "delivery_id": operation.operation_id,
  }
  let issued = service.handle_client_handoff(
    Post,
    "/v1/portal/self/client-handoffs",
    headers,
    handoff.stringify(),
    true,
  )
  assert_eq(issued.status, 201)
  guard @json.parse(issued.body) is { "handoff_code": String(code), .. } else {
    fail("missing handoff code")
  }
  let redemption : Json = { "handoff_code": code, "client_id": "gpu-terminal" }
  let redeemed = service.handle_client_handoff(
    Post,
    "/v1/client-handoffs:redeem",
    Map([]),
    redemption.stringify(),
    false,
  )
  assert_eq(redeemed.status, 200)
  assert_true(
    @json.parse(redeemed.body) is { "delivery_id": String(id), .. } &&
    id == operation.operation_id,
  )
  assert_eq(
    service.client_handoff_store.unwrap().snapshot().credentials[0].allowed_models,
    [],
  )
  let without_client = { ..service, client_launch_config: None, }
  assert_true(without_client.published_gpu_container_offering() is None)
  ignore(
    service.workspace_directory
    .unwrap()
    .revoke_lease("webide-lease-a", @async.now()),
  )
  service.reconcile_deliveries()
  assert_eq(deliveries.operations()[0].stage, Stopping)
  assert_true(durable.assignments().is_empty())
}
