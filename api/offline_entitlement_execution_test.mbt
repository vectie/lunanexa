///|
async fn authority_execution_fixture(
  directory : String,
  tenant? : String = "tenant-a",
  kind? : @offline.EntitlementKind = WorkspaceLease,
) -> (
  @api.ApiService,
  @offline_store.OfflineCommerceStore,
  @directory.FileWorkspaceDirectory,
  @offline.EntitlementActivation,
) {
  let (service, initial) = offline_api_fixture(directory)
  let now = @async.now()
  let order : @offline.CommercialOrder = {
    order_id: "authority-order",
    idempotency_key: "authority-order",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    purchaser_subject_ref: "subject-a",
    selected_service_code: "exclusive-dgx",
    selected_sla_code: "standard",
    policy: {
      require_executed_agreement: false,
      require_payment: false,
      invoice_timing: InvoiceNotRequired,
      require_identity_verification: false,
      require_internal_approval: false,
    },
    quote: Some(offline_test_quote("authority", now - 1000L)),
    agreement_ref: None,
    artifact_ids: [],
    entitlement_ref: None,
    requested_undertaking_term: None,
    technical_acceptance_waiver: None,
    state: FulfillmentPending,
    generation: 2L,
    created_unix_ms: now - 1000L,
    updated_unix_ms: now,
    expires_unix_ms: now + 3600000L,
  }
  let activation : @offline.EntitlementActivation = {
    activation_id: "authority-activation",
    idempotency_key: "authority-activation",
    order_id: order.order_id,
    organization_id: order.organization_id,
    purchaser_subject_ref: order.purchaser_subject_ref,
    kind,
    authority_target_ref: "authority-lease",
    expected_order_generation: 1L,
    state: EntitlementActivationRequested,
    entitlement_ref: None,
    authority_receipt: None,
    reason_code: None,
    requested_by: "operator-a",
    requested_unix_ms: now,
    completed_unix_ms: None,
  }
  let snapshot = {
    ..initial.snapshot(),
    orders: [order],
    entitlement_activations: [activation],
  }
  let path = "\{directory}/authority-state.json"
  @fs.write_file(
    path,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  let offline = @offline_store.OfflineCommerceStore::open(path)
  let workspaces = @directory.FileWorkspaceDirectory::open(
    "\{directory}/authority-workspaces.json",
  )
  ignore(
    workspaces.create_user({
      version: @workspace.contract_version,
      user_id: "authority-user",
      subject_ref: "subject-a",
      display_name: "Authority test",
      email: "authority@example.test",
      state: UserActive,
      created_unix_ms: now - 1000L,
      last_active_unix_ms: None,
      identity_receipt: "identity-authority",
    }),
  )
  ignore(
    workspaces.issue_access_grant(
      {
        version: @workspace.contract_version,
        grant_id: "authority-grant",
        user_id: "authority-user",
        tenant_ref: tenant,
        access: Developer,
        starts_unix_ms: now - 1000L,
        expires_unix_ms: now + 3600000L,
        state: GrantActive,
        policy_receipt: "authority-policy",
      },
      now,
    ),
  )
  ignore(
    workspaces.issue_lease(
      {
        version: @workspace.contract_version,
        lease_id: "authority-lease",
        tenant_ref: tenant,
        subject_ref: "subject-a",
        access: Developer,
        limits: {
          max_active_sessions: 1,
          max_session_duration_ms: 60000L,
          capabilities: [
            {
              capability: TextGenerate,
              max_concurrent_requests: 1,
              max_requests_per_hour: 10,
              max_input_units_per_request: 100,
              max_output_units_per_request: 100,
            },
          ],
        },
        starts_unix_ms: now - 1000L,
        expires_unix_ms: now + 3500000L,
        state: Requested,
        policy_receipt: "authority-policy",
      },
      now,
    ),
  )
  (
    service
    .with_offline_commerce_store(offline)
    .with_workspace_directory(workspaces, true),
    offline,
    workspaces,
    activation,
  )
}

///|
async test "offline authority executes real workspace activation reversal and replay" {
  let temporary = @fs.tmpdir(prefix="lunanexa-authority-execute-")
  defer @fs.rmdir(temporary, recursive=true)
  let (service, store, directory, activation) = authority_execution_fixture(
    temporary,
  )
  let endpoint = "/v1/offline-commerce/operator/entitlement-execute"
  let body : Json = { "activation": activation.to_json() }
  let unauthenticated = service.handle(
    Post,
    endpoint,
    chain_operator(),
    body.stringify(),
  )
  assert_eq(unauthenticated.status, 401)
  let unclaimed = service.handle(
    Post,
    endpoint,
    chain_authority(),
    body.stringify(),
  )
  assert_eq(unclaimed.status, 409)
  assert_eq(directory.snapshot(@async.now()).leases[0].state, Requested)
  ignore(store.claim_authority_work(@async.now()))
  let forged : Json = {
    "activation": { ..activation, authority_target_ref: "other-target", }.to_json(),
  }
  assert_eq(
    service.handle(Post, endpoint, chain_authority(), forged.stringify()).status,
    409,
  )
  let response = service.handle(
    Post,
    endpoint,
    chain_authority(),
    body.stringify(),
  )
  assert_eq(response.status, 200, msg=response.body)
  let result : @offline.EntitlementActivation = @json.from_json(
    @json.parse(response.body),
  )
  assert_eq(result.state, EntitlementActivationConfirmed)
  assert_eq(directory.snapshot(@async.now()).leases[0].state, Active)
  assert_true(directory.self_view("subject-a", @async.now()).authorized)
  assert_eq(store.order_for_operator(activation.order_id).state, Fulfilled)
  assert_eq(
    service.handle(Post, endpoint, chain_authority(), body.stringify()).body,
    response.body,
  )
  let callback = service.handle(
    Post,
    "/v1/offline-commerce/operator/entitlement-activation-results",
    chain_authority(),
    response.body,
  )
  assert_eq(callback.status, 200, msg=callback.body)
  let reopened = @offline_store.OfflineCommerceStore::open(
    "\{temporary}/authority-state.json",
  )
  let restored = @directory.FileWorkspaceDirectory::open(
    "\{temporary}/authority-workspaces.json",
  )
  let service = service
    .with_offline_commerce_store(reopened)
    .with_workspace_directory(restored, true)
  assert_eq(
    service.handle(Post, endpoint, chain_authority(), body.stringify()).body,
    response.body,
  )
  let order = reopened.order_for_operator(activation.order_id)
  let reversal : @offline.CommercialReversal = {
    reversal_id: "authority-reversal",
    idempotency_key: "authority-reversal",
    order_id: order.order_id,
    organization_id: order.organization_id,
    entitlement_ref: "authority-lease",
    reason: CustomerCancellation,
    expected_order_generation: order.generation,
    state: ReversalRequested,
    authority_receipt: None,
    reason_code: None,
    requested_by: "operator-a",
    requested_unix_ms: @async.now(),
    completed_unix_ms: None,
  }
  ignore(reopened.request_reversal(reversal))
  ignore(reopened.claim_authority_work(@async.now()))
  let reversal_body : Json = { "reversal": reversal.to_json() }
  let revoked = service.handle(
    Post,
    endpoint,
    chain_authority(),
    reversal_body.stringify(),
  )
  assert_eq(revoked.status, 200, msg=revoked.body)
  assert_eq(restored.snapshot(@async.now()).leases[0].state, Revoked)
  assert_false(restored.self_view("subject-a", @async.now()).authorized)
  assert_eq(reopened.order_for_operator(order.order_id).state, Revoked)
  assert_eq(
    service.handle(Post, endpoint, chain_authority(), reversal_body.stringify()).body,
    revoked.body,
  )
}

///|
async test "offline authority rejects cross tenant target without modifying it" {
  let temporary = @fs.tmpdir(prefix="lunanexa-authority-tenant-")
  defer @fs.rmdir(temporary, recursive=true)
  let (service, store, directory, activation) = authority_execution_fixture(
    temporary,
    tenant="tenant-b",
  )
  ignore(store.claim_authority_work(@async.now()))
  let body : Json = { "activation": activation.to_json() }
  let response = service.handle(
    Post,
    "/v1/offline-commerce/operator/entitlement-execute",
    chain_authority(),
    body.stringify(),
  )
  assert_eq(response.status, 409, msg=response.body)
  assert_true(response.body.contains("EntitlementTargetMismatch"))
  assert_eq(directory.snapshot(@async.now()).leases[0].state, Requested)
  assert_eq(
    store.order_for_operator(activation.order_id).state,
    FulfillmentPending,
  )
}

///|
async test "offline exclusive execution waits for actual provisioning and sanitization" {
  let temporary = @fs.tmpdir(prefix="lunanexa-authority-exclusive-")
  defer @fs.rmdir(temporary, recursive=true)
  let (service, store, _, activation) = authority_execution_fixture(
    temporary,
    kind=ExclusiveMachineLease,
  )
  let leases = @nodelease_store.FileExclusiveLeaseStore::open(
    "\{temporary}/exclusive.json",
    "test-only-authority-signing-secret",
  )
  let now = @async.now()
  let lease = leases.issue(
    {
      version: @nodelease.contract_version,
      idempotency_key: "authority-lease",
      lease_id: "authority-lease",
      node_id: "test-node",
      subject_ref: "subject-a",
      unix_username: "testuser",
      access_credential_ref: "ssh-cert:test-only",
      starts_unix_ms: now - 1000L,
      expires_unix_ms: now + 3400000L,
    },
    now,
  )
  let service = service.with_exclusive_lease_store(leases)
  ignore(store.claim_authority_work(now))
  let body : Json = { "activation": activation.to_json() }
  let endpoint = "/v1/offline-commerce/operator/entitlement-execute"
  assert_eq(
    service.handle(Post, endpoint, chain_authority(), body.stringify()).status,
    202,
  )
  let current = leases.lease(lease.intent.lease_id).unwrap()
  assert_eq(current.state, Provisioning)
  assert_eq(
    store.order_for_operator(activation.order_id).state,
    FulfillmentPending,
  )
  // Test-only injection of the existing node authority's observed state.
  ignore(
    leases.transition(
      current.intent.lease_id,
      {
        expected_generation: current.generation,
        state: Active,
        evidence_receipt: "test-only-node-provisioned",
      },
      @async.now(),
    ),
  )
  let response = service.handle(
    Post,
    endpoint,
    chain_authority(),
    body.stringify(),
  )
  assert_eq(response.status, 200, msg=response.body)
  let order = store.order_for_operator(activation.order_id)
  let reversal : @offline.CommercialReversal = {
    reversal_id: "exclusive-reverse",
    idempotency_key: "exclusive-reverse",
    order_id: order.order_id,
    organization_id: order.organization_id,
    entitlement_ref: "authority-lease",
    reason: CustomerCancellation,
    expected_order_generation: order.generation,
    state: ReversalRequested,
    authority_receipt: None,
    reason_code: None,
    requested_by: "operator-a",
    requested_unix_ms: @async.now(),
    completed_unix_ms: None,
  }
  ignore(store.request_reversal(reversal))
  ignore(store.claim_authority_work(@async.now()))
  let body : Json = { "reversal": reversal.to_json() }
  assert_eq(
    service.handle(Post, endpoint, chain_authority(), body.stringify()).status,
    202,
  )
  assert_eq(store.order_for_operator(order.order_id).state, ReversalPending)
  let states : Array[@nodelease.ExclusiveLeaseState] = [
    Draining,
    RevokingAccess,
    Sanitizing,
    Completed,
  ]
  for state in states {
    let current = leases.lease("authority-lease").unwrap()
    ignore(
      leases.transition(
        "authority-lease",
        {
          expected_generation: current.generation,
          state,
          evidence_receipt: "test-only-node-cleanup",
        },
        @async.now(),
      ),
    )
  }
  let response = service.handle(
    Post,
    endpoint,
    chain_authority(),
    body.stringify(),
  )
  assert_eq(response.status, 200, msg=response.body)
  assert_eq(store.order_for_operator(order.order_id).state, Revoked)
}
