///|
pub fn valid_unix_username(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 32 &&
  value != "root" &&
  value != "daemon" &&
  value != "lunanexa" &&
  value[0] >= 'a' &&
  value[0] <= 'z' &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= '0' && character <= '9') ||
    character == '_' ||
    character == '-'
  })
}

///|
pub fn valid_access_credential_ref(value : String) -> Bool {
  @contracts.valid_identifier(value, maximum_length=512) &&
  (value.has_prefix("ssh-cert:") || value.has_prefix("secret:"))
}

///|
pub fn validate_intent(
  intent : ExclusiveNodeLeaseIntent,
) -> Unit raise ExclusiveLeaseError {
  if intent.version != contract_version {
    raise UnsupportedVersion(intent.version)
  }
  if !@contracts.valid_identifier(intent.idempotency_key) ||
    !@contracts.valid_identifier(intent.lease_id) ||
    !@contracts.valid_identifier(intent.node_id, maximum_length=128) ||
    !@contracts.valid_identifier(intent.subject_ref) {
    raise InvalidIntent("lease identifiers contain unsafe characters")
  }
  if !valid_unix_username(intent.unix_username) {
    raise InvalidIntent("unix username is invalid or reserved")
  }
  if !valid_access_credential_ref(intent.access_credential_ref) {
    raise InvalidIntent(
      "access credential must be an ssh-cert: or secret: reference",
    )
  }
  if intent.starts_unix_ms <= 0L ||
    intent.expires_unix_ms <= intent.starts_unix_ms {
    raise InvalidIntent("lease time window is invalid")
  }
}

///|
pub fn state_blocks_managed_placement(state : ExclusiveLeaseState) -> Bool {
  match state {
    Completed | Cancelled => false
    Requested
    | Reserved
    | Provisioning
    | Active
    | Expiring
    | Draining
    | RevokingAccess
    | Sanitizing
    | Quarantined => true
  }
}

///|
pub fn transition_allowed(
  from : ExclusiveLeaseState,
  to : ExclusiveLeaseState,
) -> Bool {
  match (from, to) {
    (Requested, Reserved | Cancelled | Quarantined) => true
    (Reserved, Provisioning | Cancelled | Quarantined) => true
    (Provisioning, Active | Expiring | RevokingAccess | Quarantined) => true
    (Active, Expiring | Draining | Quarantined) => true
    (Expiring, Draining | Quarantined) => true
    (Draining, RevokingAccess | Quarantined) => true
    (RevokingAccess, Sanitizing | Quarantined) => true
    (Sanitizing, Completed | Quarantined) => true
    (Quarantined, RevokingAccess | Sanitizing) => true
    _ => false
  }
}

///|
pub fn ExclusiveNodeLease::transition(
  self : ExclusiveNodeLease,
  to : ExclusiveLeaseState,
  expected_generation : Int64,
  evidence_receipt : String,
  now_unix_ms : Int64,
) -> ExclusiveNodeLease raise ExclusiveLeaseError {
  if expected_generation != self.generation {
    raise StaleGeneration
  }
  if !transition_allowed(self.state, to) {
    raise InvalidTransition(self.state, to)
  }
  if !@contracts.valid_identifier(evidence_receipt, maximum_length=512) {
    raise InvalidIntent("a safe transition evidence receipt is required")
  }
  if now_unix_ms < self.updated_unix_ms {
    raise InvalidIntent("transition time moved backwards")
  }
  {
    ..self,
    state: to,
    generation: self.generation + 1L,
    updated_unix_ms: now_unix_ms,
    evidence_receipt,
    authority_receipt: "",
  }
}
