///|
/// Internal control-plane primitive: the caller must independently authenticate
/// and verify runtime termination evidence. An HTTP 404 or replacement endpoint
/// is not such evidence. Never expose this as a customer-asserted transition.
pub async fn JobStore::acknowledge_instance_termination(
  self : JobStore,
  id : String,
  owner : Owner,
  expected_binding : String,
  expected_context : ExecutionContext,
  evidence_ref : String,
  observed_unix_ms : Int64,
  now : Int64,
) -> StoredJob {
  if !execution_context_valid(expected_context) ||
    expected_context.instance_id is None ||
    !@contracts.valid_identifier(evidence_ref) ||
    observed_unix_ms > now {
    raise InvalidInput
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let job = self.owned(id, owner)
  if job.deployment_id != expected_binding ||
    job.execution_context != Some(expected_context) ||
    observed_unix_ms < job.created_unix_ms {
    raise Conflict
  }
  if job.termination_evidence_ref is Some(previous) {
    if previous != evidence_ref ||
      job.termination_observed_unix_ms != Some(observed_unix_ms) {
      raise Conflict
    }
    return job
  }
  // Preserve completed/previously terminal outcomes; never turn a lost worker
  // into a successful generation or overwrite prior settlement.
  if job.execution_terminal || now < job.updated_unix_ms || job.state == Intent {
    raise InvalidTransition
  }
  self.commit({
    ..job,
    state: if job.expiry_requested {
      Expired
    } else if job.state == Cancelling {
      Cancelled
    } else {
      Failed
    },
    execution_terminal: true,
    terminal_unix_ms: Some(now),
    updated_unix_ms: now,
    termination_evidence_ref: Some(evidence_ref),
    termination_observed_unix_ms: Some(observed_unix_ms),
  })
}
