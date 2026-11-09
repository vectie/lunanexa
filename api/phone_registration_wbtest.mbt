///|
async test "gateway-signed phone contact registers an ordinary durable account; contact tampering is denied" {
  let directory = @fs.tmpdir(prefix="phone-registration-")
  defer @fs.rmdir(directory, recursive=true)
  let secret = "phone-assertion-secret-more-than-32-bytes"
  let session_secret = "phone-session-secret-more-than-32-bytes"
  let accounts = @account.AccountStore::open(
    directory + "/accounts.json",
    session_secret,
  )
  let durable = @store.FileStore::open(directory + "/state.json")
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
  ).with_account_store(accounts, secret)
  let now = @async.now()
  let headers = signed_registration_headers(
    secret,
    "https://identity.example/realms/lunanexa",
    "phone-subject",
    "+8613800138000",
    "Phone Creator",
    "phone-nonce",
    now,
    now + 30000L,
  )
  let forged = headers.copy()
  forged["X-LunaNexa-Identity-Email"] = "+8613800138001"
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
  let reply = service.handle_with_transport(
    Post,
    "/v1/auth/register",
    headers,
    "{\"lifetime_ms\":\"60000\"}",
    true,
  )
  assert_eq(reply.status, 201)
  let registered : @account.OpenRegisteredAccount = @json.from_json(
    @json.parse(reply.body),
  )
  assert_eq(registered.account.roles, [EnterpriseUser])
  // The existing signed wire/storage slot is retained for compatibility; it
  // holds the actual contact identifier, never a fabricated email address.
  assert_eq(registered.account.email, "+8613800138000")
  let reopened = @account.AccountStore::open(
    directory + "/accounts.json",
    session_secret,
  )
  assert_true(
    reopened
    .views()
    .any(account => {
      account.account_id == registered.account.account_id &&
      account.email == "+8613800138000"
    }),
  )
}
