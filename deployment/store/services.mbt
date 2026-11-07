///|
/// Separate signed material preserves v2 catalog/operation snapshot signatures.
priv struct ServicesSnapshot {
  schema_version : String
  instances : Array[@deployment.ModelServiceInstance]
  signature : String
} derive(ToJson, FromJson)

///|
fn services_signature(snapshot : ServicesSnapshot, secret : String) -> String {
  sign_material(
    ToJson::to_json({ ..snapshot, signature: "", }).stringify(),
    secret,
  )
}

///|
async fn FileDeploymentStore::load_services(self : FileDeploymentStore) -> Unit {
  let raw = match self.persistence {
    DeploymentFile(path) =>
      if @fs.exists(path + ".services") {
        Some(@fs.read_file(path + ".services").text())
      } else {
        None
      }
    DeploymentPostgres(db) =>
      db.load_snapshot("model_services", "lunanexa.services.v1")
  }
  guard raw is Some(raw) else { return }
  let value : ServicesSnapshot = @json.from_json(@json.parse(raw))
  guard value.schema_version == "lunanexa.services.v1" &&
    value.signature == services_signature(value, self.signing_secret) else {
    raise DeploymentStoreError::InvalidSnapshot(
      "model service integrity check failed",
    )
  }
  for instance in value.instances {
    if self.services.contains(instance.service_id) {
      raise DeploymentStoreError::InvalidSnapshot("duplicate model service")
    }
    self.services[instance.service_id] = instance
  }
}

///|
async fn FileDeploymentStore::persist_services(
  self : FileDeploymentStore,
) -> Unit {
  let instances = self.services.values().to_array()
  instances.sort_by((a, b) => a.service_id.compare(b.service_id))
  let unsigned : ServicesSnapshot = {
    schema_version: "lunanexa.services.v1",
    instances,
    signature: "",
  }
  let value = {
    ..unsigned,
    signature: services_signature(unsigned, self.signing_secret),
  }
  let raw = ToJson::to_json(value).stringify()
  match self.persistence {
    DeploymentPostgres(db) =>
      db.save_opaque_snapshot("model_services", "lunanexa.services.v1", raw)
    DeploymentFile(path) => {
      let next = path + ".services.next"
      errdefer (@fs.remove(next) catch { _ => () })
      @fs.write_file(next, raw, permission=0o600, sync=Full)
      @fs.rename(next, path + ".services", replace=true)
    }
  }
}

///|
pub async fn FileDeploymentStore::services(
  self : FileDeploymentStore,
) -> Array[@deployment.ModelServiceInstance] {
  self.mutex.acquire()
  defer self.mutex.release()
  self.services.values().to_array()
}

///|
pub async fn FileDeploymentStore::service(
  self : FileDeploymentStore,
  id : String,
) -> @deployment.ModelServiceInstance? {
  self.mutex.acquire()
  defer self.mutex.release()
  self.services.get(id)
}

///|
/// Adoption writes metadata only. It never dispatches a runtime action or
/// replaces a previously adopted binding/owner on a controller restart.
pub async fn FileDeploymentStore::adopt_service(
  self : FileDeploymentStore,
  value : @deployment.ModelServiceInstance,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  guard value.service_id != "" &&
    value.node_ids.length() > 0 &&
    value.node_ids.all(n => n != "") else {
    raise @deployment.DeploymentError::InvalidState("invalid service binding")
  }
  if self.services.get(value.service_id) is Some(current) {
    guard current.owner == value.owner &&
      current.node_ids == value.node_ids &&
      current.runtime_kind == value.runtime_kind &&
      current.binding_ref == value.binding_ref else {
      raise @deployment.DeploymentError::InvalidState(
        "adopted service binding changed",
      )
    }
    return
  }
  for _, other in self.services {
    if @deployment.service_conflicts(value, other) &&
      (
        value.holds_resources() ||
        (value.owner.tenant_ref != "" && other.owner.tenant_ref != "")
      ) {
      raise @deployment.DeploymentError::InvalidState(
        "service resource conflict",
      )
    }
  }
  self.services[value.service_id] = value
  errdefer self.services.remove(value.service_id)
  self.persist_services()
}

///|
/// Persist desired ownership before dispatch. An unknown/partial outcome holds
/// the claim across restart, and an old generation cannot overwrite a new one.
pub async fn FileDeploymentStore::set_service_desired(
  self : FileDeploymentStore,
  id : String,
  generation : Int64,
  running : Bool,
  now : Int64,
) -> @deployment.ModelServiceInstance {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.services.get(id) is Some(current) &&
    current.generation == generation else {
    raise @deployment.DeploymentError::InvalidState(
      "service generation changed",
    )
  }
  if running {
    for _, other in self.services {
      if @deployment.service_conflicts(current, other) {
        raise @deployment.DeploymentError::InvalidState(
          "service resource conflict",
        )
      }
    }
  }
  let value = {
    ..current,
    desired_running: running,
    generation: generation + 1L,
    updated_unix_ms: now,
  }
  self.services[id] = value
  errdefer {
    self.services[id] = current
  }
  self.persist_services()
  value
}

///|
pub async fn FileDeploymentStore::observe_service(
  self : FileDeploymentStore,
  id : String,
  generation : Int64,
  observed : @deployment.ServiceRuntimeState,
  now : Int64,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.services.get(id) is Some(current) &&
    current.generation == generation else {
    raise @deployment.DeploymentError::InvalidState(
      "service generation changed",
    )
  }
  if current.observed == observed {
    return
  }
  self.services[id] = { ..current, observed, updated_unix_ms: now, }
  errdefer {
    self.services[id] = current
  }
  self.persist_services()
}
