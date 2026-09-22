///|
/// A technical run does not mutate the undertaking into an effective contract.
/// Every documentary gate consults the same expiring, deployment-bound waiver.
fn ApiService::technical_documentary_waiver_allowed(
  self : ApiService,
  order : @offline.CommercialOrder,
  now : Int64,
) -> Bool {
  guard order.technical_acceptance_waiver is Some(w) &&
    self.technical_acceptance_authorization is Some(scope) &&
    scope.order_binding == w.order_binding &&
    now >= w.issued_unix_ms &&
    now < w.expires_unix_ms &&
    self.technical_scope_allows(
      order,
      w.user_authorization_ref,
      w.expires_unix_ms,
      now,
    ) else {
    return false
  }
  @offline.validate_technical_waiver(order) catch {
    _ => return false
  }
  true
}

///|
/// Recover only the persisted target, even after deployment authorization was
/// removed. Machine recovery is pending until the real node reports cleanup;
/// recording an Expiring intention must not pretend access is revoked.
async fn ApiService::compensate_technical_target(
  self : ApiService,
  order : @offline.CommercialOrder,
  request : @offline.EntitlementActivation,
  now : Int64,
) -> Bool {
  guard order.technical_acceptance_waiver is Some(w) &&
    request.kind == w.entitlement_kind() &&
    request.authority_target_ref == w.authority_target_ref else {
    return false
  }
  match request.kind {
    WorkspaceLease => {
      guard self.workspace_directory is Some(directory) else { return false }
      if directory.snapshot(now).leases
        .iter()
        .find_first(l => l.lease_id == w.authority_target_ref)
        is Some(lease) {
        guard lease.tenant_ref == order.tenant_ref &&
          lease.subject_ref == order.purchaser_subject_ref else {
          return false
        }
        if lease.state != Revoked && lease.state != Expired {
          ignore(directory.revoke_lease(lease.lease_id, now))
        }
      }
      true
    }
    ExclusiveMachineLease => {
      guard self.exclusive_lease_store is Some(leases) &&
        leases.lease(w.authority_target_ref) is Some(lease) &&
        lease.intent.subject_ref == order.purchaser_subject_ref else {
        return false
      }
      let next : @nodelease.ExclusiveLeaseState? = match lease.state {
        Requested => Some(Cancelled)
        Reserved | Provisioning | Active => Some(Expiring)
        Quarantined => Some(RevokingAccess)
        _ => None
      }
      let current = match next {
        None => lease
        Some(state) =>
          leases.transition(
            lease.intent.lease_id,
            {
              expected_generation: lease.generation,
              state,
              evidence_receipt: offline_execution_receipt(
                "technical-recovery",
                request.activation_id,
                "Requested",
              ),
            },
            now,
          )
      }
      self.publish_exclusive_lease_directive(
        current,
        directive_state_for_exclusive_lease(current.state),
      )
      current.state == Completed || current.state == Cancelled
    }
    CapacityCommitment => {
      self.commercial_mutex.acquire()
      defer self.commercial_mutex.release()
      let before = self.commercial_store.durable_snapshot()
      errdefer self.commercial_store.replace_from_durable_snapshot(before)
      guard self.commercial_store.snapshot(order.organization_id).commitments.any(c => {
          c.commitment_id == w.authority_target_ref &&
          c.organization_id == order.organization_id
        },
      ) else {
        return false
      }
      ignore(
        self.commercial_store.revoke_offline_commitment(
          order.organization_id,
          w.authority_target_ref,
        ),
      )
      self.persist_commercial_state()
      true
    }
  }
}

///|
async fn ApiService::technical_target_expiry(
  self : ApiService,
  order : @offline.CommercialOrder,
  target : String,
) -> Int64? {
  let kind = self.technical_acceptance_authorization.map_or(
    @offline.WorkspaceLease,
    s => s.order_binding.map_or(WorkspaceLease, b => b.entitlement_kind),
  )
  match kind {
    WorkspaceLease => {
      guard self.workspace_directory is Some(directory) else { return None }
      directory.snapshot(@async.now()).leases
      .iter()
      .find_first(l => {
        l.lease_id == target &&
        l.tenant_ref == order.tenant_ref &&
        l.subject_ref == order.purchaser_subject_ref
      })
      .map(l => l.expires_unix_ms)
    }
    ExclusiveMachineLease => {
      guard self.exclusive_lease_store is Some(leases) &&
        leases.lease(target) is Some(l) &&
        l.intent.subject_ref == order.purchaser_subject_ref else {
        return None
      }
      Some(l.intent.expires_unix_ms)
    }
    CapacityCommitment =>
      self.commercial_store.snapshot(order.organization_id).commitments
      .iter()
      .find_first(c => {
        c.commitment_id == target && c.organization_id == order.organization_id
      })
      .map(c => c.effective_until_unix_ms)
  }
}
