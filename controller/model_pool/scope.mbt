///|
/// The configured four-service authority never expands. Operators choose which
/// of those services participate; older journals retain their original scope.
pub fn Pool::selected_targets(self : Pool) -> Array[Target] {
  match self.journal.selected_nodes {
    None => self.targets()
    Some(nodes) => self.targets.filter(t => nodes.contains(t.node_id))
  }
}

///|
pub fn Pool::node_name(self : Pool, node_id : String) -> String {
  self.journal.node_names.map_or(node_id, names => {
    names.get(node_id).unwrap_or(node_id)
  })
}

///|
/// Save routing exclusion before stopping any replica. A retry preserves the
/// smaller scope even if Kubernetes could not finish releasing a service.
pub async fn Pool::select_nodes(
  self : Pool,
  nodes : Array[String],
  names : Map[String, String],
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if !self.adopted() {
    raise PoolError::NotAdopted
  }
  let selected = self.targets.filter(t => nodes.contains(t.node_id))
  if nodes.is_empty() ||
    selected.length() != nodes.length() ||
    !names
    .iter()
    .all(pair => {
      let (id, name) = pair
      self.targets.any(t => t.node_id == id) &&
      name.trim() != "" &&
      name.length() <= 64 &&
      !name.contains("\n") &&
      !name.contains("\r")
    }) {
    raise PoolError::InvalidConfiguration
  }
  let ordered = selected.map(t => t.node_id)
  self.save({
    ..self.journal,
    selected_nodes: Some(ordered),
    node_names: Some(names.copy()),
    generation: self.journal.generation + 1L,
  })
}

///|
/// Only the adopted service is scaled down, never a node or another workload.
pub async fn Pool::pause_excluded(self : Pool, node_id : String) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.selected_targets().any(t => t.node_id == node_id) {
    raise PoolError::OutsideScope
  }
  let target = self.target(node_id)
  let value = self.read(target)
  guard value
    is {
      "metadata": { "uid": String(uid), "resourceVersion": String(version), .. },
      ..
    } &&
    self.journal.replicas.any(r => r.target == target && r.uid == uid) else {
    raise PoolError::Conflict
  }
  if value is { "spec": { "replicas": 0, .. }, .. } {
    return
  }
  let patch : Json = [
    { "op": "test", "path": "/metadata/uid", "value": uid },
    { "op": "test", "path": "/metadata/resourceVersion", "value": version },
    { "op": "add", "path": "/spec/replicas", "value": 0 },
  ]
  let (status, _) = (self.transport)(
    "PATCH",
    self.resource_path(target),
    Some(patch),
  )
  if status < 200 || status >= 300 {
    raise PoolError::Unavailable
  }
}

///|
pub async fn Pool::paused(self : Pool, node_id : String) -> Bool {
  let value = self.read(self.target(node_id))
  guard value is { "spec": { "replicas": 0, .. }, "status": Object(status), .. } else {
    return false
  }
  ["replicas", "readyReplicas", "availableReplicas", "terminatingReplicas"].all(key => {
      status.get(key).unwrap_or(Json(0)) == Json(0)
    },
  )
}
