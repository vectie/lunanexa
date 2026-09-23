///|
enum Persistence {
  File(String)
  Postgres(@database.PostgresDatabase)
}

///|
pub struct DeliveryStore {
  persistence : Persistence
  mut operations : Array[Operation]
  mut model_services : Array[ModelService]
  mutex : @async.Mutex
}

///|
fn restore(raw : String) -> Snapshot raise {
  let snapshot : Snapshot = @json.from_json(@json.parse(raw))
  if snapshot.schema_version != "lunanexa.exclusive-deliveries.v1" {
    raise InvalidSnapshot
  }
  snapshot
}

///|
pub async fn DeliveryStore::open(path : String) -> DeliveryStore {
  let snapshot = if @fs.exists(path) {
    restore(@fs.read_file(path).text())
  } else {
    {
      schema_version: "lunanexa.exclusive-deliveries.v1",
      operations: [],
      model_services: None,
    }
  }
  {
    persistence: File(path),
    operations: snapshot.operations,
    model_services: snapshot.model_services.unwrap_or([]),
    mutex: Mutex(),
  }
}

///|
pub async fn DeliveryStore::open_postgres(
  database : @database.PostgresDatabase,
) -> DeliveryStore {
  let raw = database.load_snapshot(
    "exclusive_deliveries", "lunanexa.exclusive-deliveries.v1",
  )
  let snapshot = match raw {
    Some(raw) => restore(raw)
    None =>
      {
        schema_version: "lunanexa.exclusive-deliveries.v1",
        operations: [],
        model_services: None,
      }
  }
  {
    persistence: Postgres(database),
    operations: snapshot.operations,
    model_services: snapshot.model_services.unwrap_or([]),
    mutex: Mutex(),
  }
}

///|
async fn DeliveryStore::commit(
  self : DeliveryStore,
  operations : Array[Operation],
  model_services? : Array[ModelService],
) -> Unit {
  let snapshot : Snapshot = {
    schema_version: "lunanexa.exclusive-deliveries.v1",
    operations,
    model_services: Some(model_services.unwrap_or(self.model_services)),
  }
  let raw = snapshot.to_json().stringify()
  match self.persistence {
    File(path) => {
      let temporary = "\{path}.next"
      errdefer (@fs.remove(temporary) catch { _ => () })
      @fs.write_file(
        temporary,
        raw,
        create_mode=CreateOrTruncate,
        permission=0o600,
        sync=Full,
      )
      @fs.rename(temporary, path, replace=true)
    }
    Postgres(database) =>
      database.save_opaque_snapshot(
        "exclusive_deliveries",
        snapshot.schema_version,
        raw,
      )
  }
  let restored = restore(raw)
  self.operations = restored.operations
  self.model_services = restored.model_services.unwrap_or([])
}

///|
pub async fn DeliveryStore::create(
  self : DeliveryStore,
  intent : Intent,
  now : Int64,
) -> Operation {
  self.mutex.acquire()
  defer self.mutex.release()
  for operation in self.operations {
    if operation.intent.tenant_id == intent.tenant_id &&
      operation.intent.organization_id == intent.organization_id &&
      operation.intent.idempotency_key == intent.idempotency_key {
      if operation.intent != intent {
        raise IdempotencyConflict
      }
      return operation
    }
  }
  if intent.tenant_id == "" ||
    intent.organization_id == "" ||
    intent.authorization_ref == "" ||
    intent.lease_id == "" ||
    intent.idempotency_key == "" ||
    intent.template_id == "" ||
    intent.template_version == "" ||
    intent.node_count < 1 ||
    (intent.kind == ModelApi && intent.model_digest is None) {
    raise InvalidIntent
  }
  if intent.expires_at_ms <= now {
    raise AuthorizationExpired
  }
  let operation : Operation = {
    operation_id: "delivery-\{self.operations.length() + 1}",
    intent,
    generation: 1L,
    stage: Reserving,
    resume_stage: Reserving,
    reservation_id: None,
    node_ids: [],
    cache_hit: false,
    transferred_bytes: 0L,
    total_bytes: None,
    model_service_id: None,
    model_assignment_generation: None,
    model_replicas: None,
    workspace_id: None,
    failure_code: None,
    stop_requested_at_ms: None,
    updated_at_ms: now,
  }
  let operations = self.operations.copy()
  operations.push(operation)
  self.commit(operations)
  operation
}

///|
fn DeliveryStore::index(
  self : DeliveryStore,
  operation_id : String,
  generation : Int64,
) -> Int raise DeliveryError {
  for index, operation in self.operations {
    if operation.operation_id == operation_id {
      if operation.generation != generation {
        raise StaleGeneration
      }
      return index
    }
  }
  raise NotFound
}

///|
pub async fn DeliveryStore::observe(
  self : DeliveryStore,
  operation_id : String,
  generation : Int64,
  observation : Observation,
  now : Int64,
) -> Operation {
  self.mutex.acquire()
  defer self.mutex.release()
  let index = self.index(operation_id, generation)
  let next = advance(self.operations[index], observation, now)
  let operations = self.operations.copy()
  operations[index] = next
  self.commit(operations)
  next
}

///|
pub async fn DeliveryStore::retry(
  self : DeliveryStore,
  operation_id : String,
  generation : Int64,
  now : Int64,
) -> Operation {
  self.mutex.acquire()
  defer self.mutex.release()
  let index = self.index(operation_id, generation)
  let operation = self.operations[index]
  if operation.stage != Failed {
    raise UnexpectedObservation
  }
  if now >= operation.intent.expires_at_ms && operation.resume_stage != Stopping {
    raise AuthorizationExpired
  }
  let next = {
    ..operation,
    stage: operation.resume_stage,
    failure_code: None,
    generation: generation + 1L,
    updated_at_ms: now,
  }
  let operations = self.operations.copy()
  operations[index] = next
  self.commit(operations)
  next
}

///|
/// Access must be denied immediately when stopping. The reservation is not
/// released by this transition: its authority needs actual cleanup observations.
pub async fn DeliveryStore::stop(
  self : DeliveryStore,
  operation_id : String,
  generation : Int64,
  now : Int64,
) -> Operation {
  self.mutex.acquire()
  defer self.mutex.release()
  let index = self.index(operation_id, generation)
  let operation = self.operations[index]
  if operation.stage is (Stopping | Stopped | Expired) {
    return operation
  }
  let next = {
    ..operation,
    stage: Stopping,
    stop_requested_at_ms: Some(now),
    failure_code: None,
    generation: generation + 1L,
    updated_at_ms: now,
  }
  let operations = self.operations.copy()
  operations[index] = next
  self.commit(operations)
  next
}

///|
pub async fn DeliveryStore::operations(
  self : DeliveryStore,
) -> Array[Operation] {
  self.mutex.acquire()
  defer self.mutex.release()
  // JSON copy prevents callers mutating the stored node array outside a commit.
  @json.from_json(self.operations.to_json())
}

///|
pub async fn DeliveryStore::operation(
  self : DeliveryStore,
  operation_id : String,
) -> Operation? {
  for operation in self.operations() {
    if operation.operation_id == operation_id {
      return Some(operation)
    }
  }
  None
}

///|
/// Called by reconciliation before dispatching adapters. Expiry requests stop;
/// it never fabricates termination or releases the whole-node reservation.
pub async fn DeliveryStore::expire_due(
  self : DeliveryStore,
  now : Int64,
) -> Array[Operation] {
  self.mutex.acquire()
  defer self.mutex.release()
  let operations = self.operations.copy()
  let changed : Array[Operation] = []
  for index, operation in operations {
    if operation.intent.expires_at_ms <= now &&
      !(operation.stage is (Stopping | Stopped | Expired)) {
      let next = {
        ..operation,
        stage: Stopping,
        stop_requested_at_ms: Some(now),
        failure_code: None,
        generation: operation.generation + 1L,
        updated_at_ms: now,
      }
      operations[index] = next
      changed.push(next)
    }
  }
  if !changed.is_empty() {
    self.commit(operations)
  }
  changed
}
