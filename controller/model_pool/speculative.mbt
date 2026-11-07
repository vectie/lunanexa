///|
pub fn Pool::speculative_tokens(self : Pool) -> Int32 {
  self.journal.speculative_tokens.unwrap_or(0)
}

///|
pub fn Pool::runtime_image(self : Pool) -> String {
  self.runtime_image
}

///|
/// Persist intent before touching replicas. Repeating the same intent retries a
/// partially applied update; disabling keeps the selected A3B model and route.
pub async fn Pool::set_speculative_tokens(self : Pool, tokens : Int32) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if tokens < 0 || tokens > 5 {
    raise PoolError::InvalidConfiguration
  }
  if !self.adopted() || self.selection() is None {
    raise PoolError::NotAdopted
  }
  if tokens > 0 &&
    self.runtime_profile(self.selection().unwrap().artifact.digest).speculative
    is None {
    raise PoolError::InvalidConfiguration
  }
  if self.speculative_tokens() != tokens {
    self.save({
      ..self.journal,
      speculative_tokens: Some(tokens),
      generation: self.journal.generation + 1L,
    })
  }
}

///|
pub(all) struct ReplicaConfiguration {
  speculative_tokens : Int32
  ready : Bool
} derive(Eq, ToJson)

///|
pub extend ReplicaConfiguration with Eq::{equal, not_equal}

///|
pub extend ReplicaConfiguration with ToJson::{to_json}

///|
fn observed_speculative_tokens(args : Array[String]) -> Int32 {
  let positions : Array[Int32] = []
  for i, arg in args {
    if arg == "--speculative-config" {
      positions.push(i)
    }
  }
  if positions.is_empty() {
    return 0
  }
  if positions.length() != 1 {
    return -1
  }
  guard args.get(positions[0] + 1) is Some(raw) else { return -1 }
  let value = @json.parse(raw) catch { _ => return -1 }
  if value
    is { "method": String(_), "num_speculative_tokens": Number(n, ..), .. } &&
    n >= 1.0 &&
    n <= 5.0 &&
    n == n.round() {
    n.to_int()
  } else {
    -1
  }
}

///|
fn configuration_observation(
  value : Json,
  selection : Selection,
  tokens : Int32,
  image : String,
  tuning~ : Tuning = default_tuning(),
  profile~ : RuntimeProfile = default_runtime_profile(),
) -> ReplicaConfiguration {
  let unknown : ReplicaConfiguration = { speculative_tokens: -1, ready: false, }
  guard value
    is {
      "metadata": { "generation": Number(generation, ..), .. },
      "spec": {
        "replicas": 1,
        "template": { "spec": { "containers": Array(containers), .. }, .. },
        ..
      },
      ..
    } else {
    return unknown
  }
  guard containers.iter().find_first(c => c is { "name": "vllm", .. })
    is Some(
      {
        "args": Array(raw_args),
        "command": ["vllm"],
        "image": String(actual_image),
        ..
      }
    ) else {
    return unknown
  }
  let args : Array[String] = @json.from_json(Json(raw_args)) catch {
    _ => return unknown
  }
  let observed = observed_speculative_tokens(args)
  let rolled_out = match value {
    {
      "status": {
        "observedGeneration": Number(seen, ..),
        "replicas": 1,
        "updatedReplicas": 1,
        "readyReplicas": 1,
        "availableReplicas": 1,
        ..
      },
      ..
    } => seen >= generation
    _ => false
  }
  {
    speculative_tokens: observed,
    ready: rolled_out &&
    args == runtime_args(selection, tokens, tuning~, profile~) &&
    (image == "" || actual_image == image),
  }
}

///|
/// A healthy old endpoint is not evidence that the new configuration is live.
pub async fn Pool::configuration(
  self : Pool,
  node_id : String,
) -> ReplicaConfiguration {
  guard self.selection() is Some(selection) else {
    return { speculative_tokens: -1, ready: false, }
  }
  let target = self.target(node_id)
  let value = self.read(target)
  configuration_observation(
    value,
    selection,
    self.speculative_tokens(),
    self.runtime_image,
    tuning=self.tuning(),
    profile=self.runtime_profile(selection.artifact.digest),
  )
}
