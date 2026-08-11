///|
pub(all) suberror WorkspaceContractError {
  UnsupportedVersion(String)
  MissingField(String)
  InvalidIdentifier(String)
  InvalidTimeRange(String)
  InvalidLimit(String)
  DuplicateCapability(WorkspaceCapability)
  LeaseMismatch(String)
  LeaseUnavailable(WorkspaceLeaseState)
  TransitionDenied(String)
} derive(Debug, Eq)

///|
pub(all) suberror WorkspaceDirectoryError {
  DuplicateRecord(String)
  RecordNotFound(String)
  SubjectConflict(String)
  InvalidDirectoryState(String)
  AccessDenied(WorkspaceReadiness)
  ConcurrentRequestLimitExceeded(String)
  HourlyRequestLimitExceeded(String)
} derive(Debug, Eq)

///|
pub fn valid_identifier(value : String, maximum_length? : Int = 256) -> Bool {
  value != "" &&
  value.length() <= maximum_length &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == ':'
  })
}

///|
fn require_identifier(
  value : String,
  field : String,
) -> Unit raise WorkspaceContractError {
  if value == "" {
    raise MissingField(field)
  }
  if !valid_identifier(value) {
    raise InvalidIdentifier(field)
  }
}

///|
fn require_bounded_text(
  value : String,
  field : String,
  maximum_length : Int,
) -> Unit raise WorkspaceContractError {
  if value.trim() == "" {
    raise MissingField(field)
  }
  if value.length() > maximum_length ||
    value.any(character => {
      character == '\u0000' || character == '\n' || character == '\r'
    }) {
    raise InvalidIdentifier(field)
  }
}

///|
pub fn validate_workspace_user(
  user : WorkspaceUser,
) -> Unit raise WorkspaceContractError {
  if user.version != contract_version {
    raise UnsupportedVersion(user.version)
  }
  require_identifier(user.user_id, "user_id")
  require_identifier(user.subject_ref, "subject_ref")
  require_identifier(user.identity_receipt, "identity_receipt")
  require_bounded_text(user.display_name, "display_name", 128)
  require_bounded_text(user.email, "email", 320)
  if user.created_unix_ms <= 0L {
    raise InvalidTimeRange("user_created")
  }
  match user.last_active_unix_ms {
    Some(last_active) =>
      if last_active < user.created_unix_ms {
        raise InvalidTimeRange("user_last_active")
      }
    None => ()
  }
}

///|
pub fn validate_workspace_access_grant(
  grant : WorkspaceAccessGrant,
) -> Unit raise WorkspaceContractError {
  if grant.version != contract_version {
    raise UnsupportedVersion(grant.version)
  }
  require_identifier(grant.grant_id, "grant_id")
  require_identifier(grant.user_id, "user_id")
  require_identifier(grant.tenant_ref, "tenant_ref")
  require_identifier(grant.policy_receipt, "policy_receipt")
  if grant.starts_unix_ms <= 0L || grant.expires_unix_ms <= grant.starts_unix_ms {
    raise InvalidTimeRange("access_grant")
  }
}

///|
/// Whether an actual workspace role satisfies a requested minimum role.
pub fn workspace_access_satisfies(
  actual : WorkspaceAccess,
  required : WorkspaceAccess,
) -> Bool {
  match required {
    Administrator => actual == Administrator
    Developer => actual == Administrator || actual == Developer
    Observer => true
  }
}

///|
pub fn validate_capability_limit(
  limit : CapabilityLimit,
) -> Unit raise WorkspaceContractError {
  if limit.max_concurrent_requests <= 0 || limit.max_concurrent_requests > 1024 {
    raise InvalidLimit("max_concurrent_requests")
  }
  if limit.max_requests_per_hour <= 0 || limit.max_requests_per_hour > 10000000 {
    raise InvalidLimit("max_requests_per_hour")
  }
  if limit.max_input_units_per_request <= 0 ||
    limit.max_input_units_per_request > 10000000 {
    raise InvalidLimit("max_input_units_per_request")
  }
  if limit.max_output_units_per_request <= 0 ||
    limit.max_output_units_per_request > 1000000 {
    raise InvalidLimit("max_output_units_per_request")
  }
}

///|
pub fn validate_workspace_limits(
  limits : WorkspaceLimits,
) -> Unit raise WorkspaceContractError {
  if limits.max_active_sessions <= 0 || limits.max_active_sessions > 128 {
    raise InvalidLimit("max_active_sessions")
  }
  if limits.max_session_duration_ms <= 0L ||
    limits.max_session_duration_ms > 604800000L {
    raise InvalidLimit("max_session_duration_ms")
  }
  if limits.capabilities.length() == 0 || limits.capabilities.length() > 5 {
    raise InvalidLimit("capabilities")
  }
  for index, limit in limits.capabilities {
    validate_capability_limit(limit)
    for previous in 0..<index {
      if limits.capabilities[previous].capability == limit.capability {
        raise DuplicateCapability(limit.capability)
      }
    }
  }
}

///|
pub fn validate_workspace_lease(
  lease : WorkspaceLease,
) -> Unit raise WorkspaceContractError {
  if lease.version != contract_version {
    raise UnsupportedVersion(lease.version)
  }
  require_identifier(lease.lease_id, "lease_id")
  require_identifier(lease.tenant_ref, "tenant_ref")
  require_identifier(lease.subject_ref, "subject_ref")
  require_identifier(lease.policy_receipt, "policy_receipt")
  if lease.starts_unix_ms <= 0L || lease.expires_unix_ms <= lease.starts_unix_ms {
    raise InvalidTimeRange("lease")
  }
  validate_workspace_limits(lease.limits)
}

///|
pub fn validate_workspace_session(
  session : WorkspaceSession,
) -> Unit raise WorkspaceContractError {
  if session.version != contract_version {
    raise UnsupportedVersion(session.version)
  }
  require_identifier(session.session_id, "session_id")
  require_identifier(session.lease_id, "lease_id")
  require_identifier(session.subject_ref, "subject_ref")
  require_identifier(session.correlation_receipt, "correlation_receipt")
  if session.created_unix_ms <= 0L ||
    session.expires_unix_ms <= session.created_unix_ms {
    raise InvalidTimeRange("session")
  }
}

///|
/// Validates that a session consumes only the capacity represented by its lease.
pub fn validate_session_against_lease(
  session : WorkspaceSession,
  lease : WorkspaceLease,
) -> Unit raise WorkspaceContractError {
  validate_workspace_session(session)
  validate_workspace_lease(lease)
  if session.lease_id != lease.lease_id {
    raise LeaseMismatch("lease_id")
  }
  if session.subject_ref != lease.subject_ref {
    raise LeaseMismatch("subject_ref")
  }
  if lease.state != Active {
    raise LeaseUnavailable(lease.state)
  }
  if session.created_unix_ms < lease.starts_unix_ms ||
    session.expires_unix_ms > lease.expires_unix_ms {
    raise InvalidTimeRange("session_outside_lease")
  }
  if session.expires_unix_ms - session.created_unix_ms >
    lease.limits.max_session_duration_ms {
    raise InvalidTimeRange("session_duration")
  }
}

///|
pub fn capability_limit(
  lease : WorkspaceLease,
  capability : WorkspaceCapability,
) -> CapabilityLimit? {
  let found = lease.limits.capabilities.search_by(limit => {
    limit.capability == capability
  })
  match found {
    Some(index) => lease.limits.capabilities.get(index)
    None => None
  }
}
