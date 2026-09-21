///|
pub(all) struct Owner {
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  authority : Authority
} derive(Eq)

///|
pub(all) enum Authority {
  DedicatedOrder(String)
  PrivateWorkspace(String)
} derive(Debug, Eq)

///|
pub(all) enum State {
  Intent
  Submitting
  SubmissionUnknown
  Queued
  Running
  Completed
  Failed
  Cancelling
  Cancelled
  Expired
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Durable placement facts for authorization and settlement, not a network
/// route. Provider URLs and credentials still require current discovery.
pub(all) struct ExecutionContext {
  deployment_id : String
  generation : Int64
  node_id : String
  // None for legacy/static bindings; never infer it from a replacement.
  instance_id : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Internal persistence contract; never serialize this object to a customer.
/// Raw prompts, model credentials and endpoint URLs are deliberately absent.
pub(all) struct StoredJob {
  job_id : String
  owner : Owner
  request_digest : String
  idempotency_digest : String
  model : String
  deployment_id : String
  execution_context : ExecutionContext?
  provider_job_id : String?
  state : State
  progress : Int?
  created_unix_ms : Int64
  updated_unix_ms : Int64
  deadline_unix_ms : Int64
  retain_until_unix_ms : Int64
  expiry_requested : Bool
  execution_terminal : Bool
  terminal_unix_ms : Int64?
  usage_receipt : String?
  termination_evidence_ref : String?
  termination_observed_unix_ms : Int64?
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct Snapshot {
  schema_version : String
  jobs : Array[StoredJob]
  terminations : Array[AcceptedTermination]?
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct AcceptedTermination {
  node_id : String
  evidence : @contracts.RuntimeTermination
} derive(Eq, ToJson, FromJson)

///|
pub let schema_version : String = "lunanexa.media-jobs.v2"

///|
pub(all) suberror JobError {
  InvalidInput
  InvalidSnapshot
  NotFound
  Conflict
  Busy
  InvalidTransition
  CapacityExceeded
} derive(Debug, Eq)

///|
pub struct JobStore {
  mut jobs : Map[String, StoredJob]
  mut terminations : Array[AcceptedTermination]
  persist : async (Snapshot) -> Unit
  mutex : @async.Mutex
  maximum_jobs : Int
}
