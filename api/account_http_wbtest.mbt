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
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
    @store.FileStore::open("\{directory}/state.json"),
    runtime,
    "operator-token",
    "inference-token",
    "node-token",
    "0.1.0",
  ).with_account_store(
    accounts, "identity-assertion-create-secret-more-than-32-bytes",
  )
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
  @fs.rmdir(directory, recursive=true)
}
