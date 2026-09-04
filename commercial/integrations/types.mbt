///|
pub let integration_schema_version : String = "lunanexa.commercial.integration.v1"

///|
pub(all) suberror IntegrationError {
  InvalidInput(String)
  NotFound(String)
  AlreadyExists(String)
  TenantMismatch
  IdempotencyConflict(String)
  InvalidTransition(String)
  EvidenceMismatch(String)
  UnverifiedCallback
} derive(Debug, Eq)

///|
pub(all) enum ReconciliationResult {
  Applied
  Replayed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ExternalRecordKind {
  IdentityVerification
  Payment
  /// Explicit outbound reversal of a settled payment. Keeping this distinct
  /// prevents a refund request from being interpreted as another charge.
  PaymentRefund
  TaxInvoice
  QualifiedSignature
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ExternalRecordState {
  Pending
  Submitted
  Verified
  Authorized
  Settled
  Issued
  Failed
  Expired
  Voided
  Credited
  Refunded
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExternalRecord {
  record_id : String
  organization_id : String
  kind : ExternalRecordKind
  provider : String
  environment : String
  external_ref : String
  state : ExternalRecordState
  expected_amount_minor : Int64?
  currency : String?
  money_scale : Int?
  expected_document_hash : String?
  entitlement_transaction_ref : String?
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExternalCallback {
  callback_id : String
  record_id : String
  organization_id : String
  provider : String
  environment : String
  external_ref : String
  expected_previous_state : ExternalRecordState
  next_state : ExternalRecordState
  amount_minor : Int64?
  currency : String?
  document_hash : String?
  provider_event_unix_ms : Int64
  received_unix_ms : Int64
  signature_verified : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ExternalRecordView {
  record_id : String
  organization_id : String
  kind : ExternalRecordKind
  provider : String
  environment : String
  external_ref_sha256 : String
  state : ExternalRecordState
  expected_amount_minor : Int64?
  currency : String?
  money_scale : Int?
  expected_document_hash : String?
  entitlement_transaction_ref_sha256 : String?
  action_url : String?
  action_expires_unix_ms : Int64?
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Minimal machine-only intent claimed by the configured provider adapter.
/// Tenant and human identity are deliberately absent.
pub(all) struct ExternalProviderIntent {
  record_id : String
  kind : ExternalRecordKind
  provider : String
  environment : String
  external_ref : String
  expected_amount_minor : Int64?
  currency : String?
  money_scale : Int?
  expected_document_hash : String?
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Adapter acknowledgement of a browser action. It cannot settle payment or
/// execute a signature; only the independently signed provider callback can.
pub(all) struct ExternalDispatchReceipt {
  record_id : String
  provider : String
  environment : String
  external_ref : String
  action_url : String
  action_expires_unix_ms : Int64
  accepted_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IntegrationSnapshot {
  schema_version : String
  organization_id : String
  records : Array[ExternalRecordView]
  reconciliation_exception_count : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IntegrationDurableSnapshot {
  schema_version : String
  records : Array[ExternalRecord]
  callbacks : Array[ExternalCallback]
  dispatch_receipts : Array[ExternalDispatchReceipt]?
  /// Retired browser-action receipts retained for audit and replay rejection.
  dispatch_receipt_history : Array[ExternalDispatchReceipt]?
  reconciliation_exception_counts : Map[String, Int]
} derive(Debug, Eq, ToJson, FromJson)
