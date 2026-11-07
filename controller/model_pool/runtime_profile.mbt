///|
/// Reviewed runtime data binds exact artifacts to execution options. The
/// controller never chooses a parser or decoding algorithm by model name.
pub(all) struct RuntimeProfile {
  artifact_digests : Array[String]
  architecture : String
  arguments : Array[String]
  speculative : Json?
} derive(Eq, ToJson, FromJson)

///|
pub extend RuntimeProfile with Eq::{equal, not_equal}

///|
pub extend RuntimeProfile with ToJson::{to_json}

///|
pub extend RuntimeProfile with FromJson::{from_json}

///|
fn default_runtime_profile() -> RuntimeProfile {
  { artifact_digests: [], architecture: "", arguments: [], speculative: None, }
}

///|
pub fn Pool::supports_artifact(
  self : Pool,
  digest : String,
  architectures : Array[String],
) -> Bool {
  self.profiles.any(p => {
    p.artifact_digests.contains(digest) &&
    architectures.contains(p.architecture)
  })
}

///|
fn Pool::runtime_profile(
  self : Pool,
  digest : String,
) -> RuntimeProfile raise PoolError {
  guard self.profiles
    .iter()
    .find_first(p => p.artifact_digests.contains(digest))
    is Some(profile) else {
    raise PoolError::InvalidConfiguration
  }
  profile
}
