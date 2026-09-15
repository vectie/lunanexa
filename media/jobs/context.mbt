///|
/// Placement metadata survives loss of the current endpoint. This method never
/// returns an address, credential, or permission to contact a retired instance.
///
/// ```mbt nocheck
/// let placement = store.context_for_binding(job.deployment_id)
/// ```
pub async fn JobStore::context_for_binding(
  self : JobStore,
  identity : String,
) -> ExecutionContext? {
  self.mutex.acquire()
  defer self.mutex.release()
  for job in self.jobs.values() {
    if job.deployment_id == identity && job.execution_context is Some(context) {
      return Some(context)
    }
  }
  None
}

///|
/// Backfill legacy records only from a currently verified immutable binding.
/// A conflicting placement is rejected, including during credential rotation.
///
/// ```mbt nocheck
/// store.remember_execution(binding_id, {
///   deployment_id: "deployment-a", generation: 1L, node_id: "node-a",
/// })
/// ```
pub async fn JobStore::remember_execution(
  self : JobStore,
  identity : String,
  context : ExecutionContext,
) -> Unit {
  if !@contracts.valid_identifier(identity) || !execution_context_valid(context) {
    raise InvalidInput
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let next = self.jobs.copy()
  let mut changed = false
  for id, job in self.jobs {
    if job.deployment_id != identity {
      continue
    }
    match job.execution_context {
      Some(previous) => if previous != context { raise Conflict }
      None => {
        next[id] = { ..job, execution_context: Some(context), }
        changed = true
      }
    }
  }
  if changed {
    (self.persist)(snapshot(next))
    self.jobs = next
  }
}
