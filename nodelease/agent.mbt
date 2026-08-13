///|
pub let agent_snapshot_schema_version : String = "lunanexa.exclusive-lease-agent.v1"

///|
pub(all) enum LeaseAgentAction {
  NoAction
  ProvisionAccess(
    lease_id~ : String,
    username~ : String,
    credential_ref~ : String,
    expires_unix_ms~ : Int64,
    generation~ : Int64
  )
  RevokeAccess(lease_id~ : String, username~ : String, generation~ : Int64)
  SanitizeLease(lease_id~ : String, username~ : String, generation~ : Int64)
  QuarantineNode(lease_id~ : String, username~ : String, generation~ : Int64)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum LeaseAgentState {
  Idle
  ProvisionPending
  AccessActive
  RevocationPending
  SanitizationPending
  Sanitized
  QuarantinedAgent
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct LeaseAgentSnapshot {
  schema_version : String
  node_id : String
  lease : ExclusiveNodeLease?
  state : LeaseAgentState
  observed_generation : Int64
  last_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct LeaseAgentGuard {
  mut snapshot : LeaseAgentSnapshot
}

///|
pub fn LeaseAgentGuard::new(node_id : String) -> LeaseAgentGuard {
  {
    snapshot: {
      schema_version: agent_snapshot_schema_version,
      node_id,
      lease: None,
      state: Idle,
      observed_generation: 0L,
      last_receipt: "agent:initialized",
    },
  }
}

///|
pub fn LeaseAgentGuard::from_snapshot(
  snapshot : LeaseAgentSnapshot,
) -> LeaseAgentGuard raise ExclusiveLeaseError {
  if snapshot.schema_version != agent_snapshot_schema_version ||
    snapshot.node_id == "" ||
    snapshot.observed_generation < 0L ||
    snapshot.last_receipt.length() > 1024 {
    raise InvalidIntent("invalid exclusive lease agent snapshot")
  }
  match snapshot.lease {
    None if snapshot.state != Idle || snapshot.observed_generation != 0L =>
      raise InvalidIntent("lease agent state is missing its lease")
    Some(lease) => {
      validate_intent(lease.intent)
      if lease.intent.node_id != snapshot.node_id ||
        lease.generation != snapshot.observed_generation {
        raise InvalidIntent("lease agent snapshot is misbound")
      }
    }
    None => ()
  }
  { snapshot, }
}

///|
pub fn LeaseAgentGuard::snapshot(self : LeaseAgentGuard) -> LeaseAgentSnapshot {
  self.snapshot
}

///|
pub fn LeaseAgentGuard::helper_authorization(
  self : LeaseAgentGuard,
  action : LeaseAgentAction,
  now_unix_ms : Int64,
) -> String? {
  match self.snapshot.lease {
    Some(lease) =>
      helper_authorization_from_transport_lease(lease, action, now_unix_ms)
    None => None
  }
}

///|
pub fn LeaseAgentGuard::observe_remote(
  self : LeaseAgentGuard,
  lease : ExclusiveNodeLease?,
  now_unix_ms : Int64,
) -> LeaseAgentAction raise ExclusiveLeaseError {
  match lease {
    Some(value) => {
      if self.snapshot.lease is Some(existing) &&
        existing.intent.lease_id != value.intent.lease_id {
        if self.snapshot.state != Idle && self.snapshot.state != Sanitized {
          raise StaleGeneration
        }
        self.snapshot = {
          ..self.snapshot,
          lease: Some(value),
          state: Idle,
          observed_generation: value.generation,
          last_receipt: value.authority_receipt,
        }
        return self.tick(now_unix_ms)
      }
      if value.intent.node_id != self.snapshot.node_id ||
        value.generation < self.snapshot.observed_generation {
        raise StaleGeneration
      }
      if value.generation > self.snapshot.observed_generation {
        self.snapshot = {
          ..self.snapshot,
          lease: Some(value),
          observed_generation: value.generation,
          last_receipt: value.authority_receipt,
        }
      } else if self.snapshot.lease is Some(existing) && existing != value {
        raise StaleGeneration
      }
    }
    None =>
      if self.snapshot.state == Sanitized {
        self.snapshot = {
          ..self.snapshot,
          lease: None,
          state: Idle,
          observed_generation: 0L,
          last_receipt: "agent:cleanup-complete",
        }
      }
  }
  self.tick(now_unix_ms)
}

///|
pub fn LeaseAgentGuard::tick(
  self : LeaseAgentGuard,
  now_unix_ms : Int64,
) -> LeaseAgentAction {
  guard self.snapshot.lease is Some(lease) else {
    self.snapshot = { ..self.snapshot, state: Idle }
    return NoAction
  }
  if self.snapshot.state == QuarantinedAgent {
    match lease.state {
      RevokingAccess => {
        self.snapshot = { ..self.snapshot, state: RevocationPending }
        return RevokeAccess(
          lease_id=lease.intent.lease_id,
          username=lease.intent.unix_username,
          generation=lease.generation,
        )
      }
      Sanitizing => {
        self.snapshot = { ..self.snapshot, state: SanitizationPending }
        return SanitizeLease(
          lease_id=lease.intent.lease_id,
          username=lease.intent.unix_username,
          generation=lease.generation,
        )
      }
      Quarantined => return NoAction
      _ =>
        return QuarantineNode(
          lease_id=lease.intent.lease_id,
          username=lease.intent.unix_username,
          generation=lease.generation,
        )
    }
  }
  if lease.state == Quarantined {
    self.snapshot = { ..self.snapshot, state: QuarantinedAgent }
    return QuarantineNode(
      lease_id=lease.intent.lease_id,
      username=lease.intent.unix_username,
      generation=lease.generation,
    )
  }
  let expired = now_unix_ms >= lease.intent.expires_unix_ms
  match self.snapshot.state {
    Idle | ProvisionPending if !expired &&
      (lease.state == Provisioning || lease.state == Active) => {
      self.snapshot = { ..self.snapshot, state: ProvisionPending }
      ProvisionAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        credential_ref=lease.intent.access_credential_ref,
        expires_unix_ms=lease.intent.expires_unix_ms,
        generation=lease.generation,
      )
    }
    Idle | ProvisionPending if expired ||
      lease.state == Expiring ||
      lease.state == Draining ||
      lease.state == RevokingAccess ||
      lease.state == Sanitizing => {
      self.snapshot = { ..self.snapshot, state: RevocationPending }
      RevokeAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    }
    AccessActive if expired ||
      lease.state == Expiring ||
      lease.state == Draining ||
      lease.state == RevokingAccess ||
      lease.state == Sanitizing ||
      lease.state == Completed ||
      lease.state == Cancelled => {
      self.snapshot = { ..self.snapshot, state: RevocationPending }
      RevokeAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    }
    RevocationPending =>
      RevokeAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    SanitizationPending if lease.state == RevokingAccess ||
      lease.state == Sanitizing =>
      SanitizeLease(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    SanitizationPending if lease.state == Expiring || lease.state == Draining => {
      self.snapshot = { ..self.snapshot, state: RevocationPending }
      RevokeAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    }
    _ => NoAction
  }
}

///|
fn action_name(action : LeaseAgentAction) -> String {
  match action {
    ProvisionAccess(..) => "provision"
    RevokeAccess(..) => "revoke"
    SanitizeLease(..) => "sanitize"
    QuarantineNode(..) => "quarantine"
    NoAction => "none"
  }
}

///|
pub fn LeaseAgentGuard::pending_helper_action(
  self : LeaseAgentGuard,
) -> LeaseAgentAction {
  guard self.snapshot.lease is Some(lease) else { return NoAction }
  let candidate = match self.snapshot.state {
    AccessActive =>
      ProvisionAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        credential_ref=lease.intent.access_credential_ref,
        expires_unix_ms=lease.intent.expires_unix_ms,
        generation=lease.generation,
      )
    SanitizationPending =>
      RevokeAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    Sanitized =>
      SanitizeLease(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    QuarantinedAgent =>
      QuarantineNode(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        generation=lease.generation,
      )
    Idle | ProvisionPending | RevocationPending => NoAction
  }
  if valid_helper_receipt(candidate, self.snapshot.last_receipt) {
    candidate
  } else {
    NoAction
  }
}

///|
pub fn LeaseAgentGuard::pending_observation(
  self : LeaseAgentGuard,
  observed_unix_ms : Int64,
) -> LeaseAgentObservation? {
  let action = self.pending_helper_action()
  guard action != NoAction && self.snapshot.lease is Some(lease) else {
    return None
  }
  Some({
    lease_id: lease.intent.lease_id,
    observed_generation: lease.generation,
    action: action_name(action),
    receipt: self.snapshot.last_receipt,
    observed_unix_ms,
  })
}

///|
pub fn LeaseAgentGuard::acknowledge_observation(
  self : LeaseAgentGuard,
  receipt : String,
) -> Unit raise ExclusiveLeaseError {
  guard self.pending_observation(0L) is Some(pending) &&
    pending.receipt == receipt else {
    raise StaleGeneration
  }
  self.snapshot = {
    ..self.snapshot,
    last_receipt: "controller:observation-accepted",
  }
}

///|
pub fn LeaseAgentGuard::record_success(
  self : LeaseAgentGuard,
  action : LeaseAgentAction,
  receipt : String,
) -> Unit raise ExclusiveLeaseError {
  if action != NoAction && !valid_helper_receipt(action, receipt) {
    raise InvalidIntent("lease helper receipt is invalid or misbound")
  }
  let next = match action {
    ProvisionAccess(..) => AccessActive
    RevokeAccess(..) => SanitizationPending
    SanitizeLease(..) => Sanitized
    QuarantineNode(..) => QuarantinedAgent
    NoAction => self.snapshot.state
  }
  self.snapshot = { ..self.snapshot, state: next, last_receipt: receipt }
}

///|
pub fn LeaseAgentGuard::record_failure(
  self : LeaseAgentGuard,
  _action : LeaseAgentAction,
) -> LeaseAgentAction {
  let lease_id = self.snapshot.lease
    .map(value => value.intent.lease_id)
    .unwrap_or("unknown")
  self.snapshot = {
    ..self.snapshot,
    state: QuarantinedAgent,
    last_receipt: "agent:helper-failed",
  }
  let username = self.snapshot.lease
    .map(value => value.intent.unix_username)
    .unwrap_or("invalid")
  QuarantineNode(
    lease_id~,
    username~,
    generation=self.snapshot.observed_generation,
  )
}
