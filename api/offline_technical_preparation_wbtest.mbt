///|
async test "named operator prepares existing purchaser workspace and records bounded waiver without fabricated evidence" {
  let dir = @fs.tmpdir(prefix="technical-preparation-")
  defer @fs.rmdir(dir, recursive=true)
  let (base, commerce, _, _) = contract_bridge_fixture(dir)
  let now = @async.now()
  let draft = {
    ..undertaking_test_order(),
    order_id: "offline-order-current-test",
    idempotency_key: "current-test",
    quote: None,
    artifact_ids: [],
    state: Draft,
    created_unix_ms: now,
    updated_unix_ms: now,
    expires_unix_ms: now + 86400000L,
    policy: {
      require_executed_agreement: true,
      require_payment: true,
      invoice_timing: InvoiceBeforeFulfillment,
      require_identity_verification: true,
      require_internal_approval: true,
    },
  }
  ignore(commerce.create_order(draft))
  let quoted = commerce.quote_order(
    draft.order_id,
    {
      ..undertaking_test_order().quote.unwrap(),
      quote_id: "current-quote",
      created_unix_ms: now,
      valid_until_unix_ms: now + 3600000L,
    },
    "operator",
    now,
  )
  let order = commerce.begin_offline_execution(
    draft.order_id,
    quoted.generation,
    now,
  )
  let accounts = @account.AccountStore::open(
    dir + "/accounts.json",
    "test-only-session-secret-longer-than-thirty-two-bytes",
  )
  let issuer = "https://identity.example"
  for name in ["operator", "buyer"] {
    ignore(
      accounts.create({
        version: @account.contract_version,
        account_id: name,
        subject_ref: if name == "buyer" {
          "subject-a"
        } else {
          "subject-operator"
        },
        identity_issuer: issuer,
        identity_subject_sha256: @account.identity_subject_digest(issuer, name),
        display_name: name,
        email: name + "@example.test",
        identity_receipt: "actual-session-test-" + name,
        roles: if name == "operator" {
          [PlatformOperator]
        } else {
          [EnterpriseUser]
        },
        state: Active,
        created_unix_ms: now,
        updated_unix_ms: now,
      }),
    )
  }
  let operator = accounts.issue_session(
    issuer, "operator", "operator-login", 3600000L, now,
  )
  ignore(accounts.issue_session(issuer, "buyer", "buyer-login", 3600000L, now))
  let directory = @directory.FileWorkspaceDirectory::open(
    dir + "/workspace.json",
  )
  let journal = @onboarding.AccessOnboardingStore::open(
    dir + "/onboarding.json",
  )
  let portal = @portal_store.FilePortalStore::open(
    dir + "/technical-portal.json",
  )
  let scope : @offline.TechnicalAcceptanceAuthorization = {
    order_id: order.order_id,
    purchaser_subject_ref: order.purchaser_subject_ref,
    user_authorization_ref: "explicit-current-test-approval",
    expires_unix_ms: now + 7200000L,
    order_binding: Some({
      tenant_ref: order.tenant_ref,
      organization_id: order.organization_id,
      quote: order.quote.unwrap(),
      entitlement_kind: WorkspaceLease,
    }),
  }
  let service = base
    .with_account_store(
      accounts, "test-only-assertion-secret-longer-than-thirty-two-bytes",
    )
    .with_portal_store(portal)
    .with_workspace_directory(directory, true)
    .with_access_onboarding_store(journal)
    .with_technical_acceptance_authorization(scope)
  let headers = { "Authorization": "Bearer " + operator.secret }
  let body = (
    { "order_id": order.order_id, "expected_generation": order.generation } :
    Json).stringify()
  assert_eq(
    service.prepare_technical_workspace(
      { "Authorization": "Bearer operator-token" },
      body,
    ).status,
    403,
  )
  let prepared = service.prepare_technical_workspace(headers, body)
  assert_eq(prepared.status, 201, msg=prepared.body)
  let first = directory.snapshot(now)
  assert_eq(first.leases.length(), 1)
  let lease = first.leases[0]
  assert_eq(lease.state, Requested)
  assert_true(lease.expires_unix_ms - lease.starts_unix_ms <= 2700000L)
  assert_eq(lease.subject_ref, order.purchaser_subject_ref)
  assert_eq(lease.tenant_ref, order.tenant_ref)
  assert_eq(service.prepare_technical_workspace(headers, body).status, 201)
  assert_eq(directory.snapshot(now).leases, first.leases)
  assert_eq(accounts.views().length(), 2)
  let waiver_request : Json = {
    "order_id": order.order_id,
    "expected_generation": order.generation,
    "waiver_id": "current-waiver",
    "authority_target_ref": lease.lease_id,
    "grant_id": first.access_grants[0].grant_id,
    "user_authorization_ref": scope.user_authorization_ref,
    "reason": "unsigned-unpaid-test",
  }
  let waived = service.authorize_technical_waiver(
    headers,
    waiver_request.stringify(),
  )
  assert_eq(waived.status, 201, msg=waived.body)
  let result = commerce.order_for_operator(order.order_id)
  assert_eq(result.state, UnderReconciliation)
  assert_eq(result.expires_unix_ms, lease.expires_unix_ms)
  assert_eq(result.quote, order.quote)
  assert_eq(result.agreement_ref, None)
  assert_eq(result.artifact_ids, [])
  assert_eq(commerce.snapshot().reviews.length(), 0)
  assert_eq(directory.snapshot(now).leases[0].state, Requested)
  assert_true(service.technical_documentary_waiver_allowed(result, now + 1000L))
  assert_false(
    service.technical_documentary_waiver_allowed(result, result.expires_unix_ms),
  )
}
