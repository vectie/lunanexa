///|
pub let contract_version : String = "lunanexa.account.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.account.snapshot.v1"

///|
pub(all) enum AccountRole {
  PlatformOperator
  AuditReader
  EnterpriseUser
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AccountState {
  Invited
  Active
  Suspended
  Revoked
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A human account authenticated by an external identity provider. Passwords,
/// MFA material, provider tokens, and browser-session secrets are never fields.
pub(all) struct HumanAccount {
  version : String
  account_id : String
  subject_ref : String
  identity_issuer : String
  identity_subject_sha256 : String
  display_name : String
  email : String
  identity_receipt : String
  roles : Array[AccountRole]
  state : AccountState
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Durable session record. Only a digest of the bearer secret and source
/// assertion is retained.
pub(all) struct BrowserSession {
  session_id : String
  account_id : String
  secret_sha256 : String
  source_assertion_sha256 : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  last_used_unix_ms : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Operator-issued, one-time enterprise registration capability. Only a hash
/// of the invitation secret is durable; self-registration can never mint an
/// operator or audit role.
pub(all) struct AccountInvitation {
  invitation_id : String
  secret_sha256 : String
  email : String
  organization_id : String
  tenant_ref : String
  project_id : String
  created_by : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  consumed_account_id : String?
  consumed_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AccountInvitationIntent {
  invitation_id : String
  email : String
  organization_id : String
  tenant_ref : String
  project_id : String
  created_by : String
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AccountInvitationView {
  invitation_id : String
  email : String
  organization_id : String
  tenant_ref : String
  project_id : String
  created_by : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  consumed_account_id : String?
  consumed_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IssuedAccountInvitation {
  invitation : AccountInvitationView
  secret : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RegisteredAccount {
  account : AccountView
  invitation : AccountInvitationView
  session : IssuedBrowserSession
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct OpenRegisteredAccount {
  account : AccountView
  session : IssuedBrowserSession
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AccountSnapshot {
  schema_version : String
  accounts : Array[HumanAccount]
  sessions : Array[BrowserSession]
  // Optional for backward-compatible restoration of pre-registration state.
  invitations : Array[AccountInvitation]?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AccountView {
  account_id : String
  subject_ref : String
  identity_issuer : String
  display_name : String
  email : String
  identity_receipt : String
  roles : Array[AccountRole]
  state : AccountState
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BrowserSessionView {
  session_id : String
  account_id : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  last_used_unix_ms : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IssuedBrowserSession {
  session : BrowserSessionView
  secret : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AccountAuthorization {
  session_id : String
  account : AccountView
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror AccountError {
  InvalidInput(String)
  AlreadyExists(String)
  NotFound(String)
  InvalidTransition(String)
  Unauthorized
  AssertionReplayed
  InvalidSnapshot(String)
} derive(Debug, Eq)

///|
pub fn role_allows(roles : Array[AccountRole], required : AccountRole) -> Bool {
  roles.contains(PlatformOperator) || roles.contains(required)
}
