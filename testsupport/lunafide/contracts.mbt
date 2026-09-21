///|
/// Provider-neutral protocol identifier used by the LunaFide test double.
pub let protocol_version : String = "qualified-services.v1"

///|
pub(all) enum ServiceMode {
  TestOnly
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ServiceIdentity {
  service_name : String
  protocol_version : String
  mode : ServiceMode
  production_ready : Bool
  stores_real_pii : Bool
  stores_payment_credentials : Bool
  trust_claim : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct HealthPayload {
  identity : ServiceIdentity
  status : String
  state_backend : String
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn service_identity() -> ServiceIdentity {
  {
    service_name: "LunaFide",
    protocol_version,
    mode: TestOnly,
    production_ready: false,
    stores_real_pii: false,
    stores_payment_credentials: false,
    trust_claim: "none; deterministic test double only",
  }
}

///|
pub(all) enum VerificationSubjectType {
  Organization
  Individual
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum VerificationState {
  Pending
  Verified
  Rejected
  Expired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct VerificationRequest {
  protocol_version : String
  idempotency_key : String
  tenant_ref : String
  subject_ref : String
  subject_type : VerificationSubjectType
  requested_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct VerificationResolution {
  protocol_version : String
  idempotency_key : String
  tenant_ref : String
  verification_ref : String
  state : VerificationState
  reason_code : String
  resolved_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct VerificationRecord {
  verification_ref : String
  tenant_ref : String
  subject_ref : String
  subject_type : VerificationSubjectType
  state : VerificationState
  reason_code : String
  requested_unix_ms : Int64
  resolved_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum EnvelopeState {
  AwaitingSigner
  AwaitingCountersignature
  Executed
  Declined
  Voided
  Expired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EnvelopeRequest {
  protocol_version : String
  idempotency_key : String
  tenant_ref : String
  template_ref : String
  document_sha256 : String
  signer_ref : String
  countersigner_ref : String?
  expires_unix_ms : Int64
  requested_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum SignatureParty {
  Signer
  Countersigner
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum SignatureDecision {
  Signed
  Declined
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SignatureAction {
  protocol_version : String
  idempotency_key : String
  tenant_ref : String
  envelope_ref : String
  actor_ref : String
  party : SignatureParty
  decision : SignatureDecision
  acted_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EnvelopeRecord {
  envelope_ref : String
  tenant_ref : String
  template_ref : String
  document_sha256 : String
  signer_ref : String
  countersigner_ref : String?
  state : EnvelopeState
  expires_unix_ms : Int64
  executed_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum PaymentOutcome {
  Succeed
  Decline
  RequireReview
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum PaymentState {
  Settled
  Declined
  UnderReview
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PaymentRequest {
  protocol_version : String
  idempotency_key : String
  tenant_ref : String
  order_ref : String
  amount_minor : Int64
  currency : String
  simulated_outcome : PaymentOutcome
  requested_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PaymentRecord {
  payment_ref : String
  tenant_ref : String
  order_ref : String
  amount_minor : Int64
  currency : String
  state : PaymentState
  reason_code : String
  processed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum InvoiceState {
  Issued
  Voided
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct InvoiceRequest {
  protocol_version : String
  idempotency_key : String
  tenant_ref : String
  bill_ref : String
  billing_profile_ref : String
  amount_minor : Int64
  currency : String
  bill_content_sha256 : String
  requested_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct InvoiceAction {
  protocol_version : String
  idempotency_key : String
  tenant_ref : String
  invoice_ref : String
  reason_code : String
  acted_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct InvoiceRecord {
  invoice_ref : String
  tenant_ref : String
  bill_ref : String
  billing_profile_ref : String
  amount_minor : Int64
  currency : String
  bill_content_sha256 : String
  state : InvoiceState
  issued_unix_ms : Int64
  voided_unix_ms : Int64?
  replaces_invoice_ref : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum WebhookKind {
  VerificationRequested
  VerificationResolved
  EnvelopeCreated
  EnvelopeUpdated
  PaymentUpdated
  InvoiceIssued
  InvoiceVoided
  InvoiceReissued
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WebhookEvent {
  protocol_version : String
  provider : String
  environment : String
  event_id : String
  kind : WebhookKind
  tenant_ref : String
  aggregate_ref : String
  sequence : Int64
  occurred_unix_ms : Int64
  idempotency_key : String
  payload : Json
  key_id : String
  auth_scheme : String
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror LunaFideError {
  InvalidRequest(String)
  IdempotencyConflict(String)
  NotFound(String)
  IllegalTransition(String)
  ForgedWebhook(String)
  ReplayWebhook(String)
  StaleWebhook(String)
  ExpiredWebhook(String)
} derive(Debug, Eq)
