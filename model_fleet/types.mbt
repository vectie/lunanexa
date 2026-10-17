///|
pub suberror CompatibilityError {
  InvalidInput(String)
}

///|
pub(all) struct Query {
  schema_version : String
  now_unix_ms : Int64
  maximum_age_ms : Int64
  memory_reserve_mib : Int
  model_id : String
  version : String
  node_id : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct Row {
  model_id : String
  version : String
  artifact_digest : String
  recorded_model_state : @contracts.ModelState
  declared_architectures : Array[String]
  declared_minimum_memory_mib : Int
  required_with_reserve_mib : Int64
  node_id : String
  recorded_node_state : String
  observed_unix_ms : Int64
  freshness : String
  device_id : String?
  device_architecture : String?
  recorded_device_healthy : Bool?
  observed_total_mib : Int?
  observed_free_mib : Int?
  memory_margin_mib : Int64?
  architecture_matches : Bool?
  memory_matches : Bool?
  declaration_comparison : String
  cautions : Array[String]
} derive(Eq, ToJson)

///|
pub extend Query with Eq::{not_equal, equal}

///|
pub extend Query with ToJson::{to_json}

///|
pub extend Query with FromJson::{from_json}

///|
pub extend Row with Eq::{not_equal, equal}

///|
pub extend Row with ToJson::{to_json}

///|
pub extend ModelSummary with Eq::{not_equal, equal}

///|
pub extend ModelSummary with ToJson::{to_json}

///|
pub extend Report with Eq::{not_equal, equal}

///|
pub extend Report with ToJson::{to_json}

///|
pub(all) struct ModelSummary {
  model_id : String
  version : String
  compared_devices : Int
  devices_matching_declarations : Int
  nodes_without_devices : Int
} derive(Eq, ToJson)

///|
pub(all) struct Report {
  schema_version : String
  scope : String
  query : Query
  source_model_count : Int
  source_node_count : Int
  selected_model_count : Int
  selected_node_count : Int
  unassessed : Array[String]
  models : Array[ModelSummary]
  rows : Array[Row]
} derive(Eq, ToJson)
