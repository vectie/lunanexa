///|
pub fn AcceptedTermination::reference(self : AcceptedTermination) -> String {
  "runtime-termination-" +
  digest(ToJson::to_json(self).stringify())[7:].to_owned()
}

///|
pub async fn JobStore::termination_for_context(
  self : JobStore,
  context : ExecutionContext,
) -> AcceptedTermination? {
  self.mutex.acquire()
  defer self.mutex.release()
  self.terminations
  .iter()
  .find_first(value => {
    context.node_id == value.node_id &&
    context.deployment_id == value.evidence.deployment_id &&
    context.generation == value.evidence.generation &&
    context.instance_id == Some(value.evidence.instance_id)
  })
}

///|
fn termination_valid(value : AcceptedTermination) -> Bool {
  let entry = value.evidence
  @contracts.valid_identifier(value.node_id) &&
  @contracts.valid_identifier(entry.assignment_id) &&
  @contracts.valid_identifier(entry.deployment_id) &&
  entry.generation > 0L &&
  entry.controller_epoch >= 0L &&
  entry.observed_unix_ms >= 0L &&
  @contracts.valid_sha256_digest("sha256:" + entry.instance_id) &&
  @contracts.valid_sha256_digest(entry.artifact_digest) &&
  @contracts.valid_sha256_digest(entry.image_digest)
}

///|
/// Persist independently verified evidence before acknowledging the node.
/// Authentication and original-assignment verification belong to the caller.
/// Reusing an incarnation with changed evidence is a conflict, not an update.
pub async fn JobStore::accept_termination(
  self : JobStore,
  value : AcceptedTermination,
) -> Unit {
  if !termination_valid(value) {
    raise InvalidInput
  }
  self.mutex.acquire()
  defer self.mutex.release()
  for previous in self.terminations {
    if previous.node_id == value.node_id &&
      previous.evidence.instance_id == value.evidence.instance_id {
      if previous != value {
        raise Conflict
      }
      return
    }
  }
  if self.terminations.length() >= 10000 {
    raise CapacityExceeded
  }
  let next = self.terminations.copy()
  next.push(value)
  (self.persist)(snapshot(self.jobs, next))
  self.terminations = next
}
