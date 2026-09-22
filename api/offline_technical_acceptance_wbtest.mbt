///|
async test "technical waiver requires live operator session and actual purchaser login not static token or account existence" {
  let dir = @fs.tmpdir(prefix="waiver-auth-")
  defer @fs.rmdir(dir, recursive=true)
  let accounts = @account.AccountStore::open(
    dir + "/accounts.json",
    "technical-test-session-secret-more-than-32-bytes",
  )
  let durable = @store.FileStore::open(dir + "/state.json")
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
  ).with_account_store(
    accounts, "technical-test-assertion-secret-more-than-32-bytes",
  )
  let now = @async.now()
  let order : @offline.CommercialOrder = {
    order_id: "technical-acceptance-scope",
    idempotency_key: "scope",
    tenant_ref: "technical-acceptance-tenant",
    organization_id: "technical-acceptance-org",
    project_id: "project",
    purchaser_subject_ref: "subject-technical",
    selected_service_code: "technical-workspace-acceptance",
    selected_sla_code: "technical",
    policy: hybrid_offline_policy(),
    quote: None,
    agreement_ref: None,
    artifact_ids: [],
    entitlement_ref: None,
    requested_undertaking_term: None,
    technical_acceptance_waiver: None,
    state: Draft,
    generation: 1L,
    created_unix_ms: now,
    updated_unix_ms: now,
    expires_unix_ms: now + 60000L,
  }
  assert_false(
    service.technical_scope_allows(
      order,
      "explicit-user-authorization",
      now + 60000L,
      now,
    ),
  )
  let scoped = service.with_technical_acceptance_authorization({
    order_id: order.order_id,
    purchaser_subject_ref: order.purchaser_subject_ref,
    user_authorization_ref: "explicit-user-authorization",
    expires_unix_ms: now + 60000L,
  })
  assert_true(
    scoped.technical_scope_allows(
      order,
      "explicit-user-authorization",
      now + 60000L,
      now,
    ),
  )
  assert_false(
    scoped.technical_scope_allows(
      { ..order, order_id: "technical-acceptance-other", },
      "explicit-user-authorization",
      now + 60000L,
      now,
    ),
  )
  assert_false(
    scoped.technical_scope_allows(
      { ..order, purchaser_subject_ref: "subject-other", },
      "explicit-user-authorization",
      now + 60000L,
      now,
    ),
  )
  assert_false(
    scoped.technical_scope_allows(
      order,
      "different-authorization",
      now + 60000L,
      now,
    ),
  )
  assert_false(
    scoped.technical_scope_allows(
      order,
      "explicit-user-authorization",
      now + 60001L,
      now,
    ),
  )
  assert_false(
    scoped.technical_scope_allows(
      order,
      "explicit-user-authorization",
      now + 60000L,
      now + 60000L,
    ),
  )
  let issuer = "https://identity.example/realms/lunanexa"
  for name in ["operator", "purchaser"] {
    ignore(
      accounts.create({
        version: @account.contract_version,
        account_id: name,
        subject_ref: name,
        identity_issuer: issuer,
        identity_subject_sha256: @account.identity_subject_digest(issuer, name),
        display_name: name,
        email: "technical-" + name + "@example.invalid",
        identity_receipt: "actual-login-proof-" + name,
        roles: if name == "operator" {
          [PlatformOperator]
        } else {
          [EnterpriseUser]
        },
        state: Active,
        created_unix_ms: now - 1L,
        updated_unix_ms: now - 1L,
      }),
    )
  }
  assert_true(service.technical_identity("purchaser", now) is None)
  let operator = accounts.issue_session(
    issuer, "operator", "operator-login-assertion", 60000L, now,
  )
  let purchaser = accounts.issue_session(
    issuer, "purchaser", "purchaser-login-assertion", 60000L, now,
  )
  assert_true(service.technical_identity("purchaser", now) is Some(_))
  assert_eq(
    service.authorize_technical_waiver(
      { "Authorization": "Bearer operator-token" },
      "{}",
    ).status,
    403,
  )
  assert_eq(
    service.authorize_technical_waiver(
      { "Authorization": "Bearer " + purchaser.secret },
      "{}",
    ).status,
    403,
  )
  assert_eq(
    service.authorize_technical_waiver(
      { "Authorization": "Bearer " + operator.secret },
      "{}",
    ).status,
    400,
  )
  ignore(
    accounts.revoke_session(purchaser.session.session_id, "purchaser", now + 1L),
  )
  assert_true(service.technical_identity("purchaser", now + 2L) is None)
}
