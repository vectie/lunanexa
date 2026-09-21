///|
/// Provider-neutral protocol identifier used by the LunaFide test double.
pub let protocol_version : String = "qualified-services.v1"

///|
pub(all) enum ServiceMode {
  TestOnly
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ServiceMode with Debug::{to_repr}

///|
pub extend ServiceMode with Eq::{not_equal, equal}

///|
pub extend ServiceMode with ToJson::{to_json}

///|
pub extend ServiceMode with FromJson::{from_json}

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
pub extend ServiceIdentity with Debug::{to_repr}

///|
pub extend ServiceIdentity with Eq::{not_equal, equal}

///|
pub extend ServiceIdentity with ToJson::{to_json}

///|
pub extend ServiceIdentity with FromJson::{from_json}

///|
pub(all) struct HealthPayload {
  identity : ServiceIdentity
  status : String
  state_backend : String
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend HealthPayload with Debug::{to_repr}

///|
pub extend HealthPayload with Eq::{not_equal, equal}

///|
pub extend HealthPayload with ToJson::{to_json}

///|
pub extend HealthPayload with FromJson::{from_json}

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
pub extend VerificationSubjectType with Debug::{to_repr}

///|
pub extend VerificationSubjectType with Eq::{not_equal, equal}

///|
pub extend VerificationSubjectType with ToJson::{to_json}

///|
pub extend VerificationSubjectType with FromJson::{from_json}

///|
pub(all) enum VerificationState {
  Pending
  Verified
  Rejected
  Expired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend VerificationState with Debug::{to_repr}

///|
pub extend VerificationState with Eq::{not_equal, equal}

///|
pub extend VerificationState with ToJson::{to_json}

///|
pub extend VerificationState with FromJson::{from_json}

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
pub extend VerificationRequest with Debug::{to_repr}

///|
pub extend VerificationRequest with Eq::{not_equal, equal}

///|
pub extend VerificationRequest with ToJson::{to_json}

///|
pub extend VerificationRequest with FromJson::{from_json}

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
pub extend VerificationResolution with Debug::{to_repr}

///|
pub extend VerificationResolution with Eq::{not_equal, equal}

///|
pub extend VerificationResolution with ToJson::{to_json}

///|
pub extend VerificationResolution with FromJson::{from_json}

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
pub extend VerificationRecord with Debug::{to_repr}

///|
pub extend VerificationRecord with Eq::{not_equal, equal}

///|
pub extend VerificationRecord with ToJson::{to_json}

///|
pub extend VerificationRecord with FromJson::{from_json}

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
pub extend EnvelopeState with Debug::{to_repr}

///|
pub extend EnvelopeState with Eq::{not_equal, equal}

///|
pub extend EnvelopeState with ToJson::{to_json}

///|
pub extend EnvelopeState with FromJson::{from_json}

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
pub extend EnvelopeRequest with Debug::{to_repr}

///|
pub extend EnvelopeRequest with Eq::{not_equal, equal}

///|
pub extend EnvelopeRequest with ToJson::{to_json}

///|
pub extend EnvelopeRequest with FromJson::{from_json}

///|
pub(all) enum SignatureParty {
  Signer
  Countersigner
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend SignatureParty with Debug::{to_repr}

///|
pub extend SignatureParty with Eq::{not_equal, equal}

///|
pub extend SignatureParty with ToJson::{to_json}

///|
pub extend SignatureParty with FromJson::{from_json}

///|
pub(all) enum SignatureDecision {
  Signed
  Declined
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend SignatureDecision with Debug::{to_repr}

///|
pub extend SignatureDecision with Eq::{not_equal, equal}

///|
pub extend SignatureDecision with ToJson::{to_json}

///|
pub extend SignatureDecision with FromJson::{from_json}

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
pub extend SignatureAction with Debug::{to_repr}

///|
pub extend SignatureAction with Eq::{not_equal, equal}

///|
pub extend SignatureAction with ToJson::{to_json}

///|
pub extend SignatureAction with FromJson::{from_json}

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
pub extend EnvelopeRecord with Debug::{to_repr}

///|
pub extend EnvelopeRecord with Eq::{not_equal, equal}

///|
pub extend EnvelopeRecord with ToJson::{to_json}

///|
pub extend EnvelopeRecord with FromJson::{from_json}

///|
pub(all) enum PaymentOutcome {
  Succeed
  Decline
  RequireReview
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PaymentOutcome with Debug::{to_repr}

///|
pub extend PaymentOutcome with Eq::{not_equal, equal}

///|
pub extend PaymentOutcome with ToJson::{to_json}

///|
pub extend PaymentOutcome with FromJson::{from_json}

///|
pub(all) enum PaymentState {
  Settled
  Declined
  UnderReview
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PaymentState with Debug::{to_repr}

///|
pub extend PaymentState with Eq::{not_equal, equal}

///|
pub extend PaymentState with ToJson::{to_json}

///|
pub extend PaymentState with FromJson::{from_json}

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
pub extend PaymentRequest with Debug::{to_repr}

///|
pub extend PaymentRequest with Eq::{not_equal, equal}

///|
pub extend PaymentRequest with ToJson::{to_json}

///|
pub extend PaymentRequest with FromJson::{from_json}

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
pub extend PaymentRecord with Debug::{to_repr}

///|
pub extend PaymentRecord with Eq::{not_equal, equal}

///|
pub extend PaymentRecord with ToJson::{to_json}

///|
pub extend PaymentRecord with FromJson::{from_json}

///|
pub(all) enum InvoiceState {
  Issued
  Voided
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend InvoiceState with Debug::{to_repr}

///|
pub extend InvoiceState with Eq::{not_equal, equal}

///|
pub extend InvoiceState with ToJson::{to_json}

///|
pub extend InvoiceState with FromJson::{from_json}

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
pub extend InvoiceRequest with Debug::{to_repr}

///|
pub extend InvoiceRequest with Eq::{not_equal, equal}

///|
pub extend InvoiceRequest with ToJson::{to_json}

///|
pub extend InvoiceRequest with FromJson::{from_json}

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
pub extend InvoiceAction with Debug::{to_repr}

///|
pub extend InvoiceAction with Eq::{not_equal, equal}

///|
pub extend InvoiceAction with ToJson::{to_json}

///|
pub extend InvoiceAction with FromJson::{from_json}

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
pub extend InvoiceRecord with Debug::{to_repr}

///|
pub extend InvoiceRecord with Eq::{not_equal, equal}

///|
pub extend InvoiceRecord with ToJson::{to_json}

///|
pub extend InvoiceRecord with FromJson::{from_json}

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
pub extend WebhookKind with Debug::{to_repr}

///|
pub extend WebhookKind with Eq::{not_equal, equal}

///|
pub extend WebhookKind with ToJson::{to_json}

///|
pub extend WebhookKind with FromJson::{from_json}

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
pub extend WebhookEvent with Debug::{to_repr}

///|
pub extend WebhookEvent with Eq::{not_equal, equal}

///|
pub extend WebhookEvent with ToJson::{to_json}

///|
pub extend WebhookEvent with FromJson::{from_json}

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

///|
pub extend LunaFideError with Debug::{to_repr}

///|
pub extend LunaFideError with Eq::{not_equal, equal}
