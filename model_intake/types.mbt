///|
pub(all) suberror IntakeError {
  InvalidInput(String)
} derive(Debug)

///|
pub(all) struct Columns {
  model_id : String
  version : String
  artifact_digest : String
  artifact_uri : String
  artifact_size_bytes : String
  signature_ref : String
  license_id : String
  provenance : String
  compatible_architectures : String
  minimum_memory_mib : String
} derive(ToJson, FromJson)

///|
pub(all) struct Mapping {
  schema_version : Int
  columns : Columns
} derive(ToJson, FromJson)

///|
pub(all) struct Draft {
  schema_version : Int
  models : Array[@contracts.ModelRecord]
} derive(ToJson, FromJson)

///|
pub(all) struct Difference {
  field : String
  candidate : Json
  registered : Json
} derive(ToJson)

///|
pub(all) struct ReviewRow {
  model_id : String
  version : String
  status : String
  registered_state : @contracts.ModelState?
  differences : Array[Difference]
} derive(ToJson)

///|
pub(all) struct Review {
  schema_version : Int
  new_count : Int
  already_registered_count : Int
  conflict_count : Int
  rows : Array[ReviewRow]
} derive(ToJson)

///|
pub extend IntakeError with Debug::{to_repr}

///|
pub extend Mapping with ToJson::{to_json}

///|
pub extend Mapping with FromJson::{from_json}

///|
pub extend Columns with ToJson::{to_json}

///|
pub extend Columns with FromJson::{from_json}

///|
pub extend Draft with ToJson::{to_json}

///|
pub extend Draft with FromJson::{from_json}

///|
pub extend Review with ToJson::{to_json}

///|
pub extend ReviewRow with ToJson::{to_json}

///|
pub extend Difference with ToJson::{to_json}
