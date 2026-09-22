///|
/// Executes an already-approved offline order against an existing commitment.
/// A proposed commitment still uses the normal procurement/four-eyes authority.
pub fn CommercialStore::activate_offline_commitment(
  self : CommercialStore,
  organization_id : String,
  commitment_id : String,
  actor_ref : String,
  now_unix_ms : Int64,
) -> CapacityCommitment raise CommercialError {
  guard self.commitments.get(commitment_id) is Some(current) else {
    raise NotFound("capacity commitment")
  }
  if current.organization_id != organization_id {
    raise TenantMismatch
  }
  if now_unix_ms < current.effective_from_unix_ms ||
    now_unix_ms >= current.effective_until_unix_ms {
    raise InvalidTransition("capacity commitment outside effective term")
  }
  match current.state {
    Proposed =>
      self.approve_commitment(
        organization_id, commitment_id, actor_ref, now_unix_ms,
      )
    Approved => {
      guard current.approved_by is Some(_) else {
        raise InvalidTransition("capacity commitment lacks approval")
      }
      let active = { ..current, state: ActiveCommitment, }
      self.commitments[commitment_id] = active
      active
    }
    ActiveCommitment => current
    _ => raise InvalidTransition("capacity commitment cannot activate")
  }
}

///|
/// Revocation is idempotent; the caller must bind this target to a persisted
/// commercial reversal before invoking this internal authority operation.
pub fn CommercialStore::revoke_offline_commitment(
  self : CommercialStore,
  organization_id : String,
  commitment_id : String,
) -> CapacityCommitment raise CommercialError {
  guard self.commitments.get(commitment_id) is Some(current) else {
    raise NotFound("capacity commitment")
  }
  if current.organization_id != organization_id {
    raise TenantMismatch
  }
  let revoked = { ..current, state: CancelledCommitment, }
  self.commitments[commitment_id] = revoked
  revoked
}
