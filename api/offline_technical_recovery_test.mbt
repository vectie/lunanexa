///|
async test "removed technical scope rejects durable pending work and compensates crash-activated workspace" {
  for crash_active in [false, true] {
    let temporary = @fs.tmpdir(prefix="technical-recovery-")
    defer @fs.rmdir(temporary, recursive=true)
    let tenant = "technical-acceptance-recovery"
    let (base, old, directory, initial) = authority_execution_fixture(
      temporary,
      tenant~,
    )
    let now = @async.now()
    let previous = old.snapshot().orders[0]
    let source_quote = previous.quote.unwrap()
    let zero = { ..source_quote.total, minor_units: 0L, }
    let quote = {
      ..source_quote,
      service_code: "technical-workspace-acceptance",
      subtotal: zero,
      tax: zero,
      total: zero,
      lines: source_quote.lines.map(l => {
        ..l,
        unit_price: zero,
        line_total: zero,
      }),
    }
    let waiver : @offline.TechnicalAcceptanceWaiver = {
      waiver_id: "recovery-waiver",
      classification: "technical-acceptance-waived-not-paid",
      waived_requirements: @offline.technical_waived_requirements(),
      order_id: previous.order_id,
      tenant_ref: tenant,
      organization_id: tenant,
      purchaser_subject_ref: previous.purchaser_subject_ref,
      quote,
      authority_target_ref: initial.authority_target_ref,
      grant_id: "authority-grant",
      purchaser_account_id: "technical-account",
      identity_issuer: "https://identity.example",
      identity_receipt: "actual-oidc-proof",
      identity_verification_method: "actual-oidc-not-commercial-kyc",
      operator_account_id: "operator-account",
      operator_subject_ref: "operator",
      operator_session_id: "non-secret-id",
      user_authorization_ref: "explicit-user-authorization",
      reason: "technical-test",
      issued_unix_ms: now - 1000L,
      expires_unix_ms: now + 3599000L,
      order_binding: None,
    }
    let order = {
      ..previous,
      tenant_ref: tenant,
      organization_id: tenant,
      selected_service_code: "technical-workspace-acceptance",
      quote: Some(quote),
      technical_acceptance_waiver: Some(waiver),
      generation: 3L,
      updated_unix_ms: now,
      expires_unix_ms: waiver.expires_unix_ms,
      policy: {
        require_executed_agreement: true,
        require_payment: true,
        invoice_timing: InvoiceBeforeFulfillment,
        require_identity_verification: true,
        require_internal_approval: true,
      },
    }
    let activation = {
      ..initial,
      organization_id: tenant,
      expected_order_generation: 2L,
    }
    let path = temporary + "/technical.json"
    @fs.write_file(
      path,
      {
        ..old.snapshot(),
        orders: [order],
        entitlement_activations: [activation],
      }
      .to_json()
      .stringify(),
      create_mode=CreateOrTruncate,
    )
    let store = @offline_store.OfflineCommerceStore::open(path)
    let service = base.with_offline_commerce_store(store)
    if crash_active {
      ignore(directory.activate_lease(activation.authority_target_ref, now))
    }
    ignore(store.claim_authority_work(now))
    let response = service.handle(
      Post,
      "/v1/offline-commerce/operator/entitlement-execute",
      chain_authority(),
      ({ "activation": activation.to_json() } : Json).stringify(),
    )
    assert_eq(response.status, 200, msg=response.body)
    let result : @offline.EntitlementActivation = @json.from_json(
      @json.parse(response.body),
    )
    assert_eq(result.state, EntitlementActivationRejected)
    assert_eq(
      result.reason_code,
      Some("TechnicalAuthorizationInvalidCompensated"),
    )
    assert_eq(directory.snapshot(now).leases[0].state, Revoked)
    let current = store.order_for_operator(order.order_id)
    assert_eq(current.state, UnderReconciliation)
    assert_eq(current.cancel(current.generation, now + 1L).state, Cancelled)
    assert_eq(
      service.handle(
        Post,
        "/v1/offline-commerce/operator/entitlement-execute",
        chain_authority(),
        ({ "activation": activation.to_json() } : Json).stringify(),
      ).body,
      response.body,
    )
  }
}
