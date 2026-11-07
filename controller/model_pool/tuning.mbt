///|
/// Omitted fields preserve the pinned runtime's defaults, including old journals.
pub(all) struct Tuning {
  prefix_caching : Bool?
  cache_aware_routing : Bool
  chunked_prefill : Bool?
  max_num_batched_tokens : Int32
} derive(Eq, ToJson, FromJson)

///|
pub extend Tuning with Eq::{equal, not_equal}

///|
pub extend Tuning with ToJson::{to_json}

///|
pub extend Tuning with FromJson::{from_json}

///|
pub fn default_tuning() -> Tuning {
  {
    prefix_caching: None,
    cache_aware_routing: false,
    chunked_prefill: None,
    max_num_batched_tokens: 0,
  }
}

///|
pub fn Pool::tuning(self : Pool) -> Tuning {
  self.journal.tuning.unwrap_or_else(default_tuning)
}

///|
pub async fn Pool::set_tuning(self : Pool, tuning : Tuning) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if ![0, 512, 1024, 2048, 4096, 8192, 16384].contains(
      tuning.max_num_batched_tokens,
    ) ||
    (tuning.cache_aware_routing && tuning.prefix_caching != Some(true)) ||
    (tuning.max_num_batched_tokens > 0 && tuning.chunked_prefill != Some(true)) ||
    tuning.chunked_prefill == Some(false) {
    raise PoolError::InvalidConfiguration
  }
  if !self.adopted() || self.selection() is None {
    raise PoolError::NotAdopted
  }
  if self.tuning() != tuning {
    self.save({
      ..self.journal,
      tuning: Some(tuning),
      generation: self.journal.generation + 1L,
    })
  }
}

///|
fn append_tuning_args(args : Array[String], tuning : Tuning) -> Unit {
  if tuning.prefix_caching is Some(enabled) {
    args.push(
      if enabled {
        "--enable-prefix-caching"
      } else {
        "--no-enable-prefix-caching"
      },
    )
  }
  if tuning.chunked_prefill == Some(true) {
    args.push("--enable-chunked-prefill")
  }
  if tuning.max_num_batched_tokens > 0 {
    args.push("--max-num-batched-tokens")
    args.push(tuning.max_num_batched_tokens.to_string())
  }
}
