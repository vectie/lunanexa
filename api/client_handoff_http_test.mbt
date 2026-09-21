///|
async fn seed_client_handoff_model(registry : @registry.FileRegistry) -> Unit {
  registry.register_runtime({
    name: "client-runtime",
    image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    version: "runtime-v1",
    architectures: ["nvidia-test"],
    capabilities: [TextGenerate],
    supports_batching: false,
    supports_multi_node: false,
  })
  registry.register_model({
    model_id: "model.client",
    version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.client/v1",
      size_bytes: 1024L,
      signature_ref: "cosign:model",
    },
    license_id: "license-client",
    provenance: "test:verified",
    compatible_architectures: ["nvidia-test"],
    minimum_memory_mib: 1000,
    state: Candidate,
  })
  registry.record_license({
    license_id: "license-client",
    model_id: "model.client",
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
      verified_unix_ms: @async.now(),
      verifier: "test-verifier",
    })
  }
  registry.record_evaluation({
    evaluation_id: "evaluation-client",
    model_id: "model.client",
    model_version: "v1",
    suite_version: "suite-v1",
    passed: true,
    score: 1.0,
    benchmark: {
      profile_id: "benchmark-client",
      model_id: "model.client",
      model_version: "v1",
      runtime_version: "runtime-v1",
      hardware_profile: "nvidia-test",
      workload_profile: "short-text",
      p50_ms: 1.0,
      p95_ms: 2.0,
      p99_ms: 3.0,
      throughput_per_second: 10.0,
      peak_memory_mib: 1000,
    },
    evidence_ref: "evidence:evaluation",
  })
  ignore(registry.approve("model.client", "v1", @async.now()))
  ignore(
    registry.promote(
      "text.default",
      "model.client",
      "v1",
      Canary,
      "operator",
      @async.now(),
    ),
  )
}

///|
async test "enterprise desktop handoff redeems once and lease loss blocks inference" {
  check_workspace_handoff(false)
}

///|
async test "private cloud desktop and ComfyUI handoffs need no rental contract but retain revocation" {
  check_workspace_handoff(true)
}

///|
async fn check_workspace_handoff(private_cloud : Bool) -> Unit {
  let temp = @fs.tmpdir(prefix="lunanexa-client-handoff-api-")
  let now = @async.now()
  let accounts = @account.AccountStore::open(
    "\{temp}/accounts.json",
    "client-account-session-secret-more-than-32-bytes",
  )
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-client",
      subject_ref: "subject-client",
      identity_issuer: "https://identity.example",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example", "client-user",
      ),
      display_name: "Client user",
      email: "client@example.invalid",
      identity_receipt: "identity-proof:client",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let durable = @store.FileStore::open("\{temp}/state.json")
  let registry = @registry.FileRegistry::open("\{temp}/registry.json")
  seed_client_handoff_model(registry)
  let portal = @portal_store.FilePortalStore::open("\{temp}/portal.json")
  ignore(
    portal.put_membership({
      membership_id: "membership-client",
      tenant_ref: "tenant-client",
      organization_id: "org-client",
      subject_ref: "subject-client",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
    }),
  )
  let documents = @contractdoc_store.ContractDocumentStore::open(
    "\{temp}/contracts.json",
  )
  if !private_cloud {
    ignore(
      documents.create_packet(
        {
          ..@contractdoc.new_packet(
            @contractdoc.youthpolicy_remote_lease_manifest(),
            "packet-client",
            "packet-client-key",
            "tenant-client",
            "org-client",
            "subject-client",
            "order-client",
            None,
            [MasterLease],
            now,
          ),
          state: Effective,
        },
        "operator",
      ),
    )
  }
  let directory = @directory.FileWorkspaceDirectory::open(
    "\{temp}/workspace.json",
    now_unix_ms=now,
  )
  ignore(
    directory.create_user({
      version: @workspace.contract_version,
      user_id: "user-client",
      subject_ref: "subject-client",
      display_name: "Client User",
      email: "client@example.invalid",
      state: UserActive,
      created_unix_ms: now,
      last_active_unix_ms: None,
      identity_receipt: "identity-client",
    }),
  )
  ignore(
    directory.issue_access_grant(
      {
        version: @workspace.contract_version,
        grant_id: "grant-client",
        user_id: "user-client",
        tenant_ref: "tenant-client",
        access: Developer,
        starts_unix_ms: now - 1000L,
        expires_unix_ms: now + 3600000L,
        state: GrantActive,
        policy_receipt: "grant-client-policy",
      },
      now,
    ),
  )
  ignore(
    directory.issue_lease(
      {
        version: @workspace.contract_version,
        lease_id: "lease-client",
        tenant_ref: "tenant-client",
        subject_ref: "subject-client",
        access: Developer,
        limits: {
          max_active_sessions: 1,
          max_session_duration_ms: 3600000L,
          capabilities: [
            {
              capability: TextGenerate,
              max_concurrent_requests: 1,
              max_requests_per_hour: 100,
              max_input_units_per_request: 4096,
              max_output_units_per_request: 1024,
            },
          ],
        },
        starts_unix_ms: now - 1000L,
        expires_unix_ms: now + 3600000L,
        state: Active,
        policy_receipt: "lease-client-policy",
      },
      now,
    ),
  )
  let handoffs = @client_handoff_store.ClientHandoffStore::open(
    "\{temp}/client-handoffs.json",
    "client-handoff-api-secret-with-at-least-thirty-two-bytes",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::with_registry(
      durable, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.1.0",
    )
    .with_portal_store(portal)
    .with_account_store(
      accounts, "client-account-assertion-secret-more-than-32-bytes",
    )
    .with_contract_document_store(documents)
    .with_private_cloud_workspace_access(private_cloud)
    .with_workspace_directory(directory, true)
    .with_client_handoff_store(handoffs, {
      client_id: "desktop-client",
      display_name: "Desktop workspace",
      launch_uri: "http://127.0.0.1:4188/connect",
      public_api_base_url: "https://models.example.invalid",
      handoff_lifetime_ms: 120000L,
      maximum_requests: 100L,
    })
  let enterprise_headers = {
    "Authorization": "Bearer inference-token",
    "X-LunaNexa-Subject": "subject-client",
  }
  let desktop_config : @client_handoff.ClientLaunchConfig = {
    client_id: "desktop-client",
    display_name: "Desktop workspace",
    launch_uri: "http://127.0.0.1:4188/connect",
    public_api_base_url: "https://models.example.invalid",
    handoff_lifetime_ms: 120000L,
    maximum_requests: 100L,
  }
  let comfy_config = {
    ..desktop_config,
    client_id: "comfyui",
    display_name: "ComfyUI",
    launch_uri: "https://creative.example.invalid/connect",
    public_api_base_url: "https://moongate.example.invalid/v1",
  }
  let service = service.with_client_launch_catalog([
    desktop_config, comfy_config,
  ])
  let catalog = service.handle(
    Get,
    "/v1/portal/self/clients",
    enterprise_headers,
    "",
  )
  assert_eq(catalog.status, 200)
  guard @json.parse(catalog.body) is Array(clients) else {
    fail("expected WebIDE catalog")
  }
  assert_eq(clients.length(), 2)
  assert_true(catalog.body.contains("ComfyUI"))
  assert_false(catalog.body.contains("api_secret"))
  assert_eq(
    service.handle(Get, "/v1/portal/self/clients", Map([]), "").status,
    401,
  )
  let client_readiness = service.handle(
    Get,
    "/v1/portal/self/client",
    enterprise_headers,
    "",
  )
  assert_eq(client_readiness.status, 200)
  let client_readiness_json = @json.parse(client_readiness.body)
  guard client_readiness_json is Object(client_fields) else {
    fail("expected desktop client readiness")
  }
  assert_eq(client_fields["contract_ready"], true)
  assert_eq(client_fields["contract_required"], (!private_cloud).to_json())
  assert_eq(client_fields["workspace_ready"], true)
  assert_eq(client_fields["models_ready"], true)
  assert_eq(client_fields["ready"], true)
  assert_eq(client_fields["approved_model_aliases"], ["text.default"])
  let issue_body = (
    {
      "request_id": "desktop-request-1",
      "client_id": "desktop-client",
      "project_id": "project-client",
      "allowed_models": ["text.default"],
    } : Json).stringify()
  assert_eq(
    service.handle(Post, "/v1/portal/self/client-handoffs", Map([]), issue_body).status,
    401,
  )
  let issued = service.handle(
    Post,
    "/v1/portal/self/client-handoffs",
    enterprise_headers,
    issue_body,
  )
  assert_eq(issued.status, 201)
  assert_false(issued.body.contains("api_secret"))
  let issued_json = @json.parse(issued.body)
  guard issued_json is Object(fields) &&
    fields["handoff_code"] is String(handoff_code) &&
    fields["handoff_id"] is String(handoff_id) else {
    fail("expected issued handoff")
  }
  let wrong_client = service.handle(
    Post,
    "/v1/client-handoffs:redeem",
    Map([]),
    ({ "client_id": "wrong-client", "handoff_code": handoff_code } : Json).stringify(),
  )
  assert_eq(wrong_client.status, 403)
  let redeemed = service.handle(
    Post,
    "/v1/client-handoffs:redeem",
    Map([]),
    ({ "client_id": "desktop-client", "handoff_code": handoff_code } : Json).stringify(),
  )
  assert_eq(redeemed.status, 200)
  guard @json.parse(redeemed.body) is Object(redeemed_fields) &&
    redeemed_fields["api_secret"] is String(api_secret) else {
    fail("expected one-time API secret")
  }
  // The second WebIDE uses its own launch bridge and provider address; neither
  // an unknown client nor another configured client can redeem its code.
  let comfy_issued = service.handle(
    Post,
    "/v1/portal/self/client-handoffs",
    enterprise_headers,
    (
      {
        "request_id": "comfy-request-1",
        "client_id": "comfyui",
        "project_id": "project-client",
        "allowed_models": ["text.default"],
      } : Json).stringify(),
  )
  assert_eq(comfy_issued.status, 201)
  guard @json.parse(comfy_issued.body)
    is {
      "handoff_code": String(comfy_code),
      "launch_uri": String(comfy_uri),
      ..
    } else {
    fail("expected ComfyUI bridge handoff")
  }
  assert_eq(comfy_uri, comfy_config.launch_uri)
  assert_eq(
    service.handle(
      Post,
      "/v1/client-handoffs:redeem",
      Map([]),
      ({ "client_id": "desktop-client", "handoff_code": comfy_code } : Json).stringify(),
    ).status,
    403,
  )
  let comfy_redeemed = service.handle(
    Post,
    "/v1/client-handoffs:redeem",
    Map([]),
    ({ "client_id": "comfyui", "handoff_code": comfy_code } : Json).stringify(),
  )
  assert_eq(comfy_redeemed.status, 200)
  guard @json.parse(comfy_redeemed.body)
    is { "api_base_url": String(comfy_api), .. } else {
    fail("missing provider binding")
  }
  assert_eq(comfy_api, comfy_config.public_api_base_url)
  assert_eq(
    service.handle(
      Post,
      "/v1/client-handoffs:redeem",
      Map([]),
      ({ "client_id": "desktop-client", "handoff_code": handoff_code } : Json).stringify(),
    ).status,
    409,
  )
  assert_eq(
    service.handle(
      Get,
      "/v1/models",
      { "Authorization": "Bearer \{api_secret}" },
      "",
    ).status,
    200,
  )
  ignore(accounts.set_state("account-client", Suspended, now + 1L))
  assert_eq(
    service.handle(
      Get,
      "/v1/models",
      { "Authorization": "Bearer \{api_secret}" },
      "",
    ).status,
    401,
  )
  ignore(accounts.set_state("account-client", Active, now + 2L))
  assert_eq(
    service.handle(
      Get,
      "/v1/models",
      { "Authorization": "Bearer \{api_secret}" },
      "",
    ).status,
    200,
  )
  ignore(directory.revoke_lease("lease-client", now + 10L))
  let after_termination = service.handle(
    Post,
    "/v1/chat/completions",
    { "Authorization": "Bearer \{api_secret}" },
    (
      {
        "model": "text.default",
        "messages": [{ "role": "user", "content": "hello" }],
      } : Json).stringify(),
  )
  assert_eq(after_termination.status, 401)
  assert_true(after_termination.body.contains("Unauthenticated"))
  assert_eq(
    service.handle(
      Get,
      "/v1/models",
      { "Authorization": "Bearer \{api_secret}" },
      "",
    ).status,
    401,
  )
  let revoked = service.handle(
    Post,
    "/v1/portal/self/client-handoffs/\{handoff_id}:revoke",
    enterprise_headers,
    "",
  )
  assert_eq(revoked.status, 200)
  assert_eq(
    service.handle(
      Get,
      "/v1/models",
      { "Authorization": "Bearer \{api_secret}" },
      "",
    ).status,
    401,
  )
}
