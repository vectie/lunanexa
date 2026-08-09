///|

///|
pub fn workspace_user_transition_allowed(
  from : WorkspaceUserState,
  to : WorkspaceUserState,
) -> Bool {
  match (from, to) {
    (UserInvited, UserActive | UserRevoked) => true
    (UserActive, UserSuspended | UserRevoked) => true
    (UserSuspended, UserActive | UserRevoked) => true
    _ => false
  }
}

///|
pub fn WorkspaceUser::transition(
  self : WorkspaceUser,
  to : WorkspaceUserState,
  now_unix_ms : Int64,
) -> WorkspaceUser raise WorkspaceContractError {
  validate_workspace_user(self)
  if now_unix_ms < self.created_unix_ms {
    raise InvalidTimeRange("workspace_user_transition")
  }
  if !workspace_user_transition_allowed(self.state, to) {
    raise TransitionDenied("workspace_user")
  }
  { ..self, state: to }
}

///|
pub fn lease_transition_allowed(
  from : WorkspaceLeaseState,
  to : WorkspaceLeaseState,
) -> Bool {
  match (from, to) {
    (Requested, Active | Expired | Revoked) => true
    (Active, Suspended | Expired | Revoked) => true
    (Suspended, Active | Expired | Revoked) => true
    _ => false
  }
}

///|
pub fn access_grant_transition_allowed(
  from : WorkspaceAccessGrantState,
  to : WorkspaceAccessGrantState,
) -> Bool {
  match (from, to) {
    (GrantActive, GrantExpired | GrantRevoked) => true
    _ => false
  }
}

///|
pub fn WorkspaceAccessGrant::transition(
  self : WorkspaceAccessGrant,
  to : WorkspaceAccessGrantState,
  now_unix_ms : Int64,
) -> WorkspaceAccessGrant raise WorkspaceContractError {
  validate_workspace_access_grant(self)
  if !access_grant_transition_allowed(self.state, to) {
    raise TransitionDenied("workspace_access_grant")
  }
  if to == GrantExpired && now_unix_ms < self.expires_unix_ms {
    raise InvalidTimeRange("access_grant_expiry")
  }
  { ..self, state: to }
}

///|
pub fn WorkspaceLease::transition(
  self : WorkspaceLease,
  to : WorkspaceLeaseState,
  now_unix_ms : Int64,
) -> WorkspaceLease raise WorkspaceContractError {
  validate_workspace_lease(self)
  if !lease_transition_allowed(self.state, to) {
    raise TransitionDenied("workspace_lease")
  }
  if to == Active &&
    (now_unix_ms < self.starts_unix_ms || now_unix_ms >= self.expires_unix_ms) {
    raise InvalidTimeRange("lease_activation")
  }
  if to == Expired && now_unix_ms < self.expires_unix_ms {
    raise InvalidTimeRange("lease_expiry")
  }
  { ..self, state: to }
}

///|
pub fn connection_transition_allowed(
  from : ConnectionState,
  to : ConnectionState,
) -> Bool {
  match (from, to) {
    (Pending, Connecting | Revoked) => true
    (Connecting, Connected | Failed | Disconnected | Revoked) => true
    (Connected, Disconnected | Failed | Revoked) => true
    (Disconnected, Connecting | Revoked) => true
    (Failed, Connecting | Revoked) => true
    _ => false
  }
}

///|
pub fn WorkspaceSession::transition(
  self : WorkspaceSession,
  to : ConnectionState,
  now_unix_ms : Int64,
) -> WorkspaceSession raise WorkspaceContractError {
  validate_workspace_session(self)
  if now_unix_ms < self.created_unix_ms || now_unix_ms >= self.expires_unix_ms {
    raise InvalidTimeRange("session_transition")
  }
  if !connection_transition_allowed(self.connection, to) {
    raise TransitionDenied("workspace_session")
  }
  { ..self, connection: to }
}
