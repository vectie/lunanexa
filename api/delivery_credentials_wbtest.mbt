///|
async test "model delivery API key is one time bound and stops with delivery" {
  let root = @fs.tmpdir(prefix="delivery-api-key-")
  defer @fs.rmdir(root, recursive=true)
  let now = @async.now()
  let durable = @store.FileStore::open("\{root}/state.json")
  let registry = @registry.FileRegistry::open("\{root}/registry.json")
  seed_shared_delivery_model(registry)
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
  let base = ApiService::with_registry(
      durable, registry, runtime, "operator-token", "inference-token", "node-token",
      "test",
    )
    .with_portal_store(portal)
    .with_delivery_store(deliveries)
    .with_deployment_store(catalog)
  let fixture = machine_webide_fixture(
    { ..base, scheduler: Some(scheduler), },
    root,
    now,
  )
  let service = fixture
    .with_private_cloud_workspace_access(true)
    .with_client_handoff_store(fixture.client_handoff_store.unwrap(), {
      client_id: "desktop-workspace",
      display_name: "Private WebIDE",
      launch_uri: "https://workspace.example.invalid/connect",
      public_api_base_url: "https://moongate.example.invalid/v1",
      handoff_lifetime_ms: 120000L,
      maximum_requests: 1000L,
    })
    .with_personal_desktop_launches([
      {
        subject_ref: "subject-a",
        launch_uri: "https://workspace-a.example.invalid/connect",
      },
      {
        subject_ref: "subject-c",
        launch_uri: "https://workspace-b.example.invalid/connect",
      },
    ])
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
  ignore(
    portal.put_membership({
      membership_id: "membership-c",
      subject_ref: "subject-c",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
    }),
  )
  let directory = service.workspace_directory.unwrap()
  let owner_workspace = directory.snapshot(now)
  ignore(
    directory.create_user({
      ..owner_workspace.users[0],
      user_id: "webide-user-c",
      subject_ref: "subject-c",
      email: "colleague@example.invalid",
    }),
  )
  ignore(
    directory.issue_access_grant(
      {
        ..owner_workspace.access_grants[0],
        grant_id: "webide-grant-c",
        user_id: "webide-user-c",
      },
      now,
    ),
  )
  ignore(
    directory.issue_lease(
      {
        ..owner_workspace.leases[0],
        lease_id: "webide-lease-c",
        subject_ref: "subject-c",
      },
      now,
    ),
  )
  let colleague_headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-c",
  }
  let colleague_reply = service.handle_delivery_access_key(
    Post,
    path,
    colleague_headers,
    "{\"request_id\":\"colleague-key\"}",
    true,
  )
  assert_eq(colleague_reply.status, 201)
  guard @json.parse(colleague_reply.body)
    is {
      "key_id": String(colleague_key_id),
      "api_secret": String(colleague_secret),
      ..
    } else {
    fail("missing colleague key")
  }
  let colleague_auth = handoffs.authorize(
    colleague_secret,
    Inference,
    model~,
    now + 1L,
    false,
  )
  let colleague_authority : @access.ApiAuthorization = {
    key_id: colleague_key_id,
    tenant_ref: colleague_auth.tenant_ref,
    subject_ref: colleague_auth.subject_ref,
    organization_id: colleague_auth.organization_id,
    project_id: colleague_auth.project_id,
  }
  let (shared, shared_denied) = service.delivery_binding(colleague_authority)
  assert_eq(shared.unwrap().operation_id, ready.operation_id)
  assert_eq(shared_denied, None)
  let owner_handoff = service.handle_client_handoff(
    Post,
    "/v1/portal/self/client-handoffs",
    headers,
    (
      {
        "request_id": "owner-webide",
        "client_id": "desktop-workspace",
        "project_id": "project-a",
        "allowed_models": [model],
        "delivery_id": ready.operation_id,
      } : Json).stringify(),
    true,
  )
  assert_eq(owner_handoff.status, 201)
  let colleague_handoff = service.handle_client_handoff(
    Post,
    "/v1/portal/self/client-handoffs",
    colleague_headers,
    (
      {
        "request_id": "colleague-webide",
        "client_id": "desktop-workspace",
        "project_id": "project-a",
        "allowed_models": [model],
        "delivery_id": ready.operation_id,
      } : Json).stringify(),
    true,
  )
  assert_eq(colleague_handoff.status, 201)
  guard @json.parse(owner_handoff.body)
    is { "handoff_code": String(owner_code), .. } &&
    @json.parse(colleague_handoff.body)
    is { "handoff_code": String(colleague_code), .. } else {
    fail("missing independent WebIDE handoff codes")
  }
  assert_true(owner_code != colleague_code)
  let redeemed_owner = service.handle_client_handoff(
    Post,
    "/v1/client-handoffs:redeem",
    {},
    ({ "client_id": "desktop-workspace", "handoff_code": owner_code } : Json).stringify(),
    false,
  )
  let redeemed_colleague = service.handle_client_handoff(
    Post,
    "/v1/client-handoffs:redeem",
    {},
    ({ "client_id": "desktop-workspace", "handoff_code": colleague_code } : Json).stringify(),
    false,
  )
  assert_eq(redeemed_owner.status, 200)
  assert_eq(redeemed_colleague.status, 200)
  guard @json.parse(redeemed_owner.body)
    is { "api_secret": String(owner_webide_secret), .. } &&
    @json.parse(redeemed_colleague.body)
    is { "api_secret": String(colleague_webide_secret), .. } else {
    fail("missing independent WebIDE credentials")
  }
  assert_true(owner_webide_secret != colleague_webide_secret)
  ignore(directory.revoke_access_grant("webide-grant-c", now + 1L))
  let (_, revoked) = service.delivery_binding(colleague_authority)
  assert_eq(revoked.unwrap().status, 403)
  assert_eq(service.delivery_binding(authority).1, None)
  assert_eq(
    service.handle_delivery_access_key(Post, path, headers, body, true).status,
    409,
  )
  ignore(directory.revoke_access_grant("webide-grant-a", now + 2L))
  assert_eq(service.delivery_binding(authority).1.unwrap().status, 403)
  assert_eq(
    service.handle_delivery_access_key(
      Post,
      path,
      headers,
      "{\"request_id\":\"after-owner-revocation\"}",
      true,
    ).status,
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

///|
async fn seed_shared_delivery_model(registry : @registry.FileRegistry) -> Unit {
  let now = @async.now()
  registry.register_runtime({
    name: "text-runtime",
    image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    version: "runtime-v1",
    architectures: ["nvidia-gb10"],
    capabilities: [TextGenerate],
    supports_batching: false,
    supports_multi_node: false,
  })
  registry.register_model({
    model_id: "model.text",
    version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.text/v1",
      size_bytes: 1024L,
      signature_ref: "cosign:model",
    },
    license_id: "license-text",
    provenance: "test:verified",
    compatible_architectures: ["nvidia-gb10"],
    minimum_memory_mib: 1000,
    state: Candidate,
  })
  registry.record_license({
    license_id: "license-text",
    model_id: "model.text",
    status: Accepted,
    accepted_by: "operator",
    evidence_ref: "evidence:license",
    expires_unix_ms: None,
  })
  for
    digest in [
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ] {
    registry.record_verification({
      digest,
      signature_verified: true,
      provenance_verified: true,
      verified_unix_ms: now,
      verifier: "test-verifier",
    })
  }
  registry.record_evaluation({
    evaluation_id: "evaluation-text",
    model_id: "model.text",
    model_version: "v1",
    suite_version: "suite-v1",
    passed: true,
    score: 1.0,
    benchmark: {
      profile_id: "benchmark-text",
      model_id: "model.text",
      model_version: "v1",
      runtime_version: "runtime-v1",
      hardware_profile: "nvidia-gb10",
      workload_profile: "short-text",
      p50_ms: 1.0,
      p95_ms: 2.0,
      p99_ms: 3.0,
      throughput_per_second: 10.0,
      peak_memory_mib: 1000,
    },
    evidence_ref: "evidence:evaluation",
  })
  ignore(registry.approve("model.text", "v1", now))
  ignore(
    registry.promote(
      "text.default",
      "model.text",
      "v1",
      Canary,
      "operator",
      now,
    ),
  )
}
