///|
/// Stop the workload without deleting its status object. Kubelet owns actual
/// process termination; a deadline, deletion intent or missing Pod is not proof.
/// Keep the Pod until all previously published instances have durable reports.
async fn RuntimeSupervisor::prepare_pod_deletion(
  self : RuntimeSupervisor,
  record : RuntimeRecord,
  pod : Json,
  path : String,
  uid : String,
) -> Bool {
  if !(pod is { "status": { "phase": "Failed" | "Succeeded", .. }, .. }) {
    if pod is { "metadata": { "deletionTimestamp": String(_), .. }, .. } ||
      pod is { "spec": { "activeDeadlineSeconds": 1, .. }, .. } {
      return false
    }
    let patch : Json = [
      { "op": "test", "path": "/metadata/uid", "value": uid },
      { "op": "add", "path": "/spec/activeDeadlineSeconds", "value": 1 },
    ]
    let (status, _) = (self.transport)("PATCH", path, Some(patch))
    if status == 409 || status == 422 {
      raise LifecycleError::OwnershipConflict
    }
    if status != 200 {
      raise LifecycleError::ApiRejected(status)
    }
    return false
  }
  let known = record.observed_containers.unwrap_or([])
  if !known.is_empty() {
    // Old journals may lack the signed assignment. A later verified assignment
    // can backfill it, but no fabricated report or destructive cleanup is safe.
    guard record.original_assignment is Some(assignment) else { return false }
    ignore(self.observation(record, assignment, pod))
    if record.observed_containers
      .unwrap_or([])
      .any(container => container.termination_observed_unix_ms is None) {
      return false
    }
  }
  // No route was ever published for an unobserved container, hence no job can
  // bind to it. Otherwise observation above persisted every exit in the outbox.
  true
}

///|
/// Restrict the transport's new PATCH authority to stopping one exact Pod.
/// It cannot alter images, identities, secrets, policies or arbitrary fields.
fn valid_stop_patch(path : String, body : Json?) -> Bool {
  path.contains("/pods/") &&
  body
  is Some(
    [
      { "op": "test", "path": "/metadata/uid", "value": String(uid), .. },
      { "op": "add", "path": "/spec/activeDeadlineSeconds", "value": 1, .. },
    ]
  ) &&
  uid != "" &&
  uid.length() <= 256
}
