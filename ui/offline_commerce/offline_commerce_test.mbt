///|
fn offline_order(
  state : @offline.OfflineOrderState,
) -> @offline.CommercialOrder {
  {
    order_id: "order-2026-001",
    idempotency_key: "order-idem-001",
    tenant_ref: "tenant-a",
    organization_id: "org-a",
    project_id: "project-vision",
    purchaser_subject_ref: "subject-a",
    selected_service_code: "exclusive-dgx",
    selected_sla_code: "standard",
    policy: {
      require_executed_agreement: true,
      require_payment: true,
      invoice_timing: InvoiceBeforeFulfillment,
      require_identity_verification: false,
      require_internal_approval: true,
    },
    quote: None,
    agreement_ref: Some("agreement-a"),
    artifact_ids: ["artifact-contract"],
    entitlement_ref: None,
    state,
    generation: 5L,
    created_unix_ms: 1000L,
    updated_unix_ms: 5000L,
    expires_unix_ms: 100000L,
  }
}

///|
fn evidence() -> @offline_commerce.OfflineArtifactSummary {
  {
    artifact_id: "artifact-contract",
    order_id: "order-2026-001",
    kind: ExecutedContractScan,
    revision: 1,
    media_type: "application/pdf",
    byte_count: 42000L,
    sha256: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    scan_state: ScanPassed,
    review_state: AwaitingReview,
    submitted_by: "subject-a",
    created_unix_ms: 4000L,
  }
}

///|
test "customer workflow is clear bilingual and hides internal object authority" {
  let english = @offline_commerce.render({
    ..@offline_commerce.default_state(English, CustomerCommerce),
    orders: [offline_order(PendingEvidenceUpload)],
    artifacts: [evidence()],
    selected_order_id: Some("order-2026-001"),
  })
  assert_true(english.contains("Orders and offline documents"))
  assert_true(english.contains("Upload Executed contract scan"))
  assert_true(english.contains("Every stage is explicit"))
  assert_false(english.contains("object_ref"))
  assert_false(english.contains("scanner_receipt"))
  let chinese = @offline_commerce.render({
    ..@offline_commerce.default_state(ChineseSimplified, CustomerCommerce),
    orders: [offline_order(PendingEvidenceUpload)],
    artifacts: [evidence()],
  })
  assert_true(chinese.contains("订单与线下材料"))
  assert_true(chinese.contains("上传已盖章合同扫描件"))
  assert_true(chinese.contains("履约核验清单"))
}

///|
test "customer cancellation and fulfilled access termination require confirmation" {
  let pending = @offline_commerce.render({
    ..@offline_commerce.default_state(English, CustomerCommerce),
    orders: [offline_order(PendingEvidenceUpload)],
  })
  assert_true(pending.contains("Cancel order"))
  let fulfilled = {
    ..offline_order(Fulfilled),
    entitlement_ref: Some("lease-order-2026-001"),
  }
  let state = {
    ..@offline_commerce.default_state(ChineseSimplified, CustomerCommerce),
    orders: [fulfilled],
  }
  assert_true(@offline_commerce.render(state).contains("结束访问并取消"))
  let action = @offline_commerce.OfflineCommerceConsequentialAction::CancelOrder(
    fulfilled.order_id,
    fulfilled.generation,
  )
  let confirming = @offline_commerce.render(
    state.update(BeginConfirmation(action)),
  )
  assert_true(
    confirming.contains("确认取消此订单或结束其有效访问？"),
  )
  assert_true(
    confirming.contains("只有授权方确认后访问权限才会结束"),
  )
}

///|
test "operator desk exposes review and generation-fenced workflow actions" {
  let review = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [offline_order(UnderReconciliation)],
    artifacts: [evidence()],
  })
  assert_true(review.contains("Offline reconciliation desk"))
  assert_true(review.contains("Accept exact digest"))
  assert_true(review.contains("Request correction"))
  assert_true(review.contains("Fulfill after all checks"))
  let fulfilled = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [
      {
        ..offline_order(Fulfilled),
        entitlement_ref: Some("lease-order-2026-001"),
      },
    ],
  })
  assert_true(fulfilled.contains("Revoke entitlement"))
  let release = @offline_commerce.render({
    ..@offline_commerce.default_state(ChineseSimplified, OperatorCommerce),
    orders: [offline_order(PendingOfflineExecution)],
  })
  assert_true(release.contains("线下材料核验台"))
  assert_true(release.contains("发布已验证 PDF"))
}

///|
test "operator can recover a failed entitlement reversal with explicit evidence" {
  let order = {
    ..offline_order(ReversalManualIntervention),
    entitlement_ref: Some("lease-order-2026-001"),
  }
  let reversal : @offline.CommercialReversal = {
    reversal_id: "reversal-failed-001",
    idempotency_key: "reversal-failed-001",
    order_id: order.order_id,
    organization_id: order.organization_id,
    entitlement_ref: "lease-order-2026-001",
    reason: CustomerCancellation,
    expected_order_generation: order.generation - 1L,
    state: ReversalFailed,
    authority_receipt: Some("authority-failure-receipt"),
    reason_code: Some("authority-unavailable"),
    requested_by: "operator-a",
    requested_unix_ms: 4500L,
    completed_unix_ms: Some(5000L),
  }
  let state = {
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [order],
    reversals: [reversal],
  }
  let html = @offline_commerce.render(state)
  assert_true(html.contains("Retry revocation"))
  assert_true(html.contains("Confirm access revoked"))
  assert_true(html.contains("Confirm access still active"))
  let action = @offline_commerce.OfflineCommerceConsequentialAction::RecoverFailedReversal(
    order.order_id,
    reversal.reversal_id,
    order.generation,
    ConfirmRevoked,
  )
  let confirming = @offline_commerce.render(
    state.update(BeginConfirmation(action)),
  )
  assert_true(confirming.contains("Confirm external access is revoked?"))
  assert_true(confirming.contains("reversal-failed-001"))
}

///|
test "empty and corrective states tell users what happens next" {
  let empty = @offline_commerce.render(
    @offline_commerce.default_state(English, CustomerCommerce),
  )
  assert_true(empty.contains("No commercial orders yet"))
  assert_true(empty.contains("Configure a new order"))
  assert_true(empty.contains("Create draft order"))
  let corrective = @offline_commerce.render({
    ..@offline_commerce.default_state(English, CustomerCommerce),
    orders: [offline_order(NeedsCorrection)],
    artifacts: [{ ..evidence(), review_state: ReviewRejected }],
  })
  assert_true(corrective.contains("Correction required"))
  assert_true(corrective.contains("Replacement required"))
}

///|
test "consequential actions require explicit evidence confirmation" {
  let base = {
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [offline_order(UnderReconciliation)],
    artifacts: [evidence()],
    entitlement_ref: "entitlement-order-2026-001",
  }
  let action = @offline_commerce.OfflineCommerceConsequentialAction::AcceptEvidence(
    "artifact-contract", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let confirming = base.update(BeginConfirmation(action))
  assert_false(confirming.loading)
  let html = @offline_commerce.render(confirming)
  assert_true(html.contains("Accept this exact evidence digest?"))
  assert_true(html.contains("sha256:aaaaaaaa"))
  assert_true(html.contains("role=\"alertdialog\""))
  let confirmed = confirming.update(ConfirmAction(action))
  assert_true(confirmed.loading)
  assert_eq(confirmed.confirmation, None)
}

///|
test "operator generation and bilingual consequential copy are visible" {
  let pending = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [offline_order(PendingOfflineExecution)],
  })
  assert_true(pending.contains("Generate Editable contract source"))
  assert_true(pending.contains("Generate Quote and cost schedule"))
  assert_true(pending.contains("Generate Print-ready contract"))
  let action = @offline_commerce.OfflineCommerceConsequentialAction::ReleaseVerifiedPacket(
    "order-2026-001", 5L,
  )
  let chinese = @offline_commerce.render(
    {
      ..@offline_commerce.default_state(ChineseSimplified, OperatorCommerce),
      orders: [offline_order(PendingOfflineExecution)],
    }.update(BeginConfirmation(action)),
  )
  assert_true(chinese.contains("确认发布已验证打印材料"))
  assert_true(chinese.contains("根据此证据确认"))
}

///|
test "immutable quote requires an approved legal terms digest" {
  let draft = {
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [offline_order(Draft)],
  }
  let blank = @offline_commerce.render(draft)
  assert_true(blank.contains("Approved legal terms / snapshot SHA-256"))
  assert_true(blank.contains("disabled"))
  let malformed = draft.update(TermsDigestChanged("sha256:not-a-digest"))
  assert_eq(malformed.terms_digest, "sha256:not-a-digest")
  assert_true(@offline_commerce.render(malformed).contains("disabled"))
  let valid = draft.update(
    TermsDigestChanged(
      "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    ),
  )
  assert_true(@offline.valid_sha256(valid.terms_digest))
}
