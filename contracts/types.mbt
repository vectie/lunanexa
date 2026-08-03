///|
pub let contract_version : String = "lunanexa.v1"

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
pub(all) enum DataClass {
  Public
  Internal
  Confidential
  Restricted
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum RetentionPolicy {
  Ephemeral
  RetainUntil(Int64)
  EvaluationCapture(consent_receipt~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum Priority {
  Background
  Normal
  Interactive
  Critical
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum LatencyClass {
  Batch
  Standard
  Realtime
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ResourceCeiling {
  max_input_units : Int
  max_output_units : Int
  max_runtime_ms : Int64
  max_accelerator_memory_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DataPolicy {
  classification : DataClass
  retention : RetentionPolicy
  allow_cache : Bool
  allow_training_reuse : Bool
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct PublicError {
  code : ErrorCode
  message : String
  retryable : Bool
  correlation_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Usage {
  input_units : Int
  output_units : Int
  accelerator_ms : Int64
  queue_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Timing {
  accepted_unix_ms : Int64
  started_unix_ms : Int64
  first_output_unix_ms : Int64
  completed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

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
  timing : Timing
  retryable : Bool
  audit_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum StreamEventKind {
  Chunk
  Completed
  Failed
  Cancelled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkloadStreamEvent {
  workload_id : String
  sequence : Int
  kind : StreamEventKind
  output : Json?
  response : WorkloadResponse?
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) enum NodeState {
  Enrolling
  Active
  Cordoned
  Draining
  Unreachable
  Retired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ArtifactRef {
  digest : String
  uri : String
  size_bytes : Int64
  signature_ref : String
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct ResourceLimits {
  accelerator_count : Int
  accelerator_memory_mib : Int
  cpu_millis : Int
  memory_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NetworkPolicy {
  allow_controller : Bool
  allow_artifact_store : Bool
  allowed_egress : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct HealthPolicy {
  readiness_path : String
  interval_ms : Int
  failure_threshold : Int
  termination_grace_ms : Int
} derive(Debug, Eq, ToJson, FromJson)

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
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AcceleratorInventory {
  device_id : String
  architecture : String
  memory_total_mib : Int
  memory_free_mib : Int
  healthy : Bool
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct NodeHeartbeat {
  node_id : String
  state : NodeState
  observed_generation : Int64
  controller_epoch : Int64
  inventory : NodeInventory
  running_deployments : Array[String]
  timestamp_unix_ms : Int64
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NodeDirective {
  node_id : String
  desired_state : NodeState
  generation : Int64
  issued_unix_ms : Int64
  receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TelemetrySample {
  node_id : String
  deployment_id : String
  metric : String
  value : Double
  timestamp_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RegistryLicenseSummary {
  license_id : String
  status : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RegistryEvaluationSummary {
  model_id : String
  model_version : String
  passed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RegistryAliasSummary {
  name : String
  model_id : String
  version : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RegistryReadContract {
  models : Array[ModelRecord]
  licenses : Array[RegistryLicenseSummary]
  evaluations : Array[RegistryEvaluationSummary]
  aliases : Array[RegistryAliasSummary]
  runtimes : Array[RuntimeSpec]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SchedulerReadContract {
  quotas : Array[Json]
  active : Array[Json]
  queued_count : Int?
  running_count : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct BenchmarkReadSummary {
  run_id : String
  profile : String
  latency_p95_ms : Int
  throughput_units_per_second : Int
  failure_per_mille : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TelemetryReadContract {
  benchmark_summaries : Array[BenchmarkReadSummary]
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct HealthResponse {
  product : String
  component : String
  version : String
  status : String
} derive(Debug, Eq, ToJson, FromJson)
