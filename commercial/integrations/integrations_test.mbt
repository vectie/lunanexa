///|
fn payment_record() -> @integrations.ExternalRecord {
  {
    record_id: "payment-1",
    organization_id: "org-a",
    kind: Payment,
    provider: "dummy-pay",
    environment: "sandbox",
    external_ref: "pay-ref-1",
    state: Pending,
    expected_amount_minor: Some(1250L),
    currency: Some("CNY"),
    money_scale: Some(2),
    expected_document_hash: None,
    entitlement_transaction_ref: Some("entitlement-tx-1"),
    created_unix_ms: 1000L,
    updated_unix_ms: 1000L,
  }
}

///|
fn payment_callback(
  callback_id : String,
  previous : @integrations.ExternalRecordState,
  next : @integrations.ExternalRecordState,
  amount_minor? : Int64 = 1250L,
) -> @integrations.ExternalCallback {
  {
    callback_id,
    record_id: "payment-1",
    organization_id: "org-a",
    provider: "dummy-pay",
    environment: "sandbox",
    external_ref: "pay-ref-1",
    expected_previous_state: previous,
    next_state: next,
    amount_minor: Some(amount_minor),
    currency: Some("CNY"),
    document_hash: None,
    provider_event_unix_ms: 1100L,
    received_unix_ms: 1200L,
    signature_verified: true,
  }
}

///|
test "record registration is idempotent and provider-reference unique" {
  let store = @integrations.IntegrationStore::new()
  let record = payment_record()
  assert_eq(store.register(record), Applied)
  assert_eq(store.register(record), Replayed)
  let mut changed = false
  ignore(store.register({ ..record, expected_amount_minor: Some(1251L) })) catch {
    IdempotencyConflict(_) => changed = true
    _ => ()
  }
  assert_true(changed)
  let mut duplicate_ref = false
  ignore(store.register({ ..record, record_id: "payment-2" })) catch {
    AlreadyExists(_) => duplicate_ref = true
    _ => ()
  }
  assert_true(duplicate_ref)
}

///|
test "verified callbacks reconcile once and reject replay mutation" {
  let store = @integrations.IntegrationStore::new()
  ignore(store.register(payment_record()))
  let callback = payment_callback("callback-1", Pending, Authorized)
  let (authorized, first) = store.reconcile_callback(callback)
  assert_eq(first, Applied)
  assert_eq(authorized.state, Authorized)
  assert_eq(store.register(payment_record()), Replayed)
  let (same, replay) = store.reconcile_callback(callback)
  assert_eq(replay, Replayed)
  assert_eq(same, authorized)
  let mut mutated = false
  ignore(store.reconcile_callback({ ..callback, next_state: Settled })) catch {
    IdempotencyConflict(_) => mutated = true
    _ => ()
  }
  assert_true(mutated)
}

///|
test "callbacks are tenant, environment, amount, currency, and order bound" {
  let store = @integrations.IntegrationStore::new()
  ignore(store.register(payment_record()))
  let mut cross_tenant = false
  ignore(
    store.reconcile_callback({
      ..payment_callback("callback-tenant", Pending, Authorized),
      organization_id: "org-b",
    }),
  ) catch {
    TenantMismatch => cross_tenant = true
    _ => ()
  }
  assert_true(cross_tenant)
  let mut amount_mismatch = false
  ignore(
    store.reconcile_callback(
      payment_callback(
        "callback-amount",
        Pending,
        Authorized,
        amount_minor=999L,
      ),
    ),
  ) catch {
    EvidenceMismatch(_) => amount_mismatch = true
    _ => ()
  }
  assert_true(amount_mismatch)
  ignore(
    store.reconcile_callback(
      payment_callback("callback-authorized", Pending, Authorized),
    ),
  )
  let mut out_of_order = false
  ignore(
    store.reconcile_callback(
      payment_callback("callback-stale", Pending, Settled),
    ),
  ) catch {
    InvalidTransition(_) => out_of_order = true
    _ => ()
  }
  assert_true(out_of_order)
  assert_true(store.snapshot("org-a").reconciliation_exception_count >= 2)
}

///|
test "unverified callback cannot mutate payment state" {
  let store = @integrations.IntegrationStore::new()
  ignore(store.register(payment_record()))
  let mut rejected = false
  ignore(
    store.reconcile_callback({
      ..payment_callback("callback-unverified", Pending, Settled),
      signature_verified: false,
    }),
  ) catch {
    UnverifiedCallback => rejected = true
    _ => ()
  }
  assert_true(rejected)
  assert_eq(store.snapshot("org-a").records[0].state, Pending)
}

///|
test "identity records reject money and signature evidence binds document hash" {
  let store = @integrations.IntegrationStore::new()
  let mut identity_money = false
  ignore(
    store.register({
      record_id: "identity-1",
      organization_id: "org-a",
      kind: IdentityVerification,
      provider: "dummy-id",
      environment: "sandbox",
      external_ref: "identity-ref-1",
      state: Pending,
      expected_amount_minor: Some(1L),
      currency: Some("CNY"),
      money_scale: Some(2),
      expected_document_hash: None,
      entitlement_transaction_ref: None,
      created_unix_ms: 1000L,
      updated_unix_ms: 1000L,
    }),
  ) catch {
    InvalidInput(_) => identity_money = true
    _ => ()
  }
  assert_true(identity_money)
  let signature : @integrations.ExternalRecord = {
    record_id: "signature-1",
    organization_id: "org-a",
    kind: QualifiedSignature,
    provider: "dummy-sign",
    environment: "sandbox",
    external_ref: "envelope-secret-1",
    state: Pending,
    expected_amount_minor: None,
    currency: None,
    money_scale: None,
    expected_document_hash: Some("sha256:document-a"),
    entitlement_transaction_ref: None,
    created_unix_ms: 1000L,
    updated_unix_ms: 1000L,
  }
  ignore(store.register(signature))
  let mut hash_mismatch = false
  ignore(
    store.reconcile_callback({
      callback_id: "signature-callback-1",
      record_id: "signature-1",
      organization_id: "org-a",
      provider: "dummy-sign",
      environment: "sandbox",
      external_ref: "envelope-secret-1",
      expected_previous_state: Pending,
      next_state: Verified,
      amount_minor: None,
      currency: None,
      document_hash: Some("sha256:document-b"),
      provider_event_unix_ms: 1100L,
      received_unix_ms: 1200L,
      signature_verified: true,
    }),
  ) catch {
    EvidenceMismatch(_) => hash_mismatch = true
    _ => ()
  }
  assert_true(hash_mismatch)
  let snapshot = store.snapshot("org-a")
  assert_eq(snapshot.records.length(), 1)
  assert_true(snapshot.records[0].external_ref_sha256.has_prefix("sha256:"))
  assert_false(snapshot.to_json().stringify().contains("envelope-secret-1"))
}

///|
test "durable integration snapshot replays verified callback history" {
  let store = @integrations.IntegrationStore::new()
  let record : @integrations.ExternalRecord = {
    record_id: "payment-durable",
    organization_id: "org-durable",
    kind: Payment,
    provider: "provider-a",
    environment: "sandbox",
    external_ref: "payment-ref",
    state: Pending,
    expected_amount_minor: Some(1000L),
    currency: Some("CNY"),
    money_scale: Some(2),
    expected_document_hash: None,
    entitlement_transaction_ref: None,
    created_unix_ms: 1000L,
    updated_unix_ms: 1000L,
  }
  ignore(store.register(record))
  ignore(
    store.reconcile_callback({
      callback_id: "callback-durable",
      record_id: record.record_id,
      organization_id: record.organization_id,
      provider: record.provider,
      environment: record.environment,
      external_ref: record.external_ref,
      expected_previous_state: Pending,
      next_state: Settled,
      amount_minor: Some(1000L),
      currency: Some("CNY"),
      document_hash: None,
      provider_event_unix_ms: 1100L,
      received_unix_ms: 1200L,
      signature_verified: true,
    }),
  )
  let snapshot = store.durable_snapshot()
  let decoded : @integrations.IntegrationDurableSnapshot = @json.from_json(
    @json.parse(snapshot.to_json().stringify()),
  )
  let restored = @integrations.IntegrationStore::from_durable_snapshot(decoded)
  assert_eq(restored.durable_snapshot(), snapshot)
}
