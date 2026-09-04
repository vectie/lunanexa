///|
async fn seed_access_package_model(registry : @registry.FileRegistry) -> Unit {
  registry.register_runtime({
    name: "onboarding-runtime",
    image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    version: "runtime-v1",
    architectures: ["nvidia-test"],
    capabilities: [TextGenerate],
    supports_batching: false,
    supports_multi_node: false,
  })
  registry.register_model({
    model_id: "model.onboarding",
    version: "v1",
    artifact: {
      digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      uri: "s3://models/model.onboarding/v1",
      size_bytes: 1024L,
      signature_ref: "cosign:model",
    },
    license_id: "license-onboarding",
    provenance: "test:verified",
    compatible_architectures: ["nvidia-test"],
    minimum_memory_mib: 1000,
    state: Candidate,
  })
  registry.record_license({
    license_id: "license-onboarding",
    model_id: "model.onboarding",
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
    evaluation_id: "evaluation-onboarding",
    model_id: "model.onboarding",
    model_version: "v1",
    suite_version: "suite-v1",
    passed: true,
    score: 1.0,
    benchmark: {
      profile_id: "benchmark-onboarding",
      model_id: "model.onboarding",
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
  ignore(registry.approve("model.onboarding", "v1", @async.now()))
  ignore(
    registry.promote(
      "qwen.default",
      "model.onboarding",
      "v1",
      Canary,
      "operator",
      @async.now(),
    ),
  )
}

///|
async test "one access package intent is resumable and enables only after contract and model gates" {
  let temp = @fs.tmpdir(prefix="lunanexa-access-onboarding-")
  let durable = @store.FileStore::open("\{temp}/state.json")
  let accounts = @account.AccountStore::open(
    "\{temp}/accounts.json",
    "account-session-issuer-secret-more-than-thirty-two-bytes",
  )
  let portal = @portal_store.FilePortalStore::open("\{temp}/portal.json")
  let directory = @directory.FileWorkspaceDirectory::open(
    "\{temp}/workspace.json",
  )
  let onboarding = @onboarding.AccessOnboardingStore::open(
    "\{temp}/onboarding.json",
  )
  let contracts = @contractdoc_store.ContractDocumentStore::open(
    "\{temp}/contracts.json",
  )
  let registry = @registry.FileRegistry::open("\{temp}/registry.json")
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
    .with_account_store(
      accounts, "identity-assertion-secret-more-than-thirty-two-bytes",
    )
    .with_portal_store(portal)
    .with_workspace_directory(directory, true)
    .with_access_onboarding_store(onboarding)
    .with_contract_document_store(contracts)
  let body = "{\"identity_issuer\":\"https://identity.example\",\"identity_subject\":\"provider-user-42\",\"display_name\":\"Friendly Developer\",\"email\":\"friendly@example.com\",\"organization_id\":\"org-friendly\",\"tenant_ref\":\"tenant-friendly\",\"template_id\":\"webide-developer\",\"lifetime_days\":30,\"identity_verified\":true}"
  assert_eq(
    service.handle(Post, "/v1/onboarding/access-packages", Map([]), body).status,
    401,
  )
  let headers = { "Authorization": "Bearer operator-token" }
  let created = service.handle(
    Post,
    "/v1/onboarding/access-packages",
    headers,
    body,
  )
  assert_eq(created.status, 201)
  assert_true(created.body.contains("ContractRequired"))
  assert_false(created.body.contains("provider-user-42"))
  assert_eq(accounts.views().length(), 1)
  assert_eq(portal.snapshot().memberships.length(), 1)
  assert_eq(directory.snapshot(@async.now()).users.length(), 1)
  assert_eq(directory.snapshot(@async.now()).access_grants.length(), 1)
  assert_eq(directory.snapshot(@async.now()).leases.length(), 1)
  let replay = service.handle(
    Post,
    "/v1/onboarding/access-packages",
    headers,
    body,
  )
  assert_eq(replay.status, 201)
  assert_eq(accounts.views().length(), 1)
  assert_eq(directory.snapshot(@async.now()).leases.length(), 1)
  let account = accounts.views()[0]
  assert_eq(
    service.handle(
      Post,
      "/v1/onboarding/access-packages/\{account.account_id}:enable",
      headers,
      "",
    ).status,
    409,
  )
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  ignore(
    contracts.create_packet(
      {
        ..@contractdoc.new_packet(
          manifest,
          "packet-access-onboarding",
          "packet-access-onboarding-key",
          "tenant-friendly",
          "org-friendly",
          account.subject_ref,
          "order-access-onboarding",
          None,
          [MasterLease],
          @async.now(),
        ),
        state: Effective,
      },
      "operator",
    ),
  )
  seed_access_package_model(registry)
  let enabled = service.handle(
    Post,
    "/v1/onboarding/access-packages/\{account.account_id}:enable",
    headers,
    "",
  )
  assert_eq(enabled.status, 200)
  assert_true(enabled.body.contains("\"state\":\"Ready\""))
  assert_true(enabled.body.contains("qwen.default"))
  let workspace = directory.snapshot(@async.now())
  assert_eq(workspace.leases[0].state, Active)
  let listed = service.handle(
    Get,
    "/v1/onboarding/access-packages",
    headers,
    "",
  )
  assert_eq(listed.status, 200)
  assert_true(listed.body.contains("Friendly Developer"))
  assert_true(listed.body.contains("\"ready\":true"))
  let audit = service.handle(Get, "/v1/audit", headers, "")
  assert_true(audit.body.contains("access-package.prepared"))
  assert_true(audit.body.contains("access-package.enabled"))
}

///|
async test "access onboarding recovers after a cross-store crash boundary and restart" {
  let temp = @fs.tmpdir(prefix="lunanexa-access-onboarding-restart-")
  let state_path = "\{temp}/state.json"
  let account_path = "\{temp}/accounts.json"
  let portal_path = "\{temp}/portal.json"
  let workspace_path = "\{temp}/workspace.json"
  let onboarding_path = "\{temp}/onboarding.json"
  let registry_path = "\{temp}/registry.json"
  let session_secret = "account-session-issuer-secret-more-than-thirty-two-bytes"
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let first_accounts = @account.AccountStore::open(account_path, session_secret)
  let first_portal = @portal_store.FilePortalStore::open(portal_path)
  let first_directory = @directory.FileWorkspaceDirectory::open(workspace_path)
  let first_journal = @onboarding.AccessOnboardingStore::open(onboarding_path)
  let first_base = ApiService::with_registry(
      @store.FileStore::open(state_path),
      @registry.FileRegistry::open(registry_path),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_account_store(
      first_accounts, "identity-assertion-secret-more-than-thirty-two-bytes",
    )
    .with_portal_store(first_portal)
    .with_workspace_directory(first_directory, true)
    .with_access_onboarding_store(first_journal)
  let first = {
    ..first_base,
    access_onboarding_fail_after_step: Some(MembershipReady),
  }
  let body = "{\"identity_issuer\":\"https://identity.example\",\"identity_subject\":\"restart-user\",\"display_name\":\"Restart User\",\"email\":\"restart@example.com\",\"organization_id\":\"org-restart\",\"tenant_ref\":\"tenant-restart\",\"template_id\":\"webide-developer\",\"lifetime_days\":30,\"identity_verified\":true}"
  let headers = { "Authorization": "Bearer operator-token" }
  let interrupted = first.handle(
    Post,
    "/v1/onboarding/access-packages",
    headers,
    body,
  )
  assert_eq(interrupted.status, 503)
  assert_eq(first_accounts.views().length(), 1)
  assert_eq(first_portal.snapshot().memberships.length(), 1)
  let interrupted_record = first_journal.snapshot().operations[0]
  assert_eq(interrupted_record.step, AccountReady)
  assert_eq(interrupted_record.status, RecoverableFailure)

  let reopened_accounts = @account.AccountStore::open(
    account_path, session_secret,
  )
  let reopened_portal = @portal_store.FilePortalStore::open(portal_path)
  let reopened_directory = @directory.FileWorkspaceDirectory::open(
    workspace_path,
  )
  let reopened_journal = @onboarding.AccessOnboardingStore::open(
    onboarding_path,
  )
  let restarted = ApiService::with_registry(
      @store.FileStore::open(state_path),
      @registry.FileRegistry::open(registry_path),
      runtime,
      "operator-token",
      "inference-token",
      "node-token",
      "0.1.0",
    )
    .with_account_store(
      reopened_accounts, "identity-assertion-secret-more-than-thirty-two-bytes",
    )
    .with_portal_store(reopened_portal)
    .with_workspace_directory(reopened_directory, true)
    .with_access_onboarding_store(reopened_journal)
  assert_eq(restarted.reconcile_access_onboarding(@async.now()), 1)
  let recovered = reopened_journal.snapshot().operations[0]
  assert_eq(recovered.step, Prepared)
  assert_eq(recovered.status, PreparedForEnablement)
  assert_eq(recovered.attempts, 2)
  assert_eq(reopened_accounts.views().length(), 1)
  assert_eq(reopened_portal.snapshot().memberships.length(), 1)
  let workspace = reopened_directory.snapshot(@async.now())
  assert_eq(workspace.users.length(), 1)
  assert_eq(workspace.access_grants.length(), 1)
  assert_eq(workspace.leases.length(), 1)
  let operations = restarted.handle(
    Get,
    "/v1/onboarding/access-packages/operations",
    headers,
    "",
  )
  assert_eq(operations.status, 200)
  assert_true(operations.body.contains("PreparedForEnablement"))
  assert_false(operations.body.contains("restart-user"))
}
