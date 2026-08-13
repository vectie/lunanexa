///|
pub(all) enum OfflineCommerceAudience {
  CustomerCommerce
  OperatorCommerce
} derive(Debug, Eq)

///|
pub(all) struct OfflineCommerceState {
  locale : @i18n.Locale
  audience : OfflineCommerceAudience
  orders : Array[@offline.CommercialOrder]
  reversals : Array[@offline.CommercialReversal]
  artifacts : Array[OfflineArtifactSummary]
  templates : Array[@offline.DocumentTemplate]
  selected_order_id : String?
  project_id : String
  service_code : String
  sla_code : String
  operator_actor_ref : String
  quote_minor_units : String
  terms_digest : String
  entitlement_ref : String
  confirmation : OfflineCommerceConfirmation?
  loading : Bool
  success_message : String?
  error_message : String?
} derive(Eq)

///|
pub(all) enum OfflineCommerceConsequentialAction {
  QuoteOrder(String, String, String, String)
  BeginOrder(String, Int64)
  ReleaseVerifiedPacket(String, Int64)
  AcceptEvidence(String, String)
  RejectEvidence(String, String)
  FulfillVerifiedOrder(String, Int64)
  CancelOrder(String, Int64)
  RequestEntitlementReversal(String, Int64)
  RecoverFailedReversal(
    String,
    String,
    Int64,
    @offline.ReversalRecoveryDecision
  )
} derive(Debug, Eq)

///|
pub(all) struct OfflineCommerceConfirmation {
  action : OfflineCommerceConsequentialAction
  title : String
  evidence : String
} derive(Debug, Eq)

///|
pub(all) struct OfflineArtifactSummary {
  artifact_id : String
  order_id : String
  kind : @offline.DocumentArtifactKind
  revision : Int
  media_type : String
  byte_count : Int64
  sha256 : String
  scan_state : @offline.ArtifactScanState
  review_state : @offline.ArtifactReviewState
  submitted_by : String
  created_unix_ms : Int64
} derive(Debug, Eq)

///|
pub(all) enum OfflineCommerceMessage {
  SelectOrder(String)
  CreateOrder
  RequestEvidenceUpload(String, @offline.DocumentArtifactKind)
  RequestArtifactDownload(String)
  RequestGeneration(String, @offline.DocumentArtifactKind)
  BeginConfirmation(OfflineCommerceConsequentialAction)
  DismissConfirmation
  ConfirmAction(OfflineCommerceConsequentialAction)
  ProjectChanged(String)
  ServiceChanged(String)
  SlaChanged(String)
  OperatorActorChanged(String)
  QuoteMinorUnitsChanged(String)
  TermsDigestChanged(String)
  EntitlementChanged(String)
  Refresh
  ClearNotice
} derive(Eq)

///|
pub fn default_state(
  locale : @i18n.Locale,
  audience : OfflineCommerceAudience,
) -> OfflineCommerceState {
  {
    locale,
    audience,
    orders: [],
    reversals: [],
    artifacts: [],
    templates: [],
    selected_order_id: None,
    project_id: "",
    service_code: "exclusive-dgx",
    sla_code: "standard",
    operator_actor_ref: "platform-operator",
    quote_minor_units: "0",
    terms_digest: "",
    entitlement_ref: "",
    confirmation: None,
    loading: false,
    success_message: None,
    error_message: None,
  }
}

///|
/// A read-only, secret-free scenario for local UI review.
pub fn demo_state(
  locale : @i18n.Locale,
  audience : OfflineCommerceAudience,
) -> OfflineCommerceState {
  let operator = audience == OperatorCommerce
  let base_order : @offline.CommercialOrder = {
    order_id: "order-capacity-2026-08",
    idempotency_key: "demo-order-capacity",
    tenant_ref: "tenant-northstar",
    organization_id: "org-northstar",
    project_id: "project-vision-lab",
    purchaser_subject_ref: "subject-alice",
    selected_service_code: "exclusive-dgx",
    selected_sla_code: "standard",
    policy: {
      require_executed_agreement: true,
      require_payment: true,
      invoice_timing: InvoiceBeforeFulfillment,
      require_identity_verification: true,
      require_internal_approval: true,
    },
    quote: Some({
      quote_id: "quote-capacity-2026-08",
      version: "v1",
      service_code: "exclusive-dgx",
      sla_code: "standard",
      currency: "CNY",
      lines: [
        {
          line_id: "capacity",
          description: "Exclusive DGX capacity",
          quantity: 1L,
          unit: "lease",
          unit_price: { minor_units: 1280000L, currency: "CNY", scale: 2 },
          line_total: { minor_units: 1280000L, currency: "CNY", scale: 2 },
        },
      ],
      subtotal: { minor_units: 1280000L, currency: "CNY", scale: 2 },
      tax: { minor_units: 0L, currency: "CNY", scale: 2 },
      total: { minor_units: 1280000L, currency: "CNY", scale: 2 },
      valid_until_unix_ms: 1787000000000L,
      terms_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      created_unix_ms: 1786300000000L,
    }),
    agreement_ref: Some("agreement-capacity-2026"),
    artifact_ids: ["artifact-contract-executed"],
    entitlement_ref: None,
    state: if operator {
      UnderReconciliation
    } else {
      PendingEvidenceUpload
    },
    generation: 6L,
    created_unix_ms: 1786300000000L,
    updated_unix_ms: 1786400000000L,
    expires_unix_ms: 1789000000000L,
  }
  let order = if operator {
    {
      ..base_order,
      state: ReversalManualIntervention,
      entitlement_ref: Some("exclusive-lease-demo"),
      generation: 8L,
    }
  } else {
    base_order
  }
  let reversals : Array[@offline.CommercialReversal] = if operator {
    [
      {
        reversal_id: "reversal-demo-failed",
        idempotency_key: "reversal-demo-failed",
        order_id: order.order_id,
        organization_id: order.organization_id,
        entitlement_ref: "exclusive-lease-demo",
        reason: PolicyRevoked,
        expected_order_generation: 7L,
        state: ReversalFailed,
        authority_receipt: Some("authority-failure-demo"),
        reason_code: Some("authority-unavailable"),
        requested_by: "platform-operator",
        requested_unix_ms: 1786400000000L,
        completed_unix_ms: Some(1786400010000L),
      },
    ]
  } else {
    []
  }
  {
    ..default_state(locale, audience),
    orders: [order],
    reversals,
    artifacts: [
      {
        artifact_id: "artifact-contract-executed",
        order_id: order.order_id,
        kind: ExecutedContractScan,
        revision: 1,
        media_type: "application/pdf",
        byte_count: 482130L,
        sha256: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        scan_state: ScanPassed,
        review_state: if operator {
          AwaitingReview
        } else {
          ReviewAccepted
        },
        submitted_by: "subject-alice",
        created_unix_ms: 1786390000000L,
      },
    ],
    selected_order_id: Some(order.order_id),
    project_id: order.project_id,
    quote_minor_units: "1280000",
    terms_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    entitlement_ref: "entitlement-capacity-2026-08",
  }
}

///|
pub fn OfflineCommerceState::update(
  self : OfflineCommerceState,
  message : OfflineCommerceMessage,
) -> OfflineCommerceState {
  match message {
    SelectOrder(order_id) => { ..self, selected_order_id: Some(order_id) }
    ProjectChanged(value) => { ..self, project_id: value }
    ServiceChanged(value) => { ..self, service_code: value }
    SlaChanged(value) => { ..self, sla_code: value }
    OperatorActorChanged(value) => { ..self, operator_actor_ref: value }
    QuoteMinorUnitsChanged(value) => { ..self, quote_minor_units: value }
    TermsDigestChanged(value) => { ..self, terms_digest: value }
    EntitlementChanged(value) => { ..self, entitlement_ref: value }
    BeginConfirmation(action) =>
      { ..self, confirmation: Some(confirmation_for_action(action)) }
    DismissConfirmation => { ..self, confirmation: None }
    ConfirmAction(_) =>
      {
        ..self,
        confirmation: None,
        loading: true,
        success_message: None,
        error_message: None,
      }
    ClearNotice => { ..self, success_message: None, error_message: None }
    _ => { ..self, loading: true, success_message: None, error_message: None }
  }
}

///|
fn confirmation_for_action(
  action : OfflineCommerceConsequentialAction,
) -> OfflineCommerceConfirmation {
  match action {
    QuoteOrder(order_id, digest, price, actor) =>
      {
        action,
        title: "Freeze quote",
        evidence: "\{order_id} · CNY minor units \{price} · \{digest} · actor \{actor}",
      }
    BeginOrder(order_id, generation) =>
      {
        action,
        title: "Start offline workflow",
        evidence: "\{order_id} · generation \{generation}",
      }
    ReleaseVerifiedPacket(order_id, generation) =>
      {
        action,
        title: "Release print packet",
        evidence: "\{order_id} · generation \{generation}",
      }
    AcceptEvidence(artifact_id, digest) =>
      {
        action,
        title: "Accept exact evidence digest",
        evidence: "\{artifact_id} · \{digest}",
      }
    RejectEvidence(artifact_id, digest) =>
      {
        action,
        title: "Reject evidence and request correction",
        evidence: "\{artifact_id} · \{digest}",
      }
    FulfillVerifiedOrder(order_id, generation) =>
      {
        action,
        title: "Create entitlement",
        evidence: "\{order_id} · generation \{generation}",
      }
    CancelOrder(order_id, generation) =>
      {
        action,
        title: "Cancel order or end access",
        evidence: "\{order_id} · generation \{generation}",
      }
    RequestEntitlementReversal(order_id, generation) =>
      {
        action,
        title: "Revoke entitlement",
        evidence: "\{order_id} · generation \{generation}",
      }
    RecoverFailedReversal(order_id, failed_reversal_id, generation, decision) =>
      {
        action,
        title: "Resolve failed entitlement reversal",
        evidence: "\{order_id} · \{failed_reversal_id} · generation \{generation} · \{Repr(decision)}",
      }
  }
}

///|
fn copy(locale : @i18n.Locale, english : String, chinese : String) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
fn command(
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  message : OfflineCommerceMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  wrap : (String) -> OfflineCommerceMessage,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn order_state_label(
  locale : @i18n.Locale,
  state : @offline.OfflineOrderState,
) -> String {
  match state {
    Draft => copy(locale, "Draft", "草稿")
    Quoted => copy(locale, "Quote ready", "报价已就绪")
    PendingInternalApproval =>
      copy(locale, "Internal approval", "内部审批中")
    PendingOfflineExecution =>
      copy(locale, "Ready to print and execute", "可打印并线下办理")
    PendingEvidenceUpload =>
      copy(locale, "Upload offline evidence", "上传线下凭证")
    UnderReconciliation =>
      copy(locale, "Evidence under review", "凭证审核中")
    FulfillmentPending =>
      copy(locale, "Entitlement activation pending", "权益激活中")
    Fulfilled => copy(locale, "Fulfilled", "已履约")
    ReversalPending =>
      copy(locale, "Access revocation pending", "访问权限撤销中")
    ReversalManualIntervention =>
      copy(
        locale, "Revocation needs operator action", "撤销失败，需运营人员处理",
      )
    Revoked => copy(locale, "Access revoked", "访问权限已撤销")
    NeedsCorrection => copy(locale, "Correction required", "需要补正")
    Rejected => copy(locale, "Rejected", "已拒绝")
    Cancelled => copy(locale, "Cancelled", "已取消")
    Expired => copy(locale, "Expired", "已过期")
  }
}

///|
fn artifact_kind_label(
  locale : @i18n.Locale,
  kind : @offline.DocumentArtifactKind,
) -> String {
  match kind {
    EditableContractDocx =>
      copy(locale, "Editable contract source", "合同可编辑源文件")
    QuoteScheduleXlsx =>
      copy(locale, "Quote and cost schedule", "报价与费用明细")
    PrintReadyContractPdf =>
      copy(locale, "Print-ready contract", "可打印合同")
    ExecutedContractScan =>
      copy(locale, "Executed contract scan", "已盖章合同扫描件")
    PaymentReceipt => copy(locale, "Payment receipt", "付款凭证")
    IssuedInvoice => copy(locale, "Issued invoice", "已开具发票")
    InternalApprovalEvidence =>
      copy(locale, "Internal approval", "内部审批凭证")
    IdentityVerificationEvidence =>
      copy(locale, "Identity verification", "身份核验凭证")
  }
}

///|
fn review_label(
  locale : @i18n.Locale,
  artifact : OfflineArtifactSummary,
) -> String {
  if artifact.scan_state == ScanRejected {
    copy(locale, "Safety check failed", "安全检查未通过")
  } else {
    match artifact.review_state {
      ReviewNotRequired => copy(locale, "Ready", "可用")
      AwaitingReview => copy(locale, "Awaiting reviewer", "等待审核")
      ReviewAccepted => copy(locale, "Verified", "已核验")
      ReviewRejected =>
        copy(locale, "Replacement required", "需要重新上传")
    }
  }
}

///|
fn policy_items(
  locale : @i18n.Locale,
  policy : @offline.FulfillmentPolicy,
) -> Array[@rabbita.Html] {
  let values = [
    (
      copy(locale, "Executed agreement", "已签署合同"),
      policy.require_executed_agreement,
    ),
    (copy(locale, "Payment receipt", "付款凭证"), policy.require_payment),
    (
      copy(locale, "Invoice before service", "服务前开票"),
      policy.invoice_timing == InvoiceBeforeFulfillment,
    ),
    (
      copy(locale, "Identity verification", "身份核验"),
      policy.require_identity_verification,
    ),
    (
      copy(locale, "Internal approval", "内部审批"),
      policy.require_internal_approval,
    ),
  ]
  values.map(value => {
    @html.li(class=if value.1 { "is-required" } else { "is-optional" }, [
      @html.span(if value.1 { "✓" } else { "—" }),
      @html.span(value.0),
      @html.small(
        if value.1 {
          copy(locale, "Required before fulfillment", "履约前必须完成")
        } else {
          copy(locale, "Not required by this order", "此订单无需提供")
        },
      ),
    ])
  })
}

///|
fn steps(
  locale : @i18n.Locale,
  current : @offline.OfflineOrderState,
) -> @rabbita.Html {
  let labels = [
    copy(locale, "Configure", "配置"),
    copy(locale, "Quote", "报价"),
    copy(locale, "Offline execution", "线下办理"),
    copy(locale, "Upload evidence", "上传凭证"),
    copy(locale, "Reconcile", "核验"),
    copy(locale, "Fulfill", "履约"),
  ]
  let index = match current {
    Draft => 0
    Quoted | PendingInternalApproval => 1
    PendingOfflineExecution => 2
    PendingEvidenceUpload | NeedsCorrection => 3
    UnderReconciliation => 4
    FulfillmentPending | Fulfilled => 5
    ReversalPending | ReversalManualIntervention | Revoked => 5
    Rejected | Cancelled | Expired => 0
  }
  @html.ol(
    class="offline-commerce-steps",
    [
      for i, label in labels => {
        @html.li(
          class=if i < index {
            "is-complete"
          } else if i == index {
            "is-current"
          } else {
            ""
          },
          [@html.span((i + 1).to_string()), @html.strong(label)],
        )
      }
    ],
  )
}

///|
fn customer_actions(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  order : @offline.CommercialOrder,
) -> @rabbita.Html {
  let actions = []
  if order.state == PendingInternalApproval ||
    order.state == PendingEvidenceUpload ||
    order.state == NeedsCorrection {
    for kind in @offline.required_evidence(order.policy) {
      let artifact_kind = match kind {
        ExecutedAgreementEvidence =>
          @offline.DocumentArtifactKind::ExecutedContractScan
        PaymentEvidence => PaymentReceipt
        InvoiceEvidence => IssuedInvoice
        InternalApproval => InternalApprovalEvidence
        IdentityVerification => IdentityVerificationEvidence
      }
      actions.push(
        @html.button(
          type_="button",
          class="secondary-action",
          disabled=state.loading,
          on_click=command(
            emit,
            RequestEvidenceUpload(order.order_id, artifact_kind),
          ),
          copy(state.locale, "Upload ", "上传") +
          artifact_kind_label(state.locale, artifact_kind),
        ),
      )
    }
  }
  if order.state != FulfillmentPending &&
    order.state != ReversalPending &&
    order.state != ReversalManualIntervention &&
    order.state != Revoked &&
    order.state != Rejected &&
    order.state != Cancelled &&
    order.state != Expired {
    actions.push(
      @html.button(
        type_="button",
        class="quiet-button",
        disabled=state.loading,
        on_click=command(
          emit,
          BeginConfirmation(CancelOrder(order.order_id, order.generation)),
        ),
        if order.state == Fulfilled {
          copy(state.locale, "End access and cancel", "结束访问并取消")
        } else {
          copy(state.locale, "Cancel order", "取消订单")
        },
      ),
    )
  }
  if actions.length() == 0 {
    actions.push(
      @html.p(
        class="offline-action-note",
        copy(
          state.locale,
          "No customer action is required at this stage. We will notify you when the next step is ready.",
          "当前阶段无需客户操作。下一步可办理时，我们会通知您。",
        ),
      ),
    )
  }
  @html.div(class="offline-actions", actions)
}

///|
fn operator_actions(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  order : @offline.CommercialOrder,
) -> @rabbita.Html {
  let actions = []
  actions.push(
    @html.div(class="offline-field", [
      @html.label(
        for_="offline-operator-actor",
        copy(state.locale, "Operator actor reference", "运营人员引用"),
      ),
      @html.input(
        id="offline-operator-actor",
        value=state.operator_actor_ref,
        maxlength=160,
        on_input=text_command(emit, value => OperatorActorChanged(value)),
      ),
    ]),
  )
  if order.state == Draft {
    actions.push(
      @html.div(class="offline-field", [
        @html.label(
          for_="offline-quote-minor-units",
          copy(
            state.locale,
            "Price (minor units)",
            "价格（最小货币单位）",
          ),
        ),
        @html.input(
          id="offline-quote-minor-units",
          value=state.quote_minor_units,
          inputmode="numeric",
          maxlength=18,
          on_input=text_command(emit, value => QuoteMinorUnitsChanged(value)),
        ),
      ]),
    )
    actions.push(
      @html.div(class="offline-field", [
        @html.label(
          for_="offline-terms-digest",
          copy(
            state.locale,
            "Approved legal terms / snapshot SHA-256",
            "已批准法律条款/快照 SHA-256",
          ),
        ),
        @html.input(
          id="offline-terms-digest",
          value=state.terms_digest,
          maxlength=71,
          placeholder="sha256:…",
          on_input=text_command(emit, value => TermsDigestChanged(value)),
        ),
      ]),
    )
    actions.push(
      @html.button(
        type_="button",
        class="primary-action",
        disabled=state.loading ||
          state.operator_actor_ref.trim() == "" ||
          state.quote_minor_units.trim() == "" ||
          !@offline.valid_sha256(state.terms_digest.trim().to_owned()),
        on_click=command(
          emit,
          BeginConfirmation(
            QuoteOrder(
              order.order_id,
              state.terms_digest.trim().to_owned(),
              state.quote_minor_units.trim().to_owned(),
              state.operator_actor_ref.trim().to_owned(),
            ),
          ),
        ),
        copy(state.locale, "Create immutable quote", "创建不可变报价"),
      ),
    )
  }
  if order.state == Quoted {
    actions.push(
      @html.button(
        type_="button",
        class="primary-action",
        disabled=state.loading,
        on_click=command(
          emit,
          BeginConfirmation(BeginOrder(order.order_id, order.generation)),
        ),
        copy(state.locale, "Start workflow", "启动流程"),
      ),
    )
  }
  if order.state == PendingInternalApproval ||
    order.state == PendingOfflineExecution {
    for
      kind in [
        @offline.DocumentArtifactKind::EditableContractDocx,
        QuoteScheduleXlsx,
        PrintReadyContractPdf,
      ] {
      actions.push(
        @html.button(
          type_="button",
          class="secondary-action",
          disabled=state.loading,
          on_click=command(emit, RequestGeneration(order.order_id, kind)),
          copy(state.locale, "Generate ", "生成") +
          artifact_kind_label(state.locale, kind),
        ),
      )
    }
  }
  if order.state == PendingOfflineExecution {
    actions.push(
      @html.button(
        type_="button",
        class="primary-action",
        disabled=state.loading,
        on_click=command(
          emit,
          BeginConfirmation(
            ReleaseVerifiedPacket(order.order_id, order.generation),
          ),
        ),
        copy(state.locale, "Release verified PDF", "发布已验证 PDF"),
      ),
    )
  }
  if order.state == UnderReconciliation {
    actions.push(
      @html.div(class="offline-field", [
        @html.label(
          for_="offline-entitlement",
          copy(state.locale, "Entitlement reference", "权益引用"),
        ),
        @html.input(
          id="offline-entitlement",
          value=state.entitlement_ref,
          maxlength=160,
          on_input=text_command(emit, value => EntitlementChanged(value)),
        ),
      ]),
    )
    actions.push(
      @html.button(
        type_="button",
        class="primary-action",
        disabled=state.loading || state.entitlement_ref.trim() == "",
        on_click=command(
          emit,
          BeginConfirmation(
            FulfillVerifiedOrder(order.order_id, order.generation),
          ),
        ),
        copy(state.locale, "Fulfill after all checks", "全部核验后履约"),
      ),
    )
  }
  if order.state == Fulfilled {
    actions.push(
      @html.button(
        type_="button",
        class="danger-action",
        disabled=state.loading,
        on_click=command(
          emit,
          BeginConfirmation(
            RequestEntitlementReversal(order.order_id, order.generation),
          ),
        ),
        copy(state.locale, "Revoke entitlement", "撤销权益"),
      ),
    )
  }
  if order.state == ReversalManualIntervention {
    let failed_reversal_id = state.reversals
      .iter()
      .find_first(reversal => {
        reversal.order_id == order.order_id && reversal.state == ReversalFailed
      })
      .map(reversal => reversal.reversal_id)
      .unwrap_or("")
    actions.push(
      @html.p(
        class="offline-action-note",
        copy(
          state.locale,
          "Compare the external entitlement authority with the failed reversal receipt before selecting a recovery.",
          "选择恢复方式前，请对照失败撤销回执核验外部权益授权方的实际状态。",
        ),
      ),
    )
    actions.push(
      @html.button(
        type_="button",
        class="secondary-action",
        disabled=state.loading || failed_reversal_id == "",
        on_click=command(
          emit,
          BeginConfirmation(
            RecoverFailedReversal(
              order.order_id,
              failed_reversal_id,
              order.generation,
              RetryReversal,
            ),
          ),
        ),
        copy(state.locale, "Retry revocation", "重新尝试撤销"),
      ),
    )
    actions.push(
      @html.button(
        type_="button",
        class="danger-action",
        disabled=state.loading || failed_reversal_id == "",
        on_click=command(
          emit,
          BeginConfirmation(
            RecoverFailedReversal(
              order.order_id,
              failed_reversal_id,
              order.generation,
              ConfirmRevoked,
            ),
          ),
        ),
        copy(
          state.locale,
          "Confirm access revoked",
          "确认访问权限已撤销",
        ),
      ),
    )
    actions.push(
      @html.button(
        type_="button",
        class="quiet-button",
        disabled=state.loading || failed_reversal_id == "",
        on_click=command(
          emit,
          BeginConfirmation(
            RecoverFailedReversal(
              order.order_id,
              failed_reversal_id,
              order.generation,
              ConfirmStillActive,
            ),
          ),
        ),
        copy(
          state.locale,
          "Confirm access still active",
          "确认访问权限仍有效",
        ),
      ),
    )
  }
  @html.div(class="offline-actions", actions)
}

///|
fn artifact_card(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  artifact : OfflineArtifactSummary,
) -> @rabbita.Html {
  @html.article(class="offline-artifact-card", [
    @html.div(class="offline-card-heading", [
      @html.div([
        @html.small(copy(state.locale, "DOCUMENT", "文档")),
        @html.h4(artifact_kind_label(state.locale, artifact.kind)),
      ]),
      @html.span(class="status-pill", review_label(state.locale, artifact)),
    ]),
    @html.dl(class="offline-artifact-facts", [
      @html.div([
        @html.dt(copy(state.locale, "Revision", "版本")),
        @html.dd(artifact.revision.to_string()),
      ]),
      @html.div([
        @html.dt(copy(state.locale, "Size", "大小")),
        @html.dd("\{artifact.byte_count} bytes"),
      ]),
      @html.div([@html.dt("SHA-256"), @html.dd(class="mono", artifact.sha256)]),
    ]),
    if state.audience == CustomerCommerce && artifact.scan_state == ScanPassed {
      @html.button(
        type_="button",
        class="secondary-action",
        disabled=state.loading,
        on_click=command(emit, RequestArtifactDownload(artifact.artifact_id)),
        copy(state.locale, "Download verified file", "下载已验证文件"),
      )
    } else if state.audience == OperatorCommerce &&
      artifact.review_state == AwaitingReview {
      @html.div(class="review-actions", [
        @html.button(
          type_="button",
          class="quiet-button",
          disabled=state.loading,
          on_click=command(
            emit,
            BeginConfirmation(
              RejectEvidence(artifact.artifact_id, artifact.sha256),
            ),
          ),
          copy(state.locale, "Request correction", "要求补正"),
        ),
        @html.button(
          type_="button",
          class="primary-action",
          disabled=state.loading,
          on_click=command(
            emit,
            BeginConfirmation(
              AcceptEvidence(artifact.artifact_id, artifact.sha256),
            ),
          ),
          copy(state.locale, "Accept exact digest", "接受此文件摘要"),
        ),
      ])
    } else {
      @html.p(
        class="offline-action-note",
        copy(
          state.locale,
          "The file is tracked by digest. Replacements create a new revision.",
          "文件按摘要跟踪；重新上传会创建新版本。",
        ),
      )
    },
  ])
}

///|
fn order_detail(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  order : @offline.CommercialOrder,
) -> @rabbita.Html {
  let artifacts = state.artifacts.filter(value => {
    value.order_id == order.order_id
  })
  @html.div(class="offline-detail-stack", [
    @html.section(class="offline-order-hero", [
      @html.div([
        @html.p(
          class="eyebrow",
          copy(state.locale, "HYBRID ORDER", "线上线下协同订单"),
        ),
        @html.h2(order.order_id),
        @html.p(
          copy(
            state.locale,
            "Online configuration and tracking; offline seal, treasury, and invoice controls remain unchanged.",
            "线上完成配置与跟踪；线下盖章、资金与开票流程保持不变。",
          ),
        ),
      ]),
      @html.span(
        class="status-pill",
        order_state_label(state.locale, order.state),
      ),
    ]),
    steps(state.locale, order.state),
    @html.div(class="offline-two-column", [
      @html.section(class="offline-panel", [
        @html.h3(copy(state.locale, "Order details", "订单详情")),
        @html.dl([
          @html.div([
            @html.dt(copy(state.locale, "Service", "服务")),
            @html.dd(order.selected_service_code),
          ]),
          @html.div([@html.dt("SLA"), @html.dd(order.selected_sla_code)]),
          @html.div([
            @html.dt(copy(state.locale, "Project", "项目")),
            @html.dd(order.project_id),
          ]),
          @html.div([
            @html.dt(copy(state.locale, "Expires", "到期时间")),
            @html.dd(order.expires_unix_ms.to_string()),
          ]),
          @html.div([
            @html.dt(copy(state.locale, "Generation", "状态版本")),
            @html.dd(order.generation.to_string()),
          ]),
        ]),
      ]),
      @html.section(class="offline-panel", [
        @html.h3(
          copy(state.locale, "Fulfillment checklist", "履约核验清单"),
        ),
        @html.ul(
          class="offline-policy-list",
          policy_items(state.locale, order.policy),
        ),
      ]),
    ]),
    if state.audience == CustomerCommerce {
      customer_actions(state, emit, order)
    } else {
      operator_actions(state, emit, order)
    },
    @html.section(class="offline-documents", [
      @html.div(class="section-heading", [
        @html.div([
          @html.h3(
            copy(state.locale, "Documents and evidence", "文档与凭证"),
          ),
          @html.p(
            copy(
              state.locale,
              "Generated sources, print copy, uploads, safety checks, and review stay linked to this order.",
              "生成源文件、打印件、上传材料、安全检查与审核均关联到此订单。",
            ),
          ),
        ]),
        @html.span("\{artifacts.length()}"),
      ]),
      @html.div(
        class="offline-artifact-grid",
        [
          for artifact in artifacts => artifact_card(state, emit, artifact)
        ],
      ),
    ]),
  ])
}

///|
fn create_order_form(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
) -> @rabbita.Html {
  @html.section(class="offline-create-form", [
    @html.h3(copy(state.locale, "Configure a new order", "配置新订单")),
    @html.p(
      copy(
        state.locale,
        "Start with service intent. Pricing, the contract packet, and every required offline control are added as explicit later stages.",
        "请先填写服务意向。报价、合同材料与所需线下控制会在后续阶段逐项明确添加。",
      ),
    ),
    @html.div(class="offline-form-grid", [
      @html.div(class="offline-field", [
        @html.label(
          for_="offline-project",
          copy(state.locale, "Project ID", "项目 ID"),
        ),
        @html.input(
          id="offline-project",
          value=state.project_id,
          maxlength=160,
          on_input=text_command(emit, value => ProjectChanged(value)),
        ),
      ]),
      @html.div(class="offline-field", [
        @html.label(
          for_="offline-service",
          copy(state.locale, "Service", "服务"),
        ),
        @html.input(
          id="offline-service",
          value=state.service_code,
          maxlength=160,
          on_input=text_command(emit, value => ServiceChanged(value)),
        ),
      ]),
      @html.div(class="offline-field", [
        @html.label(for_="offline-sla", "SLA"),
        @html.input(
          id="offline-sla",
          value=state.sla_code,
          maxlength=160,
          on_input=text_command(emit, value => SlaChanged(value)),
        ),
      ]),
    ]),
    @html.button(
      type_="button",
      class="primary-action",
      disabled=state.loading ||
        state.project_id.trim() == "" ||
        state.service_code.trim() == "" ||
        state.sla_code.trim() == "",
      on_click=command(emit, CreateOrder),
      copy(state.locale, "Create draft order", "创建订单草稿"),
    ),
  ])
}

///|
fn confirmation_title(
  locale : @i18n.Locale,
  action : OfflineCommerceConsequentialAction,
) -> String {
  match action {
    QuoteOrder(_, _, _, _) =>
      copy(
        locale, "Freeze this immutable quote?", "确认冻结此不可变报价？",
      )
    BeginOrder(_, _) =>
      copy(
        locale, "Start the offline workflow?", "确认启动线下办理流程？",
      )
    ReleaseVerifiedPacket(_, _) =>
      copy(
        locale, "Release the verified print packet?", "确认发布已验证打印材料？",
      )
    AcceptEvidence(_, _) =>
      copy(
        locale, "Accept this exact evidence digest?", "确认接受此文件摘要？",
      )
    RejectEvidence(_, _) =>
      copy(
        locale, "Reject this evidence revision?", "确认拒绝此凭证版本？",
      )
    FulfillVerifiedOrder(_, _) =>
      copy(locale, "Create the entitlement now?", "确认立即创建权益？")
    CancelOrder(_, _) =>
      copy(
        locale, "Cancel this order or end its active access?", "确认取消此订单或结束其有效访问？",
      )
    RequestEntitlementReversal(_, _) =>
      copy(locale, "Revoke this entitlement?", "确认撤销此权益？")
    RecoverFailedReversal(_, _, _, RetryReversal) =>
      copy(
        locale, "Retry entitlement revocation?", "重新尝试撤销权益？",
      )
    RecoverFailedReversal(_, _, _, ConfirmRevoked) =>
      copy(
        locale, "Confirm external access is revoked?", "确认外部访问权限已撤销？",
      )
    RecoverFailedReversal(_, _, _, ConfirmStillActive) =>
      copy(
        locale, "Confirm external access is still active?", "确认外部访问权限仍有效？",
      )
  }
}

///|
fn confirmation_description(
  locale : @i18n.Locale,
  action : OfflineCommerceConsequentialAction,
) -> String {
  match action {
    QuoteOrder(_, _, _, _) =>
      copy(
        locale, "The price, validity window, terms digest, service, and SLA become immutable for this quote revision.",
        "本报价版本的价格、有效期、条款摘要、服务与 SLA 将不可变更。",
      )
    BeginOrder(_, _) =>
      copy(
        locale, "This generation-fenced transition starts internal approval or offline execution. Refresh if the order changed.",
        "此操作受状态版本保护，并将进入内部审批或线下办理；如订单已变化，请先刷新。",
      )
    ReleaseVerifiedPacket(_, _) =>
      copy(
        locale, "Only a verified print-ready PDF may be released. The customer will be asked to complete offline seal, treasury, and invoice controls.",
        "仅可发布已验证的可打印 PDF；客户随后需完成线下盖章、资金与开票流程。",
      )
    AcceptEvidence(_, _) =>
      copy(
        locale, "Acceptance binds the exact SHA-256 digest. The submitter cannot review their own evidence.",
        "接受操作绑定确切 SHA-256 摘要；材料提交人不得审核自己的材料。",
      )
    RejectEvidence(_, _) =>
      copy(
        locale, "The order enters correction-required status and the customer must upload a new revision.",
        "订单将进入需要补正状态，客户必须上传新版本。",
      )
    FulfillVerifiedOrder(_, _) =>
      copy(
        locale, "Fulfillment creates the entitlement only when every policy-required artifact is scan-passed and independently accepted.",
        "仅当所有策略要求的材料均通过扫描并经独立审核接受后，履约才会创建权益。",
      )
    CancelOrder(_, _) =>
      copy(
        locale, "Before fulfillment this cancels the order. After fulfillment it starts a generation-fenced entitlement reversal; access ends only after authority confirmation.",
        "履约前将取消订单；履约后将启动受状态版本保护的权益撤销，只有授权方确认后访问权限才会结束。",
      )
    RequestEntitlementReversal(_, _) =>
      copy(
        locale, "This starts a generation-fenced authority request. Access remains tracked until the external entitlement authority confirms revocation.",
        "此操作会启动受状态版本保护的授权方请求；系统将继续跟踪访问权限，直至外部权益授权方确认撤销。",
      )
    RecoverFailedReversal(_, _, _, RetryReversal) =>
      copy(
        locale, "A new generation-fenced authority request will be created; the failed receipt remains in the audit history.",
        "系统将创建受状态版本保护的新授权方请求；失败回执仍保留在审计历史中。",
      )
    RecoverFailedReversal(_, _, _, ConfirmRevoked) =>
      copy(
        locale, "Use only after independently verifying that the external entitlement is already revoked.",
        "仅在独立核验外部权益确已撤销后使用此操作。",
      )
    RecoverFailedReversal(_, _, _, ConfirmStillActive) =>
      copy(
        locale, "This returns the order to fulfilled state because the external entitlement remains active.",
        "因外部权益仍有效，此操作会将订单恢复为已履约状态。",
      )
  }
}

///|
fn commerce_confirmation(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
) -> @rabbita.Html {
  match state.confirmation {
    None => @html.nothing
    Some(value) =>
      @html.aside(
        class="offline-confirmation",
        attrs=@html.Attrs::build()
          .role("alertdialog")
          .aria_labelledby("offline-confirmation-title")
          .aria_describedby("offline-confirmation-description"),
        [
          @html.p(
            class="eyebrow",
            copy(state.locale, "CONSEQUENTIAL ACTION", "重要操作"),
          ),
          @html.h3(
            id="offline-confirmation-title",
            confirmation_title(state.locale, value.action),
          ),
          @html.p(
            id="offline-confirmation-description",
            confirmation_description(state.locale, value.action),
          ),
          @html.code(value.evidence),
          @html.div(class="offline-confirmation-actions", [
            @html.button(
              type_="button",
              class="quiet-button",
              on_click=command(emit, DismissConfirmation),
              copy(state.locale, "Go back", "返回"),
            ),
            @html.button(
              type_="button",
              class="primary-action",
              on_click=command(emit, ConfirmAction(value.action)),
              copy(
                state.locale,
                "Confirm with this evidence",
                "根据此证据确认",
              ),
            ),
          ]),
        ],
      )
  }
}

///|
fn offline_view(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
) -> @rabbita.Html {
  let stylesheet =
    #|.offline-commerce-workspace{display:grid;gap:1.1rem}.offline-order-layout{display:grid;grid-template-columns:minmax(13rem,.28fr) minmax(0,1fr);gap:1rem}.offline-order-list{display:grid;align-content:start;gap:.45rem}.offline-order-item{min-height:4.5rem;padding:.75rem;border:1px solid var(--line,#d5dee4);border-radius:.6rem;background:transparent;color:inherit;text-align:left;display:grid;gap:.15rem;cursor:pointer}.offline-order-item.is-active{border-color:var(--mint,#35bd8d);background:rgba(53,189,141,.08)}.offline-order-item span,.offline-order-item small,.offline-action-note{color:var(--muted,#80949c)}.offline-detail-stack{display:grid;gap:1rem}.offline-order-hero,.offline-card-heading,.section-heading{display:flex;justify-content:space-between;align-items:flex-start;gap:1rem}.offline-order-hero h2,.offline-card-heading h4,.section-heading h2,.section-heading h3{margin:.1rem 0}.offline-commerce-steps{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:.4rem;padding:0;list-style:none}.offline-commerce-steps li{display:grid;gap:.25rem;color:var(--muted,#80949c)}.offline-commerce-steps li span{width:2rem;height:2rem;border:1px solid var(--line,#d5dee4);border-radius:50%;display:grid;place-items:center}.offline-commerce-steps .is-current span,.offline-commerce-steps .is-complete span{border-color:var(--mint,#35bd8d);color:var(--mint,#168363)}.offline-two-column,.offline-artifact-grid,.offline-form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.75rem}.offline-panel,.offline-artifact-card,.offline-create-form{padding:1rem;border:1px solid var(--line,#d5dee4);border-radius:.7rem;background:var(--panel,#fff)}.offline-panel dl>div,.offline-artifact-facts>div{display:flex;justify-content:space-between;gap:.5rem;padding:.35rem 0}.offline-panel dd,.offline-artifact-facts dd{margin:0;overflow-wrap:anywhere}.offline-policy-list{display:grid;gap:.4rem;padding:0;list-style:none}.offline-policy-list li{display:grid;grid-template-columns:auto 1fr;column-gap:.5rem}.offline-policy-list small{grid-column:2;color:var(--muted,#80949c)}.offline-actions,.review-actions,.offline-confirmation-actions{display:flex;align-items:flex-end;flex-wrap:wrap;gap:.55rem}.offline-field{display:grid;gap:.3rem;min-width:12rem}.offline-field input{min-height:2.75rem;padding:.6rem .7rem;border:1px solid var(--line,#d5dee4);border-radius:.45rem;background:var(--bg,#fff);color:inherit}.offline-confirmation{position:sticky;bottom:1rem;margin-left:auto;max-width:42rem;padding:1rem;border:1px solid var(--amber,#b88300);border-radius:.7rem;background:var(--panel,#fff);box-shadow:0 1rem 3rem rgba(0,0,0,.25);z-index:5}.offline-confirmation code{display:block;padding:.65rem;margin:.6rem 0;border-radius:.4rem;background:rgba(128,148,156,.12);overflow-wrap:anywhere}.offline-confirmation-actions{justify-content:flex-end}.empty-state{padding:1rem;border:1px dashed var(--line,#d5dee4);border-radius:.7rem}@media(max-width:70rem){.offline-commerce-steps{grid-template-columns:repeat(3,minmax(0,1fr))}.offline-order-layout{grid-template-columns:1fr}.offline-order-list{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:40rem){.offline-order-list,.offline-commerce-steps,.offline-two-column,.offline-artifact-grid,.offline-form-grid{grid-template-columns:1fr}.offline-order-hero,.section-heading{flex-direction:column}.offline-confirmation{position:relative;bottom:auto}.offline-confirmation-actions{display:grid}}@media(prefers-reduced-motion:reduce){.offline-commerce-workspace *{transition:none!important;animation:none!important}}
  let selected : @offline.CommercialOrder? = match state.selected_order_id {
    Some(id) =>
      match state.orders.iter().find_first(order => order.order_id == id) {
        Some(order) => Some(order)
        None => state.orders.get(0)
      }
    None => state.orders.get(0)
  }
  @html.section(class="offline-commerce-workspace", [
    @html.style_tag(stylesheet),
    @html.header(class="section-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          copy(state.locale, "COMMERCIAL WORKFLOW", "商务办理流程"),
        ),
        @html.h2(
          if state.audience == CustomerCommerce {
            copy(
              state.locale,
              "Orders and offline documents",
              "订单与线下材料",
            )
          } else {
            copy(
              state.locale,
              "Offline reconciliation desk",
              "线下材料核验台",
            )
          },
        ),
        @html.p(
          copy(
            state.locale,
            "Every stage is explicit. Uploading a document never silently activates capacity.",
            "每个阶段均清晰可见；上传文件不会自动开通算力。",
          ),
        ),
      ]),
      @html.button(
        type_="button",
        class="quiet-button",
        disabled=state.loading,
        on_click=command(emit, Refresh),
        copy(state.locale, "Refresh", "刷新"),
      ),
    ]),
    @html.div(class="offline-order-layout", [
      @html.nav(
        class="offline-order-list",
        attrs=@html.Attrs::build().aria_label(
          copy(state.locale, "Commercial orders", "商务订单"),
        ),
        [
          for order in state.orders => {
            @html.button(
              type_="button",
              class=if selected.map_or(false, value => {
                  value.order_id == order.order_id
                }) {
                "offline-order-item is-active"
              } else {
                "offline-order-item"
              },
              on_click=command(emit, SelectOrder(order.order_id)),
              [
                @html.strong(order.order_id),
                @html.span(order_state_label(state.locale, order.state)),
                @html.small(
                  "\{order.selected_service_code} · \{order.selected_sla_code}",
                ),
              ],
            )
          }
        ],
      ),
      match selected {
        Some(order) => order_detail(state, emit, order)
        None =>
          @html.div(class="empty-state", [
            @html.h3(
              copy(
                state.locale,
                "No commercial orders yet",
                "暂无商务订单",
              ),
            ),
            @html.p(
              copy(
                state.locale,
                "Create an order to configure service, SLA, pricing, and required offline evidence.",
                "创建订单后，可配置服务、SLA、报价与所需线下凭证。",
              ),
            ),
            if state.audience == CustomerCommerce {
              create_order_form(state, emit)
            } else {
              @html.span("")
            },
          ])
      },
    ]),
    commerce_confirmation(state, emit),
  ])
}

///|
pub fn view(state : OfflineCommerceState) -> @rabbita.Html {
  offline_view(state, None)
}

///|
pub fn interactive_view(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage],
) -> @rabbita.Html {
  offline_view(state, Some(emit))
}

///|
#warnings("-alert_unstable")
pub fn render(state : OfflineCommerceState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
