///|
pub(all) struct StoreSnapshot {
  schema_version : String
  assignments : Array[@contracts.DesiredAssignment]
  audits : Array[@contracts.AuditEvent]
  heartbeats : Array[@contracts.NodeHeartbeat]
  workload_results : Array[WorkloadResultRecord]
  node_directives : Array[@contracts.NodeDirective]
  controller_epoch : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct WorkloadResultRecord {
  idempotency_key : String
  response : @contracts.WorkloadResponse
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct MemoryStore {
  assignments : Map[String, @contracts.DesiredAssignment]
  audits : Array[@contracts.AuditEvent]
  heartbeats : Map[String, @contracts.NodeHeartbeat]
  workload_by_id : Map[String, WorkloadResultRecord]
  workload_by_idempotency : Map[String, WorkloadResultRecord]
  node_directives : Map[String, @contracts.NodeDirective]
  mut controller_epoch : Int64
}

///|
pub fn MemoryStore::new() -> MemoryStore {
  {
    assignments: Map([]),
    audits: [],
    heartbeats: Map([]),
    workload_by_id: Map([]),
    workload_by_idempotency: Map([]),
    node_directives: Map([]),
    controller_epoch: 1L,
  }
}

///|
pub fn MemoryStore::controller_epoch(self : MemoryStore) -> Int64 {
  self.controller_epoch
}

///|
pub fn MemoryStore::set_controller_epoch(
  self : MemoryStore,
  epoch : Int64,
) -> Unit {
  self.controller_epoch = epoch
}

///|
pub fn MemoryStore::put_assignment(
  self : MemoryStore,
  assignment : @contracts.DesiredAssignment,
) -> Unit {
  self.assignments[assignment.assignment_id] = assignment
}

///|
pub fn MemoryStore::get_assignment(
  self : MemoryStore,
  assignment_id : String,
) -> @contracts.DesiredAssignment? {
  self.assignments.get(assignment_id)
}

///|
pub fn MemoryStore::remove_assignment(
  self : MemoryStore,
  assignment_id : String,
) -> Bool {
  let existed = self.assignments.contains(assignment_id)
  ignore(self.assignments.remove(assignment_id))
  existed
}

///|
pub fn MemoryStore::assignments(
  self : MemoryStore,
) -> Array[@contracts.DesiredAssignment] {
  [
    for _, assignment in self.assignments => assignment
  ]
}

///|
pub fn MemoryStore::append_audit(
  self : MemoryStore,
  event : @contracts.AuditEvent,
) -> Unit {
  self.audits.push(event)
}

///|
pub fn MemoryStore::audit_events(
  self : MemoryStore,
) -> Array[@contracts.AuditEvent] {
  self.audits.copy()
}

///|
pub fn MemoryStore::put_heartbeat(
  self : MemoryStore,
  heartbeat : @contracts.NodeHeartbeat,
) -> Unit {
  self.heartbeats[heartbeat.node_id] = heartbeat
}

///|
pub fn MemoryStore::heartbeats(
  self : MemoryStore,
) -> Array[@contracts.NodeHeartbeat] {
  [
    for _, heartbeat in self.heartbeats => heartbeat
  ]
}

///|
pub fn MemoryStore::put_node_directive(
  self : MemoryStore,
  directive : @contracts.NodeDirective,
) -> Unit {
  self.node_directives[directive.node_id] = directive
}

///|
pub fn MemoryStore::node_directive(
  self : MemoryStore,
  node_id : String,
) -> @contracts.NodeDirective? {
  self.node_directives.get(node_id)
}

///|
pub fn MemoryStore::node_directives(
  self : MemoryStore,
) -> Array[@contracts.NodeDirective] {
  [
    for _, directive in self.node_directives => directive
  ]
}

///|
pub fn MemoryStore::put_workload_result(
  self : MemoryStore,
  idempotency_key : String,
  response : @contracts.WorkloadResponse,
) -> Unit {
  let record : WorkloadResultRecord = { idempotency_key, response }
  self.workload_by_id[response.workload_id] = record
  self.workload_by_idempotency[idempotency_key] = record
}

///|
pub fn MemoryStore::workload_result(
  self : MemoryStore,
  workload_id : String,
) -> @contracts.WorkloadResponse? {
  self.workload_by_id.get(workload_id).map(record => record.response)
}

///|
pub fn MemoryStore::idempotent_result(
  self : MemoryStore,
  idempotency_key : String,
) -> @contracts.WorkloadResponse? {
  self.workload_by_idempotency
  .get(idempotency_key)
  .map(record => record.response)
}

///|
pub fn MemoryStore::workload_results(
  self : MemoryStore,
) -> Array[WorkloadResultRecord] {
  [
    for _, record in self.workload_by_id => record
  ]
}

///|
pub fn MemoryStore::snapshot(self : MemoryStore) -> String {
  let snapshot : StoreSnapshot = {
    schema_version: "lunanexa.store.v1",
    assignments: self.assignments(),
    audits: self.audit_events(),
    heartbeats: self.heartbeats(),
    workload_results: self.workload_results(),
    node_directives: self.node_directives(),
    controller_epoch: self.controller_epoch,
  }
  snapshot.to_json().stringify()
}

///|
pub fn MemoryStore::restore(json : String) -> MemoryStore raise {
  let snapshot : StoreSnapshot = @json.from_json(@json.parse(json))
  if snapshot.schema_version != "lunanexa.store.v1" {
    raise Failure::Failure("unsupported durable store schema")
  }
  let store = MemoryStore::new()
  store.set_controller_epoch(snapshot.controller_epoch)
  for assignment in snapshot.assignments {
    store.put_assignment(assignment)
  }
  for event in snapshot.audits {
    store.append_audit(event)
  }
  for heartbeat in snapshot.heartbeats {
    store.put_heartbeat(heartbeat)
  }
  for record in snapshot.workload_results {
    store.put_workload_result(record.idempotency_key, record.response)
  }
  for directive in snapshot.node_directives {
    store.put_node_directive(directive)
  }
  store
}

///|
pub impl MetadataStore for MemoryStore with fn put_assignment(self, assignment) {
  self.put_assignment(assignment)
}

///|
pub impl MetadataStore for MemoryStore with fn get_assignment(
  self,
  assignment_id,
) {
  self.get_assignment(assignment_id)
}

///|
pub impl MetadataStore for MemoryStore with fn append_audit(self, event) {
  self.append_audit(event)
}

///|
pub impl MetadataStore for MemoryStore with fn audit_events(self) {
  self.audit_events()
}
