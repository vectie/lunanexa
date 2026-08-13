///|
async test "offline commerce PostgreSQL restart preserves state and rolls back conflicts" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  database.save_opaque_snapshot(
    "offline_commerce",
    @offline.snapshot_schema_version,
    @offline.OfflineCommerceSnapshot::{
      schema_version: @offline.snapshot_schema_version,
      templates: [],
      orders: [],
      artifacts: [],
      generation_requests: [],
      upload_grants: [],
      upload_callbacks: [],
      reviews: [],
      entitlement_activations: [],
      reversals: [],
      reversal_recoveries: [],
      transfer_sessions: [],
      transfer_evidence: [],
      work_claims: [],
      worker_health: @offline.empty_offline_worker_health(),
    }
    .to_json()
    .stringify(),
  )
  let now = @async.now()
  let store = @store.OfflineCommerceStore::open_postgres(database)
  let order : @offline.CommercialOrder = {
    order_id: "postgres-offline-order",
    idempotency_key: "postgres-offline-idempotency",
    tenant_ref: "postgres-tenant",
    organization_id: "postgres-org",
    project_id: "postgres-project",
    purchaser_subject_ref: "postgres-subject",
    selected_service_code: "exclusive-dgx",
    selected_sla_code: "standard",
    policy: {
      require_executed_agreement: true,
      require_payment: true,
      invoice_timing: InvoiceBeforeFulfillment,
      require_identity_verification: true,
      require_internal_approval: true,
    },
    quote: None,
    agreement_ref: None,
    artifact_ids: [],
    entitlement_ref: None,
    state: Draft,
    generation: 1L,
    created_unix_ms: now,
    updated_unix_ms: now,
    expires_unix_ms: now + 3600000L,
  }
  assert_eq(store.create_order(order), order)
  store.record_worker_acceptance(ArtifactDispatcher, now)
  store.record_worker_acceptance(EntitlementDispatcher, now)
  store.record_reconciler_attempt(now)
  store.record_reconciler_success(now)
  ignore(store.create_order({ ..order, selected_sla_code: "mutated" })) catch {
    @offline.OfflineCommerceError::IdempotencyConflict(_) => ()
    _ => fail("mutated PostgreSQL replay was accepted")
  }
  let reopened = @store.OfflineCommerceStore::open_postgres(database)
  assert_eq(reopened.order(order.organization_id, order.order_id), order)
  assert_eq(reopened.snapshot().orders.length(), 1)
  assert_eq(reopened.worker_readiness_blockers(now + 1L), [])
  let transfer_order : @offline.CommercialOrder = {
    ..order,
    order_id: "postgres-transfer-order",
    idempotency_key: "postgres-transfer-order-idempotency",
    quote: Some({
      quote_id: "postgres-transfer-quote",
      version: "v1",
      service_code: order.selected_service_code,
      sla_code: order.selected_sla_code,
      currency: "CNY",
      lines: [
        {
          line_id: "line",
          description: "transfer",
          quantity: 1L,
          unit: "lease",
          unit_price: { currency: "CNY", minor_units: 1L, scale: 2 },
          line_total: { currency: "CNY", minor_units: 1L, scale: 2 },
        },
      ],
      subtotal: { currency: "CNY", minor_units: 1L, scale: 2 },
      tax: { currency: "CNY", minor_units: 0L, scale: 2 },
      total: { currency: "CNY", minor_units: 1L, scale: 2 },
      valid_until_unix_ms: now + 3600000L,
      terms_digest: "sha256:" + "a".repeat(64),
      created_unix_ms: now,
    }),
    agreement_ref: Some("postgres-transfer-agreement"),
    state: PendingEvidenceUpload,
  }
  let grant : @offline.EvidenceUploadGrant = {
    grant_id: "postgres-transfer-grant",
    idempotency_key: "postgres-transfer-grant-idem",
    order_id: transfer_order.order_id,
    organization_id: transfer_order.organization_id,
    subject_ref: transfer_order.purchaser_subject_ref,
    artifact_id: "postgres-transfer-artifact",
    kind: ExecutedContractScan,
    revision: 1,
    expected_object_ref: "object://offline/postgres/transfer",
    allowed_media_types: ["application/pdf"],
    maximum_byte_count: 1000L,
    expires_unix_ms: now + 300000L,
    state: UploadGranted,
    created_unix_ms: now,
  }
  let session : @offline.OfflineTransferSession = {
    session_id: "postgres-transfer-session",
    idempotency_key: "postgres-transfer-session-idem",
    session_token_sha256: "sha256:" + "b".repeat(64),
    organization_id: transfer_order.organization_id,
    subject_ref: transfer_order.purchaser_subject_ref,
    order_id: transfer_order.order_id,
    artifact_id: grant.artifact_id,
    direction: UploadTransfer,
    media_types: grant.allowed_media_types,
    maximum_byte_count: grant.maximum_byte_count,
    expected_sha256: None,
    state: TransferIssued,
    issued_unix_ms: now,
    expires_unix_ms: now + 300000L,
    consumed_unix_ms: None,
  }
  database.save_opaque_snapshot(
    "offline_commerce",
    @offline.snapshot_schema_version,
    @offline.OfflineCommerceSnapshot::{
      schema_version: @offline.snapshot_schema_version,
      templates: [],
      orders: [transfer_order],
      artifacts: [],
      generation_requests: [],
      upload_grants: [grant],
      upload_callbacks: [],
      reviews: [],
      entitlement_activations: [],
      reversals: [],
      reversal_recoveries: [],
      transfer_sessions: [session],
      transfer_evidence: [],
      work_claims: [],
      worker_health: @offline.empty_offline_worker_health(),
    }
    .to_json()
    .stringify(),
  )
  let transfer_store = @store.OfflineCommerceStore::open_postgres(database)
  assert_eq(
    transfer_store.consume_transfer_session(
      session.session_id,
      session.session_token_sha256,
      "application/pdf",
      100L,
      "sha256:" + "c".repeat(64),
      "provider-transfer-postgres",
      now + 1L,
    ).state,
    TransferConsumed,
  )
  let transfer_reopened = @store.OfflineCommerceStore::open_postgres(database)
  assert_eq(
    transfer_reopened.transfer_session(
      session.organization_id,
      session.subject_ref,
      session.session_id,
    ).state,
    TransferConsumed,
  )
  let transfer_snapshot = transfer_reopened.snapshot()
  assert_eq(transfer_snapshot.transfer_evidence.length(), 1)
  assert_eq(
    transfer_snapshot.transfer_evidence[0].provider_receipt,
    "provider-transfer-postgres",
  )
  database.close()
}
