///|
pub(all) struct Owner {
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  order_id : String
} derive(Eq, ToJson, FromJson)

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
/// Internal persistence contract; never serialize this object to a customer.
/// Raw prompts, model credentials and endpoint URLs are deliberately absent.
pub(all) struct StoredJob {
  job_id : String
  owner : Owner
  request_digest : String
  idempotency_digest : String
  model : String
  deployment_id : String
  provider_job_id : String?
  state : State
  progress : Int?
  created_unix_ms : Int64
  updated_unix_ms : Int64
  deadline_unix_ms : Int64
  retain_until_unix_ms : Int64
  expiry_requested : Bool
  execution_terminal : Bool
  usage_receipt : String?
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct Snapshot {
  schema_version : String
  jobs : Array[StoredJob]
} derive(Eq, ToJson, FromJson)

///|
pub let schema_version : String = "lunanexa.media-jobs.v1"

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
  persist : async (Snapshot) -> Unit
  mutex : @async.Mutex
  maximum_jobs : Int
}
