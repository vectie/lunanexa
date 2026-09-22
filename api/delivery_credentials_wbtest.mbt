///|
async test "model delivery API key is one time bound and stops with delivery" {
  let root = @fs.tmpdir(prefix="delivery-api-key-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let durable = @store.FileStore::open("\{root}/state.json")
  let scheduler = @scheduler.FileScheduler::open("\{root}/scheduler.json", 4)
  let deliveries = @delivery.DeliveryStore::open("\{root}/deliveries.json")
  let catalog = @deployment_store.FileDeploymentStore::open(
    "\{root}/catalog.json",
    "test-signing-secret",
  )
  let template = catalog.register_template(machine_dedicated_template())
  let portal = @portal_store.FilePortalStore::open("\{root}/portal.json")
  for
    (subject_ref, tenant_ref, organization_id) in [
      ("subject-a", "tenant-a", "org-a"),
      ("subject-b", "tenant-b", "org-b"),
    ] {
    ignore(
      portal.put_membership({
        membership_id: subject_ref,
        subject_ref,
        tenant_ref,
        organization_id,
        roles: [Developer],
        active: true,
        created_unix_ms: now,
      }),
    )
  }
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "test",
    "v1",
    template.runtime.image_digest,
    template.artifact.digest,
    allow_http_loopback=true,
  )
  let base = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "test",
    )
    .with_portal_store(portal)
    .with_delivery_store(deliveries)
    .with_deployment_store(catalog)
  let service = machine_webide_fixture(
    { ..base, scheduler: Some(scheduler), },
    root,
    now,
  )
  ignore(
    scheduler.reserve_nodes(
      {
        reservation_id: "reservation-a",
        idempotency_key: "reservation-a",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        authority_ref: "webide-grant-a",
        lease_id: "webide-lease-a",
        node_ids: ["node-a"],
        starts_unix_ms: now,
        expires_unix_ms: now + 60000L,
        memory_mib_per_node: 10000,
        gpu_memory_mib_per_node: 8000,
        max_concurrency_per_node: 4,
      },
      ["node-a"],
      now,
    ),
  )
  let created = deliveries.create(
    {
      tenant_id: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      authorization_ref: "webide-grant-a",
      lease_id: "webide-lease-a",
      idempotency_key: "delivery-key",
      kind: ModelApi,
      template_id: template.template_id,
      template_version: template.version,
      model_digest: Some(template.artifact.digest),
      node_count: 1,
      expires_at_ms: now + 60000L,
    },
    now,
  )
  let reserved = deliveries.observe(
    created.operation_id,
    created.generation,
    Reserved(reservation_id="reservation-a", node_ids=["node-a"]),
    now,
  )
  let prepared = deliveries.observe(
    created.operation_id,
    reserved.generation,
    ModelPrepared(digest=template.artifact.digest, cache_hit=true),
    now,
  )
  let ready = deliveries.observe(
    created.operation_id,
    prepared.generation,
    ModelResponded(service_id="model-a", digest=template.artifact.digest),
    now,
  )
  assert_eq(ready.stage, Ready)
  let path = "/v1/portal/self/deliveries/\{ready.operation_id}/access-key"
  let headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-a",
  }
  let body = ({ "request_id": "create-key" } : Json).stringify()
  let foreign = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-b",
  }
  assert_eq(
    service.handle_delivery_access_key(Post, path, foreign, body, true).status,
    404,
  )
  let reply = service.handle_delivery_access_key(
    Post,
    path,
    headers,
    body,
    true,
  )
  assert_eq(reply.status, 201)
  guard @json.parse(reply.body)
    is {
      "key_id": String(key_id),
      "api_secret": String(secret),
      "model": String(model),
      "base_url": String(base_url),
      ..
    } else {
    fail("missing key response")
  }
  assert_eq(model, template.model_selector)
  assert_eq(base_url, "https://moongate.example.invalid/v1")
  let handoffs = service.client_handoff_store.unwrap()
  assert_eq(
    handoffs.snapshot().credentials[0].delivery_id,
    Some(ready.operation_id),
  )
  let authorization = handoffs.authorize(
    secret,
    Inference,
    model~,
    now + 1L,
    true,
  )
  assert_eq(handoffs.snapshot().credentials[0].consumed_requests, 1L)
  let authority : @access.ApiAuthorization = {
    key_id,
    tenant_ref: authorization.tenant_ref,
    subject_ref: authorization.subject_ref,
    organization_id: authorization.organization_id,
    project_id: authorization.project_id,
  }
  let (bound, denied) = service.delivery_binding(authority)
  assert_eq(bound.unwrap().operation_id, ready.operation_id)
  assert_eq(denied, None)
  assert_eq(
    service.handle_delivery_access_key(Post, path, headers, body, true).status,
    409,
  )
  ignore(deliveries.stop(ready.operation_id, ready.generation, @async.now()))
  assert_eq(
    service.handle_delivery_access_key(
      Post,
      path,
      headers,
      "{\"request_id\":\"another-key\"}",
      true,
    ).status,
    409,
  )
  let (stopped, rejected) = service.delivery_binding(authority)
  assert_eq(stopped, None)
  assert_eq(rejected.unwrap().status, 403)
}
