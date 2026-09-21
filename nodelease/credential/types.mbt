///|
pub let contract_version : String = "lunanexa.machine-credential-handoff.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.machine-credential-handoff.snapshot.v1"

///|
pub let issuer_readiness_contract_version : String = "lunanexa.machine-credential-issuer-readiness.v1"

///|
/// Retained evidence from a deployment-owned credential issuer health check.
/// The controller does not infer issuer readiness from its local handoff store.
pub(all) struct CredentialIssuerReadinessEvidence {
  version : String
  adapter_id : String
  health_endpoint : String
  evidence_ref : String
  checked_unix_ms : Int64
  expires_unix_ms : Int64
  healthy : Bool
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialIssuerReadinessEvidence with Debug::{to_repr}

///|
pub extend CredentialIssuerReadinessEvidence with Eq::{not_equal, equal}

///|
pub extend CredentialIssuerReadinessEvidence with ToJson::{to_json}

///|
pub extend CredentialIssuerReadinessEvidence with FromJson::{from_json}

///|
pub(all) struct CredentialHandoffIssueIntent {
  request_id : String
  lease_id : String
  expected_generation : Int64
  host_alias : String
  ssh_port : Int
  host_key_fingerprint : String
  issuer_redirect_url : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialHandoffIssueIntent with Debug::{to_repr}

///|
pub extend CredentialHandoffIssueIntent with Eq::{not_equal, equal}

///|
pub extend CredentialHandoffIssueIntent with ToJson::{to_json}

///|
pub extend CredentialHandoffIssueIntent with FromJson::{from_json}

///|
/// Operator intent before an external credential issuer has created its
/// browser ceremony. Node and human subject are derived from the active lease.
pub(all) struct CredentialIssuerRequestIntent {
  request_id : String
  lease_id : String
  expected_generation : Int64
  host_alias : String
  ssh_port : Int
  host_key_fingerprint : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialIssuerRequestIntent with Debug::{to_repr}

///|
pub extend CredentialIssuerRequestIntent with Eq::{not_equal, equal}

///|
pub extend CredentialIssuerRequestIntent with ToJson::{to_json}

///|
pub extend CredentialIssuerRequestIntent with FromJson::{from_json}

///|
/// Durable minimal-disclosure issuer outbox record.
pub(all) struct CredentialIssuerRequest {
  request_id : String
  lease_id : String
  expected_generation : Int64
  username : String
  host_alias : String
  ssh_port : Int
  host_key_fingerprint : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  issuer_redirect_url : String?
  dispatched_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialIssuerRequest with Debug::{to_repr}

///|
pub extend CredentialIssuerRequest with Eq::{not_equal, equal}

///|
pub extend CredentialIssuerRequest with ToJson::{to_json}

///|
pub extend CredentialIssuerRequest with FromJson::{from_json}

///|
/// Machine adapter receipt. It acknowledges ceremony creation only; it does
/// not contain an SSH key, certificate, password, or node identity.
pub(all) struct CredentialIssuerDispatchReceipt {
  request_id : String
  issuer_redirect_url : String
  accepted_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialIssuerDispatchReceipt with Debug::{to_repr}

///|
pub extend CredentialIssuerDispatchReceipt with Eq::{not_equal, equal}

///|
pub extend CredentialIssuerDispatchReceipt with ToJson::{to_json}

///|
pub extend CredentialIssuerDispatchReceipt with FromJson::{from_json}

///|
pub(all) struct CredentialHandoffRecord {
  version : String
  handoff_ref : String
  request_id : String
  lease_id : String
  node_id : String
  subject_ref : String
  generation : Int64
  username : String
  host_alias : String
  ssh_port : Int
  host_key_fingerprint : String
  issuer_redirect_url : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  redeemed_unix_ms : Int64?
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialHandoffRecord with Debug::{to_repr}

///|
pub extend CredentialHandoffRecord with Eq::{not_equal, equal}

///|
pub extend CredentialHandoffRecord with ToJson::{to_json}

///|
pub extend CredentialHandoffRecord with FromJson::{from_json}

///|
pub(all) struct CustomerCredentialHandoffView {
  handoff_ref : String
  lease_ref : String
  generation : Int64
  username : String
  host_alias : String
  ssh_port : Int
  host_key_fingerprint : String
  connection_command : String
  valid_until_unix_ms : Int64
  can_redeem : Bool
  can_recover : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CustomerCredentialHandoffView with Debug::{to_repr}

///|
pub extend CustomerCredentialHandoffView with Eq::{not_equal, equal}

///|
pub extend CustomerCredentialHandoffView with ToJson::{to_json}

///|
pub extend CustomerCredentialHandoffView with FromJson::{from_json}

///|
pub(all) struct CredentialHandoffRedemption {
  version : String
  handoff_ref : String
  lease_ref : String
  generation : Int64
  issuer_redirect_url : String
  host_alias : String
  ssh_port : Int
  host_key_fingerprint : String
  connection_command : String
  valid_until_unix_ms : Int64
  redemption_receipt : String
  one_time : Bool
  raw_secret_included : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialHandoffRedemption with Debug::{to_repr}

///|
pub extend CredentialHandoffRedemption with Eq::{not_equal, equal}

///|
pub extend CredentialHandoffRedemption with ToJson::{to_json}

///|
pub extend CredentialHandoffRedemption with FromJson::{from_json}

///|
pub(all) struct CredentialHandoffSnapshot {
  schema_version : String
  records : Array[CredentialHandoffRecord]
  issuer_requests : Array[CredentialIssuerRequest]?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CredentialHandoffSnapshot with Debug::{to_repr}

///|
pub extend CredentialHandoffSnapshot with Eq::{not_equal, equal}

///|
pub extend CredentialHandoffSnapshot with ToJson::{to_json}

///|
pub extend CredentialHandoffSnapshot with FromJson::{from_json}

///|
pub(all) suberror CredentialHandoffError {
  InvalidInput(String)
  InvalidSnapshot(String)
  NotFound
  Unauthorized
  AlreadyRedeemed
  Expired
  Revoked
  StaleGeneration
  IdempotencyConflict
} derive(Debug, Eq)

///|
pub extend CredentialHandoffError with Debug::{to_repr}

///|
pub extend CredentialHandoffError with Eq::{not_equal, equal}
