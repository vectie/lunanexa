///|
pub let agent_snapshot_schema_version : String = "lunanexa.exclusive-lease-agent.v1"

///|
pub(all) enum LeaseAgentAction {
  NoAction
  ProvisionAccess(
    lease_id~ : String,
    username~ : String,
    credential_ref~ : String,
    expires_unix_ms~ : Int64
  )
  RevokeAccess(lease_id~ : String, username~ : String)
  SanitizeLease(lease_id~ : String, username~ : String)
  QuarantineNode(lease_id~ : String)
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
    snapshot.observed_generation < 0L {
    raise InvalidIntent("invalid exclusive lease agent snapshot")
  }
  { snapshot, }
}

///|
pub fn LeaseAgentGuard::snapshot(self : LeaseAgentGuard) -> LeaseAgentSnapshot {
  self.snapshot
}

///|
pub fn LeaseAgentGuard::observe_remote(
  self : LeaseAgentGuard,
  lease : ExclusiveNodeLease?,
  now_unix_ms : Int64,
) -> LeaseAgentAction raise ExclusiveLeaseError {
  match lease {
    Some(value) => {
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
    None => ()
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
  if self.snapshot.state == QuarantinedAgent || lease.state == Quarantined {
    self.snapshot = { ..self.snapshot, state: QuarantinedAgent }
    return QuarantineNode(lease_id=lease.intent.lease_id)
  }
  let expired = now_unix_ms >= lease.intent.expires_unix_ms
  match self.snapshot.state {
    Idle | ProvisionPending if !expired &&
      (
        lease.state == Reserved ||
        lease.state == Provisioning ||
        lease.state == Active
      ) => {
      self.snapshot = { ..self.snapshot, state: ProvisionPending }
      ProvisionAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
        credential_ref=lease.intent.access_credential_ref,
        expires_unix_ms=lease.intent.expires_unix_ms,
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
      )
    }
    RevocationPending =>
      RevokeAccess(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
      )
    SanitizationPending =>
      SanitizeLease(
        lease_id=lease.intent.lease_id,
        username=lease.intent.unix_username,
      )
    _ => NoAction
  }
}

///|
pub fn LeaseAgentGuard::record_success(
  self : LeaseAgentGuard,
  action : LeaseAgentAction,
  receipt : String,
) -> Unit raise ExclusiveLeaseError {
  if receipt == "" || receipt.length() > 512 || receipt.contains_char('\n') {
    raise InvalidIntent("invalid lease agent receipt")
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
  action : LeaseAgentAction,
) -> LeaseAgentAction {
  let lease_id = self.snapshot.lease
    .map(value => value.intent.lease_id)
    .unwrap_or("unknown")
  self.snapshot = {
    ..self.snapshot,
    state: QuarantinedAgent,
    last_receipt: "agent:helper-failed:\{Repr(action)}",
  }
  QuarantineNode(lease_id~)
}
