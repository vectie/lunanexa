///|
pub let contract_version : String = "lunanexa.client-handoff.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.client-handoff.snapshot.v1"

///|
/// Deployment-owned description of one supported local workspace client.
pub(all) struct ClientLaunchConfig {
  client_id : String
  display_name : String
  launch_uri : String
  public_api_base_url : String
  handoff_lifetime_ms : Int64
  maximum_requests : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Subject-scoped intent created by the enterprise portal.
pub(all) struct ClientHandoffIssueIntent {
  request_id : String
  client_id : String
  tenant_ref : String
  subject_ref : String
  display_name : String
  allowed_models : Array[String]
  handoff_expires_unix_ms : Int64
  credential_expires_unix_ms : Int64
  maximum_requests : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Persisted one-time handoff. Neither the handoff code nor API secret is stored.
pub(all) struct ClientHandoffRecord {
  version : String
  handoff_id : String
  request_id : String
  client_id : String
  tenant_ref : String
  subject_ref : String
  api_key_id : String
  code_sha256 : String
  display_name : String
  allowed_models : Array[String]
  created_unix_ms : Int64
  handoff_expires_unix_ms : Int64
  credential_expires_unix_ms : Int64
  maximum_requests : Int64
  redeemed_unix_ms : Int64?
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Credential created with the handoff and revealed only during redemption.
pub(all) struct ClientCredential {
  key_id : String
  handoff_id : String
  client_id : String
  tenant_ref : String
  subject_ref : String
  secret_sha256 : String
  allowed_models : Array[String]
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  maximum_requests : Int64
  consumed_requests : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Portal response. The code is short-lived and is not a bearer credential.
pub(all) struct IssuedClientHandoff {
  handoff_id : String
  client_id : String
  handoff_code : String
  handoff_expires_unix_ms : Int64
  credential_expires_unix_ms : Int64
  redemption_path : String
  one_time : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Secret-bearing response returned exactly once to the local client.
pub(all) struct ClientHandoffRedemption {
  handoff_id : String
  client_id : String
  api_key_id : String
  api_secret : String
  tenant_ref : String
  subject_ref : String
  allowed_models : Array[String]
  expires_unix_ms : Int64
  maximum_requests : Int64
  one_time : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Secret-free connection status shown to the owning enterprise subject.
pub(all) struct ClientHandoffView {
  handoff_id : String
  request_id : String
  client_id : String
  api_key_id : String
  display_name : String
  allowed_models : Array[String]
  created_unix_ms : Int64
  handoff_expires_unix_ms : Int64
  credential_expires_unix_ms : Int64
  maximum_requests : Int64
  consumed_requests : Int64
  redeemed_unix_ms : Int64?
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientHandoffSnapshot {
  schema_version : String
  handoffs : Array[ClientHandoffRecord]
  credentials : Array[ClientCredential]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClientAuthorization {
  key_id : String
  tenant_ref : String
  subject_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror ClientHandoffError {
  InvalidInput(String)
  InvalidSnapshot(String)
  AlreadyExists(String)
  IdempotencyConflict
  NotFound
  Unauthorized
  ClientMismatch
  AlreadyRedeemed
  Expired
  Revoked
  QuotaExceeded
} derive(Debug, Eq)
