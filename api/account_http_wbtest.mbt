///|
fn signed_identity_headers(
  secret : String,
  issuer : String,
  subject : String,
  nonce : String,
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
) -> Map[String, String] {
  let issued = issued_unix_ms.to_string()
  let expires = expires_unix_ms.to_string()
  let canonical = "lunanexa.identity.assertion.v1\n\{issuer}\n\{subject}\n\{issued}\n\{expires}\n\{nonce}"
  let signature = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode(canonical).view(),
    ),
  )
  {
    "X-LunaNexa-Identity-Issuer": issuer,
    "X-LunaNexa-Identity-Subject": subject,
    "X-LunaNexa-Identity-Issued-At": issued,
    "X-LunaNexa-Identity-Expires-At": expires,
    "X-LunaNexa-Identity-Nonce": nonce,
    "X-LunaNexa-Identity-Signature": "sha256:\{signature}",
  }
}

///|
async test "identity exchange requires trusted transport and stored roles" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-http-")
  let assertion_secret = "identity-assertion-test-secret-more-than-32-bytes"
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "browser-session-test-secret-more-than-32-bytes",
  )
  let now = @async.now()
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-enterprise",
      subject_ref: "subject-enterprise",
      identity_issuer: "https://identity.example/realms/lunanexa",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example/realms/lunanexa", "provider-subject-enterprise",
      ),
      display_name: "Enterprise User",
      email: "enterprise@example.invalid",
      identity_receipt: "identity-proof:enterprise",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now - 1L,
      updated_unix_ms: now - 1L,
    }),
  )
  let durable = @store.FileStore::open("\{directory}/state.json")
  durable.fence_controller(1L)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
  ).with_account_store(accounts, assertion_secret)
  let assertion_headers = signed_identity_headers(
    assertion_secret,
    "https://identity.example/realms/lunanexa",
    "provider-subject-enterprise",
    "assertion-nonce-one",
    now,
    now + 30000L,
  )
  assert_true(
    service.trusted_identity_assertion(assertion_headers, now) is Some(_),
  )
  let overlong_assertion = signed_identity_headers(
    assertion_secret,
    "https://identity.example/realms/lunanexa",
    "provider-subject-enterprise",
    "assertion-nonce-overlong",
    now,
    now + 30001L,
  )
  assert_true(
    service.trusted_identity_assertion(overlong_assertion, now) is None,
  )
  // A valid signature is not enough: only the transport-proved gateway may
  // exchange it for a browser session.
  let untrusted = service.handle_with_transport(
    Post,
    "/v1/auth/session:exchange",
    assertion_headers,
    "{\"lifetime_ms\":\"60000\"}",
    false,
  )
  assert_eq(untrusted.status, 401)
  assert_true(
    service.trusted_identity_assertion(assertion_headers, @async.now())
    is Some(_),
  )
  let exchanged = service.handle_with_transport(
    Post,
    "/v1/auth/session:exchange",
    assertion_headers,
    "{\"lifetime_ms\":\"60000\"}",
    true,
  )
  assert_eq(exchanged.status, 201)
  let issued : @account.IssuedBrowserSession = @json.from_json(
    @json.parse(exchanged.body),
  )
  let session_headers = {
    "Authorization": "Bearer \{issued.secret}",
    // These values are attacker-controlled and must never grant authority.
    "X-LunaNexa-Roles": "PlatformOperator",
    "X-LunaNexa-Tenant": "attacker-tenant",
  }
  let self = service.handle_with_transport(
    Get,
    "/v1/auth/self",
    session_headers,
    "",
    false,
  )
  assert_eq(self.status, 200)
  assert_true(self.body.contains("EnterpriseUser"))
  let sessions = service.handle_with_transport(
    Get,
    "/v1/auth/sessions",
    session_headers,
    "",
    false,
  )
  assert_eq(sessions.status, 200)
  assert_false(sessions.body.contains("lnxs_"))
  assert_false(sessions.body.contains("sha256:"))
  let operator_list = service.handle_with_transport(
    Get,
    "/v1/accounts",
    session_headers,
    "",
    false,
  )
  assert_eq(operator_list.status, 401)
  let replay = service.handle_with_transport(
    Post,
    "/v1/auth/session:exchange",
    assertion_headers,
    "{\"lifetime_ms\":\"60000\"}",
    true,
  )
  assert_eq(replay.status, 409)
  let changed_timestamp_replay = signed_identity_headers(
    assertion_secret,
    "https://identity.example/realms/lunanexa",
    "provider-subject-enterprise",
    "assertion-nonce-one",
    now + 1L,
    now + 29999L,
  )
  let changed_timestamp_reply = service.handle_with_transport(
    Post,
    "/v1/auth/session:exchange",
    changed_timestamp_replay,
    "{\"lifetime_ms\":\"60000\"}",
    true,
  )
  assert_eq(changed_timestamp_reply.status, 409)
  let suspended = service.handle_with_transport(
    Post,
    "/v1/accounts/account-enterprise:suspend",
    { "Authorization": "Bearer operator-token" },
    "",
    false,
  )
  assert_eq(suspended.status, 200)
  let after_suspend = service.handle_with_transport(
    Get,
    "/v1/auth/self",
    session_headers,
    "",
    false,
  )
  assert_eq(after_suspend.status, 401)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "operator account creation returns only the safe public view" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-create-http-")
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "browser-session-create-secret-more-than-32-bytes",
  )
  let access = @access.AccessStore::open(
    "\{directory}/access.json",
    "personal-api-key-test-secret-more-than-32-bytes",
  )
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let durable = @store.FileStore::open("\{directory}/state.json")
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_account_store(
      accounts, "identity-assertion-create-secret-more-than-32-bytes",
    )
    .with_access_store(access)
  let created = service.handle(
    Post,
    "/v1/accounts",
    { "Authorization": "Bearer operator-token" },
    "{\"account_id\":\"account-created\",\"subject_ref\":\"subject-created\",\"identity_issuer\":\"https://identity.example\",\"identity_subject\":\"raw-provider-subject\",\"display_name\":\"Created User\",\"email\":\"created@example.invalid\",\"identity_receipt\":\"identity-proof:created\",\"roles\":[\"AuditReader\"],\"state\":\"Active\"}",
  )
  assert_eq(created.status, 201)
  assert_true(created.body.contains("account-created"))
  assert_false(created.body.contains("raw-provider-subject"))
  assert_false(created.body.contains("identity_subject_sha256"))
  assert_false(
    @fs.read_file("\{directory}/accounts.json")
    .text()
    .contains("raw-provider-subject"),
  )
  let audit_session = accounts.issue_session(
    "https://identity.example",
    "raw-provider-subject",
    "created-account-audit-session",
    60000L,
    @async.now(),
  )
  let audit_headers = { "Authorization": "Bearer \{audit_session.secret}" }
  assert_eq(service.handle(Get, "/v1/audit", audit_headers, "").status, 200)
  assert_eq(service.handle(Get, "/v1/accounts", audit_headers, "").status, 401)
  let promoted = service.handle(
    Post,
    "/v1/accounts/account-created:set-roles",
    { "Authorization": "Bearer operator-token" },
    "{\"roles\":[\"PlatformOperator\"]}",
  )
  assert_eq(promoted.status, 200)
  // A role change revokes existing sessions, even when it increases authority.
  assert_eq(service.handle(Get, "/v1/audit", audit_headers, "").status, 401)
  let operator_session = accounts.issue_session(
    "https://identity.example",
    "raw-provider-subject",
    "created-account-operator-session",
    60000L,
    @async.now(),
  )
  let operator_headers = {
    "Authorization": "Bearer \{operator_session.secret}",
  }
  assert_eq(
    service.handle(Get, "/v1/accounts", operator_headers, "").status,
    200,
  )
  assert_eq(service.handle(Get, "/v1/audit", operator_headers, "").status, 200)
  let attribution_key = access.issue(
    {
      key_id: "key-operator-attribution",
      tenant_ref: "tenant-created",
      subject_ref: "subject-created",
      display_name: "Operator attribution proof",
      scopes: [Inference],
      allowed_models: [],
      expires_unix_ms: @async.now() + 60000L,
      maximum_requests: 10L,
    },
    @async.now(),
  )
  let attributed_revoke = service.handle(
    Post,
    "/v1/access/api-keys/key-operator-attribution:revoke",
    operator_headers,
    "",
  )
  assert_eq(attributed_revoke.status, 200)
  assert_true(
    durable
    .audit_events()
    .iter()
    .any(event => {
      event.actor == "subject-created" &&
      event.action == "operator.http.post" &&
      event.target == "/v1/access/api-keys/key-operator-attribution:revoke"
    }),
  )
  try
    access.authorize(
      attribution_key.secret,
      Inference,
      tenant_ref="tenant-created",
      @async.now(),
      false,
    )
  catch {
    @access.AccessError::Unauthorized => ()
    _ => fail("unexpected attributed API-key revocation error")
  } noraise {
    _ => fail("attributed operator revoke left the API key active")
  }
  let issued_key = access.issue(
    {
      key_id: "key-created-account",
      tenant_ref: "tenant-created",
      subject_ref: "subject-created",
      display_name: "Created account key",
      scopes: [Inference],
      allowed_models: [],
      expires_unix_ms: @async.now() + 60000L,
      maximum_requests: 10L,
    },
    @async.now(),
  )
  let invalid_roles = service.handle(
    Post,
    "/v1/accounts/account-created:set-roles",
    { "Authorization": "Bearer operator-token" },
    "{\"roles\":[\"AuditReader\",\"AuditReader\"]}",
  )
  assert_eq(invalid_roles.status, 400)
  ignore(
    access.authorize(
      issued_key.secret,
      Inference,
      tenant_ref="tenant-created",
      @async.now(),
      false,
    ),
  )
  let suspended = service.handle(
    Post,
    "/v1/accounts/account-created:suspend",
    { "Authorization": "Bearer operator-token" },
    "",
  )
  assert_eq(suspended.status, 200)
  try
    access.authorize(
      issued_key.secret,
      Inference,
      tenant_ref="tenant-created",
      @async.now(),
      false,
    )
  catch {
    @access.AccessError::Unauthorized => ()
    _ => fail("unexpected suspended-account key error")
  } noraise {
    _ => fail("suspending an account did not revoke its personal API key")
  }
  @fs.rmdir(directory, recursive=true)
}
