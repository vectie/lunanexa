///|
fn text_limit() -> @workspace.CapabilityLimit {
  {
    capability: TextGenerate,
    max_concurrent_requests: 4,
    max_requests_per_hour: 1000,
    max_input_units_per_request: 32768,
    max_output_units_per_request: 8192,
  }
}

///|
fn active_lease() -> @workspace.WorkspaceLease {
  {
    version: @workspace.contract_version,
    lease_id: "lease-001",
    tenant_ref: "tenant-opaque-01",
    subject_ref: "user-opaque-07",
    access: Developer,
    limits: {
      max_active_sessions: 3,
      max_session_duration_ms: 28800000L,
      capabilities: [text_limit()],
    },
    starts_unix_ms: 2000000000000L,
    expires_unix_ms: 2000086400000L,
    state: Active,
    policy_receipt: "policy-001",
  }
}

///|
fn active_user() -> @workspace.WorkspaceUser {
  {
    version: @workspace.contract_version,
    user_id: "user-opaque-07",
    subject_ref: "user-opaque-07",
    display_name: "Ari Chen",
    email: "ari@example.test",
    state: UserActive,
    created_unix_ms: 1999999999000L,
    last_active_unix_ms: Some(2000000000000L),
    identity_receipt: "identity-001",
  }
}

///|
fn active_grant() -> @workspace.WorkspaceAccessGrant {
  {
    version: @workspace.contract_version,
    grant_id: "grant-001",
    user_id: "user-opaque-07",
    tenant_ref: "tenant-opaque-01",
    access: Developer,
    starts_unix_ms: 1999999999000L,
    expires_unix_ms: 2000086400000L,
    state: GrantActive,
    policy_receipt: "policy-grant-001",
  }
}

///|
fn web_session() -> @workspace.WorkspaceSession {
  {
    version: @workspace.contract_version,
    session_id: "session-001",
    lease_id: "lease-001",
    subject_ref: "user-opaque-07",
    editor: WebIde,
    integration: Some(CodeBuddy),
    connection: Pending,
    created_unix_ms: 2000000001000L,
    expires_unix_ms: 2000028801000L,
    correlation_receipt: "receipt-001",
  }
}

///|
test "workspace lease and session validate without node or credential data" {
  let lease = active_lease()
  let session = web_session()
  @workspace.validate_workspace_lease(lease)
  @workspace.validate_session_against_lease(session, lease)
  assert_eq(
    @workspace.capability_limit(lease, TextGenerate),
    Some(text_limit()),
  )
  assert_eq(@workspace.capability_limit(lease, EmbeddingCreate), None)
}

///|
test "lease transitions enforce lifecycle and wall-clock bounds" {
  let requested : @workspace.WorkspaceLease = {
    ..active_lease(),
    state: Requested,
  }
  let activated = requested.transition(Active, 2000000000000L)
  assert_eq(activated.state, Active)
  assert_false(@workspace.lease_transition_allowed(Revoked, Active))
  try activated.transition(Expired, 2000000001000L) catch {
    InvalidTimeRange("lease_expiry") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("lease expired before its entitlement ended")
  }
}

///|
test "workspace user lifecycle is checked and revocation is terminal" {
  let invited : @workspace.WorkspaceUser = {
    ..active_user(),
    state: UserInvited,
    last_active_unix_ms: None,
  }
  let active = invited.transition(UserActive, invited.created_unix_ms + 1L)
  let suspended = active.transition(UserSuspended, invited.created_unix_ms + 2L)
  let reactivated = suspended.transition(
    UserActive,
    invited.created_unix_ms + 3L,
  )
  let revoked = reactivated.transition(
    UserRevoked,
    invited.created_unix_ms + 4L,
  )
  assert_false(
    @workspace.workspace_user_transition_allowed(UserRevoked, UserActive),
  )
  try revoked.transition(UserActive, invited.created_unix_ms + 5L) catch {
    TransitionDenied("workspace_user") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("revoked workspace user was reactivated")
  }
}

///|
test "connection transitions are deterministic and terminal revocation is final" {
  let pending = web_session()
  let connecting = pending.transition(Connecting, 2000000002000L)
  let connected = connecting.transition(Connected, 2000000003000L)
  assert_eq(connected.connection, Connected)
  let revoked = connected.transition(Revoked, 2000000004000L)
  try revoked.transition(Connecting, 2000000005000L) catch {
    TransitionDenied("workspace_session") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("revoked connection was reopened")
  }
}

///|
test "unsafe identifiers, duplicate capabilities, and lease mismatch fail closed" {
  let lease = active_lease()
  try
    @workspace.validate_workspace_lease({ ..lease, subject_ref: "../../user" })
  catch {
    InvalidIdentifier("subject_ref") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("path-like subject reference was accepted")
  }
  try
    @workspace.validate_workspace_lease({
      ..lease,
      limits: { ..lease.limits, capabilities: [text_limit(), text_limit()] },
    })
  catch {
    DuplicateCapability(TextGenerate) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("duplicate capability was accepted")
  }
  try
    @workspace.validate_session_against_lease(
      { ..web_session(), lease_id: "lease-other" },
      lease,
    )
  catch {
    LeaseMismatch("lease_id") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("mismatched lease was accepted")
  }
}

///|
test "workspace users and access grants validate and serialize provider-neutrally" {
  let user = active_user()
  let grant = active_grant()
  @workspace.validate_workspace_user(user)
  @workspace.validate_workspace_access_grant(grant)
  let snapshot : @workspace.WorkspaceDirectorySnapshot = {
    schema_version: @workspace.directory_schema_version,
    users: [user],
    access_grants: [grant],
    leases: [active_lease()],
  }
  let restored : @workspace.WorkspaceDirectorySnapshot = @json.from_json(
    snapshot.to_json(),
  )
  assert_eq(restored, snapshot)
  assert_true(@workspace.workspace_access_satisfies(Administrator, Developer))
  assert_true(@workspace.workspace_access_satisfies(Developer, Observer))
  assert_false(@workspace.workspace_access_satisfies(Developer, Administrator))
}

///|
test "access grant expiry and revocation are terminal checked transitions" {
  let grant = active_grant()
  let expired = grant.transition(GrantExpired, grant.expires_unix_ms)
  assert_eq(expired.state, GrantExpired)
  try expired.transition(GrantRevoked, grant.expires_unix_ms + 1L) catch {
    TransitionDenied("workspace_access_grant") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expired access grant was revoked a second time")
  }
  let revoked = grant.transition(GrantRevoked, grant.starts_unix_ms)
  assert_eq(revoked.state, GrantRevoked)
}

///|
test "identity metadata rejects control characters and invalid timestamps" {
  for
    display_name in [
      "Ari\noperator",
      "Ari\roperator",
      "Ari\u0000operator",
      " ".repeat(128) + "x",
    ] {
    try
      @workspace.validate_workspace_user({ ..active_user(), display_name, })
    catch {
      InvalidIdentifier("display_name") => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("control or oversized identity metadata was accepted")
    }
  }
  try
    @workspace.validate_workspace_access_grant({
      ..active_grant(),
      expires_unix_ms: active_grant().starts_unix_ms,
    })
  catch {
    InvalidTimeRange("access_grant") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("empty grant time window was accepted")
  }
}

///|
test "workspace user canonical HTTP fixture decodes" {
  let fixture =
    #|{"version":"lunanexa.workspace.v1","user_id":"sim-user","subject_ref":"subject-simulated-user","display_name":"Simulation Developer","email":"simulation@example.invalid","state":"UserActive","created_unix_ms":"2000000000000","identity_receipt":"identity-sim-user"}
  let user : @workspace.WorkspaceUser = @json.from_json(@json.parse(fixture))
  assert_eq(user.user_id, "sim-user")
  assert_eq(user.subject_ref, "subject-simulated-user")
  assert_eq(user.state, UserActive)
  assert_eq(user.last_active_unix_ms, None)
}
