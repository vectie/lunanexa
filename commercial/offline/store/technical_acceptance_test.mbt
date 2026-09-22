///|
fn technical_order_fixture() -> @offline.CommercialOrder {
  {
    ..order("technical-order"),
    tenant_ref: "technical-acceptance-tenant",
    organization_id: "technical-acceptance-org",
    selected_service_code: "technical-workspace-acceptance",
    agreement_ref: None,
    policy: {
      require_executed_agreement: true,
      require_payment: true,
      invoice_timing: InvoiceBeforeFulfillment,
      require_identity_verification: true,
      require_internal_approval: true,
    },
  }
}

///|
fn technical_quote_fixture() -> @offline.ImmutableQuote {
  {
    ..quote(),
    service_code: "technical-workspace-acceptance",
    subtotal: money(0L),
    tax: money(0L),
    total: money(0L),
    lines: [
      { ..quote().lines[0], unit_price: money(0L), line_total: money(0L), },
    ],
  }
}

///|
fn technical_waiver_fixture(
  o : @offline.CommercialOrder,
) -> @offline.TechnicalAcceptanceWaiver {
  {
    waiver_id: "waiver-test",
    classification: "technical-acceptance-waived-not-paid",
    waived_requirements: @offline.technical_waived_requirements(),
    order_id: o.order_id,
    tenant_ref: o.tenant_ref,
    organization_id: o.organization_id,
    purchaser_subject_ref: o.purchaser_subject_ref,
    quote: o.quote.unwrap(),
    authority_target_ref: "technical-lease",
    grant_id: "technical-grant",
    purchaser_account_id: "technical-account",
    identity_issuer: "https://id.example",
    identity_receipt: "actual-oidc-receipt",
    identity_verification_method: "actual-oidc-not-commercial-kyc",
    operator_account_id: "operator-account",
    operator_subject_ref: "operator-subject",
    operator_session_id: "non-secret-session-id",
    user_authorization_ref: "docs/evidence/authorization.md",
    reason: "isolated technical verification only",
    issued_unix_ms: 1200L,
    expires_unix_ms: 100000L,
    order_binding: None,
  }
}

///|
async test "technical waiver persists without fabricating evidence and rejects changed target expiry kind and injected draft" {
  let dir = @fs.tmpdir(prefix="technical-waiver-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/state.json"
  let s = @store.OfflineCommerceStore::open(path)
  ignore(s.create_order(technical_order_fixture()))
  let q = s.quote_order(
    "technical-order",
    technical_quote_fixture(),
    "operator",
    1100L,
  )
  let w = technical_waiver_fixture(q)
  let approved = s.authorize_technical_acceptance(q.order_id, q.generation, w)
  assert_eq(approved.state, UnderReconciliation)
  assert_eq(approved.policy, q.policy)
  assert_eq(s.snapshot().reviews.length(), 0)
  assert_eq(
    s.authorize_technical_acceptance(q.order_id, q.generation, w),
    approved,
  )
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_eq(reopened.order_for_operator(q.order_id), approved)
  let a = {
    ..activation(approved, 1300L),
    kind: WorkspaceLease,
    authority_target_ref: w.authority_target_ref,
  }
  for
    bad in [
      { ..a, kind: ExclusiveMachineLease, },
      { ..a, authority_target_ref: "another-target", },
    ] {
    try reopened.fulfill(q.order_id, approved.generation, bad, 1300L) catch {
      _ => ()
    } noraise {
      _ => fail("bad target accepted")
    }
  }
  try
    reopened.fulfill(q.order_id, approved.generation, a, w.expires_unix_ms)
  catch {
    _ => ()
  } noraise {
    _ => fail("expired waiver accepted")
  }
  for
    bad in [
      { ..approved, tenant_ref: "another-tenant", },
      { ..approved, quote: Some(quote()), },
      {
        ..approved,
        technical_acceptance_waiver: Some({ ..w, expires_unix_ms: 4000000L, }),
      },
    ] {
    try @offline.validate_order(bad) catch {
      _ => ()
    } noraise {
      _ => fail("rebound waiver accepted")
    }
  }
  try reopened.create_order({ ..approved, state: Draft, }) catch {
    _ => ()
  } noraise {
    _ => fail("injected waiver accepted")
  }
  assert_eq(
    reopened.fulfill(q.order_id, approved.generation, a, 1300L).state,
    FulfillmentPending,
  )
  assert_eq(reopened.snapshot().reviews.length(), 0)
  let pending = reopened.order_for_operator(q.order_id)
  let fulfilled = pending.confirm_activation(
    pending.generation,
    w.authority_target_ref,
    1400L,
  )
  assert_eq(
    fulfilled.request_reversal(fulfilled.generation, w.expires_unix_ms + 1L).state,
    ReversalPending,
  )
  assert_true(
    fulfilled
    .to_json()
    .stringify()
    .contains("technical-acceptance-waived-not-paid"),
  )
  let corrupt = {
    ..reopened.snapshot(),
    entitlement_activations: [{ ..a, kind: ExclusiveMachineLease, }],
  }
  let bad_path = dir + "/corrupt.json"
  @fs.write_file(
    bad_path,
    corrupt.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  try @store.OfflineCommerceStore::open(bad_path) catch {
    _ => ()
  } noraise {
    _ => fail("malformed technical target restored")
  }
}

///|
async test "explicit quoted-order extension preserves unpaid quote and narrows term across all entitlement kinds" {
  for
    kind in [@offline.WorkspaceLease, CapacityCommitment, ExclusiveMachineLease] {
    let dir = @fs.tmpdir(prefix="technical-extension-")
    defer @fs.rmdir(dir, recursive=true)
    let path = dir + "/state.json"
    let store = @store.OfflineCommerceStore::open(path)
    let draft = {
      ..order(
        "offline-order-extension",
        policy=technical_order_fixture().policy,
      ),
      agreement_ref: None,
      expires_unix_ms: 3000000000L,
    }
    ignore(store.create_order(draft))
    let quoted = store.quote_order(draft.order_id, quote(), "operator", 1100L)
    let begun = store.begin_offline_execution(
      draft.order_id,
      quoted.generation,
      1150L,
    )
    assert_eq(begun.state, PendingInternalApproval)
    let binding : @offline.TechnicalAcceptanceOrderBinding = {
      organization_id: begun.organization_id,
      tenant_ref: begun.tenant_ref,
      quote: begun.quote.unwrap(),
      entitlement_kind: kind,
    }
    let waiver = {
      ..technical_waiver_fixture(begun),
      order_binding: Some(binding),
    }
    let accepted = store.authorize_technical_acceptance(
      begun.order_id,
      begun.generation,
      waiver,
    )
    assert_eq(accepted.quote, begun.quote)
    assert_true(accepted.quote.unwrap().total.minor_units > 0L)
    assert_eq(accepted.expires_unix_ms, waiver.expires_unix_ms)
    assert_eq(accepted.agreement_ref, None)
    assert_eq(store.snapshot().reviews.length(), 0)
    assert_eq(accepted.artifact_ids.length(), 0)
    let a = {
      ..activation(accepted, 1300L),
      kind,
      authority_target_ref: waiver.authority_target_ref,
    }
    @offline.validate_technical_activation(accepted, a, 1300L)
    for
      wrong in [
        @offline.WorkspaceLease,
        CapacityCommitment,
        ExclusiveMachineLease,
      ] {
      if wrong != kind {
        try
          @offline.validate_technical_activation(
            accepted,
            { ..a, kind: wrong, },
            1300L,
          )
        catch {
          _ => ()
        } noraise {
          _ => fail("extension widened entitlement kind")
        }
      }
    }
    let changed = {
      ..waiver,
      order_binding: Some({ ..binding, tenant_ref: "other-tenant", }),
    }
    try
      @offline.validate_technical_waiver({
        ..accepted,
        technical_acceptance_waiver: Some(changed),
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("extension rebound tenant")
    }
    let pending = store.fulfill(
      accepted.order_id,
      accepted.generation,
      a,
      1300L,
    )
    assert_eq(pending.state, FulfillmentPending)
    assert_eq(
      @store.OfflineCommerceStore::open(path).order_for_operator(
        accepted.order_id,
      ),
      pending,
    )
  }
}
