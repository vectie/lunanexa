///|
/// Deployment-scoped, one-order opt-in. Default service configuration is None.
pub(all) struct TechnicalAcceptanceAuthorization {
  order_id : String
  purchaser_subject_ref : String
  user_authorization_ref : String
  expires_unix_ms : Int64
  order_binding : TechnicalAcceptanceOrderBinding?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Explicit extension to an existing quoted customer order. The quoted amount
/// is preserved as a proposal, never represented as money received. One order
/// still authorizes exactly one pre-existing resource target.
pub(all) struct TechnicalAcceptanceOrderBinding {
  organization_id : String
  tenant_ref : String
  quote : ImmutableQuote
  entitlement_kind : EntitlementKind
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend TechnicalAcceptanceOrderBinding with Debug::{to_repr}

///|
pub extend TechnicalAcceptanceOrderBinding with Eq::{equal, not_equal}

///|
pub extend TechnicalAcceptanceOrderBinding with ToJson::{to_json}

///|
pub extend TechnicalAcceptanceOrderBinding with FromJson::{from_json}

///|
pub extend TechnicalAcceptanceAuthorization with Debug::{to_repr}

///|
pub extend TechnicalAcceptanceAuthorization with Eq::{equal, not_equal}

///|
pub extend TechnicalAcceptanceAuthorization with ToJson::{to_json}

///|
pub extend TechnicalAcceptanceAuthorization with FromJson::{from_json}

///|
/// Explicit non-commercial, per-order authorization. This is not payment,
/// signing, invoicing, commercial KYC, or accepted evidence.
pub(all) struct TechnicalAcceptanceWaiver {
  waiver_id : String
  classification : String
  waived_requirements : Array[OfflineEvidenceKind]
  order_id : String
  tenant_ref : String
  organization_id : String
  purchaser_subject_ref : String
  quote : ImmutableQuote
  authority_target_ref : String
  grant_id : String
  purchaser_account_id : String
  identity_issuer : String
  identity_receipt : String
  identity_verification_method : String
  operator_account_id : String
  operator_subject_ref : String
  operator_session_id : String
  user_authorization_ref : String
  reason : String
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  order_binding : TechnicalAcceptanceOrderBinding?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn TechnicalAcceptanceWaiver::entitlement_kind(
  self : TechnicalAcceptanceWaiver,
) -> EntitlementKind {
  self.order_binding.map_or(WorkspaceLease, binding => binding.entitlement_kind)
}

///|
pub fn TechnicalAcceptanceOrderBinding::matches_order(
  self : TechnicalAcceptanceOrderBinding,
  order : CommercialOrder,
) -> Bool {
  !self.organization_id.is_empty() &&
  !self.tenant_ref.is_empty() &&
  self.organization_id == order.organization_id &&
  self.tenant_ref == order.tenant_ref &&
  order.quote == Some(self.quote) &&
  self.quote.service_code == order.selected_service_code
}

///|
fn technical_order_shape(
  order : CommercialOrder,
  w : TechnicalAcceptanceWaiver,
) -> Bool {
  match w.order_binding {
    Some(binding) => binding.matches_order(order)
    None =>
      order.selected_service_code == "technical-workspace-acceptance" &&
      order.organization_id.has_prefix("technical-acceptance-") &&
      order.tenant_ref.has_prefix("technical-acceptance-") &&
      w.quote.total.minor_units == 0L &&
      w.quote.subtotal.minor_units == 0L &&
      w.quote.tax.minor_units == 0L &&
      w.quote.lines.all(l => {
        l.unit_price.minor_units == 0L && l.line_total.minor_units == 0L
      }) &&
      order.requested_undertaking_term is None
  }
}

///|
pub fn technical_waived_requirements() -> Array[OfflineEvidenceKind] {
  [
    ExecutedAgreementEvidence,
    PaymentEvidence,
    InvoiceEvidence,
    InternalApproval,
  ]
}

///|
pub extend TechnicalAcceptanceWaiver with Debug::{to_repr}

///|
pub extend TechnicalAcceptanceWaiver with Eq::{equal, not_equal}

///|
pub extend TechnicalAcceptanceWaiver with ToJson::{to_json}

///|
pub extend TechnicalAcceptanceWaiver with FromJson::{from_json}

///|
pub fn validate_technical_waiver(
  order : CommercialOrder,
) -> Unit raise OfflineCommerceError {
  guard order.technical_acceptance_waiver is Some(w) else { return }
  guard w.classification == "technical-acceptance-waived-not-paid" &&
    (
      order.state == UnderReconciliation ||
      order.state == FulfillmentPending ||
      order.state == Fulfilled ||
      order.state == Cancelled ||
      order.state == Expired ||
      order.state == Rejected ||
      order.state == ReversalPending ||
      order.state == ReversalManualIntervention ||
      order.state == Revoked
    ) &&
    order.generation >= 3L &&
    order.updated_unix_ms >= w.issued_unix_ms &&
    w.waived_requirements == technical_waived_requirements() &&
    w.order_id == order.order_id &&
    w.tenant_ref == order.tenant_ref &&
    w.organization_id == order.organization_id &&
    w.purchaser_subject_ref == order.purchaser_subject_ref &&
    order.quote == Some(w.quote) &&
    technical_order_shape(order, w) &&
    order.policy.require_executed_agreement &&
    order.policy.require_payment &&
    order.policy.invoice_timing == InvoiceBeforeFulfillment &&
    order.policy.require_identity_verification &&
    order.policy.require_internal_approval &&
    order.agreement_ref is None &&
    w.identity_verification_method == "actual-oidc-not-commercial-kyc" &&
    w.issued_unix_ms > 0L &&
    w.expires_unix_ms > w.issued_unix_ms &&
    w.expires_unix_ms - w.issued_unix_ms <= 3600000L &&
    order.expires_unix_ms <= w.expires_unix_ms &&
    [
      w.waiver_id,
      w.authority_target_ref,
      w.grant_id,
      w.purchaser_account_id,
      w.identity_issuer,
      w.identity_receipt,
      w.operator_account_id,
      w.operator_subject_ref,
      w.operator_session_id,
      w.user_authorization_ref,
      w.reason,
    ].all(s => s.length() > 0 && s.length() <= 2048) else {
    raise InvalidInput("invalid or rebound technical acceptance waiver")
  }
}

///|
pub fn validate_technical_activation(
  order : CommercialOrder,
  activation : EntitlementActivation,
  now : Int64,
) -> Unit raise OfflineCommerceError {
  guard order.technical_acceptance_waiver is Some(w) else { return }
  validate_technical_waiver(order)
  guard now >= w.issued_unix_ms &&
    now < w.expires_unix_ms &&
    activation.kind == w.entitlement_kind() &&
    activation.authority_target_ref == w.authority_target_ref else {
    raise InvalidInput("technical waiver expired or authority target differs")
  }
}

///|
pub fn technical_requirement_satisfied(
  order : CommercialOrder,
  kind : OfflineEvidenceKind,
) -> Bool {
  guard order.technical_acceptance_waiver is Some(w) else { return false }
  // Identity is not waived: actual OIDC verification is a distinct proof.
  w.waived_requirements.contains(kind) ||
  (
    kind == IdentityVerification &&
    w.identity_verification_method == "actual-oidc-not-commercial-kyc"
  )
}
