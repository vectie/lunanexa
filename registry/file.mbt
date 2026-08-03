///|
pub struct FileRegistry {
  path : String
  registry : ModelRegistry
  mutex : @async.Mutex
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
pub async fn FileRegistry::open(path : String) -> FileRegistry {
  let registry = if @fs.exists(path) {
    ModelRegistry::restore(@fs.read_file(path).text())
  } else {
    ModelRegistry::new()
  }
  let durable = { path, registry, mutex: @async.Mutex::Mutex() }
  if !@fs.exists(path) {
    write_registry(path, registry.snapshot())
  }
  durable
}

///|
async fn FileRegistry::persist(self : FileRegistry) -> Unit {
  write_registry(self.path, self.registry.snapshot())
}

///|
pub async fn FileRegistry::register_model(
  self : FileRegistry,
  model : @contracts.ModelRecord,
) -> Unit {
  self.mutex.acquire()
  try {
    self.registry.register_model(model)
    self.persist()
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileRegistry::register_runtime(
  self : FileRegistry,
  runtime : @contracts.RuntimeSpec,
) -> Unit {
  self.mutex.acquire()
  try {
    self.registry.register_runtime(runtime)
    self.persist()
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileRegistry::deployment_allowed(
  self : FileRegistry,
  artifact_digest : String,
  runtime : @contracts.RuntimeSpec,
) -> Bool {
  self.mutex.acquire()
  let allowed = self.registry.deployment_allowed(artifact_digest, runtime)
  self.mutex.release()
  allowed
}

///|
pub async fn FileRegistry::scheduling_target(
  self : FileRegistry,
  selector : String,
  capability : @contracts.Capability,
) -> SchedulingTarget? {
  self.mutex.acquire()
  let target = self.registry.scheduling_target(selector, capability)
  self.mutex.release()
  target
}

///|
pub async fn FileRegistry::record_license(
  self : FileRegistry,
  license : LicenseRecord,
) -> Unit {
  self.mutex.acquire()
  try {
    self.registry.record_license(license)
    self.persist()
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileRegistry::record_verification(
  self : FileRegistry,
  verification : ArtifactVerification,
) -> Unit {
  self.mutex.acquire()
  try {
    self.registry.record_verification(verification)
    self.persist()
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileRegistry::record_evaluation(
  self : FileRegistry,
  evaluation : EvaluationRecord,
) -> Unit {
  self.mutex.acquire()
  try {
    self.registry.record_evaluation(evaluation)
    self.persist()
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}

///|
pub async fn FileRegistry::approve(
  self : FileRegistry,
  model_id : String,
  version : String,
  now_unix_ms : Int64,
) -> @contracts.ModelRecord {
  self.mutex.acquire()
  try {
    let model = self.registry.approve(model_id, version, now_unix_ms)
    self.persist()
    self.mutex.release()
    model
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
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
  self.mutex.acquire()
  try {
    let receipt = self.registry.promote(
      alias_name, model_id, version, stage, actor, now_unix_ms,
    )
    self.persist()
    self.mutex.release()
    receipt
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileRegistry::rollback(
  self : FileRegistry,
  alias_name : String,
  actor : String,
  now_unix_ms : Int64,
) -> PromotionReceipt {
  self.mutex.acquire()
  try {
    let receipt = self.registry.rollback(alias_name, actor, now_unix_ms)
    self.persist()
    self.mutex.release()
    receipt
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileRegistry::snapshot(self : FileRegistry) -> RegistrySnapshot {
  self.mutex.acquire()
  let snapshot : RegistrySnapshot = @json.from_json(
    @json.parse(self.registry.snapshot()),
  )
  self.mutex.release()
  snapshot
}
