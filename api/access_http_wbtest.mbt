///|
test "bearer credential mutation fuzz rejects controls and ambiguous syntax" {
  assert_eq(
    bearer_secret({ "Authorization": "Bearer token._~-safe" }),
    Some("token._~-safe"),
  )
  for
    value in [
      "",
      "Bearer",
      "Bearer ",
      "bearer token",
      "Basic token",
      "Bearer token value",
      "Bearer token\nX-Forged: yes",
      "Bearer token\rX-Forged: yes",
      "Bearer token\tvalue",
      "Bearer 服务",
      "Bearer \u{7f}",
      "Bearer " + "a".repeat(4097),
    ] {
    assert_eq(bearer_secret({ "Authorization": value }), None)
  }
  for character in [' ', '\n', '\r', '\t', '\u{0}', '\u{7f}'] {
    let value = "Bearer left\{character}right"
    assert_eq(bearer_secret({ "Authorization": value }), None)
  }
}

///|
test "OpenAI compatibility decoder rejects malformed and oversized shapes" {
  for
    body in [
      "", "{", "[]", "null", "true", "{}", "{\"model\":1}", "{\"model\":\"model-a\",\"messages\":{}}",
    ] {
    assert_true(decode_openai_chat(body) is None)
  }
  let valid = "{\"model\":\"model-a\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  assert_true(decode_openai_chat(valid) is Some(_))
}

///|
async test "personal API keys recheck the current account before quota use" {
  let directory = @fs.tmpdir(prefix="lunanexa-access-account-check-")
  let now = @async.now()
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "account-check-session-secret-more-than-32-bytes",
  )
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-api-user",
      subject_ref: "subject-api-user",
      identity_issuer: "https://identity.example",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example", "provider-api-user",
      ),
      display_name: "API User",
      email: "api-user@example.invalid",
      identity_receipt: "identity-proof:api-user",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let access = @access.AccessStore::open(
    "\{directory}/access.json",
    "account-check-api-key-secret-more-than-32-bytes",
  )
  let issued = access.issue(
    {
      key_id: "key-account-check",
      tenant_ref: "tenant-account-check",
      subject_ref: "subject-api-user",
      display_name: "Account-bound key",
      scopes: [Inference],
      allowed_models: [],
      expires_unix_ms: now + 60000L,
      maximum_requests: 10L,
    },
    now,
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
    )
    .with_access_store(access)
    .with_account_store(
      accounts, "account-check-assertion-secret-more-than-32-bytes",
    )
    .with_legacy_unbound_access_for_local_testing()
  let headers = { "Authorization": "Bearer \{issued.secret}" }
  assert_true(
    service.api_key_check(headers, Inference, None, None, true)
    is KeyAuthorized(_),
  )
  assert_eq(access.snapshot().credentials[0].consumed_requests, 1L)
  ignore(accounts.set_state("account-api-user", Suspended, now + 1L))
  assert_true(
    service.api_key_check(headers, Inference, None, None, true) is KeyDenied,
  )
  assert_eq(access.snapshot().credentials[0].consumed_requests, 1L)
  @fs.rmdir(directory, recursive=true)
}
