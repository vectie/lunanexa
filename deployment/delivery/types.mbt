///|
pub(all) enum DeliveryKind {
  GpuContainer
  ModelApi
  Workspace
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum Stage {
  Reserving
  PreparingModel
  LoadingModel
  StartingWorkspace
  Ready
  Failed
  Stopping
  Stopped
  Expired
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Controller-approved intent, not an untrusted browser request. Template and
/// authorization resolution happen before creation; node selection happens later.
pub(all) struct Intent {
  tenant_id : String
  organization_id : String
  project_id : String
  authorization_ref : String
  lease_id : String
  idempotency_key : String
  kind : DeliveryKind
  template_id : String
  template_version : String
  model_digest : String?
  node_count : Int
  expires_at_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ModelReplica {
  assignment_id : String
  node_id : String
  generation : Int64
  prepared : Bool
  ready : Bool
  stopped : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelReplica with Debug::{to_repr}

///|
pub extend ModelReplica with Eq::{equal, not_equal}

///|
pub extend ModelReplica with ToJson::{to_json}

///|
pub extend ModelReplica with @json.FromJson::{from_json}

///|
pub(all) struct Operation {
  operation_id : String
  intent : Intent
  generation : Int64
  stage : Stage
  resume_stage : Stage
  reservation_id : String?
  node_ids : Array[String]
  cache_hit : Bool
  transferred_bytes : Int64
  total_bytes : Int64?
  model_service_id : String?
  model_assignment_generation : Int64?
  model_replicas : Array[ModelReplica]?
  workspace_id : String?
  failure_code : String?
  stop_requested_at_ms : Int64?
  updated_at_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// These observations are internal adapter results. A runtime being Running is
/// deliberately insufficient: readiness requires the model-specific adapter's
/// response (text inference, or loaded media health plus exact model identity).
/// Successful generated media remains a separate end-to-end acceptance check.
pub(all) enum Observation {
  Reserved(reservation_id~ : String, node_ids~ : Array[String])
  TransferProgress(transferred_bytes~ : Int64, total_bytes~ : Int64?)
  ModelPrepared(digest~ : String, cache_hit~ : Bool)
  ModelResponded(service_id~ : String, digest~ : String)
  ModelAssignmentPublished(generation~ : Int64)
  ModelReplicaObserved(ModelReplica)
  WorkspaceResponded(workspace_id~ : String)
  WorkspaceStarting(workspace_id~ : String)
  WorkspaceStopped
  ContainerResponded(instance_id~ : String)
  WorkloadsStopped
  Failure(code~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror DeliveryError {
  InvalidIntent
  IdempotencyConflict
  NotFound
  StaleGeneration
  UnexpectedObservation
  AuthorizationExpired
  InvalidSnapshot
} derive(Debug, Eq)

///|
pub extend DeliveryError with Debug::{to_repr}

///|
struct Snapshot {
  schema_version : String
  operations : Array[Operation]
  model_services : Array[ModelService]?
} derive(ToJson, FromJson)

///|
/// Physical model lifecycle is independent of the delivery that first created
/// it. Members retain their own workspace, credentials and stop state.
pub(all) struct ModelService {
  runtime : Operation
  consumer_ids : Array[String]
} derive(Eq, ToJson, FromJson)

///|
pub extend ModelService with Eq::{equal, not_equal}

///|
pub extend ModelService with ToJson::{to_json}

///|
pub extend ModelService with @json.FromJson::{from_json}

///|
pub extend DeliveryKind with Debug::{to_repr}

///|
pub extend DeliveryKind with Eq::{equal, not_equal}

///|
pub extend DeliveryKind with ToJson::{to_json}

///|
pub extend DeliveryKind with @json.FromJson::{from_json}

///|
pub extend Stage with Debug::{to_repr}

///|
pub extend Stage with Eq::{equal, not_equal}

///|
pub extend Stage with ToJson::{to_json}

///|
pub extend Stage with @json.FromJson::{from_json}

///|
pub extend Intent with Debug::{to_repr}

///|
pub extend Intent with Eq::{equal, not_equal}

///|
pub extend Intent with ToJson::{to_json}

///|
pub extend Intent with @json.FromJson::{from_json}

///|
pub extend Operation with Debug::{to_repr}

///|
pub extend Operation with Eq::{equal, not_equal}

///|
pub extend Operation with ToJson::{to_json}

///|
pub extend Operation with @json.FromJson::{from_json}

///|
pub extend Observation with Debug::{to_repr}

///|
pub extend Observation with Eq::{equal, not_equal}

///|
pub extend Observation with ToJson::{to_json}

///|
pub extend Observation with @json.FromJson::{from_json}

///|
pub extend DeliveryError with Eq::{equal, not_equal}

///|
pub extend Snapshot with ToJson::{to_json}

///|
pub extend Snapshot with @json.FromJson::{from_json}
