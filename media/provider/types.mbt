///|
/// Admission evidence must supply these limits; this is not hardware qualification.
pub(all) struct Profile {
  model : String
  provider_model : String
  widths : Array[Int]
  heights : Array[Int]
  maximum_frames : Int
  maximum_fps : Int
  maximum_steps : Int
  sound_supported : Bool
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
  progress : Int?
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
  timeout_ms : Int
}
