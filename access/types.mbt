///|
pub let snapshot_schema_version : String = "lunanexa.access.snapshot.v1"

///|
pub(all) enum ApiKeyScope {
  ModelList
  Inference
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ApiKeyIssueIntent {
  key_id : String
  tenant_ref : String
  subject_ref : String
  display_name : String
  scopes : Array[ApiKeyScope]
  allowed_models : Array[String]
  expires_unix_ms : Int64
  maximum_requests : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ApiCredential {
  key_id : String
  tenant_ref : String
  subject_ref : String
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
pub(all) struct IssuedApiKey {
  credential : ApiCredential
  secret : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AccessSnapshot {
  schema_version : String
  credentials : Array[ApiCredential]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ApiAuthorization {
  key_id : String
  tenant_ref : String
  subject_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ApiCredentialView {
  key_id : String
  tenant_ref : String
  subject_ref : String
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
pub(all) suberror AccessError {
  InvalidInput(String)
  AlreadyExists(String)
  NotFound(String)
  Unauthorized
  QuotaExceeded
  InvalidSnapshot(String)
} derive(Debug, Eq)
