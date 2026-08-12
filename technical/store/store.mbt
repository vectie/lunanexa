///|
pub let snapshot_schema_version : String = "lunanexa.technical.operations.v1"

///|
pub(all) struct TechnicalSnapshot {
  schema_version : String
  prewarm_operations : Array[@technical.PrewarmOperation]
  consumed_transfer_nonces : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror TechnicalStoreError {
  InvalidSnapshot(String)
  OperationConflict(String)
  OperationNotFound(String)
} derive(Debug, Eq)

///|
enum TechnicalPersistence {
  TechnicalFile(String)
  TechnicalPostgres(@database.PostgresDatabase)
}

///|
pub struct TechnicalStore {
  persistence : TechnicalPersistence
  mut prewarm : Map[String, @technical.PrewarmOperation]
  consumed_nonces : Map[String, Unit]
  mutex : @async.Mutex
}

///|
fn TechnicalStore::snapshot_unlocked(
  self : TechnicalStore,
) -> TechnicalSnapshot {
  let operations = self.prewarm.values().to_array()
  operations.sort_by_key(value => value.intent.operation_id)
  let nonces = self.consumed_nonces.keys().to_array()
  nonces.sort()
  {
    schema_version: snapshot_schema_version,
    prewarm_operations: operations,
    consumed_transfer_nonces: nonces,
  }
}

///|
async fn write_file(path : String, snapshot : TechnicalSnapshot) -> Unit {
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
fn TechnicalStore::restore(
  self : TechnicalStore,
  snapshot : TechnicalSnapshot,
) -> Unit raise TechnicalStoreError {
  if snapshot.schema_version != snapshot_schema_version {
    raise InvalidSnapshot("unsupported technical snapshot")
  }
  for operation in snapshot.prewarm_operations {
    if self.prewarm.contains(operation.intent.operation_id) {
      raise InvalidSnapshot("duplicate prewarm operation")
    }
    self.prewarm[operation.intent.operation_id] = operation
  }
  for nonce in snapshot.consumed_transfer_nonces {
    if nonce.length() < 16 ||
      nonce.length() > 128 ||
      self.consumed_nonces.contains(nonce) {
      raise InvalidSnapshot("invalid consumed transfer nonce")
    }
    self.consumed_nonces[nonce] = ()
  }
}

///|
pub async fn TechnicalStore::open(path : String) -> TechnicalStore {
  let store : TechnicalStore = {
    persistence: TechnicalFile(path),
    prewarm: Map([]),
    consumed_nonces: Map([]),
    mutex: Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : TechnicalSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error => raise InvalidSnapshot("\{Repr(error)}")
    }
    store.restore(snapshot)
  } else {
    write_file(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn TechnicalStore::open_postgres(
  database : @database.PostgresDatabase,
) -> TechnicalStore {
  let store : TechnicalStore = {
    persistence: TechnicalPostgres(database),
    prewarm: Map([]),
    consumed_nonces: Map([]),
    mutex: Mutex(),
  }
  match
    database.load_snapshot("technical_operations", snapshot_schema_version) {
    Some(payload) => {
      let snapshot : TechnicalSnapshot = @json.from_json(@json.parse(payload)) catch {
        error => raise InvalidSnapshot("\{Repr(error)}")
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "technical_operations",
        snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn TechnicalStore::persist(self : TechnicalStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    TechnicalFile(path) => write_file(path, snapshot)
    TechnicalPostgres(database) =>
      database.save_opaque_snapshot(
        "technical_operations",
        snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
pub async fn TechnicalStore::begin_prewarm(
  self : TechnicalStore,
  intent : @technical.PrewarmIntent,
  now_unix_ms : Int64,
) -> @technical.PrewarmDecision {
  self.mutex.acquire()
  let previous = self.prewarm.copy()
  try {
    let decision = @technical.begin_prewarm(intent, now_unix_ms)
    match self.prewarm.get(intent.operation_id) {
      Some(existing) if existing.intent == intent => {
        self.mutex.release()
        return Accepted(existing)
      }
      Some(_) => raise OperationConflict(intent.operation_id)
      None => ()
    }
    match decision {
      Accepted(candidate) => {
        self.prewarm[intent.operation_id] = candidate
        self.persist()
      }
      Rejected(_) => ()
    }
    self.mutex.release()
    decision
  } catch {
    error => {
      self.prewarm = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn TechnicalStore::advance_prewarm(
  self : TechnicalStore,
  expected : @technical.PrewarmOperation,
  event : @technical.PrewarmEvent,
  now_unix_ms : Int64,
) -> @technical.PrewarmDecision {
  self.mutex.acquire()
  let previous = self.prewarm.copy()
  try {
    guard self.prewarm.get(expected.intent.operation_id) is Some(current) else {
      raise OperationNotFound(expected.intent.operation_id)
    }
    if current != expected {
      raise OperationConflict(expected.intent.operation_id)
    }
    let advanced = @technical.advance_prewarm(current, event, now_unix_ms)
    match advanced {
      Accepted(operation) => {
        self.prewarm[current.intent.operation_id] = operation
        self.persist()
      }
      Rejected(_) => ()
    }
    self.mutex.release()
    advanced
  } catch {
    error => {
      self.prewarm = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn TechnicalStore::validate_and_consume_transfer(
  self : TechnicalStore,
  grant : @technical.TransferGrant,
  requested : @technical.TransferGrantUse,
  authenticity : @technical.GrantAuthenticity,
  now_unix_ms : Int64,
  maximum_lifetime_ms : Int64,
) -> @technical.TransferGrantDecision {
  self.mutex.acquire()
  try {
    let decision = @technical.validate_transfer_grant(
      grant,
      requested,
      authenticity,
      self.consumed_nonces.keys().to_array(),
      now_unix_ms,
      maximum_lifetime_ms,
    )
    match decision {
      Accepted(consumed_nonce~) => {
        self.consumed_nonces[consumed_nonce] = ()
        self.persist() catch {
          error => {
            ignore(self.consumed_nonces.remove(consumed_nonce))
            raise error
          }
        }
      }
      Rejected(_) => ()
    }
    self.mutex.release()
    decision
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn TechnicalStore::snapshot(
  self : TechnicalStore,
) -> TechnicalSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}
