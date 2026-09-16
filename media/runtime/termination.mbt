///|
/// Trusted control-plane recovery only. The caller must authenticate and verify
/// original-instance termination; never pass a customer assertion or infer this
/// from a missing provider URL. Persist the terminal evidence before settlement.
pub async fn VideoRuntime::reconcile_verified_termination(
  self : VideoRuntime,
  id : String,
  owner : @jobs.Owner,
  expected_binding : String,
  context : @jobs.ExecutionContext,
  evidence_ref : String,
  observed_unix_ms : Int64,
) -> @jobs.StoredJob {
  let terminal = self.store.acknowledge_instance_termination(
    id,
    owner,
    expected_binding,
    context,
    evidence_ref,
    observed_unix_ms,
    (self.now)(),
  )
  self.record_terminal(terminal)
}
