///|
/// Saves the operator policy under the account-store lock. After the first
/// registration, only admission and request budgets can change; dates, model,
/// request counts and machine scope stay fixed.
pub async fn AccountStore::put_event(
  self : AccountStore,
  policy : @event_trial.Policy,
) -> @event_trial.Policy {
  if !policy.valid() {
    raise InvalidInput("invalid event trial policy")
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let previous = self.events.copy()
  let previous_mode = self.event_mode_selected
  errdefer {
    self.events = previous
    self.event_mode_selected = previous_mode
  }
  if self.trials.values().any(t => t.event_id == Some(policy.event_id)) {
    guard self.events.get(policy.event_id) is Some(existing) &&
      {
        ..existing,
        registration_open: policy.registration_open,
        max_output_tokens: policy.max_output_tokens,
        max_input_bytes: policy.max_input_bytes,
      } ==
      policy else {
      raise AlreadyExists("event policy is immutable after registration")
    }
  }
  if policy.registration_open &&
    self.events
    .values()
    .any(other => {
      other.event_id != policy.event_id &&
      other.registration_open &&
      policy.overlaps(other)
    }) {
    raise AlreadyExists("another event has overlapping registration")
  }
  self.events[policy.event_id] = policy
  if policy.registration_open {
    self.event_mode_selected = true
  }
  self.persist()
  policy
}

///|
/// A tenant's event association is derived from durable grants, never headers.
pub async fn AccountStore::event_for_tenant(
  self : AccountStore,
  tenant_ref : String,
) -> @event_trial.Policy? {
  self.mutex.acquire()
  defer self.mutex.release()
  match self.trials.values().find_first(t => t.tenant_ref == tenant_ref) {
    Some({ event_id: Some(id), .. }) => self.events.get(id)
    _ => None
  }
}
