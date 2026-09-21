///|
pub let contract_version : String = "lunanexa.workspace.v1"

///|
/// The on-disk workspace authority schema. This version is separate from the
/// public workspace contract so persistence migrations remain explicit.
pub let directory_schema_version : String = "lunanexa.workspace.directory.v1"

///|
/// Lifecycle of an opaque identity-provider subject known to LunaNexa.
pub(all) enum WorkspaceUserState {
  UserInvited
  UserActive
  UserSuspended
  UserRevoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceUserState with Debug::{to_repr}

///|
pub extend WorkspaceUserState with Eq::{not_equal, equal}

///|
pub extend WorkspaceUserState with ToJson::{to_json}

///|
pub extend WorkspaceUserState with FromJson::{from_json}

///|
/// Provider-neutral identity metadata used by workspace policy.
///
/// This record never contains an authentication credential, source checkout,
/// editor state, or managed-node identifier.
pub(all) struct WorkspaceUser {
  version : String
  user_id : String
  subject_ref : String
  display_name : String
  email : String
  state : WorkspaceUserState
  created_unix_ms : Int64
  last_active_unix_ms : Int64?
  identity_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceUser with Debug::{to_repr}

///|
pub extend WorkspaceUser with Eq::{not_equal, equal}

///|
pub extend WorkspaceUser with ToJson::{to_json}

///|
pub extend WorkspaceUser with FromJson::{from_json}

///|
/// An access level within the user-facing workspace control plane.
pub(all) enum WorkspaceAccess {
  Administrator
  Developer
  Observer
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceAccess with Debug::{to_repr}

///|
pub extend WorkspaceAccess with Eq::{not_equal, equal}

///|
pub extend WorkspaceAccess with ToJson::{to_json}

///|
pub extend WorkspaceAccess with FromJson::{from_json}

///|
pub(all) enum WorkspaceAccessGrantState {
  GrantActive
  GrantExpired
  GrantRevoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceAccessGrantState with Debug::{to_repr}

///|
pub extend WorkspaceAccessGrantState with Eq::{not_equal, equal}

///|
pub extend WorkspaceAccessGrantState with ToJson::{to_json}

///|
pub extend WorkspaceAccessGrantState with FromJson::{from_json}

///|
/// A time-bounded role assignment for one user and opaque tenant scope.
pub(all) struct WorkspaceAccessGrant {
  version : String
  grant_id : String
  user_id : String
  tenant_ref : String
  access : WorkspaceAccess
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  state : WorkspaceAccessGrantState
  policy_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceAccessGrant with Debug::{to_repr}

///|
pub extend WorkspaceAccessGrant with Eq::{not_equal, equal}

///|
pub extend WorkspaceAccessGrant with ToJson::{to_json}

///|
pub extend WorkspaceAccessGrant with FromJson::{from_json}

///|
/// Generic inference capabilities available through a workspace lease.
///
/// This intentionally excludes repository, shell, credential, and agent-runtime
/// capabilities. Those concerns must remain outside managed GPU nodes.
pub(all) enum WorkspaceCapability {
  TextGenerate
  EmbeddingCreate
  ImageGenerate
  VideoGenerate
  AudioGenerate
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceCapability with Debug::{to_repr}

///|
pub extend WorkspaceCapability with Eq::{not_equal, equal}

///|
pub extend WorkspaceCapability with ToJson::{to_json}

///|
pub extend WorkspaceCapability with FromJson::{from_json}

///|
pub(all) struct CapabilityLimit {
  capability : WorkspaceCapability
  max_concurrent_requests : Int
  max_requests_per_hour : Int
  /// Northbound admission safety limit measured as UTF-8 bytes of canonical
  /// workload payload JSON, matching ResourceCeiling.max_input_units.
  max_input_units_per_request : Int
  max_output_units_per_request : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CapabilityLimit with Debug::{to_repr}

///|
pub extend CapabilityLimit with Eq::{not_equal, equal}

///|
pub extend CapabilityLimit with ToJson::{to_json}

///|
pub extend CapabilityLimit with FromJson::{from_json}

///|
pub(all) struct WorkspaceLimits {
  /// Maximum simultaneously connected server-side editor/workbench sessions.
  /// The current browser-local workbench does not create these sessions;
  /// inference concurrency is governed independently by capability limits.
  max_active_sessions : Int
  /// Maximum lifetime of one server-side WorkspaceSession. This does not bound
  /// inference request duration, which is carried by the workload envelope.
  max_session_duration_ms : Int64
  capabilities : Array[CapabilityLimit]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceLimits with Debug::{to_repr}

///|
pub extend WorkspaceLimits with Eq::{not_equal, equal}

///|
pub extend WorkspaceLimits with ToJson::{to_json}

///|
pub extend WorkspaceLimits with FromJson::{from_json}

///|
pub(all) enum WorkspaceLeaseState {
  Requested
  Active
  Suspended
  Expired
  Revoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceLeaseState with Debug::{to_repr}

///|
pub extend WorkspaceLeaseState with Eq::{not_equal, equal}

///|
pub extend WorkspaceLeaseState with ToJson::{to_json}

///|
pub extend WorkspaceLeaseState with FromJson::{from_json}

///|
/// A control-plane capacity entitlement for generic inference access.
///
/// A lease never identifies a managed node and never authorizes repository
/// checkout, arbitrary shell access, application credentials, or IDE agents.
pub(all) struct WorkspaceLease {
  version : String
  lease_id : String
  tenant_ref : String
  subject_ref : String
  access : WorkspaceAccess
  limits : WorkspaceLimits
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  state : WorkspaceLeaseState
  policy_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceLease with Debug::{to_repr}

///|
pub extend WorkspaceLease with Eq::{not_equal, equal}

///|
pub extend WorkspaceLease with ToJson::{to_json}

///|
pub extend WorkspaceLease with FromJson::{from_json}

///|
pub(all) enum EditorConnectionKind {
  WebIde
  VSCode
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend EditorConnectionKind with Debug::{to_repr}

///|
pub extend EditorConnectionKind with Eq::{not_equal, equal}

///|
pub extend EditorConnectionKind with ToJson::{to_json}

///|
pub extend EditorConnectionKind with FromJson::{from_json}

///|
/// An external editor or assistant integration. This is routing metadata only;
/// credentials are deployment-owned references and do not belong in sessions.
pub(all) enum IntegrationProvider {
  CodeBuddy
  WorkBuddy
  Trae
  Qoder
  Generic
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend IntegrationProvider with Debug::{to_repr}

///|
pub extend IntegrationProvider with Eq::{not_equal, equal}

///|
pub extend IntegrationProvider with ToJson::{to_json}

///|
pub extend IntegrationProvider with FromJson::{from_json}

///|
pub(all) enum ConnectionState {
  Pending
  Connecting
  Connected
  Disconnected
  Failed
  Revoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ConnectionState with Debug::{to_repr}

///|
pub extend ConnectionState with Eq::{not_equal, equal}

///|
pub extend ConnectionState with ToJson::{to_json}

///|
pub extend ConnectionState with FromJson::{from_json}

///|
/// A connection to a user-facing workspace hosted outside the managed-node
/// plane. It carries opaque control-plane references, never endpoint secrets.
pub(all) struct WorkspaceSession {
  version : String
  session_id : String
  lease_id : String
  subject_ref : String
  editor : EditorConnectionKind
  integration : IntegrationProvider?
  connection : ConnectionState
  created_unix_ms : Int64
  expires_unix_ms : Int64
  correlation_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceSession with Debug::{to_repr}

///|
pub extend WorkspaceSession with Eq::{not_equal, equal}

///|
pub extend WorkspaceSession with ToJson::{to_json}

///|
pub extend WorkspaceSession with FromJson::{from_json}

///|
/// Durable, topology-free workspace authority state.
pub(all) struct WorkspaceDirectorySnapshot {
  schema_version : String
  users : Array[WorkspaceUser]
  access_grants : Array[WorkspaceAccessGrant]
  leases : Array[WorkspaceLease]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceDirectorySnapshot with Debug::{to_repr}

///|
pub extend WorkspaceDirectorySnapshot with Eq::{not_equal, equal}

///|
pub extend WorkspaceDirectorySnapshot with ToJson::{to_json}

///|
pub extend WorkspaceDirectorySnapshot with FromJson::{from_json}

///|
/// Why an individual workbench can or cannot submit a new workload.
pub(all) enum WorkspaceReadiness {
  WorkspaceReady
  UserUnavailable
  AccessUnavailable
  LeaseUnavailable
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceReadiness with Debug::{to_repr}

///|
pub extend WorkspaceReadiness with Eq::{not_equal, equal}

///|
pub extend WorkspaceReadiness with ToJson::{to_json}

///|
pub extend WorkspaceReadiness with FromJson::{from_json}

///|
/// The subject-scoped read contract used by an individual workbench.
///
/// Historical revoked and expired records remain visible in the arrays. The
/// selected `active_lease` is present only when `authorized` is true.
pub(all) struct WorkspaceSelfContract {
  version : String
  subject_ref : String
  user : WorkspaceUser
  access_grants : Array[WorkspaceAccessGrant]
  leases : Array[WorkspaceLease]
  active_lease : WorkspaceLease?
  authorized : Bool
  readiness : WorkspaceReadiness
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceSelfContract with Debug::{to_repr}

///|
pub extend WorkspaceSelfContract with Eq::{not_equal, equal}

///|
pub extend WorkspaceSelfContract with ToJson::{to_json}

///|
pub extend WorkspaceSelfContract with FromJson::{from_json}

///|
/// Evidence selected by a successful workspace authorization decision.
pub(all) struct WorkspaceAuthorization {
  subject_ref : String
  user_id : String
  access_grant : WorkspaceAccessGrant
  lease : WorkspaceLease
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkspaceAuthorization with Debug::{to_repr}

///|
pub extend WorkspaceAuthorization with Eq::{not_equal, equal}

///|
pub extend WorkspaceAuthorization with ToJson::{to_json}

///|
pub extend WorkspaceAuthorization with FromJson::{from_json}
