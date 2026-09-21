///|
pub(all) suberror DurableStoreError {
  InvalidState(String)
} derive(Debug, Eq)

///|
pub extend DurableStoreError with Debug::{to_repr}

///|
pub extend DurableStoreError with Eq::{not_equal, equal}

///|
enum StorePersistence {
  StoreFile(String)
  StorePostgres(@database.PostgresDatabase, String, Int64)
}

///|
pub struct FileStore {
  persistence : StorePersistence
  mut state : MemoryStore
  mutex : @async.Mutex
  requires_epoch_advance : Bool
  mut controller_fenced : Bool
  mut leadership_lost : Bool
}

///|
async fn read_snapshot(path : String) -> MemoryStore {
  if !@fs.exists(path) {
    return MemoryStore::new()
  }
  let text = @fs.read_file(path).text()
  MemoryStore::restore(text) catch {
    error => raise DurableStoreError::InvalidState("\{Repr(error)}")
  }
}

///|
async fn write_snapshot(path : String, snapshot : String) -> Unit {
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
pub async fn FileStore::open(path : String) -> FileStore {
  let existed = @fs.exists(path)
  let state = read_snapshot(path)
  let store : FileStore = {
    persistence: StoreFile(path),
    state,
    mutex: Mutex(),
    requires_epoch_advance: existed,
    controller_fenced: false,
    leadership_lost: false,
  }
  if !existed {
    write_snapshot(path, state.snapshot())
  }
  store
}

///|
pub async fn FileStore::open_postgres(
  database : @database.PostgresDatabase,
  holder_id : String,
  fencing_token : Int64,
) -> FileStore {
  if !database.controller_leadership_is_current(holder_id, fencing_token) {
    raise DurableStoreError::InvalidState(
      "controller PostgreSQL leadership is not current",
    )
  }
  let payload = database.load_snapshot("control", "lunanexa.store.v1")
  let state = match payload {
    Some(snapshot) =>
      MemoryStore::restore(snapshot) catch {
        error => raise DurableStoreError::InvalidState("\{Repr(error)}")
      }
    None => MemoryStore::new()
  }
  let store : FileStore = {
    persistence: StorePostgres(database, holder_id, fencing_token),
    state,
    mutex: Mutex(),
    requires_epoch_advance: payload is Some(_),
    controller_fenced: false,
    leadership_lost: false,
  }
  if payload is None {
    database.save_opaque_snapshot(
      "control",
      "lunanexa.store.v1",
      state.snapshot(),
    )
  }
  store
}

///|
async fn FileStore::persist(self : FileStore, next : MemoryStore) -> Unit {
  if self.leadership_lost {
    raise DurableStoreError::InvalidState(
      "controller leadership was permanently lost",
    )
  }
  match self.persistence {
    StoreFile(path) => {
      let lock_file = @fs.open(
        "\{path}.lock",
        mode=ReadWrite,
        create_mode=OpenOrCreate,
        permission=0o600,
      )
      defer lock_file.close()
      lock_file.lock(Exclusive)
      defer lock_file.unlock()
      let durable = read_snapshot(path)
      if durable.controller_epoch() > next.controller_epoch() {
        self.state = durable
        self.leadership_lost = true
        raise DurableStoreError::InvalidState(
          "controller was fenced by a newer durable epoch",
        )
      }
      write_snapshot(path, next.snapshot())
    }
    StorePostgres(database, holder_id, fencing_token) => {
      if !database.controller_leadership_is_current(holder_id, fencing_token) {
        self.leadership_lost = true
        raise DurableStoreError::InvalidState(
          "controller PostgreSQL leadership was lost",
        )
      }
      database.save_opaque_snapshot(
        "control",
        "lunanexa.store.v1",
        next.snapshot(),
      )
    }
  }
}

///|
// The candidate owns independent maps. Readers cannot observe a mutation until
// its snapshot is durable, and cancellation always releases the process lock.
async fn FileStore::update(
  self : FileStore,
  change : async (MemoryStore) -> Unit,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  let next = self.state.candidate()
  change(next)
  self.persist(next)
  self.state = next
}

///|
pub async fn FileStore::put_assignment(
  self : FileStore,
  assignment : @contracts.DesiredAssignment,
) -> Unit {
  self.update(next => next.put_assignment(assignment))
}

///|
pub async fn FileStore::controller_epoch(self : FileStore) -> Int64 {
  self.mutex.acquire()
  let epoch = self.state.controller_epoch()
  self.mutex.release()
  epoch
}

///|
pub async fn FileStore::current_epoch_is_durable(self : FileStore) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.leadership_lost {
    return false
  }
  match self.persistence {
    StoreFile(path) => {
      let lock_file = @fs.open(
        "\{path}.lock",
        mode=ReadWrite,
        create_mode=OpenOrCreate,
        permission=0o600,
      )
      defer lock_file.close()
      lock_file.lock(Exclusive)
      defer lock_file.unlock()
      let durable = read_snapshot(path)
      durable.controller_epoch() == self.state.controller_epoch()
    }
    StorePostgres(database, holder_id, fencing_token) =>
      database.controller_leadership_is_current(holder_id, fencing_token) &&
      fencing_token == self.state.controller_epoch()
  }
}

///|
pub async fn FileStore::fence_controller(
  self : FileStore,
  epoch : Int64,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.leadership_lost ||
    self.controller_fenced ||
    epoch <= 0L ||
    epoch < self.state.controller_epoch() ||
    (self.requires_epoch_advance && epoch <= self.state.controller_epoch()) {
    raise DurableStoreError::InvalidState("controller epoch is stale")
  }
  if epoch > self.state.controller_epoch() {
    let next = self.state.candidate()
    next.set_controller_epoch(epoch)
    self.persist(next)
    self.state = next
  }
  self.controller_fenced = true
}

///|
pub async fn FileStore::put_node_directive(
  self : FileStore,
  directive : @contracts.NodeDirective,
) -> Unit {
  self.update(next => next.put_node_directive(directive))
}

///|
pub async fn FileStore::node_directive(
  self : FileStore,
  node_id : String,
) -> @contracts.NodeDirective? {
  self.mutex.acquire()
  let directive = self.state.node_directive(node_id)
  self.mutex.release()
  directive
}

///|
pub async fn FileStore::commit_node_directive(
  self : FileStore,
  directive : @contracts.NodeDirective,
  audit : @contracts.AuditEvent,
) -> Unit {
  self.update(next => {
    next.put_node_directive(directive)
    next.append_audit(audit)
  })
}

///|
pub async fn FileStore::commit_assignment(
  self : FileStore,
  assignment : @contracts.DesiredAssignment,
  audit : @contracts.AuditEvent,
) -> Unit {
  self.update(next => {
    next.put_assignment(assignment)
    next.append_audit(audit)
  })
}

///|
pub async fn FileStore::commit_assignment_removal(
  self : FileStore,
  assignment_id : String,
  audit : @contracts.AuditEvent,
) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  let next = self.state.candidate()
  let removed = next.remove_assignment(assignment_id)
  if !removed {
    return false
  }
  next.append_audit(audit)
  self.persist(next)
  self.state = next
  true
}

///|
pub async fn FileStore::append_audit(
  self : FileStore,
  event : @contracts.AuditEvent,
) -> Unit {
  self.update(next => next.append_audit(event))
}

///|
pub async fn FileStore::assignment(
  self : FileStore,
  assignment_id : String,
) -> @contracts.DesiredAssignment? {
  self.mutex.acquire()
  let value = self.state.get_assignment(assignment_id)
  self.mutex.release()
  value
}

///|
pub async fn FileStore::assignments(
  self : FileStore,
) -> Array[@contracts.DesiredAssignment] {
  self.mutex.acquire()
  let values = self.state.assignments()
  self.mutex.release()
  values
}

///|
pub async fn FileStore::audit_events(
  self : FileStore,
) -> Array[@contracts.AuditEvent] {
  self.mutex.acquire()
  let values = self.state.audit_events()
  self.mutex.release()
  values
}

///|
pub async fn FileStore::put_heartbeat(
  self : FileStore,
  heartbeat : @contracts.NodeHeartbeat,
) -> Unit {
  self.update(next => next.put_heartbeat(heartbeat))
}

///|
pub async fn FileStore::heartbeats(
  self : FileStore,
) -> Array[@contracts.NodeHeartbeat] {
  self.mutex.acquire()
  let values = self.state.heartbeats()
  self.mutex.release()
  values
}

///|
pub async fn FileStore::put_workload_result(
  self : FileStore,
  idempotency_key : String,
  response : @contracts.WorkloadResponse,
) -> Unit {
  self.update(next => next.put_workload_result(idempotency_key, response))
}

///|
pub async fn FileStore::commit_workload(
  self : FileStore,
  idempotency_key : String,
  response : @contracts.WorkloadResponse,
  audit : @contracts.AuditEvent,
) -> Unit {
  self.update(next => {
    next.put_workload_result(idempotency_key, response)
    next.append_audit(audit)
  })
}

///|
pub async fn FileStore::workload_result(
  self : FileStore,
  workload_id : String,
) -> @contracts.WorkloadResponse? {
  self.mutex.acquire()
  let value = self.state.workload_result(workload_id)
  self.mutex.release()
  value
}

///|
pub async fn FileStore::idempotent_result(
  self : FileStore,
  idempotency_key : String,
) -> @contracts.WorkloadResponse? {
  self.mutex.acquire()
  let value = self.state.idempotent_result(idempotency_key)
  self.mutex.release()
  value
}

///|
pub async fn FileStore::backup_snapshot(self : FileStore) -> String {
  self.mutex.acquire()
  let value = self.state.snapshot()
  self.mutex.release()
  value
}
