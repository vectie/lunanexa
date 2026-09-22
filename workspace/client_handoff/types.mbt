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
pub extend ClientLaunchConfig with Debug::{to_repr}

///|
pub extend ClientLaunchConfig with Eq::{not_equal, equal}

///|
pub extend ClientLaunchConfig with ToJson::{to_json}

///|
pub extend ClientLaunchConfig with FromJson::{from_json}

///|
/// Subject-scoped intent created by the enterprise portal.
pub(all) struct ClientHandoffIssueIntent {
  request_id : String
  client_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  display_name : String
  allowed_models : Array[String]
  handoff_expires_unix_ms : Int64
  credential_expires_unix_ms : Int64
  maximum_requests : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ClientHandoffIssueIntent with Debug::{to_repr}

///|
pub extend ClientHandoffIssueIntent with Eq::{not_equal, equal}

///|
pub extend ClientHandoffIssueIntent with ToJson::{to_json}

///|
pub extend ClientHandoffIssueIntent with FromJson::{from_json}

///|
/// Persisted one-time handoff. Neither the handoff code nor API secret is stored.
pub(all) struct ClientHandoffRecord {
  delivery_id : String?
  version : String
  handoff_id : String
  request_id : String
  client_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String?
  project_id : String?
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
pub extend ClientHandoffRecord with Debug::{to_repr}

///|
pub extend ClientHandoffRecord with Eq::{not_equal, equal}

///|
pub extend ClientHandoffRecord with ToJson::{to_json}

///|
pub extend ClientHandoffRecord with FromJson::{from_json}

///|
/// Credential created with the handoff and revealed only during redemption.
pub(all) struct ClientCredential {
  delivery_id : String?
  key_id : String
  handoff_id : String
  client_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String?
  project_id : String?
  secret_sha256 : String
  allowed_models : Array[String]
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  maximum_requests : Int64
  consumed_requests : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ClientCredential with Debug::{to_repr}

///|
pub extend ClientCredential with Eq::{not_equal, equal}

///|
pub extend ClientCredential with ToJson::{to_json}

///|
pub extend ClientCredential with FromJson::{from_json}

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
pub extend IssuedClientHandoff with Debug::{to_repr}

///|
pub extend IssuedClientHandoff with Eq::{not_equal, equal}

///|
pub extend IssuedClientHandoff with ToJson::{to_json}

///|
pub extend IssuedClientHandoff with FromJson::{from_json}

///|
/// Secret-bearing response returned exactly once to the local client.
pub(all) struct ClientHandoffRedemption {
  handoff_id : String
  client_id : String
  api_key_id : String
  api_secret : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  allowed_models : Array[String]
  expires_unix_ms : Int64
  maximum_requests : Int64
  one_time : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ClientHandoffRedemption with Debug::{to_repr}

///|
pub extend ClientHandoffRedemption with Eq::{not_equal, equal}

///|
pub extend ClientHandoffRedemption with ToJson::{to_json}

///|
pub extend ClientHandoffRedemption with FromJson::{from_json}

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
pub extend ClientHandoffView with Debug::{to_repr}

///|
pub extend ClientHandoffView with Eq::{not_equal, equal}

///|
pub extend ClientHandoffView with ToJson::{to_json}

///|
pub extend ClientHandoffView with FromJson::{from_json}

///|
pub(all) struct ClientHandoffSnapshot {
  schema_version : String
  handoffs : Array[ClientHandoffRecord]
  credentials : Array[ClientCredential]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ClientHandoffSnapshot with Debug::{to_repr}

///|
pub extend ClientHandoffSnapshot with Eq::{not_equal, equal}

///|
pub extend ClientHandoffSnapshot with ToJson::{to_json}

///|
pub extend ClientHandoffSnapshot with FromJson::{from_json}

///|
pub(all) struct ClientAuthorization {
  key_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ClientAuthorization with Debug::{to_repr}

///|
pub extend ClientAuthorization with Eq::{not_equal, equal}

///|
pub extend ClientAuthorization with ToJson::{to_json}

///|
pub extend ClientAuthorization with FromJson::{from_json}

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

///|
pub extend ClientHandoffError with Debug::{to_repr}

///|
pub extend ClientHandoffError with Eq::{not_equal, equal}
