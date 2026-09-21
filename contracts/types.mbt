///|
pub let contract_version : String = "lunanexa.v1"

///|
/// A model artifact travels either from an upstream object store or from
/// LunaNexa's own ModelScope-verified model store. The store form names a
/// revision directory; every file in it is listed by the revision manifest
/// below, and that manifest — not a detached signature — is the artifact.
pub let model_store_scheme : String = "modelstore://"

///|
pub let model_store_manifest_name : String = "lunanexa-source-manifest.json"

///|
pub let source_manifest_schema_version : String = "lunanexa.modelsource.verified.v1"

///|
/// The only multi-node geometry LunaNexa admits: exactly two nodes joined by a
/// verified CX7 link. It is a *pair*, not a node count, so there is no profile
/// that would admit three or more, and "any two nodes" cannot be expressed.
pub let cx7_pair_topology_profile : String = "cx7-pair-v1"

///|
pub let cx7_pair_member_count : Int = 2

///|
/// The inventory label through which a node names its CX7 peer. A pair is
/// mutual by construction: a one-way claim is not a pair, and a peer that is
/// absent or unschedulable silently takes the pair out of service rather than
/// placing half of a tensor-parallel group.
pub let cx7_peer_label : String = "lunanexa.io/cx7-peer"

///|
/// The address a node is reachable at on the private fabric, which is what a
/// peer needs for rank coordination. Declared by the operator alongside the
/// peer, because which interface carries the link is a host fact the platform
/// cannot infer.
pub let cx7_address_label : String = "lunanexa.io/cx7-address"

///|
/// Whether a multi-node request names a geometry this platform admits. The
/// one admitted profile is the CX7 pair, and it must also be listed as
/// validated by policy.
pub fn cx7_pair_profile_valid(
  profile : String?,
  validated_profiles : Array[String],
) -> Bool {
  match profile {
    Some(name) =>
      name == cx7_pair_topology_profile &&
      validated_profiles.any(value => value == name)
    None => false
  }
}

///|
/// The pair among `names`, where each entry is a node id and the peer it
/// names. Returns exactly two ids ordered with the head first, or an empty
/// array when no two schedulable nodes name each other.
///
/// Deterministic: the lexicographically first admissible pair wins, so the same
/// inventory always yields the same answer. This is the single implementation
/// of the rule -- placement and planning both call it, so neither can drift
/// into admitting an unlinked pair or a third member.
pub fn cx7_pair_members(names : Array[(String, String)]) -> Array[String] {
  let ordered = names.copy()
  ordered.sort_by((left, right) => left.0.compare(right.0))
  for node in ordered {
    if node.1 == "" {
      continue
    }
    for peer in ordered {
      if peer.0 == node.1 && peer.1 == node.0 {
        if node.0.compare(peer.0) < 0 {
          return [node.0, peer.0]
        }
        return [peer.0, node.0]
      }
    }
  }
  []
}

///|
pub(all) enum Capability {
  TextGenerate
  EmbeddingCreate
  ImageGenerate
  VideoGenerate
  AudioGenerate
  ModelEvaluate
  ModelTrain
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Capability with Debug::{to_repr}

///|
pub extend Capability with Eq::{not_equal, equal}

///|
pub extend Capability with ToJson::{to_json}

///|
pub extend Capability with FromJson::{from_json}

///|
pub(all) enum DataClass {
  Public
  Internal
  Confidential
  Restricted
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DataClass with Debug::{to_repr}

///|
pub extend DataClass with Eq::{not_equal, equal}

///|
pub extend DataClass with ToJson::{to_json}

///|
pub extend DataClass with FromJson::{from_json}

///|
pub(all) enum RetentionPolicy {
  Ephemeral
  RetainUntil(Int64)
  EvaluationCapture(consent_receipt~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RetentionPolicy with Debug::{to_repr}

///|
pub extend RetentionPolicy with Eq::{not_equal, equal}

///|
pub extend RetentionPolicy with ToJson::{to_json}

///|
pub extend RetentionPolicy with FromJson::{from_json}

///|
pub(all) enum Priority {
  Background
  Normal
  Interactive
  Critical
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Priority with Debug::{to_repr}

///|
pub extend Priority with Eq::{not_equal, equal}

///|
pub extend Priority with ToJson::{to_json}

///|
pub extend Priority with FromJson::{from_json}

///|
pub(all) enum LatencyClass {
  Batch
  Standard
  Realtime
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LatencyClass with Debug::{to_repr}

///|
pub extend LatencyClass with Eq::{not_equal, equal}

///|
pub extend LatencyClass with ToJson::{to_json}

///|
pub extend LatencyClass with FromJson::{from_json}

///|
pub(all) struct ResourceCeiling {
  /// Northbound admission safety ceiling measured as UTF-8 bytes of the
  /// canonical `payload` JSON. Runtime-reported provider units remain separate
  /// usage evidence and cannot weaken this byte ceiling.
  max_input_units : Int
  max_output_units : Int
  max_runtime_ms : Int64
  max_accelerator_memory_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ResourceCeiling with Debug::{to_repr}

///|
pub extend ResourceCeiling with Eq::{not_equal, equal}

///|
pub extend ResourceCeiling with ToJson::{to_json}

///|
pub extend ResourceCeiling with FromJson::{from_json}

///|
pub(all) struct DataPolicy {
  classification : DataClass
  retention : RetentionPolicy
  allow_cache : Bool
  allow_training_reuse : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DataPolicy with Debug::{to_repr}

///|
pub extend DataPolicy with Eq::{not_equal, equal}

///|
pub extend DataPolicy with ToJson::{to_json}

///|
pub extend DataPolicy with FromJson::{from_json}

///|
pub(all) struct WorkloadEnvelope {
  version : String
  idempotency_key : String
  workload_id : String
  tenant_ref : String
  credential_scope : String
  capability : Capability
  model_selector : String
  payload : Json
  data_policy : DataPolicy
  deadline_unix_ms : Int64
  priority : Priority
  latency_class : LatencyClass
  resource_ceiling : ResourceCeiling
  stream : Bool
  output_format : String
  trace_token : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkloadEnvelope with Debug::{to_repr}

///|
pub extend WorkloadEnvelope with Eq::{not_equal, equal}

///|
pub extend WorkloadEnvelope with ToJson::{to_json}

///|
pub extend WorkloadEnvelope with FromJson::{from_json}

///|
pub(all) enum WorkloadState {
  Submitted
  Admitted
  Queued
  Running
  Streaming
  Succeeded
  Failed
  Cancelled
  Rejected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkloadState with Debug::{to_repr}

///|
pub extend WorkloadState with Eq::{not_equal, equal}

///|
pub extend WorkloadState with ToJson::{to_json}

///|
pub extend WorkloadState with FromJson::{from_json}

///|
pub(all) enum ErrorCode {
  InvalidRequest
  Unauthenticated
  Unauthorized
  QuotaExceeded
  DeadlineExceeded
  NoPlacement
  RuntimeUnavailable
  CancelledByCaller
  Internal
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ErrorCode with Debug::{to_repr}

///|
pub extend ErrorCode with Eq::{not_equal, equal}

///|
pub extend ErrorCode with ToJson::{to_json}

///|
pub extend ErrorCode with FromJson::{from_json}

///|
pub(all) struct PublicError {
  code : ErrorCode
  message : String
  retryable : Bool
  correlation_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PublicError with Debug::{to_repr}

///|
pub extend PublicError with Eq::{not_equal, equal}

///|
pub extend PublicError with ToJson::{to_json}

///|
pub extend PublicError with FromJson::{from_json}

///|
pub(all) struct Usage {
  input_units : Int
  output_units : Int
  accelerator_ms : Int64
  queue_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Usage with Debug::{to_repr}

///|
pub extend Usage with Eq::{not_equal, equal}

///|
pub extend Usage with ToJson::{to_json}

///|
pub extend Usage with FromJson::{from_json}

///|
pub(all) struct Timing {
  accepted_unix_ms : Int64
  started_unix_ms : Int64
  first_output_unix_ms : Int64
  completed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Timing with Debug::{to_repr}

///|
pub extend Timing with Eq::{not_equal, equal}

///|
pub extend Timing with ToJson::{to_json}

///|
pub extend Timing with FromJson::{from_json}

///|
pub(all) struct WorkloadResponse {
  version : String
  workload_id : String
  state : WorkloadState
  output : Json?
  error : PublicError?
  usage : Usage
  artifact_digest : String
  runtime_version : String
  // Optional so receipts written before node-level metering remain readable.
  // New runtime results always bind the receipt to the execution target.
  execution_node_id : String?
  timing : Timing
  retryable : Bool
  audit_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkloadResponse with Debug::{to_repr}

///|
pub extend WorkloadResponse with Eq::{not_equal, equal}

///|
pub extend WorkloadResponse with ToJson::{to_json}

///|
pub extend WorkloadResponse with FromJson::{from_json}

///|
pub(all) enum StreamEventKind {
  Chunk
  Completed
  Failed
  Cancelled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend StreamEventKind with Debug::{to_repr}

///|
pub extend StreamEventKind with Eq::{not_equal, equal}

///|
pub extend StreamEventKind with ToJson::{to_json}

///|
pub extend StreamEventKind with FromJson::{from_json}

///|
pub(all) struct WorkloadStreamEvent {
  workload_id : String
  sequence : Int
  kind : StreamEventKind
  output : Json?
  response : WorkloadResponse?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend WorkloadStreamEvent with Debug::{to_repr}

///|
pub extend WorkloadStreamEvent with Eq::{not_equal, equal}

///|
pub extend WorkloadStreamEvent with ToJson::{to_json}

///|
pub extend WorkloadStreamEvent with FromJson::{from_json}

///|
pub(all) enum ModelState {
  Candidate
  Verified
  Evaluated
  Approved
  Deprecated
  Revoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelState with Debug::{to_repr}

///|
pub extend ModelState with Eq::{not_equal, equal}

///|
pub extend ModelState with ToJson::{to_json}

///|
pub extend ModelState with FromJson::{from_json}

///|
pub(all) enum DeploymentState {
  Pending
  Preparing
  Starting
  Ready
  Draining
  Stopped
  Degraded
  Failed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DeploymentState with Debug::{to_repr}

///|
pub extend DeploymentState with Eq::{not_equal, equal}

///|
pub extend DeploymentState with ToJson::{to_json}

///|
pub extend DeploymentState with FromJson::{from_json}

///|
pub(all) enum NodeState {
  Enrolling
  Active
  Cordoned
  Draining
  Unreachable
  Retired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NodeState with Debug::{to_repr}

///|
pub extend NodeState with Eq::{not_equal, equal}

///|
pub extend NodeState with ToJson::{to_json}

///|
pub extend NodeState with FromJson::{from_json}

///|
pub(all) struct ArtifactRef {
  digest : String
  uri : String
  size_bytes : Int64
  signature_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ArtifactRef with Debug::{to_repr}

///|
pub extend ArtifactRef with Eq::{not_equal, equal}

///|
pub extend ArtifactRef with ToJson::{to_json}

///|
pub extend ArtifactRef with FromJson::{from_json}

///|
pub(all) struct RuntimeSpec {
  name : String
  image_digest : String
  version : String
  architectures : Array[String]
  capabilities : Array[Capability]
  supports_batching : Bool
  supports_multi_node : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RuntimeSpec with Debug::{to_repr}

///|
pub extend RuntimeSpec with Eq::{not_equal, equal}

///|
pub extend RuntimeSpec with ToJson::{to_json}

///|
pub extend RuntimeSpec with FromJson::{from_json}

///|
pub(all) struct ModelRecord {
  model_id : String
  version : String
  artifact : ArtifactRef
  license_id : String
  provenance : String
  compatible_architectures : Array[String]
  minimum_memory_mib : Int
  state : ModelState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelRecord with Debug::{to_repr}

///|
pub extend ModelRecord with Eq::{not_equal, equal}

///|
pub extend ModelRecord with ToJson::{to_json}

///|
pub extend ModelRecord with FromJson::{from_json}

///|
pub(all) struct ResourceLimits {
  accelerator_count : Int
  accelerator_memory_mib : Int
  cpu_millis : Int
  memory_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ResourceLimits with Debug::{to_repr}

///|
pub extend ResourceLimits with Eq::{not_equal, equal}

///|
pub extend ResourceLimits with ToJson::{to_json}

///|
pub extend ResourceLimits with FromJson::{from_json}

///|
pub(all) struct NetworkPolicy {
  allow_controller : Bool
  allow_artifact_store : Bool
  allowed_egress : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NetworkPolicy with Debug::{to_repr}

///|
pub extend NetworkPolicy with Eq::{not_equal, equal}

///|
pub extend NetworkPolicy with ToJson::{to_json}

///|
pub extend NetworkPolicy with FromJson::{from_json}

///|
pub(all) struct HealthPolicy {
  readiness_path : String
  interval_ms : Int
  failure_threshold : Int
  termination_grace_ms : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend HealthPolicy with Debug::{to_repr}

///|
pub extend HealthPolicy with Eq::{not_equal, equal}

///|
pub extend HealthPolicy with ToJson::{to_json}

///|
pub extend HealthPolicy with FromJson::{from_json}

///|
/// One member of a paired placement. The four values are all-or-nothing: a
/// rank is meaningless without the group it belongs to and the size of that
/// group, so they travel together or not at all.
pub(all) struct AssignmentGroup {
  group_id : String
  /// 0 is the head: the member that serves traffic and exports the peer's
  /// model store when the pair shares one copy of the weights.
  rank : Int
  /// The number of members in the group. Only two is admitted.
  world_size : Int
  /// The peer's address on the private fabric, for rank coordination.
  peer_endpoint : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AssignmentGroup with Debug::{to_repr}

///|
pub extend AssignmentGroup with Eq::{not_equal, equal}

///|
pub extend AssignmentGroup with ToJson::{to_json}

///|
pub extend AssignmentGroup with FromJson::{from_json}

///|
pub(all) struct DesiredAssignment {
  assignment_id : String
  deployment_id : String
  node_id : String
  artifact : ArtifactRef
  runtime : RuntimeSpec
  resources : ResourceLimits
  devices : Array[String]
  network : NetworkPolicy
  health : HealthPolicy
  data_policy : DataPolicy
  generation : Int64
  lease_expires_unix_ms : Int64
  controller_epoch : Int64
  /// Present only when this assignment is one member of a paired placement.
  /// Absent -- which is what every document written before pairs existed
  /// carries -- means one machine, and leaves the MAC material untouched.
  group : AssignmentGroup?
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DesiredAssignment with Debug::{to_repr}

///|
pub extend DesiredAssignment with Eq::{not_equal, equal}

///|
pub extend DesiredAssignment with ToJson::{to_json}

///|
pub extend DesiredAssignment with FromJson::{from_json}

///|
pub(all) struct AcceleratorInventory {
  device_id : String
  architecture : String
  memory_total_mib : Int
  memory_free_mib : Int
  healthy : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AcceleratorInventory with Debug::{to_repr}

///|
pub extend AcceleratorInventory with Eq::{not_equal, equal}

///|
pub extend AcceleratorInventory with ToJson::{to_json}

///|
pub extend AcceleratorInventory with FromJson::{from_json}

///|
pub(all) struct NodeInventory {
  node_id : String
  agent_version : String
  os_release : String
  runtime_names : Array[String]
  accelerators : Array[AcceleratorInventory]
  labels : Map[String, String]
  taints : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NodeInventory with Debug::{to_repr}

///|
pub extend NodeInventory with Eq::{not_equal, equal}

///|
pub extend NodeInventory with ToJson::{to_json}

///|
pub extend NodeInventory with FromJson::{from_json}

///|
pub(all) struct NodeHeartbeat {
  node_id : String
  state : NodeState
  observed_generation : Int64
  controller_epoch : Int64
  inventory : NodeInventory
  running_deployments : Array[String]
  runtime_endpoints : Array[RuntimeEndpoint]?
  timestamp_unix_ms : Int64
  signature : String
} derive(Debug, Eq, FromJson)

///|
pub extend NodeHeartbeat with Debug::{to_repr}

///|
pub extend NodeHeartbeat with Eq::{not_equal, equal}

///|
pub extend NodeHeartbeat with FromJson::{from_json}

///|
pub(all) struct NodeDirective {
  node_id : String
  desired_state : NodeState
  generation : Int64
  issued_unix_ms : Int64
  receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NodeDirective with Debug::{to_repr}

///|
pub extend NodeDirective with Eq::{not_equal, equal}

///|
pub extend NodeDirective with ToJson::{to_json}

///|
pub extend NodeDirective with FromJson::{from_json}

///|
pub(all) struct TelemetrySample {
  node_id : String
  deployment_id : String
  metric : String
  value : Double
  timestamp_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend TelemetrySample with Debug::{to_repr}

///|
pub extend TelemetrySample with Eq::{not_equal, equal}

///|
pub extend TelemetrySample with ToJson::{to_json}

///|
pub extend TelemetrySample with FromJson::{from_json}

///|
pub(all) struct RegistryLicenseSummary {
  license_id : String
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RegistryLicenseSummary with Debug::{to_repr}

///|
pub extend RegistryLicenseSummary with Eq::{not_equal, equal}

///|
pub extend RegistryLicenseSummary with ToJson::{to_json}

///|
pub extend RegistryLicenseSummary with FromJson::{from_json}

///|
pub(all) struct RegistryEvaluationSummary {
  model_id : String
  model_version : String
  passed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RegistryEvaluationSummary with Debug::{to_repr}

///|
pub extend RegistryEvaluationSummary with Eq::{not_equal, equal}

///|
pub extend RegistryEvaluationSummary with ToJson::{to_json}

///|
pub extend RegistryEvaluationSummary with FromJson::{from_json}

///|
pub(all) struct RegistryAliasSummary {
  name : String
  model_id : String
  version : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RegistryAliasSummary with Debug::{to_repr}

///|
pub extend RegistryAliasSummary with Eq::{not_equal, equal}

///|
pub extend RegistryAliasSummary with ToJson::{to_json}

///|
pub extend RegistryAliasSummary with FromJson::{from_json}

///|
pub(all) struct RegistryReadContract {
  models : Array[ModelRecord]
  licenses : Array[RegistryLicenseSummary]
  evaluations : Array[RegistryEvaluationSummary]
  aliases : Array[RegistryAliasSummary]
  runtimes : Array[RuntimeSpec]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RegistryReadContract with Debug::{to_repr}

///|
pub extend RegistryReadContract with Eq::{not_equal, equal}

///|
pub extend RegistryReadContract with ToJson::{to_json}

///|
pub extend RegistryReadContract with FromJson::{from_json}

///|
pub(all) struct SchedulerReadContract {
  quotas : Array[Json]
  active : Array[Json]
  queued_count : Int?
  running_count : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend SchedulerReadContract with Debug::{to_repr}

///|
pub extend SchedulerReadContract with Eq::{not_equal, equal}

///|
pub extend SchedulerReadContract with ToJson::{to_json}

///|
pub extend SchedulerReadContract with FromJson::{from_json}

///|
pub(all) struct BenchmarkReadSummary {
  run_id : String
  profile : String
  latency_p95_ms : Int
  throughput_units_per_second : Int
  failure_per_mille : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend BenchmarkReadSummary with Debug::{to_repr}

///|
pub extend BenchmarkReadSummary with Eq::{not_equal, equal}

///|
pub extend BenchmarkReadSummary with ToJson::{to_json}

///|
pub extend BenchmarkReadSummary with FromJson::{from_json}

///|
pub(all) struct TelemetryReadContract {
  benchmark_summaries : Array[BenchmarkReadSummary]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend TelemetryReadContract with Debug::{to_repr}

///|
pub extend TelemetryReadContract with Eq::{not_equal, equal}

///|
pub extend TelemetryReadContract with ToJson::{to_json}

///|
pub extend TelemetryReadContract with FromJson::{from_json}

///|
pub(all) struct AuditEvent {
  sequence : Int64
  event_id : String
  timestamp_unix_ms : Int64
  actor : String
  policy_version : String
  action : String
  target : String
  prior_state : String
  next_state : String
  result : String
  correlation_receipt : String
  previous_hash : String
  event_hash : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AuditEvent with Debug::{to_repr}

///|
pub extend AuditEvent with Eq::{not_equal, equal}

///|
pub extend AuditEvent with ToJson::{to_json}

///|
pub extend AuditEvent with FromJson::{from_json}

///|
pub(all) struct HealthResponse {
  product : String
  component : String
  version : String
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend HealthResponse with Debug::{to_repr}

///|
pub extend HealthResponse with Eq::{not_equal, equal}

///|
pub extend HealthResponse with ToJson::{to_json}

///|
pub extend HealthResponse with FromJson::{from_json}
