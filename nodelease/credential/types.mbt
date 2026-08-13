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
pub(all) struct CredentialHandoffSnapshot {
  schema_version : String
  records : Array[CredentialHandoffRecord]
} derive(Debug, Eq, ToJson, FromJson)

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
