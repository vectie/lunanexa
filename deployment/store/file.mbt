///|
pub(all) suberror DeploymentStoreError {
  InvalidSnapshot(String)
} derive(Debug, Eq)

///|
enum DeploymentPersistence {
  DeploymentFile(String)
  DeploymentPostgres(@database.PostgresDatabase)
}

///|
pub struct FileDeploymentStore {
  persistence : DeploymentPersistence
  signing_secret : String
  templates : Map[String, @deployment.ModelServiceTemplate]
  operations : Map[String, @deployment.DeploymentOperation]
  mutex : @async.Mutex
}

///|
fn template_key(template_id : String, version : String) -> String {
  "\{template_id}@\{version}"
}

///|
fn canonical_template(template : @deployment.ModelServiceTemplate) -> String {
  { ..template, signature: "" }.to_json().stringify()
}

///|
fn sign_material(material : String, secret : String) -> String {
  let key = @utf8.encode(secret)
  let encoded = @utf8.encode(material)
  @crypto.bytes_to_hex_string(
    @crypto.hmac(@crypto.SHA256::new(), key.view(), encoded.view()),
  )
}

///|
fn sign_template(
  template : @deployment.ModelServiceTemplate,
  secret : String,
) -> String {
  sign_material(canonical_template(template), secret)
}

///|
fn canonical_snapshot(snapshot : @deployment.DeploymentSnapshot) -> String {
  { ..snapshot, signature: "" }.to_json().stringify()
}

///|
fn sign_snapshot(
  snapshot : @deployment.DeploymentSnapshot,
  secret : String,
) -> String {
  sign_material(canonical_snapshot(snapshot), secret)
}

///|
fn snapshot_signature_valid(
  snapshot : @deployment.DeploymentSnapshot,
  secret : String,
) -> Bool {
  snapshot.signature != "" &&
  snapshot.signature == sign_snapshot(snapshot, secret)
}

///|
fn signature_valid(
  template : @deployment.ModelServiceTemplate,
  secret : String,
) -> Bool {
  template.signature != "" &&
  template.signature == sign_template(template, secret)
}

///|
fn FileDeploymentStore::snapshot_unlocked(
  self : FileDeploymentStore,
) -> @deployment.DeploymentSnapshot {
  let templates = [ for _, value in self.templates => value ]
  templates.sort_by((left, right) => {
    let by_id = left.template_id.compare(right.template_id)
    if by_id == 0 {
      left.version.compare(right.version)
    } else {
      by_id
    }
  })
  let operations = [ for _, value in self.operations => value ]
  operations.sort_by((left, right) => {
    let by_deployment = left.deployment_id.compare(right.deployment_id)
    if by_deployment == 0 {
      left.generation.compare(right.generation)
    } else {
      by_deployment
    }
  })
  let unsigned : @deployment.DeploymentSnapshot = {
    schema_version: "lunanexa.deployments.v2",
    templates,
    operations,
    signature: "",
  }
  { ..unsigned, signature: sign_snapshot(unsigned, self.signing_secret) }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @deployment.DeploymentSnapshot,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
pub async fn FileDeploymentStore::open(
  path : String,
  signing_secret : String,
) -> FileDeploymentStore {
  if signing_secret == "" {
    raise DeploymentStoreError::InvalidSnapshot(
      "catalog signing authority is unavailable",
    )
  }
  let store : FileDeploymentStore = {
    persistence: DeploymentFile(path),
    signing_secret,
    templates: Map([]),
    operations: Map([]),
    mutex: Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : @deployment.DeploymentSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error => raise InvalidSnapshot("\{Repr(error)}")
    }
    if snapshot.schema_version != "lunanexa.deployments.v2" {
      raise InvalidSnapshot("unsupported deployment snapshot")
    }
    if !snapshot_signature_valid(snapshot, signing_secret) {
      raise InvalidSnapshot("deployment snapshot integrity check failed")
    }
    for template in snapshot.templates {
      @deployment.validate_template(template) catch {
        _ => raise InvalidSnapshot("invalid catalog template")
      }
      if !signature_valid(template, signing_secret) {
        raise InvalidSnapshot("catalog template signature is invalid")
      }
      store.templates[template_key(template.template_id, template.version)] = template
    }
    for operation in snapshot.operations {
      store.operations[operation.operation_id] = operation
    }
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn FileDeploymentStore::open_postgres(
  database : @database.PostgresDatabase,
  signing_secret : String,
) -> FileDeploymentStore {
  if signing_secret == "" {
    raise DeploymentStoreError::InvalidSnapshot(
      "catalog signing authority is unavailable",
    )
  }
  let store : FileDeploymentStore = {
    persistence: DeploymentPostgres(database),
    signing_secret,
    templates: Map([]),
    operations: Map([]),
    mutex: Mutex(),
  }
  let payload = database.load_snapshot("deployments", "lunanexa.deployments.v2")
  match payload {
    Some(raw) => {
      let snapshot : @deployment.DeploymentSnapshot = @json.from_json(
        @json.parse(raw),
      ) catch {
        error => raise InvalidSnapshot("\{Repr(error)}")
      }
      if snapshot.schema_version != "lunanexa.deployments.v2" {
        raise InvalidSnapshot("unsupported deployment snapshot")
      }
      if !snapshot_signature_valid(snapshot, signing_secret) {
        raise InvalidSnapshot("deployment snapshot integrity check failed")
      }
      for template in snapshot.templates {
        @deployment.validate_template(template) catch {
          _ => raise InvalidSnapshot("invalid catalog template")
        }
        if !signature_valid(template, signing_secret) {
          raise InvalidSnapshot("catalog template signature is invalid")
        }
        store.templates[template_key(template.template_id, template.version)] = template
      }
      for operation in snapshot.operations {
        store.operations[operation.operation_id] = operation
      }
    }
    None => store.persist()
  }
  store
}

///|
async fn FileDeploymentStore::persist(self : FileDeploymentStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    DeploymentFile(path) => write_snapshot(path, snapshot)
    DeploymentPostgres(database) =>
      database.save_opaque_snapshot(
        "deployments",
        "lunanexa.deployments.v2",
        snapshot.to_json().stringify(),
      )
  }
}

///|
pub async fn FileDeploymentStore::register_template(
  self : FileDeploymentStore,
  candidate : @deployment.ModelServiceTemplate,
) -> @deployment.ModelServiceTemplate {
  if candidate.approval_receipt != "" || candidate.signature != "" {
    raise @deployment.DeploymentError::InvalidTemplate(
      "callers submit an unsigned template",
    )
  }
  @deployment.validate_template(candidate, require_signature=false)
  self.mutex.acquire()
  let key = template_key(candidate.template_id, candidate.version)
  if self.templates.contains(key) {
    self.mutex.release()
    raise @deployment.DeploymentError::InvalidTemplate(
      "catalog template already exists",
    )
  }
  let approved = {
    ..candidate,
    approval_receipt: "catalog:\{candidate.template_id}:\{candidate.version}",
  }
  let signed = {
    ..approved,
    signature: sign_template(approved, self.signing_secret),
  }
  self.templates[key] = signed
  try self.persist() catch {
    error => {
      self.templates.remove(key)
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  signed
}

///|
pub async fn FileDeploymentStore::templates(
  self : FileDeploymentStore,
) -> Array[@deployment.ModelServiceTemplate] {
  self.mutex.acquire()
  let values = self.snapshot_unlocked().templates
  self.mutex.release()
  values
}

///|
pub async fn FileDeploymentStore::template(
  self : FileDeploymentStore,
  reference : @deployment.TemplateRef,
) -> @deployment.ModelServiceTemplate? {
  self.mutex.acquire()
  let value = self.templates.get(
    template_key(reference.template_id, reference.version),
  )
  self.mutex.release()
  value
}

///|
fn operation_for_idempotency(
  operations : Map[String, @deployment.DeploymentOperation],
  idempotency_key : String,
) -> @deployment.DeploymentOperation? {
  operations
  .values()
  .find_first(operation => {
    operation.plan.intent.idempotency_key == idempotency_key
  })
}

///|
fn next_generation(
  operations : Map[String, @deployment.DeploymentOperation],
  deployment_id : String,
) -> Int64 {
  operations
  .values()
  .filter(operation => operation.deployment_id == deployment_id)
  .fold(init=0L, (maximum, operation) => maximum.max(operation.generation)) +
  1L
}

///|
pub async fn FileDeploymentStore::create_operation(
  self : FileDeploymentStore,
  plan : @deployment.DeploymentPlan,
  now_unix_ms : Int64,
) -> @deployment.DeploymentOperation {
  @deployment.validate_intent(plan.intent)
  self.mutex.acquire()
  if operation_for_idempotency(self.operations, plan.intent.idempotency_key)
    is Some(existing) {
    self.mutex.release()
    if existing.plan.intent == plan.intent {
      return existing
    }
    raise @deployment.DeploymentError::IdempotencyConflict(
      plan.intent.idempotency_key,
    )
  }
  let generation = next_generation(self.operations, plan.intent.deployment_id)
  let operation_id = "operation:\{plan.intent.deployment_id}:\{generation}"
  let operation : @deployment.DeploymentOperation = {
    operation_id,
    deployment_id: plan.intent.deployment_id,
    generation,
    state: if plan.executable {
      Planned
    } else {
      Blocked
    },
    plan,
    assignment_ids: [
      for replica in plan.replicas => replica.replica_id
    ],
    endpoint: plan.endpoint,
    message: if plan.executable {
      "deployment plan accepted"
    } else {
      "deployment is blocked by preflight findings"
    },
    audit_receipt: "deployment:\{plan.intent.deployment_id}:\{generation}",
    created_unix_ms: now_unix_ms,
    updated_unix_ms: now_unix_ms,
  }
  self.operations[operation_id] = operation
  try self.persist() catch {
    error => {
      self.operations.remove(operation_id)
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  operation
}

///|
pub async fn FileDeploymentStore::transition(
  self : FileDeploymentStore,
  operation_id : String,
  state : @deployment.DeploymentOperationState,
  message : String,
  now_unix_ms : Int64,
) -> @deployment.DeploymentOperation {
  self.mutex.acquire()
  guard self.operations.get(operation_id) is Some(current) else {
    self.mutex.release()
    raise @deployment.DeploymentError::NotFound(operation_id)
  }
  if current.state != state &&
    !@deployment.operation_transition_allowed(current.state, state) {
    self.mutex.release()
    raise @deployment.DeploymentError::InvalidState(operation_id)
  }
  let next = { ..current, state, message, updated_unix_ms: now_unix_ms }
  self.operations[operation_id] = next
  try self.persist() catch {
    error => {
      self.operations[operation_id] = current
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  next
}

///|
pub async fn FileDeploymentStore::operation(
  self : FileDeploymentStore,
  operation_id : String,
) -> @deployment.DeploymentOperation? {
  self.mutex.acquire()
  let value = self.operations.get(operation_id)
  self.mutex.release()
  value
}

///|
pub async fn FileDeploymentStore::deployment(
  self : FileDeploymentStore,
  deployment_id : String,
) -> @deployment.DeploymentOperation? {
  self.mutex.acquire()
  let value = self.operations
    .values()
    .filter(operation => operation.deployment_id == deployment_id)
    .fold(init=(None : @deployment.DeploymentOperation?), (latest, operation) => {
      match latest {
        Some(current) if current.generation >= operation.generation => latest
        _ => Some(operation)
      }
    })
  self.mutex.release()
  value
}

///|
pub async fn FileDeploymentStore::operations(
  self : FileDeploymentStore,
) -> Array[@deployment.DeploymentOperation] {
  self.mutex.acquire()
  let values = self.snapshot_unlocked().operations
  self.mutex.release()
  values
}

///|
pub async fn FileDeploymentStore::snapshot(
  self : FileDeploymentStore,
) -> @deployment.DeploymentSnapshot {
  self.mutex.acquire()
  let value = self.snapshot_unlocked()
  self.mutex.release()
  value
}
