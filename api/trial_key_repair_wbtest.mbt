///|
async test "legacy personal trial keys are repaired without reissue renewal or usage reset" {
  let dir = @fs.tmpdir(prefix="trial-key-repair-")
  let issuer = "trial-repair-issuer-secret-at-least-32-bytes"
  let accounts = @account.AccountStore::open(dir + "/accounts.json", issuer)
  let access = @access.AccessStore::open(dir + "/access.json", issuer)
  let portal = @portal_store.FilePortalStore::open(dir + "/portal.json")
  let workspace = @directory.FileWorkspaceDirectory::open(
    dir + "/workspace.json",
  )
  let durable = @store.FileStore::open(dir + "/state.json")
  durable.fence_controller(1L)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:" + "b".repeat(64),
    "sha256:" + "a".repeat(64),
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "test",
    )
    .with_account_store(accounts, issuer)
    .with_access_store(access)
    .with_portal_store(portal)
    .with_workspace_directory(workspace, true)
    .with_private_cloud_workspace_access(true)
    .with_open_registration_trial(86400000L, 100L, ["text.qwen"])
  let now = @async.now()
  let response = service.handle_with_transport(
    Post,
    "/v1/auth/register",
    signed_registration_headers(
      issuer,
      "https://identity.example",
      "repair-user",
      "repair@example.invalid",
      "Repair user",
      "repair-nonce",
      now,
      now + 30000L,
    ),
    "{\"lifetime_ms\":\"60000\"}",
    true,
  )
  assert_eq(response.status, 201)
  let registered : TrialRegistrationResponse = @json.from_json(
    @json.parse(response.body),
  )
  let trial = registered.trial.unwrap()
  // Reproduce the old private-workspace branch: issued, but never bound, with
  // expiry beyond the actual entitlement. Existing usage must survive repair.
  let intent : @access.ApiKeyIssueIntent = {
    key_id: "legacy-trial-key",
    tenant_ref: trial.tenant_ref,
    subject_ref: registered.account.subject_ref,
    organization_id: trial.organization_id,
    project_id: trial.project_id,
    display_name: "Existing key",
    scopes: [ModelList, Inference],
    allowed_models: trial.allowed_models,
    expires_unix_ms: trial.expires_unix_ms + 3600000L,
    maximum_requests: 0L,
  }
  let issued = access.issue(intent, now + 10L)
  ignore(accounts.consume_trial_request(trial.trial_id, 6L, now + 11L))
  let old = access.issue({ ..intent, key_id: "revoked-key", }, now + 10L)
  ignore(access.revoke(old.credential.key_id, now + 11L))
  ignore(
    access.issue(
      { ..intent, key_id: "wrong-project", project_id: "foreign-project", },
      now + 10L,
    ),
  )
  ignore(
    access.issue(
      { ..intent, key_id: "wrong-model", allowed_models: ["foreign-model"], },
      now + 10L,
    ),
  )
  ignore(
    access.issue(
      { ..intent, key_id: "expired-key", expires_unix_ms: now + 11L, },
      now + 10L,
    ),
  )
  let headers = { "Authorization": "Bearer " + issued.secret }
  assert_eq(service.handle(Get, "/v1/models", headers, "").status, 401)
  let duplicate = access.issue(
    { ..intent, key_id: "ambiguous-key", },
    now + 10L,
  )
  assert_eq(service.reconcile_trial_api_keys(now + 20L), (0, 0, 1))
  assert_eq(
    accounts.trial_for_account(trial.account_id).unwrap().api_key_id,
    None,
  )
  ignore(access.revoke(duplicate.credential.key_id, now + 20L))
  assert_eq(service.reconcile_trial_api_keys(now + 20L), (1, 1, 0))
  assert_eq(service.reconcile_trial_api_keys(now + 21L), (0, 0, 0))
  assert_eq(service.handle(Get, "/v1/models", headers, "").status, 200)
  let repaired = accounts.trial_for_account(trial.account_id).unwrap()
  assert_eq(repaired.api_key_id, Some(intent.key_id))
  assert_eq(repaired.starts_unix_ms, trial.starts_unix_ms)
  assert_eq(repaired.expires_unix_ms, trial.expires_unix_ms)
  assert_eq(repaired.consumed_requests, Some(7L))
  let persisted = @access.AccessStore::open(dir + "/access.json", issuer)
  let key = persisted.snapshot().credentials
    .iter()
    .find_first(k => k.key_id == intent.key_id)
    .unwrap()
  assert_eq(key.secret_sha256, issued.credential.secret_sha256)
  assert_eq(key.expires_unix_ms, trial.expires_unix_ms)
  assert_eq(key.consumed_requests, 0L)
  assert_false(
    persisted.cap_expiry_for_subject(
      intent.key_id,
      trial.tenant_ref,
      intent.subject_ref,
      trial.expires_unix_ms + 1000L,
      now + 20L,
    ),
  )
  ignore(persisted.authorize(issued.secret, ModelList, now + 20L, false))
  let restored = @account.AccountStore::open(dir + "/accounts.json", issuer)
  assert_eq(restored.trial_for_account(trial.account_id), Some(repaired))
  assert_true(
    access.views().iter().find_first(k => k.key_id == "revoked-key").unwrap().revoked_unix_ms
    is Some(_),
  )
}
