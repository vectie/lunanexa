///|
async test "live profile authority remains available when operational recording fails" {
  let directory = @fs.tmpdir(prefix="profile-observation-")
  defer @fs.rmdir(directory, recursive=true)
  let accounts = @account.AccountStore::open(
    directory + "/accounts.json",
    "profile-test-issuer-secret-longer-than-32-bytes",
  )
  let now = @async.now()
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "profile-reader",
      subject_ref: "profile-reader",
      identity_issuer: "https://profile.example",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://profile.example", "reader",
      ),
      display_name: "Reader",
      email: "reader@example.test",
      identity_receipt: "profile-test",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let session = accounts.issue_session(
    "https://profile.example", "reader", "profile-nonce", 60000L, now,
  )
  let metrics = @observability.ObservabilityStore::open(
    directory + "/metrics.json",
  )
  @fs.mkdir(directory + "/metrics.json.next")
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "test-runtime",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      @store.FileStore::open(directory + "/state.json"),
      runtime,
      "operator",
      "inference",
      "node",
      "test",
    )
    .with_account_store(
      accounts, "profile-assertion-secret-longer-than-32-bytes",
    )
    .with_observability_store(metrics)
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      service.serve_on(server)
    })
    let client = @http.Client("http://" + server.addr.to_string(), headers={
      "Authorization": "Bearer " + session.secret,
    })
    defer client.close()
    let valid = @async.with_timeout(1000, () => client.get("/v1/auth/self"))
    assert_eq(valid.code, 200)
    assert_true(client.read_all().text().contains("EnterpriseUser"))
    ignore(
      accounts.revoke_session(
        session.session.session_id,
        "profile-reader",
        @async.now(),
      ),
    )
    let revoked = @async.with_timeout(1000, () => client.get("/v1/auth/self"))
    assert_eq(revoked.code, 401)
    ignore(client.read_all())
    assert_true(metrics.snapshot().events.is_empty())
  })
}
