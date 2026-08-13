///|
pub let contract_version : String = "lunanexa.offline-commerce.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.offline-commerce.snapshot.v5"

///|
pub(all) suberror OfflineCommerceError {
  InvalidInput(String)
  NotFound(String)
  AlreadyExists(String)
  IdempotencyConflict(String)
  TenantMismatch
  Unauthorized
  StaleGeneration
  InvalidTransition(String)
  SeparationOfDuties
  EvidenceMissing(Array[OfflineEvidenceKind])
  ArtifactUnavailable(String)
} derive(Debug, Eq)

///|
pub(all) enum OfflineOrderState {
  Draft
  Quoted
  PendingInternalApproval
  PendingOfflineExecution
  PendingEvidenceUpload
  UnderReconciliation
  FulfillmentPending
  Fulfilled
  ReversalPending
  ReversalManualIntervention
  Revoked
  NeedsCorrection
  Rejected
  Cancelled
  Expired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OfflineCommerceReadinessStatus {
  OfflineCommerceAdaptersPending
  OfflineCommerceReady
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OfflineCommerceCapability {
  ApprovedLegalTemplates
  ObjectStorage
  MalwareScanner
  OoxmlWorker
  PdfRenderer
  SpreadsheetFormulaEngine
  CjkFonts
  MachineCallbackIdentity
  EntitlementAuthority
  FinanceLegalPolicy
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OfflineCommerceCapabilityEvidence {
  capability : OfflineCommerceCapability
  configured : Bool
  verified : Bool
  evidence_ref : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OfflineCommerceReadiness {
  status : OfflineCommerceReadinessStatus
  capabilities : Array[OfflineCommerceCapabilityEvidence]
  blocker_codes : Array[String]
  evaluated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum EntitlementKind {
  CapacityCommitment
  WorkspaceLease
  ExclusiveMachineLease
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum EntitlementActivationState {
  EntitlementActivationRequested
  EntitlementActivationConfirmed
  EntitlementActivationRejected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EntitlementActivation {
  activation_id : String
  idempotency_key : String
  order_id : String
  organization_id : String
  purchaser_subject_ref : String
  kind : EntitlementKind
  authority_target_ref : String
  expected_order_generation : Int64
  state : EntitlementActivationState
  entitlement_ref : String?
  authority_receipt : String?
  reason_code : String?
  requested_by : String
  requested_unix_ms : Int64
  completed_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum CommercialReversalReason {
  CustomerCancellation
  ContractExpired
  PaymentRefunded
  PaymentVoided
  InvoiceVoided
  PolicyRevoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum CommercialReversalState {
  ReversalRequested
  ReversalConfirmed
  ReversalFailed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommercialReversal {
  reversal_id : String
  idempotency_key : String
  order_id : String
  organization_id : String
  entitlement_ref : String
  reason : CommercialReversalReason
  expected_order_generation : Int64
  state : CommercialReversalState
  authority_receipt : String?
  reason_code : String?
  requested_by : String
  requested_unix_ms : Int64
  completed_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Operator decision after an authenticated entitlement authority failure.
pub(all) enum ReversalRecoveryDecision {
  RetryReversal
  ConfirmRevoked
  ConfirmStillActive
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Durable, generation-fenced evidence for resolving manual intervention.
pub(all) struct ReversalRecovery {
  recovery_id : String
  idempotency_key : String
  order_id : String
  organization_id : String
  failed_reversal_id : String
  expected_order_generation : Int64
  decision : ReversalRecoveryDecision
  replacement_reversal_id : String?
  authority_receipt : String
  reason_code : String
  recovered_by : String
  recovered_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///| Provider-neutral, browser-safe byte-transfer authority. The token is

///| opaque and one-time; object-store routing and provider credentials remain

///|
/// behind the deployment adapter.
pub(all) enum OfflineTransferDirection {
  UploadTransfer
  DownloadTransfer
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OfflineTransferState {
  TransferIssued
  TransferConsumed
  TransferExpired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OfflineTransferSession {
  session_id : String
  idempotency_key : String
  session_token_sha256 : String
  organization_id : String
  subject_ref : String
  order_id : String
  artifact_id : String
  direction : OfflineTransferDirection
  media_types : Array[String]
  maximum_byte_count : Int64
  expected_sha256 : String?
  state : OfflineTransferState
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  consumed_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///| Only this projection may cross into a browser. It exposes a same-origin

///|
/// route and raw one-time token, never the object-store key.
pub(all) struct OfflineTransferGrant {
  session_id : String
  transfer_path : String
  session_token : String
  direction : OfflineTransferDirection
  media_types : Array[String]
  maximum_byte_count : Int64
  expected_sha256 : String?
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///| Provider-neutral, byte-bound completion evidence. The raw one-time token

///|
/// is deliberately absent.
pub(all) struct OfflineTransferEvidence {
  session_id : String
  media_type : String
  byte_count : Int64
  sha256 : String
  provider_receipt : String
  completed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum InvoiceTiming {
  InvoiceBeforeFulfillment
  InvoiceAfterFulfillment
  InvoiceNotRequired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FulfillmentPolicy {
  require_executed_agreement : Bool
  require_payment : Bool
  invoice_timing : InvoiceTiming
  require_identity_verification : Bool
  require_internal_approval : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct QuoteLine {
  line_id : String
  description : String
  quantity : Int64
  unit : String
  unit_price : @commercial.FixedMoney
  line_total : @commercial.FixedMoney
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ImmutableQuote {
  quote_id : String
  version : String
  service_code : String
  sla_code : String
  currency : String
  lines : Array[QuoteLine]
  subtotal : @commercial.FixedMoney
  tax : @commercial.FixedMoney
  total : @commercial.FixedMoney
  valid_until_unix_ms : Int64
  terms_digest : String
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum DocumentTemplateKind {
  ContractTemplate
  QuoteScheduleTemplate
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DocumentTemplate {
  template_id : String
  version : String
  kind : DocumentTemplateKind
  locale : String
  media_type : String
  object_ref : String
  sha256 : String
  byte_count : Int64
  active_content_allowed : Bool
  created_unix_ms : Int64
  superseded_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum DocumentArtifactKind {
  EditableContractDocx
  QuoteScheduleXlsx
  PrintReadyContractPdf
  ExecutedContractScan
  PaymentReceipt
  IssuedInvoice
  InternalApprovalEvidence
  IdentityVerificationEvidence
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ArtifactGenerationState {
  GenerationRequested
  ArtifactGenerated
  GenerationFailed
  UserUploaded
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ArtifactScanState {
  AwaitingScan
  ScanPassed
  ScanRejected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ArtifactReviewState {
  ReviewNotRequired
  AwaitingReview
  ReviewAccepted
  ReviewRejected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DocumentArtifact {
  artifact_id : String
  order_id : String
  organization_id : String
  kind : DocumentArtifactKind
  revision : Int
  template_id : String?
  template_version : String?
  locale : String
  media_type : String
  byte_count : Int64
  sha256 : String
  object_ref : String
  generation_state : ArtifactGenerationState
  scan_state : ArtifactScanState
  review_state : ArtifactReviewState
  submitted_by : String
  creator_receipt : String
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ArtifactGenerationRequest {
  request_id : String
  order_id : String
  organization_id : String
  artifact_id : String
  kind : DocumentArtifactKind
  template_id : String
  template_version : String
  locale : String
  expected_object_ref : String
  input_snapshot_sha256 : String
  requested_by : String
  requested_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OfflineWorkerKind {
  ArtifactDispatcher
  EntitlementDispatcher
} derive(Debug, Eq, ToJson, FromJson)

///| A durable, retry-bounded claim. Re-polling before `retry_after_unix_ms`

///|
/// never creates a second attempt, and a terminal callback completes it.
pub(all) struct OfflineWorkClaim {
  work_id : String
  worker_kind : OfflineWorkerKind
  expected_order_generation : Int64
  attempt : Int
  claimed_unix_ms : Int64
  retry_after_unix_ms : Int64
  completed_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///| Durable worker evidence used by production readiness. Configuration flags

///|
/// cannot synthesize any of these timestamps.
pub(all) struct OfflineWorkerHealth {
  artifact_dispatcher_heartbeat_unix_ms : Int64?
  artifact_dispatcher_success_unix_ms : Int64?
  entitlement_dispatcher_heartbeat_unix_ms : Int64?
  entitlement_dispatcher_success_unix_ms : Int64?
  reconciler_attempt_unix_ms : Int64?
  reconciler_success_unix_ms : Int64?
  reconciler_failure_code : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn empty_offline_worker_health() -> OfflineWorkerHealth {
  {
    artifact_dispatcher_heartbeat_unix_ms: None,
    artifact_dispatcher_success_unix_ms: None,
    entitlement_dispatcher_heartbeat_unix_ms: None,
    entitlement_dispatcher_success_unix_ms: None,
    reconciler_attempt_unix_ms: None,
    reconciler_success_unix_ms: None,
    reconciler_failure_code: None,
  }
}

///|
pub(all) struct OfflineAuthorityWorkBatch {
  activations : Array[EntitlementActivation]
  reversals : Array[CommercialReversal]
  claims : Array[OfflineWorkClaim]
  heartbeat_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ArtifactGenerationResult {
  request_id : String
  artifact_id : String
  expected_object_ref : String
  media_type : String
  byte_count : Int64
  sha256 : String
  worker_receipt : String
  verified : Bool
  active_content_detected : Bool
  moonleaf_verified : Bool
  render_verified : Bool
  formula_error_count : Int
  visual_evidence_sha256 : String
  completed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum UploadGrantState {
  UploadGranted
  UploadCompleted
  UploadExpired
  UploadRejected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceUploadGrant {
  grant_id : String
  idempotency_key : String
  order_id : String
  organization_id : String
  subject_ref : String
  artifact_id : String
  kind : DocumentArtifactKind
  revision : Int
  expected_object_ref : String
  allowed_media_types : Array[String]
  maximum_byte_count : Int64
  expires_unix_ms : Int64
  state : UploadGrantState
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///| Browser-safe projection. Object-store routing, caller identity, and

///|
/// idempotency authority remain management-plane details.
pub(all) struct OfflineUploadGrantView {
  grant_id : String
  order_id : String
  artifact_id : String
  kind : DocumentArtifactKind
  revision : Int
  allowed_media_types : Array[String]
  maximum_byte_count : Int64
  expires_unix_ms : Int64
  state : UploadGrantState
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceUploadCallback {
  callback_id : String
  grant_id : String
  expected_object_ref : String
  media_type : String
  byte_count : Int64
  sha256 : String
  scan_passed : Bool
  active_content_detected : Bool
  scanner_receipt : String
  verified : Bool
  completed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OfflineEvidenceKind {
  ExecutedAgreementEvidence
  PaymentEvidence
  InvoiceEvidence
  InternalApproval
  IdentityVerification
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceReview {
  review_id : String
  order_id : String
  artifact_id : String
  expected_artifact_sha256 : String
  reviewer_ref : String
  accepted : Bool
  reason_code : String
  audit_receipt : String
  reviewed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommercialOrder {
  order_id : String
  idempotency_key : String
  tenant_ref : String
  organization_id : String
  project_id : String
  purchaser_subject_ref : String
  selected_service_code : String
  selected_sla_code : String
  policy : FulfillmentPolicy
  quote : ImmutableQuote?
  agreement_ref : String?
  artifact_ids : Array[String]
  entitlement_ref : String?
  state : OfflineOrderState
  generation : Int64
  created_unix_ms : Int64
  updated_unix_ms : Int64
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OfflineCommerceSnapshot {
  schema_version : String
  templates : Array[DocumentTemplate]
  orders : Array[CommercialOrder]
  artifacts : Array[DocumentArtifact]
  generation_requests : Array[ArtifactGenerationRequest]
  upload_grants : Array[EvidenceUploadGrant]
  upload_callbacks : Array[EvidenceUploadCallback]
  reviews : Array[EvidenceReview]
  entitlement_activations : Array[EntitlementActivation]
  reversals : Array[CommercialReversal]
  reversal_recoveries : Array[ReversalRecovery]
  transfer_sessions : Array[OfflineTransferSession]
  transfer_evidence : Array[OfflineTransferEvidence]
  work_claims : Array[OfflineWorkClaim]
  worker_health : OfflineWorkerHealth
} derive(Debug, Eq, ToJson, FromJson)
