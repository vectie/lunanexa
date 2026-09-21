///|
pub let snapshot_schema_version : String = "lunanexa.access.snapshot.v1"

///|
pub(all) enum ApiKeyScope {
  ModelList
  Inference
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ApiKeyScope with Debug::{to_repr}

///|
pub extend ApiKeyScope with Eq::{not_equal, equal}

///|
pub extend ApiKeyScope with ToJson::{to_json}

///|
pub extend ApiKeyScope with FromJson::{from_json}

///|
pub(all) struct ApiKeyIssueIntent {
  key_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  display_name : String
  scopes : Array[ApiKeyScope]
  allowed_models : Array[String]
  expires_unix_ms : Int64
  maximum_requests : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ApiKeyIssueIntent with Debug::{to_repr}

///|
pub extend ApiKeyIssueIntent with Eq::{not_equal, equal}

///|
pub extend ApiKeyIssueIntent with ToJson::{to_json}

///|
pub extend ApiKeyIssueIntent with FromJson::{from_json}

///|
pub(all) struct ApiCredential {
  key_id : String
  tenant_ref : String
  subject_ref : String
  // Optional only so pre-attribution snapshots remain readable. Credentials
  // without both values are never authorized and must be reissued.
  organization_id : String?
  project_id : String?
  display_name : String
  secret_sha256 : String
  scopes : Array[ApiKeyScope]
  allowed_models : Array[String]
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  maximum_requests : Int64
  consumed_requests : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ApiCredential with Debug::{to_repr}

///|
pub extend ApiCredential with Eq::{not_equal, equal}

///|
pub extend ApiCredential with ToJson::{to_json}

///|
pub extend ApiCredential with FromJson::{from_json}

///|
pub(all) struct IssuedApiKey {
  credential : ApiCredential
  secret : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend IssuedApiKey with Debug::{to_repr}

///|
pub extend IssuedApiKey with Eq::{not_equal, equal}

///|
pub extend IssuedApiKey with ToJson::{to_json}

///|
pub extend IssuedApiKey with FromJson::{from_json}

///|
pub(all) struct AccessSnapshot {
  schema_version : String
  credentials : Array[ApiCredential]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessSnapshot with Debug::{to_repr}

///|
pub extend AccessSnapshot with Eq::{not_equal, equal}

///|
pub extend AccessSnapshot with ToJson::{to_json}

///|
pub extend AccessSnapshot with FromJson::{from_json}

///|
pub(all) struct ApiAuthorization {
  key_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ApiAuthorization with Debug::{to_repr}

///|
pub extend ApiAuthorization with Eq::{not_equal, equal}

///|
pub extend ApiAuthorization with ToJson::{to_json}

///|
pub extend ApiAuthorization with FromJson::{from_json}

///|
pub(all) struct ApiCredentialView {
  key_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String?
  project_id : String?
  display_name : String
  scopes : Array[ApiKeyScope]
  allowed_models : Array[String]
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  maximum_requests : Int64
  consumed_requests : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ApiCredentialView with Debug::{to_repr}

///|
pub extend ApiCredentialView with Eq::{not_equal, equal}

///|
pub extend ApiCredentialView with ToJson::{to_json}

///|
pub extend ApiCredentialView with FromJson::{from_json}

///|
/// One-time issuance response safe for an API or browser. The durable secret
/// digest is deliberately excluded; callers receive only the public metadata
/// plus the one-time raw secret.
pub(all) struct IssuedApiKeyView {
  credential : ApiCredentialView
  secret : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend IssuedApiKeyView with Debug::{to_repr}

///|
pub extend IssuedApiKeyView with Eq::{not_equal, equal}

///|
pub extend IssuedApiKeyView with ToJson::{to_json}

///|
pub extend IssuedApiKeyView with FromJson::{from_json}

///|
pub(all) suberror AccessError {
  InvalidInput(String)
  AlreadyExists(String)
  NotFound(String)
  Unauthorized
  QuotaExceeded
  InvalidSnapshot(String)
} derive(Debug, Eq)

///|
pub extend AccessError with Debug::{to_repr}

///|
pub extend AccessError with Eq::{not_equal, equal}
