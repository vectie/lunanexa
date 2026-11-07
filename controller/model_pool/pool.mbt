///|
pub type Transport = async (String, String, Json?) -> (Int32, Json)

///|
pub(all) struct Target {
  deployment : String
  node_id : String
  kube_node : String
  cache_root : String
} derive(Eq, ToJson, FromJson)

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Target with ToJson::{to_json}

///|
pub extend Target with FromJson::{from_json}

///|
pub(all) struct Selection {
  model_id : String
  version : String
  model_alias : String
  served_model : String
  artifact : @contracts.ArtifactRef
} derive(Eq, ToJson, FromJson)

///|
pub extend Selection with Eq::{equal, not_equal}

///|
pub extend Selection with ToJson::{to_json}

///|
pub extend Selection with FromJson::{from_json}

///|
struct SavedReplica {
  target : Target
  uid : String
  spec : Json
} derive(ToJson, FromJson)

///|
pub extend SavedReplica with ToJson::{to_json}

///|
pub extend SavedReplica with FromJson::{from_json}

///|
struct Journal {
  replicas : Array[SavedReplica]
  selection : Selection?
  generation : Int64
  switched : Array[String]
  active : Bool?
  speculative_tokens : Int32?
  tuning : Tuning?
  selected_nodes : Array[String]?
  node_names : Map[String, String]?
} derive(ToJson, FromJson)

///|
pub extend Journal with ToJson::{to_json}

///|
pub extend Journal with FromJson::{from_json}

///|
pub(all) suberror PoolError {
  InvalidConfiguration
  InvalidDeployment
  OutsideScope
  NotAdopted
  Conflict
  Unavailable
} derive(Debug, Eq)

///|
pub extend PoolError with Debug::{to_repr}

///|
pub extend PoolError with Eq::{equal, not_equal}

///|
pub struct Pool {
  transport : Transport
  namespace_name : String
  targets : Array[Target]
  path : String
  runtime_image : String
  profiles : Array[RuntimeProfile]
  mut journal : Journal
  mutex : @async.Mutex
}

///|
fn resource_name(value : String) -> Bool {
  value != "" &&
  value.length() <= 253 &&
  value.all(c => c is ('a'..<='z' | '0'..<='9' | '-' | '.'))
}

///|
pub async fn Pool::open(
  transport : Transport,
  namespace_name : String,
  targets : Array[Target],
  path : String,
  runtime_image~ : String = "",
  profiles~ : Array[RuntimeProfile] = [],
) -> Pool {
  let nodes : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  if !resource_name(namespace_name) ||
    targets.is_empty() ||
    !path.has_prefix("/") ||
    path.contains("..") {
    raise PoolError::InvalidConfiguration
  }
  for target in targets {
    if !resource_name(target.deployment) ||
      !resource_name(target.kube_node) ||
      !@contracts.valid_identifier(target.node_id, maximum_length=128) ||
      nodes.contains(target.node_id) ||
      names.contains(target.deployment) ||
      !target.cache_root.has_prefix("/") ||
      target.cache_root == "/" ||
      target.cache_root.contains("..") ||
      target.cache_root.has_suffix("/") {
      raise PoolError::InvalidConfiguration
    }
    nodes[target.node_id] = true
    names[target.deployment] = true
  }
  let journal : Journal = if @fs.exists(path) {
    @json.from_json(@json.parse(@fs.read_file(path).text()))
  } else {
    {
      replicas: [],
      selection: None,
      generation: 0L,
      switched: [],
      active: None,
      speculative_tokens: None,
      tuning: None,
      selected_nodes: None,
      node_names: None,
    }
  }
  if !journal.replicas.is_empty() &&
    journal.replicas.map(r => r.target) != targets {
    raise PoolError::Conflict
  }
  if journal.selected_nodes is Some(nodes) &&
    (
      nodes.is_empty() ||
      targets.count_if(t => nodes.contains(t.node_id)) != nodes.length()
    ) {
    raise PoolError::InvalidConfiguration
  }
  {
    transport,
    namespace_name,
    targets,
    path,
    runtime_image,
    profiles,
    journal,
    mutex: @async.Mutex::Mutex(),
  }
}

///|
pub fn Pool::targets(self : Pool) -> Array[Target] {
  self.targets.copy()
}

///|
pub fn Pool::selection(self : Pool) -> Selection? {
  self.journal.selection
}

///|
pub fn Pool::generation(self : Pool) -> Int64 {
  self.journal.generation
}

///|
pub fn Pool::adopted(self : Pool) -> Bool {
  self.journal.replicas.length() == 4
}

///|
pub fn Pool::switched(self : Pool) -> Array[String] {
  self.journal.switched.copy()
}

///|
pub fn Pool::active(self : Pool) -> Bool {
  self.journal.active == Some(true)
}

///|
pub async fn Pool::activate(self : Pool) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if !self
    .selected_targets()
    .all(t => self.journal.switched.contains(t.node_id)) {
    raise PoolError::Conflict
  }
  self.save({ ..self.journal, active: Some(true), })
}

///|
fn Pool::target(self : Pool, node_id : String) -> Target raise PoolError {
  self.targets
  .iter()
  .find_first(t => t.node_id == node_id)
  .unwrap_or_else(() => raise OutsideScope)
}

///|
fn Pool::resource_path(self : Pool, target : Target) -> String {
  "/apis/apps/v1/namespaces/\{self.namespace_name}/deployments/\{target.deployment}"
}

///|
async fn Pool::save(self : Pool, next : Journal) -> Unit {
  let partial = self.path + ".partial"
  @fs.write_file(
    partial,
    Json(next).stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(partial, self.path, replace=true)
  self.journal = next
}

///|
async fn Pool::read(self : Pool, target : Target) -> Json {
  let (status, value) = (self.transport)(
    "GET",
    self.resource_path(target),
    None,
  )
  if status != 200 {
    raise PoolError::Unavailable
  }
  guard value
    is {
      "metadata": {
        "name": String(name),
        "uid": String(_),
        "resourceVersion": String(_),
        ..
      },
      "spec": {
        "template": {
          "spec": {
            "nodeSelector": { "kubernetes.io/hostname": String(node), .. },
            ..
          },
          ..
        },
        ..
      },
      ..
    } &&
    name == target.deployment &&
    node == target.kube_node else {
    raise PoolError::InvalidDeployment
  }
  value
}

///|
/// Capture original specs once. Repeating adoption never replaces rollback data.
pub async fn Pool::adopt(self : Pool) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.adopted() {
    return
  }
  let replicas : Array[SavedReplica] = []
  for target in self.targets {
    guard self.read(target)
      is { "metadata": { "uid": String(uid), .. }, "spec": spec, .. } else {
      raise PoolError::InvalidDeployment
    }
    replicas.push({ target, uid, spec, })
  }
  self.save({ ..self.journal, replicas, })
}

///|
pub async fn Pool::select(self : Pool, selection : Selection) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if !self.adopted() {
    raise PoolError::NotAdopted
  }
  if !@contracts.valid_sha256_digest(selection.artifact.digest) ||
    !selection.artifact.uri.has_prefix("modelstore://") ||
    !@contracts.valid_identifier(selection.served_model, maximum_length=128) ||
    selection.artifact.size_bytes <= 0L {
    raise PoolError::InvalidConfiguration
  }
  if self.journal.selection == Some(selection) {
    return
  }
  if !self.journal.switched.is_empty() {
    raise PoolError::Conflict
  }
  self.save({
    ..self.journal,
    selection: Some(selection),
    generation: self.journal.generation + 1L,
  })
}

///|
fn switch_patch(
  value : Json,
  target : Target,
  selection : Selection,
  runtime_image~ : String = "",
  speculative_tokens~ : Int32 = 0,
  tuning~ : Tuning = default_tuning(),
  profile~ : RuntimeProfile = default_runtime_profile(),
) -> Json raise PoolError {
  guard value
    is {
      "metadata": { "uid": String(uid), "resourceVersion": String(version), .. },
      "spec": {
        "template": {
          "spec": {
            "containers": Array(containers),
            "volumes": Array(volumes),
            ..
          },
          ..
        },
        ..
      },
      ..
    } else {
    raise InvalidDeployment
  }
  let mut container_index = -1
  let mut mount_index = -1
  let mut volume_index = -1
  let mut volume_name = ""
  for i, container in containers {
    if container is { "name": "vllm", "volumeMounts": Array(mounts), .. } {
      container_index = i
      for j, mount in mounts {
        if mount
          is {
            "name": "model",
            "mountPath": String(path),
            "readOnly": true,
            ..
          } &&
          path.has_prefix("/models/") {
          mount_index = j
          volume_name = "model"
        }
      }
    }
  }
  for i, volume in volumes {
    if volume
      is { "name": String(name), "hostPath": { "path": String(_), .. }, .. } &&
      name == volume_name {
      volume_index = i
    }
  }
  if container_index < 0 || mount_index < 0 || volume_index < 0 {
    raise InvalidDeployment
  }
  let path = target.cache_root +
    "/sha256/" +
    selection.artifact.digest[7:].to_owned() +
    ".revision"
  let args = runtime_args(selection, speculative_tokens, tuning~, profile~)
  let patch : Array[Json] = [
    { "op": "test", "path": "/metadata/uid", "value": uid },
    { "op": "test", "path": "/metadata/resourceVersion", "value": version },
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/\{container_index}/args",
      "value": Json(args),
    },
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/\{container_index}/volumeMounts/\{mount_index}/mountPath",
      "value": "/models/lunanexa-model",
    },
    {
      "op": "replace",
      "path": "/spec/template/spec/volumes/\{volume_index}/hostPath/path",
      "value": path,
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/\{container_index}/command",
      "value": ["vllm"],
    },
  ]
  if runtime_image != "" {
    patch.push({
      "op": "replace",
      "path": "/spec/template/spec/containers/\{container_index}/image",
      "value": runtime_image,
    })
  }
  if value is { "spec": { "replicas": 0, .. }, .. } {
    patch.push({ "op": "replace", "path": "/spec/replicas", "value": 1 })
  }
  Json(patch)
}

///|
fn runtime_args(
  selection : Selection,
  speculative_tokens : Int32,
  tuning~ : Tuning = default_tuning(),
  profile~ : RuntimeProfile = default_runtime_profile(),
) -> Array[String] {
  let args : Array[String] = [
    "serve",
    "/models/lunanexa-model",
    "--served-model-name",
    selection.served_model,
    "--host",
    "0.0.0.0",
    "--port",
    "8000",
  ]
  for arg in profile.arguments {
    args.push(arg)
  }
  if speculative_tokens > 0 && profile.speculative is Some(Object(options)) {
    args.push("--speculative-config")
    let options = options.copy()
    options["num_speculative_tokens"] = Json(speculative_tokens)
    args.push(Json::object(options).stringify())
  }
  append_tuning_args(args, tuning)
  args
}

///|
/// The caller verifies the node's fresh signed cache observation first.
pub async fn Pool::switch_replica(self : Pool, node_id : String) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if !self.selected_targets().any(t => t.node_id == node_id) {
    raise PoolError::OutsideScope
  }
  guard self.journal.selection is Some(selection) else {
    raise PoolError::NotAdopted
  }
  let target = self.target(node_id)
  let value = self.read(target)
  guard value is { "metadata": { "uid": String(uid), .. }, .. } &&
    self.journal.replicas.any(r => r.target == target && r.uid == uid) else {
    raise PoolError::Conflict
  }
  let (status, _) = (self.transport)(
    "PATCH",
    self.resource_path(target),
    Some(
      switch_patch(
        value,
        target,
        selection,
        runtime_image=self.runtime_image,
        speculative_tokens=self.speculative_tokens(),
        tuning=self.tuning(),
        profile=self.runtime_profile(selection.artifact.digest),
      ),
    ),
  )
  if status < 200 || status >= 300 {
    raise PoolError::Unavailable
  }
  let switched = self.journal.switched.copy()
  if !switched.contains(node_id) {
    switched.push(node_id)
  }
  self.save({ ..self.journal, switched, })
}

///|
pub async fn Pool::rollback(self : Pool) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if !self.adopted() {
    raise PoolError::NotAdopted
  }
  for
    saved in self.journal.replicas.filter(r => {
      self.selected_targets().contains(r.target)
    }) {
    let value = self.read(saved.target)
    guard value
      is {
        "metadata": {
          "uid": String(uid),
          "resourceVersion": String(version),
          ..
        },
        ..
      } &&
      uid == saved.uid else {
      raise PoolError::Conflict
    }
    let patch : Json = [
      { "op": "test", "path": "/metadata/uid", "value": uid },
      { "op": "test", "path": "/metadata/resourceVersion", "value": version },
      { "op": "replace", "path": "/spec", "value": saved.spec },
    ]
    let (status, _) = (self.transport)(
      "PATCH",
      self.resource_path(saved.target),
      Some(patch),
    )
    if status < 200 || status >= 300 {
      raise PoolError::Unavailable
    }
  }
  self.save({
    ..self.journal,
    selection: None,
    switched: [],
    active: None,
    speculative_tokens: None,
    tuning: None,
  })
}
