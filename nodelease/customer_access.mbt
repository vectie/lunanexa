///|
/// Customer-visible reachability is deliberately coarser than the operator
/// node state. It is enough to explain whether an active machine is reporting
/// without exposing inventory, addresses, labels, taints, or topology.
pub(all) enum CustomerMachineReachability {
  Online
  Delayed
  Unknown
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A credential handoff is a reference to the deployment-owned issuer. It is
/// never the password, private key, SSH certificate, or internal secret-store
/// reference used by the node provisioner.
pub(all) enum CustomerCredentialHandoffState {
  Pending
  Available
  Recoverable
  Closed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CustomerCredentialHandoff {
  state : CustomerCredentialHandoffState
  handoff_ref : String?
  credential_kind : String
  valid_until_unix_ms : Int64
  raw_secret_included : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Tenant-safe exclusive-machine projection. `lease_ref` is the customer
/// record already returned by the enterprise portal, while `machine_ref` is a
/// lease-scoped display reference. Neither field reveals the physical node ID.
pub(all) struct CustomerExclusiveMachineView {
  version : String
  lease_ref : String
  machine_ref : String
  state : ExclusiveLeaseState
  generation : Int64
  username : String
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  updated_unix_ms : Int64
  reachability : CustomerMachineReachability
  last_seen_unix_ms : Int64?
  credential_handoff : CustomerCredentialHandoff
  can_terminate : Bool
  termination_confirmation : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CustomerExclusiveLeaseTerminationRequest {
  expected_generation : Int64
  confirmation : String
  reason : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn customer_termination_confirmation(lease_id : String) -> String {
  "TERMINATE \{lease_id}"
}

///|
pub fn customer_termination_target(
  state : ExclusiveLeaseState,
) -> ExclusiveLeaseState? {
  match state {
    Requested => Some(Cancelled)
    Reserved | Provisioning | Active => Some(Expiring)
    Quarantined => Some(RevokingAccess)
    Expiring | Draining | RevokingAccess | Sanitizing | Completed | Cancelled =>
      None
  }
}

///|
fn customer_reachability(
  heartbeat_unix_ms : Int64?,
  now_unix_ms : Int64,
  heartbeat_timeout_ms : Int64,
) -> CustomerMachineReachability {
  match heartbeat_unix_ms {
    Some(observed) if observed > 0L &&
      observed <= now_unix_ms &&
      now_unix_ms - observed <= heartbeat_timeout_ms => Online
    Some(observed) if observed > 0L && observed <= now_unix_ms => Delayed
    _ => Unknown
  }
}

///|
/// Builds a safe customer projection without copying `node_id` or
/// `access_credential_ref`. The handoff becomes available only while the lease
/// is active and unexpired. The handoff token is a non-secret, generation-bound
/// reference that an external credential authority may redeem after repeating
/// the caller's identity checks.
pub fn customer_machine_view(
  lease : ExclusiveNodeLease,
  heartbeat_unix_ms : Int64?,
  now_unix_ms : Int64,
  heartbeat_timeout_ms : Int64,
) -> CustomerExclusiveMachineView raise ExclusiveLeaseError {
  if now_unix_ms <= 0L || heartbeat_timeout_ms <= 0L {
    raise InvalidIntent("customer machine projection timing is invalid")
  }
  let handoff_state = if lease.state == Active &&
    now_unix_ms < lease.intent.expires_unix_ms {
    CustomerCredentialHandoffState::Available
  } else if lease.state == Requested ||
    lease.state == Reserved ||
    lease.state == Provisioning {
    Pending
  } else {
    Closed
  }
  let can_terminate = customer_termination_target(lease.state) is Some(_)
  {
    version: contract_version,
    lease_ref: lease.intent.lease_id,
    machine_ref: "assigned-machine:\{lease.intent.lease_id}",
    state: lease.state,
    generation: lease.generation,
    username: lease.intent.unix_username,
    starts_unix_ms: lease.intent.starts_unix_ms,
    expires_unix_ms: lease.intent.expires_unix_ms,
    updated_unix_ms: lease.updated_unix_ms,
    reachability: customer_reachability(
      heartbeat_unix_ms, now_unix_ms, heartbeat_timeout_ms,
    ),
    last_seen_unix_ms: heartbeat_unix_ms,
    credential_handoff: {
      state: handoff_state,
      // The broker reference is intentionally available only from the
      // subject-authorized credential endpoint, never this list projection.
      handoff_ref: None,
      credential_kind: "short-lived-ssh-certificate",
      valid_until_unix_ms: lease.intent.expires_unix_ms,
      raw_secret_included: false,
    },
    can_terminate,
    termination_confirmation: if can_terminate {
      Some(customer_termination_confirmation(lease.intent.lease_id))
    } else {
      None
    },
  }
}
