///|
pub struct ControlPlane {
  version : String
  epoch : Int64
  store : @store.MemoryStore
  enrollment : @node.EnrollmentService
}

///|
pub(all) suberror AuthenticationError {
  InvalidOperatorCredential
} derive(Debug, Eq)

///|
pub(all) struct OperatorIdentity {
  subject : String
  roles : Array[String]
  authenticated : Bool
} derive(Debug, Eq)

///|
pub fn authenticate_local_operator(
  subject : String,
  presented_token : String,
  expected_token_ref : String,
) -> OperatorIdentity raise AuthenticationError {
  if presented_token == "" || presented_token != expected_token_ref {
    raise InvalidOperatorCredential
  }
  { subject, roles: ["operator"], authenticated: true }
}

///|
pub fn ControlPlane::new(version : String, epoch : Int64) -> ControlPlane {
  {
    version,
    epoch,
    store: @store.MemoryStore::new(),
    enrollment: @node.EnrollmentService::new(),
  }
}

///|
pub fn ControlPlane::from_snapshot(
  version : String,
  epoch : Int64,
  snapshot : String,
) -> ControlPlane raise {
  {
    version,
    epoch,
    store: @store.MemoryStore::restore(snapshot),
    enrollment: @node.EnrollmentService::new(),
  }
}

///|
pub fn ControlPlane::snapshot(self : ControlPlane) -> String {
  self.store.snapshot()
}

///|
pub fn ControlPlane::store(self : ControlPlane) -> @store.MemoryStore {
  self.store
}

///|
pub fn ControlPlane::enrollment(self : ControlPlane) -> @node.EnrollmentService {
  self.enrollment
}

///|
pub fn ControlPlane::publish_assignment(
  self : ControlPlane,
  assignment : @contracts.DesiredAssignment,
) -> Unit {
  if assignment.controller_epoch == self.epoch {
    self.store.put_assignment(assignment)
  }
}

///|
pub fn ControlPlane::invoke(
  self : ControlPlane,
  runtime : @runtimes.FakeRuntime,
  request : @contracts.WorkloadEnvelope,
  accepted_unix_ms : Int64,
) -> @contracts.WorkloadResponse raise {
  @contracts.validate_workload(request)
  let output = runtime.invoke(request)
  let sequence = self.store.audit_events().length() + 1
  let receipt = "receipt:\{request.workload_id}"
  let event : @contracts.AuditEvent = {
    sequence: sequence.to_int64(),
    event_id: "invoke:\{request.workload_id}",
    timestamp_unix_ms: accepted_unix_ms + 2L,
    actor: "credential-scope:\{request.credential_scope}",
    policy_version: "policy-v1",
    action: "workload.invoke",
    target: request.model_selector,
    prior_state: "admitted",
    next_state: "succeeded",
    result: "accepted",
    correlation_receipt: receipt,
    previous_hash: if sequence == 1 {
      "genesis"
    } else {
      "audit-chain"
    },
    event_hash: "event-hash:\{sequence}",
  }
  self.store.append_audit(event)
  {
    version: @contracts.contract_version,
    workload_id: request.workload_id,
    state: Succeeded,
    output: Some(output),
    error: None,
    usage: { input_units: 1, output_units: 2, accelerator_ms: 4L, queue_ms: 0L },
    artifact_digest: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    runtime_version: self.version,
    timing: {
      accepted_unix_ms,
      started_unix_ms: accepted_unix_ms,
      first_output_unix_ms: accepted_unix_ms + 1L,
      completed_unix_ms: accepted_unix_ms + 2L,
    },
    retryable: false,
    audit_receipt: receipt,
  }
}
