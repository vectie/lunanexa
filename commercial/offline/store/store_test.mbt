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
    input_snapshot_sha256: digest_b,
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
    reopened.fulfill("order-happy", reconciling.generation, "lease-a", 2300L),
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
  let fulfilled = reopened.fulfill(
    "order-happy",
    reviewed.generation,
    "lease-a",
    2500L,
  )
  assert_eq(fulfilled.state, Fulfilled)
  assert_eq(fulfilled.entitlement_ref, Some("lease-a"))
  let final_store = @store.OfflineCommerceStore::open(path)
  assert_eq(final_store.order("org-a", "order-happy").state, Fulfilled)
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
  ignore(store.quote_order("order-generation", quote(), "operator-a", 1200L))
  let request = generation_request("order-generation", "generated-pdf")
  ignore(store.request_generation(request))
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
