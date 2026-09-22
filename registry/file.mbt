///|
enum RegistryPersistence {
  RegistryFile(String)
  RegistryPostgres(@database.PostgresDatabase)
}

///|
pub struct FileRegistry {
  persistence : RegistryPersistence
  mut registry : ModelRegistry
  mutex : @async.Mutex
  /// Whether an approval must be backed by a passed evaluation. Defaults to
  /// requiring one; a deployment that has shelved evaluation says so at open
  /// time, and every receipt written under that policy records that no
  /// evaluation took part.
  require_evaluation : Bool
}

///|
async fn write_registry(path : String, snapshot : String) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    snapshot,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
pub async fn FileRegistry::open(
  path : String,
  require_evaluation? : Bool = true,
) -> FileRegistry {
  let registry = if @fs.exists(path) {
    ModelRegistry::restore(@fs.read_file(path).text())
  } else {
    ModelRegistry::new()
  }
  let durable = {
    persistence: RegistryFile(path),
    registry,
    mutex: Mutex(),
    require_evaluation,
  }
  if !@fs.exists(path) {
    write_registry(path, registry.snapshot())
  }
  durable
}

///|
pub async fn FileRegistry::open_postgres(
  database : @database.PostgresDatabase,
  require_evaluation? : Bool = true,
) -> FileRegistry {
  let payload = database.load_snapshot("model_registry", "lunanexa.registry.v1")
  let registry = match payload {
    Some(snapshot) => ModelRegistry::restore(snapshot)
    None => ModelRegistry::new()
  }
  let durable = {
    persistence: RegistryPostgres(database),
    registry,
    require_evaluation,
    mutex: Mutex(),
  }
  if payload is None {
    database.save_opaque_snapshot(
      "model_registry",
      "lunanexa.registry.v1",
      registry.snapshot(),
    )
  }
  durable
}

///|
async fn[T] FileRegistry::update(
  self : FileRegistry,
  mutate : (ModelRegistry) -> T raise,
) -> T {
  self.mutex.acquire()
  defer self.mutex.release()
  // Work on an independent snapshot. Neither failed validation nor cancelled
  // persistence may publish an uncommitted model, approval or alias in memory.
  let candidate = ModelRegistry::restore(self.registry.snapshot())
  let result = mutate(candidate)
  match self.persistence {
    RegistryFile(path) => write_registry(path, candidate.snapshot())
    RegistryPostgres(database) =>
      database.save_opaque_snapshot(
        "model_registry",
        "lunanexa.registry.v1",
        candidate.snapshot(),
      )
  }
  self.registry = candidate
  result
}

///|
pub async fn FileRegistry::register_model(
  self : FileRegistry,
  model : @contracts.ModelRecord,
) -> Unit {
  self.update(registry => registry.register_model(model))
}

///|
pub async fn FileRegistry::register_runtime(
  self : FileRegistry,
  runtime : @contracts.RuntimeSpec,
) -> Unit {
  self.update(registry => registry.register_runtime(runtime))
}

///|
pub async fn FileRegistry::deployment_allowed(
  self : FileRegistry,
  artifact_digest : String,
  runtime : @contracts.RuntimeSpec,
) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  let allowed = self.registry.deployment_allowed(artifact_digest, runtime)
  allowed
}

///|
pub async fn FileRegistry::scheduling_target(
  self : FileRegistry,
  selector : String,
  capability : @contracts.Capability,
) -> SchedulingTarget? {
  self.mutex.acquire()
  defer self.mutex.release()
  let target = self.registry.scheduling_target(selector, capability)
  target
}

///|
pub async fn FileRegistry::record_license(
  self : FileRegistry,
  license : LicenseRecord,
) -> Unit {
  self.update(registry => registry.record_license(license))
}

///|
/// Atomically adopts a verified external import as a registry candidate and
/// records its license for separate human acceptance. A persistence failure
/// restores the exact previous registry snapshot.
pub async fn FileRegistry::adopt_import(
  self : FileRegistry,
  model : @contracts.ModelRecord,
  license : LicenseRecord,
) -> Unit {
  self.update(registry => {
    let before : RegistrySnapshot = @json.from_json(
      @json.parse(registry.snapshot()),
    )
    let existing_model = before.models
      .iter()
      .find_first(value => {
        value.model_id == model.model_id && value.version == model.version
      })
    let existing_license = before.licenses
      .iter()
      .find_first(value => value.license_id == license.license_id)
    match existing_model {
      Some(value) if value != model => raise InvalidMetadata(model.model_id)
      _ => ()
    }
    match existing_license {
      Some(value) if value != license =>
        raise InvalidMetadata(license.license_id)
      _ => ()
    }
    if existing_model is None {
      registry.register_model(model)
    }
    if existing_license is None {
      registry.record_license(license)
    }
  })
}

///|
pub async fn FileRegistry::record_verification(
  self : FileRegistry,
  verification : ArtifactVerification,
) -> Unit {
  self.update(registry => registry.record_verification(verification))
}

///|
pub async fn FileRegistry::record_evaluation(
  self : FileRegistry,
  evaluation : EvaluationRecord,
) -> Unit {
  self.update(registry => registry.record_evaluation(evaluation))
}

///|
/// Whether this deployment requires a passed evaluation before a model can be
/// approved. Exposed so the deployment gate can follow the same policy the
/// registry was opened with, instead of the two disagreeing.
pub fn FileRegistry::requires_evaluation(self : FileRegistry) -> Bool {
  self.require_evaluation
}

///|
pub async fn FileRegistry::approve(
  self : FileRegistry,
  model_id : String,
  version : String,
  now_unix_ms : Int64,
) -> @contracts.ModelRecord {
  let require_evaluation = self.require_evaluation
  self.update(registry => {
    registry.approve(model_id, version, now_unix_ms, require_evaluation~)
  })
}

///|
pub async fn FileRegistry::promote(
  self : FileRegistry,
  alias_name : String,
  model_id : String,
  version : String,
  stage : RolloutStage,
  actor : String,
  now_unix_ms : Int64,
) -> PromotionReceipt {
  let require_evaluation = self.require_evaluation
  self.update(registry => {
    registry.promote(
      alias_name,
      model_id,
      version,
      stage,
      actor,
      now_unix_ms,
      require_evaluation~,
    )
  })
}

///|
pub async fn FileRegistry::rollback(
  self : FileRegistry,
  alias_name : String,
  actor : String,
  now_unix_ms : Int64,
) -> PromotionReceipt {
  self.update(registry => registry.rollback(alias_name, actor, now_unix_ms))
}

///|
pub async fn FileRegistry::snapshot(self : FileRegistry) -> RegistrySnapshot {
  self.mutex.acquire()
  defer self.mutex.release()
  let snapshot : RegistrySnapshot = @json.from_json(
    @json.parse(self.registry.snapshot()),
  )
  snapshot
}
