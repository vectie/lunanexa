///|
/// Node-reported observation of an explicitly exited runtime incarnation.
/// This is evidence data, not standalone authorization: receivers must verify
/// the node channel and the original assignment/epoch before settling any job.
/// observed_unix_ms is observation time, not an asserted process exit time.
pub(all) struct RuntimeTermination {
  original_assignment : DesiredAssignment?
  assignment_id : String
  deployment_id : String
  generation : Int64
  controller_epoch : Int64
  instance_id : String
  artifact_digest : String
  image_digest : String
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RuntimeTermination with Debug::{to_repr}

///|
pub extend RuntimeTermination with Eq::{not_equal, equal}

///|
pub extend RuntimeTermination with ToJson::{to_json}

///|
pub extend RuntimeTermination with FromJson::{from_json}

///|
/// A bounded, node-authenticated delivery batch. Retries may use a fresh send
/// timestamp while retaining identical evidence records. Acceptance must be
/// durable and idempotent before the controller acknowledges individual records.
pub(all) struct RuntimeTerminationReport {
  node_id : String
  timestamp_unix_ms : Int64
  records : Array[RuntimeTermination]
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RuntimeTerminationReport with Debug::{to_repr}

///|
pub extend RuntimeTerminationReport with Eq::{not_equal, equal}

///|
pub extend RuntimeTerminationReport with ToJson::{to_json}

///|
pub extend RuntimeTerminationReport with FromJson::{from_json}
