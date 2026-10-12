///|
pub suberror ReportError {
  InvalidInput(String)
}

///|
pub(all) struct Query {
  now_unix_ms : Int64
  maximum_age_ms : Int64
  deployment_id : String
  model_id : String
  operation_state : String
  node_id : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct DeploymentRow {
  operation_id : String
  deployment_id : String
  generation : Int64
  recorded_operation_state : String
  template_id : String
  template_version : String
  model_id : String?
  model_version : String?
  artifact_digest : String?
  runtime_name : String?
  runtime_version : String?
  runtime_image_digest : String?
  requested_replicas : Int
  planned_replicas : Int
  selected_placements : Int
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Eq, ToJson)

///|
pub(all) struct PlacementRow {
  operation_id : String
  deployment_id : String
  generation : Int64
  replica_id : String
  planned_node_id : String
  planned_device_ids : Array[String]
  node_deployment_membership : String
  observed_node_state : String?
  observed_unix_ms : Int64?
  freshness : String
  age_ms : Int64?
} derive(Eq, ToJson)

///|
pub(all) struct Report {
  schema_version : String
  query : Query
  source_operation_count : Int
  source_node_count : Int
  deployments : Array[DeploymentRow]
  placements : Array[PlacementRow]
} derive(Eq, ToJson)

///|
pub extend Query with Eq::{equal, not_equal}

///|
pub extend Query with ToJson::{to_json}

///|
pub extend Query with FromJson::{from_json}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub extend Report with ToJson::{to_json}

///|
pub extend DeploymentRow with Eq::{equal, not_equal}

///|
pub extend DeploymentRow with ToJson::{to_json}

///|
pub extend PlacementRow with Eq::{equal, not_equal}

///|
pub extend PlacementRow with ToJson::{to_json}
