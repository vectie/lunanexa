///|
let digest_a : String = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

///|
let digest_b : String = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

///|
fn temp_path(name : String) -> String {
  "/tmp/lunanexa-offline-commerce-\{@async.now()}-\{name}.json"
}

///|
fn money(value : Int64) -> @commercial.FixedMoney {
  { minor_units: value, currency: "CNY", scale: 2 }
}

///|
fn order(
  id : String,
  policy? : @offline.FulfillmentPolicy = {
    require_executed_agreement: true,
    require_payment: false,
    invoice_timing: InvoiceNotRequired,
    require_identity_verification: false,
    require_internal_approval: false,
  },
) -> @offline.CommercialOrder {
  {
    order_id: id,
    idempotency_key: "idem-\{id}",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-a",
    purchaser_subject_ref: "buyer-a",
    selected_service_code: "exclusive-dgx",
    selected_sla_code: "standard",
    policy,
    quote: None,
    agreement_ref: Some("agreement-a"),
    artifact_ids: [],
    entitlement_ref: None,
    state: Draft,
    generation: 1L,
    created_unix_ms: 1000L,
    updated_unix_ms: 1000L,
    expires_unix_ms: 100000L,
  }
}

///|
fn quote() -> @offline.ImmutableQuote {
  {
    quote_id: "quote-a",
    version: "v1",
    service_code: "exclusive-dgx",
    sla_code: "standard",
    currency: "CNY",
    lines: [
      {
        line_id: "node-day",
        description: "Exclusive DGX node day",
        quantity: 2L,
        unit: "day",
        unit_price: money(50000L),
        line_total: money(100000L),
      },
    ],
    subtotal: money(100000L),
    tax: money(6000L),
    total: money(106000L),
    valid_until_unix_ms: 90000L,
    terms_digest: digest_a,
    created_unix_ms: 1100L,
  }
}

///|
fn contract_template() -> @offline.DocumentTemplate {
  {
    template_id: "contract-cn",
    version: "v1",
    kind: ContractTemplate,
    locale: "zh-CN",
    media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    object_ref: "s3://templates/contract-cn-v1.docx",
    sha256: digest_a,
    byte_count: 20000L,
    active_content_allowed: false,
    created_unix_ms: 1000L,
    superseded_unix_ms: None,
  }
}

///|
fn generation_request(
  order_id : String,
  artifact_id : String,
) -> @offline.ArtifactGenerationRequest {
  {
    request_id: "request-\{artifact_id}",
    order_id,
    organization_id: "org-a",
    artifact_id,
    kind: PrintReadyContractPdf,
    template_id: "contract-cn",
    template_version: "v1",
    locale: "zh-CN",
    expected_object_ref: "s3://orders/\{order_id}/\{artifact_id}.pdf",
    input_snapshot_sha256: digest_a,
    requested_by: "operator-a",
    requested_unix_ms: 1400L,
  }
}

///|
async fn ready_for_upload(
  store : @store.OfflineCommerceStore,
  order_id : String,
) -> @offline.CommercialOrder {
  ignore(store.register_template(contract_template()))
  ignore(store.create_order(order(order_id)))
  let quoted = store.quote_order(order_id, quote(), "operator-a", 1200L)
  let begun = store.begin_offline_execution(order_id, quoted.generation, 1300L)
  let request = generation_request(order_id, "contract-pdf")
  ignore(store.request_generation(request))
  ignore(store.claim_generation_requests(1450L))
  ignore(
    store.complete_generation({
      request_id: request.request_id,
      artifact_id: request.artifact_id,
      expected_object_ref: request.expected_object_ref,
      media_type: "application/pdf",
      byte_count: 30000L,
      sha256: digest_a,
      worker_receipt: "worker-receipt-a",
      verified: true,
      active_content_detected: false,
      moonleaf_verified: false,
      render_verified: true,
      formula_error_count: 0,
      visual_evidence_sha256: digest_b,
      completed_unix_ms: 1500L,
    }),
  )
  let after_artifact = store.order("org-a", order_id)
  assert_eq(after_artifact.state, begun.state)
  store.release_offline_packet(order_id, after_artifact.generation, 1600L)
}

///|
fn upload_grant(
  order_id : String,
  artifact_id : String,
  kind? : @offline.DocumentArtifactKind = ExecutedContractScan,
) -> @offline.EvidenceUploadGrant {
  {
    grant_id: "grant-\{artifact_id}",
    idempotency_key: "upload-\{artifact_id}",
    order_id,
    organization_id: "org-a",
    subject_ref: "buyer-a",
    artifact_id,
    kind,
    revision: 1,
    expected_object_ref: "s3://orders/\{order_id}/uploads/\{artifact_id}.pdf",
    allowed_media_types: ["application/pdf"],
    maximum_byte_count: 1000000L,
    expires_unix_ms: 3000L,
    state: UploadGranted,
    created_unix_ms: 2000L,
  }
}

///|
fn callback(
  grant : @offline.EvidenceUploadGrant,
) -> @offline.EvidenceUploadCallback {
  {
    callback_id: "callback-\{grant.artifact_id}",
    grant_id: grant.grant_id,
    expected_object_ref: grant.expected_object_ref,
    media_type: "application/pdf",
    byte_count: 50000L,
    sha256: digest_b,
    scan_passed: true,
    active_content_detected: false,
    scanner_receipt: "scanner-\{grant.artifact_id}",
    verified: true,
    completed_unix_ms: 2200L,
  }
}

///|
fn activation(
  order : @offline.CommercialOrder,
  requested_unix_ms : Int64,
) -> @offline.EntitlementActivation {
  {
    activation_id: "activation-\{order.order_id}",
    idempotency_key: "activate-\{order.order_id}",
    order_id: order.order_id,
    organization_id: order.organization_id,
    purchaser_subject_ref: order.purchaser_subject_ref,
    kind: ExclusiveMachineLease,
    authority_target_ref: "lease-request-a",
    expected_order_generation: order.generation,
    state: EntitlementActivationRequested,
    entitlement_ref: None,
    authority_receipt: None,
    reason_code: None,
    requested_by: "operator-a",
    requested_unix_ms,
    completed_unix_ms: None,
  }
}

///|
async test "hybrid order survives restart and fulfills only reviewed evidence" {
  let path = temp_path("happy")
  let store = @store.OfflineCommerceStore::open(path)
  let awaiting = ready_for_upload(store, "order-happy")
  assert_eq(awaiting.state, PendingEvidenceUpload)
  let reopened = @store.OfflineCommerceStore::open(path)
  let grant = upload_grant("order-happy", "executed-contract")
  assert_eq(reopened.grant_upload(grant), grant)
  assert_eq(reopened.grant_upload(grant), grant)
  let uploaded = reopened.complete_upload(callback(grant))
  assert_eq(uploaded.review_state, AwaitingReview)
  let reconciling = reopened.order("org-a", "order-happy")
  assert_eq(reconciling.state, UnderReconciliation)
  ignore(
    reopened.fulfill(
      "order-happy",
      reconciling.generation,
      activation(reconciling, 2300L),
      2300L,
    ),
  ) catch {
    @offline.OfflineCommerceError::EvidenceMissing(missing) =>
      assert_eq(missing, [ExecutedAgreementEvidence])
    _ => fail("expected missing evidence")
  }
  let accepted = reopened.review_evidence({
    review_id: "review-contract",
    order_id: "order-happy",
    artifact_id: uploaded.artifact_id,
    expected_artifact_sha256: uploaded.sha256,
    reviewer_ref: "legal-a",
    accepted: true,
    reason_code: "EvidenceVerified",
    audit_receipt: "audit-review-contract",
    reviewed_unix_ms: 2400L,
  })
  assert_eq(accepted.review_state, ReviewAccepted)
  let reviewed = reopened.order("org-a", "order-happy")
  let pending = reopened.fulfill(
    "order-happy",
    reviewed.generation,
    activation(reviewed, 2500L),
    2500L,
  )
  assert_eq(pending.state, FulfillmentPending)
  let requested = activation(reviewed, 2500L)
  ignore(reopened.claim_authority_work(2550L))
  let fulfilled = reopened.complete_activation({
    ..requested,
    state: EntitlementActivationConfirmed,
    entitlement_ref: Some("lease-a"),
    authority_receipt: Some("lease-authority-receipt-a"),
    completed_unix_ms: Some(2600L),
  })
  assert_eq(fulfilled.state, Fulfilled)
  assert_eq(fulfilled.entitlement_ref, Some("lease-a"))
  let final_store = @store.OfflineCommerceStore::open(path)
  assert_eq(final_store.order("org-a", "order-happy").state, Fulfilled)
  @fs.remove(path)
}

///|
async test "v1 snapshot migrates in place without losing orders" {
  let path = temp_path("migrate-v1")
  let legacy_order = order("order-legacy")
  let legacy : Json = {
    "schema_version": "lunanexa.offline-commerce.snapshot.v1",
    "templates": [],
    "orders": [legacy_order.to_json()],
    "artifacts": [],
    "generation_requests": [],
    "upload_grants": [],
    "upload_callbacks": [],
    "reviews": [],
  }
  @fs.write_file(
    path,
    legacy.stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let migrated = @store.OfflineCommerceStore::open(path)
  assert_eq(migrated.order("org-a", "order-legacy"), legacy_order)
  let persisted = @fs.read_file(path).text()
  assert_true(persisted.contains(@offline.snapshot_schema_version))
  assert_true(persisted.contains("entitlement_activations"))
  assert_true(persisted.contains("reversals"))
  @fs.remove(path)
}

///|
async test "expiry cancellation activation and reversal are durable sagas" {
  let path = temp_path("lifecycle")
  let store = @store.OfflineCommerceStore::open(path)
  let draft = order("order-cancel")
  ignore(
    try store.create_order(draft) catch {
      error => fail("create cancel failed: \{Repr(error)}")
    } noraise {
      value => value
    },
  )
  let cancelled = try
    store.cancel_order(draft.order_id, draft.generation, 2000L)
  catch {
    error => fail("cancel failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  assert_eq(cancelled.state, Cancelled)
  ignore(
    try
      store.create_order({ ..order("order-expire"), expires_unix_ms: 3000L })
    catch {
      error => fail("create expiry failed: \{Repr(error)}")
    } noraise {
      value => value
    },
  )
  let expired = try store.expire_orders(3000L) catch {
    error => fail("expiry failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  assert_eq(expired.length(), 1)
  assert_eq(expired[0].state, Expired)

  let awaiting = try ready_for_upload(store, "order-reverse") catch {
    error => fail("ready failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  let grant = upload_grant("order-reverse", "evidence-reverse")
  ignore(store.grant_upload(grant))
  let uploaded = try store.complete_upload(callback(grant)) catch {
    error => fail("upload failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  ignore(
    try
      store.review_evidence({
        review_id: "review-reverse",
        order_id: awaiting.order_id,
        artifact_id: uploaded.artifact_id,
        expected_artifact_sha256: uploaded.sha256,
        reviewer_ref: "legal-a",
        accepted: true,
        reason_code: "EvidenceVerified",
        audit_receipt: "audit-review-reverse",
        reviewed_unix_ms: 2400L,
      })
    catch {
      error => fail("review failed: \{Repr(error)}")
    } noraise {
      value => value
    },
  )
  let reviewed = store.order("org-a", awaiting.order_id)
  let requested = activation(reviewed, 2500L)
  ignore(
    try
      store.fulfill(reviewed.order_id, reviewed.generation, requested, 2500L)
    catch {
      error => fail("fulfill request failed: \{Repr(error)}")
    } noraise {
      value => value
    },
  )
  ignore(store.claim_authority_work(2550L))
  let fulfilled = try
    store.complete_activation({
      ..requested,
      state: EntitlementActivationConfirmed,
      entitlement_ref: Some("lease-reverse"),
      authority_receipt: Some("lease-authority-receipt-reverse"),
      completed_unix_ms: Some(2600L),
    })
  catch {
    error => fail("activation failed: \{Repr(error)}")
  } noraise {
    value => value
  }
  let activation_result : @offline.EntitlementActivation = {
    ..requested,
    state: EntitlementActivationConfirmed,
    entitlement_ref: Some("lease-reverse"),
    authority_receipt: Some("lease-authority-receipt-reverse"),
    completed_unix_ms: Some(2600L),
  }
  assert_eq(store.complete_activation(activation_result), fulfilled)
  ignore(
    store.complete_activation({
      ..activation_result,
      authority_receipt: Some("different-receipt"),
    }),
  ) catch {
    @offline.OfflineCommerceError::IdempotencyConflict(_) => ()
    _ => fail("mutated activation callback did not conflict")
  }
  let reversal : @offline.CommercialReversal = {
    reversal_id: "reversal-order-reverse",
    idempotency_key: "reverse-order-reverse",
    order_id: fulfilled.order_id,
    organization_id: fulfilled.organization_id,
    entitlement_ref: "lease-reverse",
    reason: PaymentRefunded,
    expected_order_generation: fulfilled.generation,
    state: ReversalRequested,
    authority_receipt: None,
    reason_code: None,
    requested_by: "finance-a",
    requested_unix_ms: 2700L,
    completed_unix_ms: None,
  }
  let reversing = store.request_reversal(reversal)
  assert_eq(reversing.state, ReversalPending)
  ignore(store.claim_authority_work(2750L))
  let revoked = store.complete_reversal({
    ..reversal,
    state: ReversalConfirmed,
    authority_receipt: Some("revocation-receipt-a"),
    completed_unix_ms: Some(2800L),
  })
  assert_eq(revoked.state, Revoked)
  let reversal_result : @offline.CommercialReversal = {
    ..reversal,
    state: ReversalConfirmed,
    authority_receipt: Some("revocation-receipt-a"),
    completed_unix_ms: Some(2800L),
  }
  assert_eq(store.complete_reversal(reversal_result), revoked)
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_eq(reopened.order("org-a", revoked.order_id).state, Revoked)
  @fs.remove(path)
}

///|
async test "activation pending survives expiry and failed reversal is retryable" {
  let path = temp_path("saga-races")
  let store = @store.OfflineCommerceStore::open(path)
  let awaiting = ready_for_upload(store, "order-saga-race")
  let grant = upload_grant("order-saga-race", "evidence-saga-race")
  ignore(store.grant_upload(grant))
  let artifact = store.complete_upload(callback(grant))
  ignore(
    store.review_evidence({
      review_id: "review-saga-race",
      order_id: awaiting.order_id,
      artifact_id: artifact.artifact_id,
      expected_artifact_sha256: artifact.sha256,
      reviewer_ref: "legal-a",
      accepted: true,
      reason_code: "EvidenceVerified",
      audit_receipt: "audit-review-saga-race",
      reviewed_unix_ms: 2400L,
    }),
  )
  let reviewed = store.order("org-a", awaiting.order_id)
  let request = activation(reviewed, 2500L)
  let pending = store.fulfill(
    reviewed.order_id,
    reviewed.generation,
    request,
    2500L,
  )
  assert_eq(pending.state, FulfillmentPending)
  assert_eq(store.expire_orders(200000L), [])
  ignore(store.claim_authority_work(200000L))
  let fulfilled = store.complete_activation({
    ..request,
    state: EntitlementActivationConfirmed,
    entitlement_ref: Some("lease-saga-race"),
    authority_receipt: Some("activation-receipt-saga-race"),
    completed_unix_ms: Some(200001L),
  })
  let expired_fulfilled = store.expire_orders(200002L)
  assert_eq(expired_fulfilled.length(), 1)
  assert_eq(expired_fulfilled[0].state, ReversalPending)
  let fulfilled = { ..fulfilled, generation: expired_fulfilled[0].generation }
  let reversal : @offline.CommercialReversal = {
    reversal_id: "expiry-order-saga-race-\{fulfilled.generation - 1L}",
    idempotency_key: "expiry-order-saga-race-\{fulfilled.generation - 1L}",
    order_id: fulfilled.order_id,
    organization_id: fulfilled.organization_id,
    entitlement_ref: "lease-saga-race",
    reason: ContractExpired,
    expected_order_generation: fulfilled.generation - 1L,
    state: ReversalRequested,
    authority_receipt: None,
    reason_code: None,
    requested_by: "offline-expiry-reconciler",
    requested_unix_ms: 200002L,
    completed_unix_ms: None,
  }
  ignore(store.claim_authority_work(200002L))
  let restored = store.complete_reversal({
    ..reversal,
    state: ReversalFailed,
    authority_receipt: Some("reversal-failure-receipt-saga-race"),
    reason_code: Some("authority-unavailable"),
    completed_unix_ms: Some(200003L),
  })
  assert_eq(restored.state, ReversalManualIntervention)
  assert_eq(restored.entitlement_ref, Some("lease-saga-race"))
  assert_eq(store.expire_orders(300000L), [])
  let recovered = store.recover_failed_reversal({
    recovery_id: "recovery-saga-race",
    idempotency_key: "recovery-saga-race",
    order_id: restored.order_id,
    organization_id: restored.organization_id,
    failed_reversal_id: reversal.reversal_id,
    expected_order_generation: restored.generation,
    decision: RetryReversal,
    replacement_reversal_id: Some("reversal-saga-race-retry"),
    authority_receipt: "operator-verified-authority-state",
    reason_code: "authority-retry-approved",
    recovered_by: "operator-a",
    recovered_unix_ms: 300001L,
  })
  assert_eq(recovered.state, ReversalPending)
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_eq(
    reopened.order(restored.organization_id, restored.order_id).state,
    ReversalPending,
  )
  assert_true(
    reopened.snapshot().reversal_recoveries.any(recovery => {
      recovery.recovery_id == "recovery-saga-race"
    }),
  )
  @fs.remove(path)
}

///|
async test "upload callback rejects forged object digest size and active content" {
  let path = temp_path("callback")
  let store = @store.OfflineCommerceStore::open(path)
  ignore(ready_for_upload(store, "order-callback"))
  let grant = upload_grant("order-callback", "evidence-a")
  ignore(store.grant_upload(grant))
  for
    invalid in [
      {
        ..callback(grant),
        callback_id: "backdated",
        completed_unix_ms: grant.created_unix_ms - 1L,
      },
      {
        ..callback(grant),
        callback_id: "forged-ref",
        expected_object_ref: "s3://attacker/file.pdf",
      },
      {
        ..callback(grant),
        callback_id: "oversized",
        byte_count: grant.maximum_byte_count + 1L,
      },
      {
        ..callback(grant),
        callback_id: "bad-digest",
        sha256: "sha256:not-a-digest",
      },
    ] {
    ignore(store.complete_upload(invalid)) catch {
      @offline.OfflineCommerceError::ArtifactUnavailable(_) => ()
      _ => fail("unsafe callback was not rejected")
    }
  }
  let rejected = store.complete_upload({
    ..callback(grant),
    callback_id: "active-content",
    active_content_detected: true,
  })
  assert_eq(rejected.scan_state, ScanRejected)
  assert_eq(store.order("org-a", "order-callback").state, NeedsCorrection)
  @fs.remove(path)
}

///|
async test "pending sagas cannot be cancelled and transfer sessions are one-time durable" {
  let path = temp_path("transfer-saga")
  let store = @store.OfflineCommerceStore::open(path)
  ignore(ready_for_upload(store, "order-transfer"))
  let grant = upload_grant("order-transfer", "evidence-transfer")
  ignore(store.grant_upload(grant))
  let session : @offline.OfflineTransferSession = {
    session_id: "transfer-session-a",
    idempotency_key: "transfer-idempotency-a",
    session_token_sha256: digest_a,
    organization_id: grant.organization_id,
    subject_ref: grant.subject_ref,
    order_id: grant.order_id,
    artifact_id: grant.artifact_id,
    direction: UploadTransfer,
    media_types: grant.allowed_media_types,
    maximum_byte_count: grant.maximum_byte_count,
    expected_sha256: None,
    state: TransferIssued,
    issued_unix_ms: grant.created_unix_ms,
    expires_unix_ms: grant.created_unix_ms + 500L,
    consumed_unix_ms: None,
  }
  assert_eq(store.issue_transfer_session(session), session)
  let reopened = @store.OfflineCommerceStore::open(path)
  let consumed = reopened.consume_transfer_session(
    session.session_id,
    digest_a,
    "application/pdf",
    100L,
    "sha256:" + "c".repeat(64),
    "provider-transfer-a",
    session.issued_unix_ms + 1L,
  )
  assert_eq(consumed.state, TransferConsumed)
  ignore(
    reopened.consume_transfer_session(
      session.session_id,
      digest_a,
      "application/pdf",
      100L,
      "sha256:" + "c".repeat(64),
      "provider-transfer-a",
      session.issued_unix_ms + 2L,
    ),
  ) catch {
    @offline.OfflineCommerceError::Unauthorized => ()
    _ => fail("transfer replay was not rejected")
  }

  let uploaded = reopened.complete_upload(callback(grant))
  ignore(
    reopened.review_evidence({
      review_id: "review-transfer",
      order_id: grant.order_id,
      artifact_id: uploaded.artifact_id,
      expected_artifact_sha256: uploaded.sha256,
      reviewer_ref: "legal-transfer",
      accepted: true,
      reason_code: "EvidenceVerified",
      audit_receipt: "audit-transfer",
      reviewed_unix_ms: 2400L,
    }),
  )
  let reviewed = reopened.order("org-a", grant.order_id)
  let request = activation(reviewed, 2500L)
  let pending = reopened.fulfill(
    reviewed.order_id,
    reviewed.generation,
    request,
    2500L,
  )
  ignore(reopened.cancel_order(pending.order_id, pending.generation, 2600L)) catch {
    @offline.OfflineCommerceError::InvalidTransition(_) => ()
    _ => fail("pending activation cancellation was accepted")
  }
  @fs.remove(path)
}

///|
async test "review enforces digest binding separation of duties and tenant isolation" {
  let path = temp_path("review")
  let store = @store.OfflineCommerceStore::open(path)
  ignore(ready_for_upload(store, "order-review"))
  let grant = upload_grant("order-review", "evidence-review")
  ignore(store.grant_upload(grant))
  let artifact = store.complete_upload(callback(grant))
  let base : @offline.EvidenceReview = {
    review_id: "review-a",
    order_id: "order-review",
    artifact_id: artifact.artifact_id,
    expected_artifact_sha256: artifact.sha256,
    reviewer_ref: "buyer-a",
    accepted: true,
    reason_code: "EvidenceVerified",
    audit_receipt: "audit-review-a",
    reviewed_unix_ms: 2400L,
  }
  ignore(store.review_evidence(base)) catch {
    @offline.OfflineCommerceError::SeparationOfDuties => ()
    _ => fail("submitter reviewed their own evidence")
  }
  ignore(
    store.review_evidence({
      ..base,
      review_id: "review-forged",
      reviewer_ref: "legal-a",
      expected_artifact_sha256: digest_a,
    }),
  ) catch {
    @offline.OfflineCommerceError::InvalidInput(_) => ()
    _ => fail("forged digest review was accepted")
  }
  ignore(store.order("org-b", "order-review")) catch {
    @offline.OfflineCommerceError::TenantMismatch => ()
    _ => fail("cross-tenant order read succeeded")
  }
  ignore(store.artifact("org-b", artifact.artifact_id)) catch {
    @offline.OfflineCommerceError::TenantMismatch => ()
    _ => fail("cross-tenant artifact read succeeded")
  }
  @fs.remove(path)
}

///|
async test "generation result is bound to request and forbids active content" {
  let path = temp_path("generation")
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.register_template(contract_template()))
  ignore(store.create_order(order("order-generation")))
  let quoted = store.quote_order(
    "order-generation",
    quote(),
    "operator-a",
    1200L,
  )
  ignore(
    store.begin_offline_execution("order-generation", quoted.generation, 1300L),
  )
  let request = generation_request("order-generation", "generated-pdf")
  ignore(store.request_generation(request))
  ignore(store.claim_generation_requests(1450L))
  ignore(
    store.complete_generation({
      request_id: request.request_id,
      artifact_id: request.artifact_id,
      expected_object_ref: "s3://attacker/generated.pdf",
      media_type: "application/pdf",
      byte_count: 100L,
      sha256: digest_b,
      worker_receipt: "worker-forged",
      verified: true,
      active_content_detected: false,
      moonleaf_verified: false,
      render_verified: true,
      formula_error_count: 0,
      visual_evidence_sha256: digest_a,
      completed_unix_ms: 1500L,
    }),
  ) catch {
    @offline.OfflineCommerceError::ArtifactUnavailable(_) => ()
    _ => fail("forged worker object was accepted")
  }
  ignore(
    store.complete_generation({
      request_id: request.request_id,
      artifact_id: request.artifact_id,
      expected_object_ref: request.expected_object_ref,
      media_type: "application/pdf",
      byte_count: 100L,
      sha256: digest_b,
      worker_receipt: "worker-active",
      verified: true,
      active_content_detected: true,
      moonleaf_verified: false,
      render_verified: true,
      formula_error_count: 0,
      visual_evidence_sha256: digest_a,
      completed_unix_ms: 1500L,
    }),
  ) catch {
    @offline.OfflineCommerceError::ArtifactUnavailable(_) => ()
    _ => fail("active content was accepted")
  }
  assert_eq(store.snapshot().artifacts.length(), 0)
  @fs.remove(path)
}

///|
async test "generation claims fence stale order state and exhaust bounded retries" {
  let path = temp_path("generation-fencing")
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.register_template(contract_template()))
  ignore(store.create_order(order("order-generation-fencing")))
  let quoted = store.quote_order(
    "order-generation-fencing",
    quote(),
    "operator-a",
    1200L,
  )
  ignore(
    store.begin_offline_execution(quoted.order_id, quoted.generation, 1300L),
  )
  let wrong = {
    ..generation_request("order-generation-fencing", "wrong-snapshot"),
    input_snapshot_sha256: digest_b,
  }
  ignore(store.request_generation(wrong)) catch {
    @offline.OfflineCommerceError::InvalidInput(_) => ()
    _ => fail("generation request accepted a non-authoritative snapshot")
  }
  let request = generation_request("order-generation-fencing", "bounded-retry")
  ignore(store.request_generation(request))
  assert_eq(store.claim_generation_requests(1450L).length(), 1)
  assert_eq(store.claim_generation_requests(1451L).length(), 0)
  for attempt in 1..<5 {
    assert_eq(
      store
      .claim_generation_requests(1450L + Int64::from_int(attempt) * 60000L)
      .length(),
      1,
    )
  }
  assert_eq(store.claim_generation_requests(400000L).length(), 0)
  assert_true(
    store
    .worker_readiness_blockers(400000L)
    .contains("ReadinessOfflineWorkRetryExhausted"),
  )
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_true(
    reopened
    .worker_readiness_blockers(400000L)
    .contains("ReadinessOfflineWorkRetryExhausted"),
  )
  @fs.remove(path)
}

///|
async test "reconciler readiness requires a recent completed pass" {
  let path = temp_path("reconciler-health")
  let store = @store.OfflineCommerceStore::open(path)
  store.record_worker_acceptance(ArtifactDispatcher, 1000L)
  store.record_worker_acceptance(EntitlementDispatcher, 1000L)
  store.record_reconciler_attempt(1000L)
  assert_true(
    store
    .worker_readiness_blockers(1001L)
    .contains("ReadinessOfflineReconcilerDegraded"),
  )
  store.record_reconciler_success(1002L)
  assert_eq(store.worker_readiness_blockers(1003L), [])
  store.record_reconciler_attempt(1004L)
  store.record_reconciler_failure("OfflineReconcileFailed")
  let reopened = @store.OfflineCommerceStore::open(path)
  assert_true(
    reopened
    .worker_readiness_blockers(1005L)
    .contains("ReadinessOfflineReconcilerDegraded"),
  )
  @fs.remove(path)
}

///|
async test "delayed generation result cannot mutate a changed order" {
  let path = temp_path("generation-stale-result")
  let store = @store.OfflineCommerceStore::open(path)
  ignore(store.register_template(contract_template()))
  ignore(store.create_order(order("order-stale-result")))
  let quoted = store.quote_order(
    "order-stale-result",
    quote(),
    "operator-a",
    1200L,
  )
  let begun = store.begin_offline_execution(
    quoted.order_id,
    quoted.generation,
    1300L,
  )
  let request = generation_request("order-stale-result", "stale-pdf")
  ignore(store.request_generation(request))
  ignore(store.claim_generation_requests(1450L))
  ignore(store.cancel_order(begun.order_id, begun.generation, 1460L))
  ignore(
    store.complete_generation({
      request_id: request.request_id,
      artifact_id: request.artifact_id,
      expected_object_ref: request.expected_object_ref,
      media_type: "application/pdf",
      byte_count: 100L,
      sha256: digest_b,
      worker_receipt: "worker-stale-result",
      verified: true,
      active_content_detected: false,
      moonleaf_verified: false,
      render_verified: true,
      formula_error_count: 0,
      visual_evidence_sha256: digest_a,
      completed_unix_ms: 1500L,
    }),
  ) catch {
    @offline.OfflineCommerceError::StaleGeneration => ()
    _ => fail("delayed generation result mutated a changed order")
  }
  assert_eq(store.order("org-a", begun.order_id).state, Cancelled)
  @fs.remove(path)
}

///|
test "quote validation rejects arithmetic drift overflow and mutable order reuse" {
  @offline.validate_quote({ ..quote(), total: money(105999L) }) catch {
    InvalidInput(_) => ()
    _ => fail("incorrect quote total was accepted")
  }
  @offline.validate_quote({
    ..quote(),
    lines: [
      {
        ..quote().lines[0],
        quantity: 2L,
        unit_price: money(0x7fffffffffffffffL),
        line_total: money(0x7fffffffffffffffL),
      },
    ],
  }) catch {
    InvalidInput(_) => ()
    _ => fail("overflowing quote was accepted")
  }
}
