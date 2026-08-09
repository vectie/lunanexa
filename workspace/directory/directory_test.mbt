///|
fn workspace_user(
  user_id : String,
  subject_ref : String,
) -> @workspace.WorkspaceUser {
  {
    version: @workspace.contract_version,
    user_id,
    subject_ref,
    display_name: "Ari Chen",
    email: "ari@example.test",
    state: UserActive,
    created_unix_ms: 100L,
    last_active_unix_ms: Some(900L),
    identity_receipt: "identity-\{user_id}",
  }
}

///|
fn access_grant(
  grant_id : String,
  user_id : String,
  access : @workspace.WorkspaceAccess,
  expires_unix_ms : Int64,
) -> @workspace.WorkspaceAccessGrant {
  {
    version: @workspace.contract_version,
    grant_id,
    user_id,
    tenant_ref: "tenant-opaque-1",
    access,
    starts_unix_ms: 500L,
    expires_unix_ms,
    state: GrantActive,
    policy_receipt: "policy-\{grant_id}",
  }
}

///|
fn workspace_lease(
  lease_id : String,
  subject_ref : String,
  access : @workspace.WorkspaceAccess,
  starts_unix_ms : Int64,
  expires_unix_ms : Int64,
  state : @workspace.WorkspaceLeaseState,
) -> @workspace.WorkspaceLease {
  {
    version: @workspace.contract_version,
    lease_id,
    tenant_ref: "tenant-opaque-1",
    subject_ref,
    access,
    limits: {
      max_active_sessions: 2,
      max_session_duration_ms: 3600000L,
      capabilities: [
        {
          capability: TextGenerate,
          max_concurrent_requests: 2,
          max_requests_per_hour: 200,
          max_input_units_per_request: 32768,
          max_output_units_per_request: 8192,
        },
      ],
    },
    starts_unix_ms,
    expires_unix_ms,
    state,
    policy_receipt: "policy-\{lease_id}",
  }
}

///|
async fn try_suspend_with_prior(
  directory : @directory.FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceUser, @workspace.WorkspaceUser)? {
  try directory.suspend_user_with_prior(user_id, now_unix_ms) catch {
    _ => None
  } noraise {
    transition => Some(transition)
  }
}

///|
async fn try_revoke_with_prior(
  directory : @directory.FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceUser, @workspace.WorkspaceUser)? {
  try directory.revoke_user_with_prior(user_id, now_unix_ms) catch {
    _ => None
  } noraise {
    transition => Some(transition)
  }
}

///|
async test "directory persists authority and selects a deterministic lease after restart" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-directory-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  ignore(
    directory.issue_access_grant(
      access_grant("grant-1", "user-1", Developer, 10000L),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease("lease-z", "subject-1", Developer, 500L, 10000L, Active),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease("lease-a", "subject-1", Developer, 500L, 10000L, Active),
      1000L,
    ),
  )
  let self = directory.self_view("subject-1", 1000L)
  assert_true(self.authorized)
  assert_eq(self.readiness, WorkspaceReady)
  guard self.active_lease is Some(selected) else {
    fail("authorized self view omitted its selected lease")
  }
  assert_eq(selected.lease_id, "lease-a")
  assert_false(@fs.exists("\{path}.next"))
  let persisted = @fs.read_file(path).text()
  assert_false(persisted.contains("credential"))
  assert_false(persisted.contains("node_id"))
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1200L,
  )
  let authorization = reopened.authorize_subject("subject-1", Developer, 1200L)
  assert_eq(authorization.access_grant.grant_id, "grant-1")
  assert_eq(authorization.lease.lease_id, "lease-a")
  let snapshot = reopened.snapshot(1200L)
  assert_eq(snapshot.users.length(), 1)
  assert_eq(snapshot.access_grants.length(), 1)
  assert_eq(snapshot.leases[0].lease_id, "lease-a")
  assert_eq(snapshot.leases[1].lease_id, "lease-z")
  try reopened.authorize_subject("subject-1", Administrator, 1200L) catch {
    @workspace.WorkspaceDirectoryError::AccessDenied(AccessUnavailable) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("developer authority was elevated to administrator")
  }
  @fs.rmdir(temporary, recursive=true)
}

///|
async test "requested activation and destructive revocations survive restart" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-revocation-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  ignore(
    directory.issue_access_grant(
      access_grant("grant-1", "user-1", Developer, 10000L),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease(
        "lease-requested",
        "subject-1",
        Developer,
        2000L,
        10000L,
        Requested,
      ),
      1000L,
    ),
  )
  assert_eq(directory.self_view("subject-1", 1000L).readiness, LeaseUnavailable)
  let active = directory.activate_lease("lease-requested", 2000L)
  assert_eq(active.state, Active)
  assert_true(directory.self_view("subject-1", 2000L).authorized)
  let revoked_lease = directory.revoke_lease("lease-requested", 2100L)
  assert_eq(revoked_lease.state, Revoked)
  assert_eq(directory.self_view("subject-1", 2100L).readiness, LeaseUnavailable)
  ignore(
    directory.issue_lease(
      workspace_lease(
        "lease-second",
        "subject-1",
        Developer,
        500L,
        10000L,
        Active,
      ),
      2200L,
    ),
  )
  let revoked_grant = directory.revoke_access_grant("grant-1", 2300L)
  assert_eq(revoked_grant.state, GrantRevoked)
  let self = directory.self_view("subject-1", 2300L)
  assert_false(self.authorized)
  assert_eq(self.readiness, AccessUnavailable)
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=2400L,
  )
  let snapshot = reopened.snapshot(2400L)
  assert_eq(snapshot.access_grants[0].state, GrantRevoked)
  guard snapshot.leases.search_by(lease => lease.lease_id == "lease-requested")
    is Some(revoked_index) else {
    fail("reopened directory lost the revoked lease")
  }
  assert_eq(snapshot.leases[revoked_index].state, Revoked)
  try reopened.authorize_subject("subject-1", Developer, 2400L) catch {
    @workspace.WorkspaceDirectoryError::AccessDenied(AccessUnavailable) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("a revoked access grant authorized a workload")
  }
  @fs.rmdir(temporary, recursive=true)
}

///|
async test "expiry reconciles active and requested records durably" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-expiry-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  ignore(
    directory.issue_access_grant(
      access_grant("grant-1", "user-1", Developer, 5000L),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease(
        "lease-active",
        "subject-1",
        Developer,
        500L,
        2000L,
        Active,
      ),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease(
        "lease-requested",
        "subject-1",
        Developer,
        1500L,
        2000L,
        Requested,
      ),
      1000L,
    ),
  )
  let expired_leases = directory.snapshot(2000L)
  assert_true(expired_leases.leases.all(lease => lease.state == Expired))
  assert_eq(directory.self_view("subject-1", 2000L).readiness, LeaseUnavailable)
  let expired_all = directory.snapshot(5000L)
  assert_eq(expired_all.access_grants[0].state, GrantExpired)
  assert_eq(
    directory.self_view("subject-1", 5000L).readiness,
    AccessUnavailable,
  )
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=5000L,
  )
  let persisted = reopened.snapshot(5000L)
  assert_eq(persisted.access_grants[0].state, GrantExpired)
  assert_true(persisted.leases.all(lease => lease.state == Expired))
  @fs.rmdir(temporary, recursive=true)
}

///|
async test "directory rejects duplicate identity and broken subject linkage" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-linkage-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  try directory.create_user(workspace_user("user-1", "subject-2")) catch {
    @workspace.WorkspaceDirectoryError::DuplicateRecord("user:user-1") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("duplicate user identifier was accepted")
  }
  try directory.create_user(workspace_user("user-2", "subject-1")) catch {
    @workspace.WorkspaceDirectoryError::SubjectConflict("subject-1") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("duplicate identity-provider subject was accepted")
  }
  try
    directory.issue_access_grant(
      access_grant("grant-missing", "user-missing", Developer, 5000L),
      1000L,
    )
  catch {
    @workspace.WorkspaceDirectoryError::RecordNotFound("user:user-missing") =>
      ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("access grant for an unknown user was accepted")
  }
  try
    directory.issue_lease(
      workspace_lease(
        "lease-missing",
        "subject-missing",
        Developer,
        500L,
        5000L,
        Requested,
      ),
      1000L,
    )
  catch {
    @workspace.WorkspaceDirectoryError::RecordNotFound(
      "subject:subject-missing"
    ) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("lease for an unknown subject was accepted")
  }
  @fs.rmdir(temporary, recursive=true)
}

///|
async test "user lifecycle and requested lease activation persist with authorization" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-user-lifecycle-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(
    directory.invite_user({
      ..workspace_user("user-1", "subject-1"),
      state: UserInvited,
    }),
  )
  ignore(
    directory.issue_access_grant(
      access_grant("grant-1", "user-1", Developer, 10000L),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease(
        "lease-1",
        "subject-1",
        Developer,
        500L,
        10000L,
        Requested,
      ),
      1000L,
    ),
  )
  let (invited, activated_user) = directory.activate_user_with_prior(
    "user-1", 1100L,
  )
  assert_eq(invited.state, UserInvited)
  assert_eq(activated_user.state, UserActive)
  let (requested, activated_lease) = directory.activate_lease_with_prior(
    "lease-1", 1100L,
  )
  assert_eq(requested.state, Requested)
  assert_eq(activated_lease.state, Active)
  assert_true(directory.self_view("subject-1", 1100L).authorized)
  let (active_before_suspend, suspended_user) = directory.suspend_user_with_prior(
    "user-1", 1200L,
  )
  assert_eq(active_before_suspend.state, UserActive)
  assert_eq(suspended_user.state, UserSuspended)
  assert_eq(directory.self_view("subject-1", 1200L).readiness, UserUnavailable)
  let (suspended_before_activation, reactivated_user) = directory.activate_user_with_prior(
    "user-1", 1300L,
  )
  assert_eq(suspended_before_activation.state, UserSuspended)
  assert_eq(reactivated_user.state, UserActive)
  assert_true(directory.self_view("subject-1", 1300L).authorized)
  let (active_before_revoke, revoked_user) = directory.revoke_user_with_prior(
    "user-1", 1400L,
  )
  assert_eq(active_before_revoke.state, UserActive)
  assert_eq(revoked_user.state, UserRevoked)
  try directory.activate_user("user-1", 1500L) catch {
    @workspace.WorkspaceContractError::TransitionDenied("workspace_user") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("revoked user was reactivated")
  }
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1600L,
  )
  assert_eq(reopened.snapshot(1600L).users[0].state, UserRevoked)
  assert_eq(reopened.self_view("subject-1", 1600L).readiness, UserUnavailable)
  @fs.rmdir(temporary, recursive=true)
}

///|
async test "concurrent user transitions return the exact persisted prior state" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-user-race-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  @async.with_task_group <| group => {
    for index in 0..<16 {
      let user_id = "user-race-\{index}"
      let subject_ref = "subject-race-\{index}"
      ignore(directory.create_user(workspace_user(user_id, subject_ref)))
      let suspend_task = group.spawn(() => {
        try_suspend_with_prior(directory, user_id, 1100L)
      })
      let revoke_task = group.spawn(() => {
        try_revoke_with_prior(directory, user_id, 1100L)
      })
      let suspended = suspend_task.wait()
      let revoked = revoke_task.wait()
      guard revoked is Some((revoke_prior, revoke_current)) else {
        fail("concurrent revocation unexpectedly failed")
      }
      assert_eq(revoke_current.state, UserRevoked)
      match suspended {
        Some((suspend_prior, suspend_current)) => {
          assert_eq(suspend_prior.state, UserActive)
          assert_eq(suspend_current.state, UserSuspended)
          assert_eq(revoke_prior.state, UserSuspended)
        }
        None => assert_eq(revoke_prior.state, UserActive)
      }
    }
  }
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1200L,
  )
  assert_true(
    reopened.snapshot(1200L).users.all(user => user.state == UserRevoked),
  )
  @fs.rmdir(temporary, recursive=true)
}

///|
async test "capability reservations enforce concurrency and rolling hourly limits" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-admission-limits-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  ignore(
    directory.issue_access_grant(
      access_grant("grant-1", "user-1", Developer, 10000L),
      1000L,
    ),
  )
  let base = workspace_lease(
    "lease-1",
    "subject-1",
    Developer,
    500L,
    10000L,
    Active,
  )
  let limit = base.limits.capabilities[0]
  ignore(
    directory.issue_lease(
      {
        ..base,
        limits: {
          ..base.limits,
          max_active_sessions: 1,
          capabilities: [
            { ..limit, max_concurrent_requests: 2, max_requests_per_hour: 3 },
          ],
        },
      },
      1000L,
    ),
  )
  directory.reserve_workload(
    "lease-1",
    "subject-1",
    "tenant-opaque-1",
    TextGenerate,
    "workload-1",
    "request-1",
    5000L,
    1000L,
  )
  directory.reserve_workload(
    "lease-1",
    "subject-1",
    "tenant-opaque-1",
    TextGenerate,
    "workload-2",
    "request-2",
    5000L,
    1000L,
  )
  // max_active_sessions=1 is intentionally unrelated to inference; the
  // capability's request concurrency of two is the applied limit.
  try
    directory.reserve_workload(
      "lease-1",
      "subject-1",
      "tenant-opaque-1",
      TextGenerate,
      "workload-concurrent",
      "request-concurrent",
      5000L,
      1000L,
    )
  catch {
    @workspace.WorkspaceDirectoryError::ConcurrentRequestLimitExceeded(
      "lease-1"
    ) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("capability concurrency limit was bypassed")
  }
  directory.release_workload("workload-1", "request-1", 1100L)
  directory.reserve_workload(
    "lease-1",
    "subject-1",
    "tenant-opaque-1",
    TextGenerate,
    "workload-3",
    "request-3",
    5000L,
    1100L,
  )
  directory.release_workload("workload-2", "request-2", 1200L)
  directory.release_workload("workload-3", "request-3", 1200L)
  try
    directory.reserve_workload(
      "lease-1",
      "subject-1",
      "tenant-opaque-1",
      TextGenerate,
      "workload-hourly",
      "request-hourly",
      5000L,
      1200L,
    )
  catch {
    @workspace.WorkspaceDirectoryError::HourlyRequestLimitExceeded("lease-1") =>
      ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("rolling hourly request limit was bypassed")
  }
  assert_true(
    directory.workload_owned_by(
      "workload-1", "subject-1", "tenant-opaque-1", 1200L,
    ),
  )
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1300L,
  )
  assert_true(
    reopened.workload_owned_by(
      "workload-3", "subject-1", "tenant-opaque-1", 1300L,
    ),
  )
  assert_false(
    reopened.workload_owned_by("workload-3", "subject-1", "tenant-other", 1300L),
  )
  assert_true(
    reopened.workload_owned_by_subject("workload-3", "subject-1", 1300L),
  )
  assert_false(
    reopened.workload_owned_by_subject("workload-3", "subject-other", 1300L),
  )
  @fs.rmdir(temporary, recursive=true)
}

///|
async test "expired held reservation recovers concurrency after restart" {
  let temporary = @fs.tmpdir(prefix="lunanexa-workspace-admission-recovery-")
  let path = "\{temporary}/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  ignore(
    directory.issue_access_grant(
      access_grant("grant-1", "user-1", Developer, 10000L),
      1000L,
    ),
  )
  let base = workspace_lease(
    "lease-1",
    "subject-1",
    Developer,
    500L,
    10000L,
    Active,
  )
  let limit = base.limits.capabilities[0]
  ignore(
    directory.issue_lease(
      {
        ..base,
        limits: {
          ..base.limits,
          capabilities: [
            { ..limit, max_concurrent_requests: 1, max_requests_per_hour: 100 },
          ],
        },
      },
      1000L,
    ),
  )
  directory.reserve_workload(
    "lease-1",
    "subject-1",
    "tenant-opaque-1",
    TextGenerate,
    "workload-crashed",
    "request-crashed",
    1200L,
    1000L,
  )
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1300L,
  )
  reopened.reserve_workload(
    "lease-1",
    "subject-1",
    "tenant-opaque-1",
    TextGenerate,
    "workload-after-restart",
    "request-after-restart",
    2000L,
    1300L,
  )
  assert_true(
    reopened.workload_owned_by(
      "workload-crashed", "subject-1", "tenant-opaque-1", 1300L,
    ),
  )
  @fs.rmdir(temporary, recursive=true)
}
