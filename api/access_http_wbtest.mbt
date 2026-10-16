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
test "OpenAI chat accepts nullable optional parameters from compatible clients" {
  let body : Json = {
    "model": "glm-5.3.flash",
    "messages": [{ "role": "user", "content": "hi" }],
    "stream": Json::null(),
    "max_tokens": Json::null(),
    "tools": Json::null(),
    "tool_choice": Json::null(),
    "parallel_tool_calls": Json::null(),
    "temperature": Json::null(),
    "top_p": Json::null(),
  }
  guard decode_openai_chat(body.stringify()) is Some(value) else {
    fail("nullable optional fields must be treated as omitted")
  }
  assert_eq(value.stream, None)
  assert_eq(value.max_tokens, None)
  assert_eq(value.tools, None)
  assert_eq(value.tool_choice, None)
  assert_eq(value.parallel_tool_calls, None)
  assert_eq(value.temperature, None)
  assert_eq(value.top_p, None)
  let streaming : Json = {
    "model": "glm-5.3.flash",
    "messages": [{ "role": "user", "content": "hi" }],
    "stream": true,
    "max_tokens": 1024,
    "tools": Json::null(),
    "temperature": 0.5,
  }
  guard decode_openai_chat(streaming.stringify()) is Some(streamed) else {
    fail("null normalization must retain explicit parameters")
  }
  assert_eq(streamed.stream, Some(true))
  assert_eq(streamed.max_tokens, Some(1024))
  assert_eq(streamed.temperature, Some(0.5))
  let budgets = @settings.default_global_admin_settings().request_budgets
  assert_true(valid_openai_request_budget(streamed, budgets))
  assert_false(
    valid_openai_request_budget({ ..streamed, max_tokens: Some(0), }, budgets),
  )
  assert_false(
    valid_openai_request_budget(
      { ..streamed, max_tokens: Some(budgets.openai_max_output_units + 1), },
      budgets,
    ),
  )
}

///|
test "OpenAI null normalization does not accept malformed required or optional fields" {
  for
    (field, invalid) in [
      ("model", Json::null()),
      ("messages", Json::null()),
      ("stream", Json::string("true")),
      ("max_tokens", Json::string("1024")),
      ("tools", Json::object({})),
      ("parallel_tool_calls", Json::string("false")),
      ("temperature", Json::string("0.5")),
      ("top_p", Json::string("1")),
    ] {
    let fields : Map[String, Json] = {
      "model": Json::string("glm-5.3.flash"),
      "messages": Json::array([{ "role": "user", "content": "hi" }]),
    }
    fields[field] = invalid
    assert_true(decode_openai_chat(Json::object(fields).stringify()) is None)
  }
}

///|
test "OpenAI validation errors identify limits without reflecting payloads" {
  let budgets = @settings.default_global_admin_settings().request_budgets
  let body : Json = {
    "model": "glm-5.3.flash",
    "messages": [{ "role": "user", "content": "private-prompt-do-not-reflect" }],
    "max_tokens": -1,
  }
  let message = invalid_openai_chat_message(body.stringify(), budgets)
  assert_true(message.has_prefix("max_tokens must be between 1 and "))
  assert_false(message.contains("private-prompt"))
  assert_eq(
    invalid_openai_chat_message("{}", budgets),
    "model must be a nonempty model ID",
  )
  assert_eq(
    invalid_openai_chat_message(
      "{\"model\":\"glm-5.3.flash\",\"messages\":[]}", budgets,
    ),
    "messages must be an array containing 1 to 256 messages",
  )
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
      organization_id: "organization-account-check",
      project_id: "project-account-check",
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
