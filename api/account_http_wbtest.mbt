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
fn signed_registration_headers(
  secret : String,
  issuer : String,
  subject : String,
  email : String,
  display_name : String,
  nonce : String,
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
) -> Map[String, String] {
  let issued = issued_unix_ms.to_string()
  let expires = expires_unix_ms.to_string()
  let canonical = "lunanexa.identity.registration.v1\n\{issuer}\n\{subject}\n\{email}\n\{display_name}\n\{issued}\n\{expires}\n\{nonce}"
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
    "X-LunaNexa-Identity-Email": email,
    "X-LunaNexa-Identity-Display-Name": display_name,
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
async test "operator invitation enables one-time OIDC self-registration" {
  let directory = @fs.tmpdir(prefix="lunanexa-account-registration-http-")
  let assertion_secret = "registration-assertion-secret-more-than-32-bytes"
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "registration-session-secret-more-than-32-bytes",
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
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
      durable, runtime, "operator-token", "inference-token", "node-token", "test",
    )
    .with_account_store(accounts, assertion_secret)
    .with_portal_store(portal)
  let now = @async.now()
  let invitation_reply = service.handle(
    Post,
    "/v1/account-invitations",
    { "Authorization": "Bearer operator-token" },
    (
      {
        "invitation_id": "invitation-http-one",
        "email": "invited-http@example.invalid",
        "organization_id": "organization-http-one",
        "tenant_ref": "tenant-http-one",
        "project_id": "project-http-one",
        "expires_unix_ms": (now + 86400000L).to_json(),
      } : Json).stringify(),
  )
  assert_eq(invitation_reply.status, 201)
  let issued : @account.IssuedAccountInvitation = @json.from_json(
    @json.parse(invitation_reply.body),
  )
  assert_false(
    @fs.read_file("\{directory}/accounts.json").text().contains(issued.secret),
  )
  let headers = signed_registration_headers(
    assertion_secret,
    "https://identity.example/realms/lunanexa",
    "provider-subject-registration",
    "invited-http@example.invalid",
    "Registered User",
    "registration-nonce-one",
    now,
    now + 30000L,
  )
  let registration_body = (
    { "invitation_secret": issued.secret, "lifetime_ms": 60000L.to_json() } :
    Json).stringify()
  assert_eq(
    service.handle_with_transport(
      Post,
      "/v1/auth/register",
      headers,
      registration_body,
      false,
    ).status,
    401,
  )
  let registered_reply = service.handle_with_transport(
    Post,
    "/v1/auth/register",
    headers,
    registration_body,
    true,
  )
  assert_eq(registered_reply.status, 201)
  let registered : @account.RegisteredAccount = @json.from_json(
    @json.parse(registered_reply.body),
  )
  assert_eq(registered.account.roles, [EnterpriseUser])
  let membership = portal.self_view(registered.account.subject_ref).membership
  assert_eq(membership.organization_id, "organization-http-one")
  assert_eq(membership.tenant_ref, "tenant-http-one")
  assert_eq(membership.roles, [Developer])
  assert_eq(
    service.handle(
      Get,
      "/v1/auth/self",
      { "Authorization": "Bearer \{registered.session.secret}" },
      "",
    ).status,
    200,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "verified OIDC identity can register freely without machine authority" {
  let directory = @fs.tmpdir(prefix="lunanexa-open-registration-http-")
  let assertion_secret = "open-registration-assertion-secret-more-than-32-bytes"
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "open-registration-session-secret-more-than-32-bytes",
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
    durable, runtime, "operator-token", "inference-token", "node-token", "test",
  ).with_account_store(accounts, assertion_secret)
  let now = @async.now()
  let headers = signed_registration_headers(
    assertion_secret,
    "https://identity.example/realms/lunanexa",
    "provider-subject-open-registration",
    "open-registration@example.invalid",
    "Open Registration",
    "open-registration-nonce-one",
    now,
    now + 30000L,
  )
  let forged = headers.copy()
  forged["X-LunaNexa-Identity-Email"] = "attacker@example.invalid"
  assert_eq(
    service.handle_with_transport(
      Post,
      "/v1/auth/register",
      forged,
      "{\"lifetime_ms\":\"60000\"}",
      true,
    ).status,
    401,
  )
  let registered_reply = service.handle_with_transport(
    Post,
    "/v1/auth/register",
    headers,
    "{\"lifetime_ms\":\"60000\"}",
    true,
  )
  assert_eq(registered_reply.status, 201)
  let registered : @account.OpenRegisteredAccount = @json.from_json(
    @json.parse(registered_reply.body),
  )
  assert_eq(registered.account.roles, [EnterpriseUser])
  assert_eq(registered.account.email, "open-registration@example.invalid")
  let session_headers = {
    "Authorization": "Bearer \{registered.session.secret}",
  }
  assert_eq(
    service.handle(Get, "/v1/auth/self", session_headers, "").status,
    200,
  )
  // Registration never converts the browser session into operator or machine
  // authority. Those capabilities remain behind separate durable grants.
  assert_eq(
    service.handle(Get, "/v1/accounts", session_headers, "").status,
    401,
  )
  assert_eq(
    service.handle(Get, "/v1/portal/self", session_headers, "").status,
    503,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "bootstrap operator token retires after durable operator creation" {
  let directory = @fs.tmpdir(prefix="lunanexa-bootstrap-retirement-")
  let assertion_secret = "bootstrap-assertion-secret-more-than-32-bytes"
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "bootstrap-session-secret-more-than-32-bytes",
  )
  let now = @async.now()
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-platform-operator",
      subject_ref: "subject-platform-operator",
      identity_issuer: "https://identity.example/realms/lunanexa",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example/realms/lunanexa", "provider-platform-operator",
      ),
      display_name: "Platform Operator",
      email: "operator@example.invalid",
      identity_receipt: "identity-proof:platform-operator",
      roles: [PlatformOperator],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let session = accounts.issue_session(
    "https://identity.example/realms/lunanexa",
    "provider-platform-operator",
    "bootstrap-session-assertion",
    60000L,
    now + 1L,
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
      durable, runtime, "operator-token", "inference-token", "node-token", "test",
    )
    .with_account_store(accounts, assertion_secret)
    .with_retired_bootstrap_operator_token(true)
  assert_eq(
    service.handle(
      Get,
      "/v1/accounts",
      { "Authorization": "Bearer operator-token" },
      "",
    ).status,
    401,
  )
  assert_eq(
    service.handle(
      Get,
      "/v1/accounts",
      { "Authorization": "Bearer \{session.secret}" },
      "",
    ).status,
    200,
  )
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
      organization_id: "organization-created",
      project_id: "project-created",
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
      organization_id: "organization-created",
      project_id: "project-created",
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
