///|
pub let snapshot_schema_version : String = "lunanexa.access-onboarding.v1"

///|
pub(all) enum AccessOnboardingStep {
  IntentRecorded
  AccountReady
  MembershipReady
  WorkspaceUserReady
  GrantReady
  LeaseReady
  Prepared
  Enabled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessOnboardingStep with Debug::{to_repr}

///|
pub extend AccessOnboardingStep with Eq::{not_equal, equal}

///|
pub extend AccessOnboardingStep with ToJson::{to_json}

///|
pub extend AccessOnboardingStep with FromJson::{from_json}

///|
pub(all) enum AccessOnboardingStatus {
  Running
  RecoverableFailure
  PreparedForEnablement
  Completed
  Conflicted
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessOnboardingStatus with Debug::{to_repr}

///|
pub extend AccessOnboardingStatus with Eq::{not_equal, equal}

///|
pub extend AccessOnboardingStatus with ToJson::{to_json}

///|
pub extend AccessOnboardingStatus with FromJson::{from_json}

///|
pub(all) struct AccessOnboardingIntent {
  operation_id : String
  fingerprint : String
  requested_by : String
  account_id : String
  subject_ref : String
  identity_issuer : String
  identity_subject_sha256 : String
  display_name : String
  email : String
  organization_id : String
  tenant_ref : String
  membership_id : String
  user_id : String
  grant_id : String
  lease_id : String
  identity_receipt : String
  expires_unix_ms : Int64
  /// Missing in older journal snapshots: those remain text-only.
  enterprise_gpu_capabilities : Bool?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessOnboardingIntent with Debug::{to_repr}

///|
pub extend AccessOnboardingIntent with Eq::{not_equal, equal}

///|
pub extend AccessOnboardingIntent with ToJson::{to_json}

///|
pub extend AccessOnboardingIntent with FromJson::{from_json}

///|
pub(all) struct AccessOnboardingRecord {
  intent : AccessOnboardingIntent
  step : AccessOnboardingStep
  status : AccessOnboardingStatus
  attempts : Int
  last_error_code : String?
  last_error_message : String?
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessOnboardingRecord with Debug::{to_repr}

///|
pub extend AccessOnboardingRecord with Eq::{not_equal, equal}

///|
pub extend AccessOnboardingRecord with ToJson::{to_json}

///|
pub extend AccessOnboardingRecord with FromJson::{from_json}

///|
pub(all) struct AccessOnboardingSnapshot {
  schema_version : String
  operations : Array[AccessOnboardingRecord]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessOnboardingSnapshot with Debug::{to_repr}

///|
pub extend AccessOnboardingSnapshot with Eq::{not_equal, equal}

///|
pub extend AccessOnboardingSnapshot with ToJson::{to_json}

///|
pub extend AccessOnboardingSnapshot with FromJson::{from_json}

///|
pub(all) suberror AccessOnboardingError {
  InvalidIntent(String)
  IdempotencyConflict(String)
  OperationNotFound(String)
  InvalidTransition(String)
  InvalidSnapshot(String)
} derive(Debug, Eq)

///|
pub extend AccessOnboardingError with Debug::{to_repr}

///|
pub extend AccessOnboardingError with Eq::{not_equal, equal}
