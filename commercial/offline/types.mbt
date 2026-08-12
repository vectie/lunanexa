///|
pub let contract_version : String = "lunanexa.offline-commerce.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.offline-commerce.snapshot.v1"

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
  Fulfilled
  NeedsCorrection
  Rejected
  Cancelled
  Expired
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
} derive(Debug, Eq, ToJson, FromJson)
