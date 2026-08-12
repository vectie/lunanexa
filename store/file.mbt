///|
pub(all) suberror DurableStoreError {
  InvalidState(String)
} derive(Debug, Eq)

///|
pub struct FileStore {
  path : String
  mut state : MemoryStore
  mutex : @async.Mutex
  requires_epoch_advance : Bool
  mut controller_fenced : Bool
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
    path,
    state,
    mutex: Mutex(),
    requires_epoch_advance: existed,
    controller_fenced: false,
  }
  if !existed {
    write_snapshot(path, state.snapshot())
  }
  store
}

///|
async fn FileStore::persist(self : FileStore) -> Unit {
  let lock_file = @fs.open(
    "\{self.path}.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock_file.close()
  lock_file.lock(Exclusive)
  defer lock_file.unlock()
  let durable = read_snapshot(self.path)
  if durable.controller_epoch() > self.state.controller_epoch() {
    self.state = durable
    raise DurableStoreError::InvalidState(
      "controller was fenced by a newer durable epoch",
    )
  }
  write_snapshot(self.path, self.state.snapshot())
}

///|
pub async fn FileStore::put_assignment(
  self : FileStore,
  assignment : @contracts.DesiredAssignment,
) -> Unit {
  self.mutex.acquire()
  try {
    self.state.put_assignment(assignment)
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
  let lock_file = @fs.open(
    "\{self.path}.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock_file.close()
  lock_file.lock(Exclusive)
  defer lock_file.unlock()
  let durable = read_snapshot(self.path)
  durable.controller_epoch() == self.state.controller_epoch()
}

///|
pub async fn FileStore::fence_controller(
  self : FileStore,
  epoch : Int64,
) -> Unit {
  self.mutex.acquire()
  if self.controller_fenced ||
    epoch <= 0L ||
    epoch < self.state.controller_epoch() ||
    (self.requires_epoch_advance && epoch <= self.state.controller_epoch()) {
    self.mutex.release()
    raise DurableStoreError::InvalidState("controller epoch is stale")
  }
  if epoch > self.state.controller_epoch() {
    self.state.set_controller_epoch(epoch)
    try self.persist() catch {
      error => {
        self.mutex.release()
        raise error
      }
    } noraise {
      _ => ()
    }
  }
  self.controller_fenced = true
  self.mutex.release()
}

///|
pub async fn FileStore::put_node_directive(
  self : FileStore,
  directive : @contracts.NodeDirective,
) -> Unit {
  self.mutex.acquire()
  try {
    self.state.put_node_directive(directive)
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
  self.mutex.acquire()
  try {
    self.state.put_node_directive(directive)
    self.state.append_audit(audit)
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
pub async fn FileStore::commit_assignment(
  self : FileStore,
  assignment : @contracts.DesiredAssignment,
  audit : @contracts.AuditEvent,
) -> Unit {
  self.mutex.acquire()
  try {
    self.state.put_assignment(assignment)
    self.state.append_audit(audit)
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
pub async fn FileStore::commit_assignment_removal(
  self : FileStore,
  assignment_id : String,
  audit : @contracts.AuditEvent,
) -> Bool {
  self.mutex.acquire()
  let removed = self.state.remove_assignment(assignment_id)
  if !removed {
    self.mutex.release()
    return false
  }
  try {
    self.state.append_audit(audit)
    self.persist()
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  true
}

///|
pub async fn FileStore::append_audit(
  self : FileStore,
  event : @contracts.AuditEvent,
) -> Unit {
  self.mutex.acquire()
  try {
    self.state.append_audit(event)
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
  self.mutex.acquire()
  try {
    self.state.put_heartbeat(heartbeat)
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
  self.mutex.acquire()
  try {
    self.state.put_workload_result(idempotency_key, response)
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
pub async fn FileStore::commit_workload(
  self : FileStore,
  idempotency_key : String,
  response : @contracts.WorkloadResponse,
  audit : @contracts.AuditEvent,
) -> Unit {
  self.mutex.acquire()
  try {
    self.state.put_workload_result(idempotency_key, response)
    self.state.append_audit(audit)
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
