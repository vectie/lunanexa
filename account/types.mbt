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
pub extend AccountRole with Debug::{to_repr}

///|
pub extend AccountRole with Eq::{not_equal, equal}

///|
pub extend AccountRole with ToJson::{to_json}

///|
pub extend AccountRole with FromJson::{from_json}

///|
pub(all) enum AccountState {
  Invited
  Active
  Suspended
  Revoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccountState with Debug::{to_repr}

///|
pub extend AccountState with Eq::{not_equal, equal}

///|
pub extend AccountState with ToJson::{to_json}

///|
pub extend AccountState with FromJson::{from_json}

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
pub extend HumanAccount with Debug::{to_repr}

///|
pub extend HumanAccount with Eq::{not_equal, equal}

///|
pub extend HumanAccount with ToJson::{to_json}

///|
pub extend HumanAccount with FromJson::{from_json}

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
pub extend BrowserSession with Debug::{to_repr}

///|
pub extend BrowserSession with Eq::{not_equal, equal}

///|
pub extend BrowserSession with ToJson::{to_json}

///|
pub extend BrowserSession with FromJson::{from_json}

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
pub extend AccountInvitation with Debug::{to_repr}

///|
pub extend AccountInvitation with Eq::{not_equal, equal}

///|
pub extend AccountInvitation with ToJson::{to_json}

///|
pub extend AccountInvitation with FromJson::{from_json}

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
pub extend AccountInvitationIntent with Debug::{to_repr}

///|
pub extend AccountInvitationIntent with Eq::{not_equal, equal}

///|
pub extend AccountInvitationIntent with ToJson::{to_json}

///|
pub extend AccountInvitationIntent with FromJson::{from_json}

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
pub extend AccountInvitationView with Debug::{to_repr}

///|
pub extend AccountInvitationView with Eq::{not_equal, equal}

///|
pub extend AccountInvitationView with ToJson::{to_json}

///|
pub extend AccountInvitationView with FromJson::{from_json}

///|
pub(all) struct IssuedAccountInvitation {
  invitation : AccountInvitationView
  secret : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend IssuedAccountInvitation with Debug::{to_repr}

///|
pub extend IssuedAccountInvitation with Eq::{not_equal, equal}

///|
pub extend IssuedAccountInvitation with ToJson::{to_json}

///|
pub extend IssuedAccountInvitation with FromJson::{from_json}

///|
pub(all) struct RegisteredAccount {
  account : AccountView
  invitation : AccountInvitationView
  session : IssuedBrowserSession
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RegisteredAccount with Debug::{to_repr}

///|
pub extend RegisteredAccount with Eq::{not_equal, equal}

///|
pub extend RegisteredAccount with ToJson::{to_json}

///|
pub extend RegisteredAccount with FromJson::{from_json}

///|
pub(all) struct OpenRegisteredAccount {
  account : AccountView
  session : IssuedBrowserSession
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OpenRegisteredAccount with Debug::{to_repr}

///|
pub extend OpenRegisteredAccount with Eq::{not_equal, equal}

///|
pub extend OpenRegisteredAccount with ToJson::{to_json}

///|
pub extend OpenRegisteredAccount with FromJson::{from_json}

///|
/// A free-trial entitlement authorizes only the bounded shared-workspace path.
/// It is not a node lease and cannot be used as machine or operator authority.
pub(all) struct TrialEntitlement {
  trial_id : String
  account_id : String
  organization_id : String
  tenant_ref : String
  project_id : String
  allowed_models : Array[String]
  maximum_requests : Int64
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  api_key_id : String?
  revoked_unix_ms : Int64?
  consumed_requests : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend TrialEntitlement with Debug::{to_repr}

///|
pub extend TrialEntitlement with Eq::{not_equal, equal}

///|
pub extend TrialEntitlement with ToJson::{to_json}

///|
pub extend TrialEntitlement with FromJson::{from_json}

///|
pub(all) struct TrialEntitlementIntent {
  trial_id : String
  account_id : String
  organization_id : String
  tenant_ref : String
  project_id : String
  allowed_models : Array[String]
  maximum_requests : Int64
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend TrialEntitlementIntent with Debug::{to_repr}

///|
pub extend TrialEntitlementIntent with Eq::{not_equal, equal}

///|
pub extend TrialEntitlementIntent with ToJson::{to_json}

///|
pub extend TrialEntitlementIntent with FromJson::{from_json}

///|
pub(all) struct AccountSnapshot {
  schema_version : String
  accounts : Array[HumanAccount]
  sessions : Array[BrowserSession]
  // Optional for backward-compatible restoration of pre-registration state.
  invitations : Array[AccountInvitation]?
  // Optional for backward-compatible restoration of pre-trial state.
  trials : Array[TrialEntitlement]?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccountSnapshot with Debug::{to_repr}

///|
pub extend AccountSnapshot with Eq::{not_equal, equal}

///|
pub extend AccountSnapshot with ToJson::{to_json}

///|
pub extend AccountSnapshot with FromJson::{from_json}

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
pub extend AccountView with Debug::{to_repr}

///|
pub extend AccountView with Eq::{not_equal, equal}

///|
pub extend AccountView with ToJson::{to_json}

///|
pub extend AccountView with FromJson::{from_json}

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
pub extend BrowserSessionView with Debug::{to_repr}

///|
pub extend BrowserSessionView with Eq::{not_equal, equal}

///|
pub extend BrowserSessionView with ToJson::{to_json}

///|
pub extend BrowserSessionView with FromJson::{from_json}

///|
pub(all) struct IssuedBrowserSession {
  session : BrowserSessionView
  secret : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend IssuedBrowserSession with Debug::{to_repr}

///|
pub extend IssuedBrowserSession with Eq::{not_equal, equal}

///|
pub extend IssuedBrowserSession with ToJson::{to_json}

///|
pub extend IssuedBrowserSession with FromJson::{from_json}

///|
pub(all) struct AccountAuthorization {
  session_id : String
  account : AccountView
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccountAuthorization with Debug::{to_repr}

///|
pub extend AccountAuthorization with Eq::{not_equal, equal}

///|
pub extend AccountAuthorization with ToJson::{to_json}

///|
pub extend AccountAuthorization with FromJson::{from_json}

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
pub extend AccountError with Debug::{to_repr}

///|
pub extend AccountError with Eq::{not_equal, equal}

///|
pub fn role_allows(roles : Array[AccountRole], required : AccountRole) -> Bool {
  roles.contains(PlatformOperator) || roles.contains(required)
}
