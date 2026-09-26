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
    requested_undertaking_term: None,
    technical_acceptance_waiver: None,
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
test "terminal customer orders do not promise a future activation notification" {
  for
    status in [
      @offline.OfflineOrderState::Revoked,
      Expired,
      Cancelled,
      Rejected,
    ] {
    let rendered = @offline_commerce.render({
      ..@offline_commerce.default_state(ChineseSimplified, CustomerCommerce),
      orders: [offline_order(status)],
      selected_order_id: Some("order-2026-001"),
    })
    assert_true(
      rendered.contains("此订单已结束，不会自动开通权限"),
    )
    assert_false(
      rendered.contains("下一步可办理时，我们会通知您"),
    )
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
  assert_true(chinese.contains("履约要求"))
  assert_true(chinese.contains("并非已完成的核验"))
  assert_false(chinese.contains("<span>✓</span>"))
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
    artifacts: [{ ..evidence(), review_state: ReviewRejected, }],
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

///|
test "the route reports its own failures instead of looking inert" {
  // Every rejected action on this route used to leave the screen unchanged: a
  // failed order creation looked like a button that did nothing.
  let failed = @offline_commerce.render({
    ..@offline_commerce.default_state(English, CustomerCommerce),
    error_message: Some("Operation: The action failed. Refresh and retry."),
  })
  assert_true(failed.contains("role=\"alert\""))
  assert_true(failed.contains("The action failed"))
  let accepted = @offline_commerce.render({
    ..@offline_commerce.default_state(English, CustomerCommerce),
    success_message: Some("Draft order created."),
  })
  assert_true(accepted.contains("Draft order created."))
  let busy = @offline_commerce.render({
    ..@offline_commerce.default_state(English, CustomerCommerce),
    loading: true,
  })
  assert_true(busy.contains("Working…"))
}

///|
test "both sides render the undertaking's tiers from the one list" {
  // The customer's own order form carries the tier picker, and the operator's
  // tariff picker renders the same five options with the same prices.
  let customer = @offline_commerce.render(
    @offline_commerce.default_state(English, CustomerCommerce),
  )
  assert_true(customer.contains("id=\"offline-undertaking-term\""))
  assert_true(customer.contains("Rental tier"))
  let operator = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [offline_order(Draft)],
  })
  assert_true(operator.contains("id=\"undertaking-tariff\""))
  for
    label in [
      "1 day · 49", "7 days · 322", "30 days · 1290", "90 days · 3600", "365 days · 13870",
    ] {
    assert_true(customer.contains(label))
    assert_true(operator.contains(label))
  }
  // Chinese renders the same tiers.
  let chinese = @offline_commerce.render(
    @offline_commerce.default_state(ChineseSimplified, CustomerCommerce),
  )
  assert_true(chinese.contains("租赁档位"))
  assert_true(chinese.contains("7 天 · 322 元"))
}

///|
test "order details distinguish requested lease term from draft validity" {
  let order = {
    ..offline_order(Draft),
    requested_undertaking_term: Some("day"),
  }
  let customer = @offline_commerce.render({
    ..@offline_commerce.default_state(ChineseSimplified, CustomerCommerce),
    orders: [order],
    selected_order_id: Some(order.order_id),
  })
  assert_true(customer.contains("申请租期与档位"))
  assert_true(customer.contains("1 天 · 49 元"))
  assert_true(
    customer.contains("订单授权截止（须覆盖完整租期）"),
  )
}

///|
test "opening an order adopts the tier the customer asked for" {
  let base = @offline_commerce.default_state(English, OperatorCommerce)
  let requested = {
    ..offline_order(Draft),
    requested_undertaking_term: Some("quarter"),
    technical_acceptance_waiver: None,
  }
  // The state default is month; opening the order must move the picker to the
  // tier that was actually requested.
  assert_eq(base.undertaking_term, "month")
  let opened = base.update(SelectOrder(requested.order_id))
  // No order in the list yet, so the default stands.
  assert_eq(opened.undertaking_term, "month")
  let with_order = { ..base, orders: [requested], }.update(
    SelectOrder(requested.order_id),
  )
  assert_eq(with_order.undertaking_term, "quarter")
  // A request that is not a fixed tier is ignored rather than adopted.
  let unknown = {
    ..offline_order(Draft),
    requested_undertaking_term: Some("hour"),
    technical_acceptance_waiver: None,
  }
  let ignored = { ..base, orders: [unknown], }.update(
    SelectOrder(unknown.order_id),
  )
  assert_eq(ignored.undertaking_term, "month")
}

///|
test "the undertaking quote confirmation states the amount it freezes" {
  // The dialog asks the operator to freeze an immutable price, so it has to
  // name the price. It used to show only the term and the device count.
  let state = {
    ..@offline_commerce.default_state(English, OperatorCommerce),
    orders: [offline_order(Draft)],
  }
  let html = @offline_commerce.render(
    state.update(
      BeginConfirmation(QuoteUndertakingOrder("order-2026-001", "week", "2")),
    ),
  )
  assert_true(html.contains("Freeze this immutable quote?"))
  // 322 CNY per device × 2 devices.
  assert_true(html.contains("CNY 644"))
  // A device count that is not a number leaves the amount out rather than
  // stating a total nobody typed.
  let unparsable = @offline_commerce.render(
    state.update(
      BeginConfirmation(QuoteUndertakingOrder("order-2026-001", "week", "two")),
    ),
  )
  assert_true(unparsable.contains("week × two"))
  assert_false(unparsable.contains("week × two · CNY"))
}

///|
/// The ten gates the readiness document must carry, in the order the control
/// plane evaluates them.
fn readiness_gate_set(
  configured : Bool,
  verified : Bool,
) -> Array[@offline.OfflineCommerceCapabilityEvidence] {
  let capabilities : Array[@offline.OfflineCommerceCapability] = [
    ApprovedLegalTemplates,
    ObjectStorage,
    MalwareScanner,
    OoxmlWorker,
    PdfRenderer,
    SpreadsheetFormulaEngine,
    CjkFonts,
    MachineCallbackIdentity,
    EntitlementAuthority,
    FinanceLegalPolicy,
  ]
  capabilities.map(capability => {
    capability,
    configured,
    verified,
    evidence_ref: if configured && verified {
      Some("evidence/readiness-\{Repr(capability)}")
    } else {
      None
    },
  })
}

///|
test "the readiness panel lists every gate and every blocker code verbatim" {
  let html = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    readiness_status: OfflineCommerceAdaptersPending,
    readiness_capabilities: readiness_gate_set(false, false),
    readiness_blocker_codes: [
      "ApprovedLegalTemplatesPending", "ReadinessTransferAdapterUnavailable",
    ],
  })
  assert_true(html.contains("Offline commerce readiness"))
  assert_true(html.contains("OfflineCommerceAdaptersPending"))
  assert_true(html.contains("Adapters pending"))
  // The refusal an operator will actually meet is stated plainly.
  assert_true(html.contains("503 OfflineCommerceNotReady"))
  for
    capability in [
      "ApprovedLegalTemplates", "ObjectStorage", "MalwareScanner", "OoxmlWorker",
      "PdfRenderer", "SpreadsheetFormulaEngine", "CjkFonts", "MachineCallbackIdentity",
      "EntitlementAuthority", "FinanceLegalPolicy",
    ] {
    assert_true(html.contains(capability))
  }
  // Both facts are stated for every gate, not only the combined verdict.
  assert_true(html.contains("· Configured"))
  assert_true(html.contains("· Verified"))
  assert_true(html.contains("class=\"offline-readiness-capabilities\""))
  // Blocker codes are shown exactly as the API spells them.
  assert_true(html.contains("ApprovedLegalTemplatesPending"))
  assert_true(html.contains("ReadinessTransferAdapterUnavailable"))
}

///|
test "a fully verified readiness document renders ready without blockers" {
  let html = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    readiness_status: OfflineCommerceReady,
    readiness_capabilities: readiness_gate_set(true, true),
    readiness_blocker_codes: [],
  })
  assert_true(html.contains("OfflineCommerceReady"))
  assert_true(html.contains("✓ Configured"))
  assert_true(html.contains("✓ Verified"))
  assert_true(html.contains("No blocker codes are recorded."))
  assert_false(html.contains("OfflineCommerceAdaptersPending"))
  assert_false(html.contains("503 OfflineCommerceNotReady"))
  assert_false(html.contains("ReadinessTransferAdapterUnavailable"))
}

///|
test "an empty capability set is an explicit empty state not a checklist" {
  let html = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    readiness_status: OfflineCommerceAdaptersPending,
    readiness_capabilities: [],
    readiness_blocker_codes: ["ReadinessCapabilitySetInvalid"],
  })
  assert_true(html.contains("No signed readiness document is configured"))
  assert_true(html.contains("cmd/offline-readiness"))
  // The empty state replaces the checklist rather than leaving a blank list.
  assert_false(html.contains("class=\"offline-readiness-capabilities\""))
  assert_true(html.contains("ReadinessCapabilitySetInvalid"))
  let chinese = @offline_commerce.render({
    ..@offline_commerce.default_state(ChineseSimplified, OperatorCommerce),
    readiness_capabilities: [],
    readiness_blocker_codes: ["ReadinessCapabilitySetInvalid"],
  })
  assert_true(chinese.contains("未配置已签名的就绪文档"))
  assert_true(chinese.contains("阻塞代码"))
  assert_true(chinese.contains("503 OfflineCommerceNotReady"))
}

///|
test "evidence references are shown when retained and never rendered as null" {
  let html = @offline_commerce.render({
    ..@offline_commerce.default_state(English, OperatorCommerce),
    readiness_status: OfflineCommerceAdaptersPending,
    readiness_capabilities: [
      {
        capability: MachineCallbackIdentity,
        configured: true,
        verified: true,
        evidence_ref: Some(
          "lunanexa-control-credentials/callback-identities-20260922-3x64B-distinct-from-human",
        ),
      },
      {
        capability: ApprovedLegalTemplates,
        configured: false,
        verified: false,
        evidence_ref: None,
      },
    ],
    readiness_blocker_codes: ["ApprovedLegalTemplatesPending"],
  })
  assert_true(
    html.contains(
      "lunanexa-control-credentials/callback-identities-20260922-3x64B-distinct-from-human",
    ),
  )
  // A gate with no retained reference contributes no placeholder at all.
  assert_false(html.contains("null"))
  assert_true(html.contains("✓"))
  assert_true(html.contains("·"))
}

///|
test "the readiness panel stays operator-only" {
  let html = @offline_commerce.render({
    ..@offline_commerce.default_state(English, CustomerCommerce),
    readiness_status: OfflineCommerceReady,
    readiness_capabilities: readiness_gate_set(true, true),
  })
  assert_false(html.contains("Offline commerce readiness"))
  assert_false(html.contains("OfflineCommerceReady"))
}
