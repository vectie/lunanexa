///|
async test "registered account approval derives identity and tenant, preserves gates and retries without duplicate grants" {
  let temp = @fs.tmpdir(prefix="registered-access-")
  defer @fs.rmdir(temp, recursive=true)
  let now = @async.now()
  let durable = @store.FileStore::open(temp + "/state.json")
  let accounts = @account.AccountStore::open(
    temp + "/accounts.json",
    "test-only-secret-longer-than-thirty-two-bytes",
  )
  let portal = @portal_store.FilePortalStore::open(temp + "/portal.json")
  let directory = @directory.FileWorkspaceDirectory::open(
    temp + "/workspace.json",
  )
  let journal = @onboarding.AccessOnboardingStore::open(
    temp + "/onboarding.json",
  )
  let registry = @registry.FileRegistry::open(temp + "/registry.json")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "test-only-runtime",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let base = ApiService::with_registry(
      durable, registry, runtime, "operator-token", "inference-token", "node-token",
      "0.1.0",
    )
    .with_account_store(
      accounts, "test-only-assertion-secret-longer-than-thirty-two-bytes",
    )
    .with_portal_store(portal)
    .with_workspace_directory(directory, true)
    .with_access_onboarding_store(journal)
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "registered-alice",
      subject_ref: "registered-subject",
      identity_issuer: "https://id.example",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://id.example", "private-provider-subject",
      ),
      display_name: "Alice",
      email: "alice@example.test",
      identity_receipt: "verified-login-receipt",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  base.commercial_store.add_organization({
    organization_id: "approved-org",
    display_name: "Approved company",
    state: Active,
    verification_ref: Some("operator-review"),
    legal_profile: None,
    created_unix_ms: now,
  })
  base.commercial_store.add_organization({
    organization_id: "pending-org",
    display_name: "Pending company",
    state: PendingVerification,
    verification_ref: None,
    legal_profile: None,
    created_unix_ms: now,
  })
  ignore(
    portal.put_membership({
      membership_id: "owner-member",
      organization_id: "approved-org",
      tenant_ref: "approved-tenant",
      subject_ref: "organization-owner",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
    }),
  )
  let headers = { "Authorization": "Bearer operator-token" }
  let path = "/v1/onboarding/access-packages"
  let body = "{\"account_id\":\"registered-alice\",\"organization_id\":\"approved-org\",\"lifetime_days\":7,\"tenant_ref\":\"forged-tenant\",\"email\":\"forged@example.test\"}"
  assert_eq(base.handle(Post, path, Map([]), body).status, 401)
  assert_eq(
    base.handle(Post, path, { "Authorization": "Bearer inference-token" }, body).status,
    401,
  )
  assert_eq(base.handle(Get, path + "/options", Map([]), "").status, 401)
  let options = base.handle(Get, path + "/options", headers, "")
  assert_eq(options.status, 200)
  assert_true(options.body.contains("Approved company"))
  assert_false(options.body.contains("Pending company"))
  assert_eq(
    base.handle(
      Post,
      path,
      headers,
      body.replace(old="approved-org", new="pending-org"),
    ).status,
    409,
  )
  assert_eq(
    base.handle(Post, path, headers, body.replace(old="7", new="0")).status,
    400,
  )
  let prepared = base.handle(Post, path, headers, body)
  assert_eq(prepared.status, 201)
  assert_true(prepared.body.contains("ContractRequired"))
  assert_false(prepared.body.contains("forged"))
  assert_false(prepared.body.contains("private-provider-subject"))
  assert_eq(directory.snapshot(now).leases[0].state, Requested)
  let expires = directory.snapshot(now).leases[0].expires_unix_ms
  // Private-cloud access omits commercial contracts, but still needs a model.
  let private_cloud = base
    .with_private_cloud_workspace_access(true)
    .with_access_onboarding_store(
      @onboarding.AccessOnboardingStore::open(temp + "/onboarding.json"),
    )
  assert_eq(private_cloud.handle(Post, path, headers, body).status, 201)
  assert_eq(directory.snapshot(now).leases[0].state, Requested)
  seed_access_package_model(registry)
  let adapter = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let model_present = [false]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      adapter.run_forever(allow_failure=true) <| ((request, _, connection) => {
        let response = if request.path == "/health" {
          "ok"
        } else if model_present[0] {
          "{\"data\":[{\"id\":\"served-test\"}]}"
        } else {
          "{\"data\":[]}"
        }
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write_string(response)
        connection.end_response()
      })
    }
    let wrong_tenant = private_cloud.with_external_text_route(
      "qwen.default",
      "other-tenant",
      "node-test",
      "http://\{adapter.addr}",
      "served-test",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
    )
    assert_true(
      wrong_tenant.handle(Post, path, headers, body).body.contains(
        "ModelRequired",
      ),
    )
    assert_eq(
      wrong_tenant.handle(Post, path + "/registered-alice:enable", headers, "").status,
      409,
    )
    let private_cloud = private_cloud.with_external_text_route(
      "qwen.default",
      "approved-tenant",
      "node-test",
      "http://\{adapter.addr}",
      "served-test",
      "runtime-v1",
      "sha256:" + "b".repeat(64),
      "sha256:" + "a".repeat(64),
    )
    assert_true(
      private_cloud.handle(Post, path, headers, body).body.contains(
        "ModelRequired",
      ),
    )
    assert_eq(
      private_cloud.handle(Post, path + "/registered-alice:enable", headers, "").status,
      409,
    )
    model_present[0] = true
    let enabled = private_cloud.handle(Post, path, headers, body)
    assert_eq(enabled.status, 200)
    assert_eq(directory.snapshot(now).leases[0].state, Active)
    assert_eq(private_cloud.handle(Post, path, headers, body).status, 201)
    assert_eq(directory.snapshot(now).leases.length(), 1)
    assert_eq(directory.snapshot(now).access_grants.length(), 1)
    assert_eq(directory.snapshot(now).leases[0].expires_unix_ms, expires)
    assert_eq(
      private_cloud.handle(Post, path, headers, body.replace(old="7", new="30")).status,
      409,
    )
    ignore(accounts.set_state("registered-alice", Suspended, now + 1L))
    assert_eq(private_cloud.handle(Post, path, headers, body).status, 409)
    assert_eq(accounts.views()[0].state, Suspended)
  }
}
