///|
/// Admission evidence must supply these limits; this is not hardware qualification.
pub(all) struct Profile {
  model : String
  provider_model : String
  widths : Array[Int32]
  heights : Array[Int32]
  maximum_frames : Int32
  maximum_fps : Int32
  maximum_steps : Int32
  sound_supported : Bool
  image_reference_supported : Bool?
  image_reference_required : Bool?
} derive(Eq, ToJson, FromJson)

///|
pub extend Profile with Eq::{not_equal, equal}

///|
pub extend Profile with ToJson::{to_json}

///|
pub extend Profile with FromJson::{from_json}

///|
/// Prompt-bearing values intentionally have no Debug or automatic serialization.
pub struct VideoRequest {
  model : String
  fields : Map[String, String]
}

///|
pub(all) struct Observation {
  id : String
  state : @jobs.State
  progress : Int32?
} derive(Debug, Eq)

///|
pub extend Observation with Debug::{to_repr}

///|
pub extend Observation with Eq::{not_equal, equal}

///|
pub(all) suberror ProviderError {
  InvalidConfiguration
  InvalidRequest
  Unavailable
  InvalidResponse
  ContentUnavailable
} derive(Debug, Eq)

///|
pub extend ProviderError with Debug::{to_repr}

///|
pub extend ProviderError with Eq::{not_equal, equal}

///|
/// Construct only from approved deployment configuration, never a caller URL.
pub struct Provider {
  origin : String
  bearer : String?
  profile : Profile
  timeout_ms : Int32
}
