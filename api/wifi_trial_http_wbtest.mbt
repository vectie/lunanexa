///|
async test "Wi-Fi QR redemption requires gateway proof and grants one fixed hour" {
  let directory = @fs.tmpdir(prefix="lunanexa-wifi-trial-")
  let secret = "wifi-trial-identity-assertion-secret-over-32-bytes"
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "wifi-trial-session-secret-more-than-32-bytes",
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let workspace = @directory.FileWorkspaceDirectory::open(
    "\{directory}/workspace.json",
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
    .with_account_store(accounts, secret)
    .with_portal_store(portal)
    .with_workspace_directory(workspace, true)
    .with_wifi_trial(25L, ["text.qwen"])
  let now = @async.now()
  let registration = service.handle_with_transport(
    Post,
    "/v1/auth/register",
    signed_registration_headers(
      secret,
      "https://identity.example",
      "wifi-visitor",
      "visitor@example.invalid",
      "Visitor",
      "wifi-visitor-registration",
      now,
      now + 30000L,
    ),
    "{\"lifetime_ms\":\"60000\"}",
    true,
  )
  assert_eq(registration.status, 201)
  let registered : TrialRegistrationResponse = @json.from_json(
    @json.parse(registration.body),
  )
  assert_true(registered.trial is None)
  let bearer = registered.session.secret
  let headers = { "Authorization": "Bearer \{bearer}" }
  assert_eq(
    service.handle(Post, "/v1/auth/wifi-trial:redeem", headers, "{}").status,
    403,
  )
  let issued = @async.now().to_string()
  let canonical = "lunanexa.wifi-trial.v1\n\{bearer}\n\{issued}"
  let digest = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).exact_view(),
      @utf8.encode(canonical).exact_view(),
    ),
  )
  headers["X-LunaNexa-Wifi-Trial-Issued-At"] = issued
  headers["X-LunaNexa-Wifi-Trial-Signature"] = "sha256:forged"
  assert_eq(
    service.handle(Post, "/v1/auth/wifi-trial:redeem", headers, "{}").status,
    403,
  )
  headers["X-LunaNexa-Wifi-Trial-Signature"] = "sha256:\{digest}"
  let redeemed = service.handle(
    Post,
    "/v1/auth/wifi-trial:redeem",
    headers,
    "{}",
  )
  assert_eq(redeemed.status, 201)
  let trial : @account.TrialEntitlement = @json.from_json(
    @json.parse(redeemed.body),
  )
  assert_eq(trial.expires_unix_ms - trial.starts_unix_ms, 3600000L)
  assert_eq(trial.maximum_requests, 25L)
  assert_eq(trial.allowed_models, ["text.qwen"])
  assert_eq(
    service.handle(Post, "/v1/auth/wifi-trial:redeem", headers, "{}").status,
    200,
  )
  assert_eq(
    accounts.trial_for_account(registered.account.account_id).unwrap().expires_unix_ms,
    trial.expires_unix_ms,
  )
  let restarted = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "wifi-trial-session-secret-more-than-32-bytes",
  )
  assert_eq(
    restarted.trial_for_account(registered.account.account_id).unwrap().expires_unix_ms,
    trial.expires_unix_ms,
  )
  assert_true(
    restarted.active_trial_for_subject(
      registered.account.subject_ref,
      trial.expires_unix_ms,
    )
    is None,
  )
  @fs.rmdir(directory, recursive=true)
}
