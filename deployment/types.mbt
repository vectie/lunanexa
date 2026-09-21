///|
pub(all) struct TemplateRef {
  template_id : String
  version : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RolloutPolicy {
  canary_replicas : Int
  automatic_promotion : Bool
  automatic_rollback : Bool
  readiness_timeout_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ModelServiceTemplate {
  template_id : String
  version : String
  display_name : String
  description : String
  model_selector : String
  model_id : String
  model_version : String
  artifact : @contracts.ArtifactRef
  runtime : @contracts.RuntimeSpec
  capability : @contracts.Capability
  architecture : String
  resources : @contracts.ResourceLimits
  network : @contracts.NetworkPolicy
  health : @contracts.HealthPolicy
  data_policy : @contracts.DataPolicy
  secret_refs : Array[String]
  rollout : RolloutPolicy
  approval_receipt : String
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ModelServiceIntent {
  version : String
  idempotency_key : String
  deployment_id : String
  template : TemplateRef
  replicas : Int
  data_class : @contracts.DataClass
  lease_duration_ms : Int64
  promote_when_ready : Bool
  /// The geometry this deployment asks for. `None` is one machine; the only
  /// other value LunaNexa admits is the validated CX7 pair, because that is the
  /// one multi-node shape whose membership rule is verifiable.
  topology_profile : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RegistryEvidence {
  model_id : String
  model_version : String
  model_state : @contracts.ModelState
  artifact_digest : String
  runtime_name : String
  runtime_version : String
  runtime_image_digest : String
  model_selector : String
  license_accepted : Bool
  artifact_verified : Bool
  runtime_verified : Bool
  evaluation_passed : Bool
  alias_points_to_model : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ManagementNode {
  node_id : String
  state : @contracts.NodeState
  architecture : String
  memory_free_mib : Int
  runtime_names : Array[String]
  device_ids : Array[String]
  allowed_data_classes : Array[@contracts.DataClass]
  /// The CX7 peer this node names, or "" when it claims none. Planning reads it
  /// from the same inventory label placement does, so a pair that placement
  /// would refuse cannot be planned either.
  cx7_peer : String
  /// This node's own address on the private fabric, or "" when undeclared. A
  /// pair needs both ends addressed, because rank coordination happens over
  /// that link and not over the management network.
  cx7_address : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlanningContext {
  registry : Array[RegistryEvidence]
  nodes : Array[ManagementNode]
  available_secret_refs : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum FindingSeverity {
  Blocking
  Warning
  Information
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum FindingCode {
  InvalidIntent
  TemplateNotFound
  TemplateNotApproved
  ModelNotApproved
  RuntimeNotRegistered
  ArtifactNotVerified
  ArtifactMaterializationUnsupported
  RuntimeNotVerified
  LicenseNotAccepted
  EvaluationNotPassed
  AliasNotApproved
  MissingSecretReference
  NoCompatibleNode
  InsufficientCapacity
  AutomaticPromotionDenied
  /// The runtime needs two machines but the intent did not name the admitted
  /// topology.
  GeometryNotDeclared
  /// A paired placement was asked for from a runtime that does not declare it.
  RuntimeCannotPair
  /// The pair was asked for but no two compatible nodes name each other, or one
  /// end declared no fabric address.
  NoCx7Pair
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PreflightFinding {
  code : FindingCode
  severity : FindingSeverity
  message : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PlannedReplica {
  replica_id : String
  node_id : String
  devices : Array[String]
  /// Present only when this replica is one member of a paired placement, in
  /// which case the group carries its rank and its peer's fabric address.
  group : @contracts.AssignmentGroup?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ServiceEndpoint {
  canonical_path : String
  model_selector : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeploymentPlan {
  plan_id : String
  intent : ModelServiceIntent
  template : ModelServiceTemplate?
  replicas : Array[PlannedReplica]
  findings : Array[PreflightFinding]
  executable : Bool
  endpoint : ServiceEndpoint?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum DeploymentOperationState {
  Submitted
  Blocked
  Planned
  Reconciling
  Ready
  Degraded
  RollingBack
  RolledBack
  Failed
  Deleted
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeploymentOperation {
  operation_id : String
  deployment_id : String
  generation : Int64
  state : DeploymentOperationState
  plan : DeploymentPlan
  assignment_ids : Array[String]
  endpoint : ServiceEndpoint?
  message : String
  audit_receipt : String
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeploymentSnapshot {
  schema_version : String
  templates : Array[ModelServiceTemplate]
  operations : Array[DeploymentOperation]
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror DeploymentError {
  InvalidTemplate(String)
  InvalidIntent(String)
  InvalidState(String)
  IdempotencyConflict(String)
  NotFound(String)
} derive(Debug, Eq)
