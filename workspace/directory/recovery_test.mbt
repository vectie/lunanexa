///|
async test "user creation and lifecycle failure preserve durable authority and retry" {
  let temporary = @fs.tmpdir(prefix="lunanexa-user-recovery-")
  defer @fs.rmdir(temporary, recursive=true)
  let path = temporary + "/directory.json"
  let directory = @directory.FileWorkspaceDirectory::open(path)
  let user = workspace_user("recovery-user", "recovery-subject")
  @fs.mkdir(path + ".next")
  try directory.create_user(user) catch {
    _ => ()
  } noraise {
    _ => fail("user creation unexpectedly persisted")
  }
  @async.with_timeout(1000, () => {
    assert_eq(directory.snapshot(1000L).users.length(), 0)
  })
  @fs.rmdir(path + ".next")
  ignore(directory.create_user(user))
  for operation in 0..<2 {
    @fs.mkdir(path + ".next")
    try {
      if operation == 0 {
        ignore(directory.suspend_user(user.user_id, 1001L))
      } else {
        ignore(directory.revoke_user(user.user_id, 1001L))
      }
    } catch {
      _ => ()
    } noraise {
      _ => fail("transition unexpectedly persisted")
    }
    @async.with_timeout(1000, () => {
      assert_eq(directory.snapshot(1002L).users[0], user)
      let reopened = @directory.FileWorkspaceDirectory::open(path)
      assert_eq(reopened.snapshot(1002L).users[0], user)
    })
    @fs.rmdir(path + ".next")
  }
  assert_eq(directory.revoke_user(user.user_id, 1003L).state, UserRevoked)
  try directory.activate_user(user.user_id, 1004L) catch {
    _ => ()
  } noraise {
    _ => fail("revoked user was resurrected")
  }
  let reopened = @directory.FileWorkspaceDirectory::open(path)
  assert_eq(reopened.snapshot(1005L).users[0].state, UserRevoked)
}

///|
async test "admission write failures preserve reservation ownership and allow retry" {
  let temporary = @fs.tmpdir(prefix="lunanexa-admission-recovery-")
  defer @fs.rmdir(temporary, recursive=true)
  let path = temporary + "/directory.json"
  let directory = @directory.FileWorkspaceDirectory::open(path)
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  ignore(
    directory.issue_access_grant(
      access_grant("grant-1", "user-1", Developer, 10000L),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease("lease-1", "subject-1", Developer, 500L, 10000L, Active),
      1000L,
    ),
  )
  @fs.mkdir(path + ".admissions.next")
  try
    directory.reserve_workload(
      "lease-1",
      "subject-1",
      "tenant-opaque-1",
      TextGenerate,
      "workload-1",
      "request-1",
      9000L,
      1001L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("reservation unexpectedly persisted")
  }
  @async.with_timeout(1000, () => {
    assert_false(
      directory.workload_owned_by(
        "workload-1", "subject-1", "tenant-opaque-1", 1002L,
      ),
    )
  })
  @fs.rmdir(path + ".admissions.next")
  directory.reserve_workload(
    "lease-1",
    "subject-1",
    "tenant-opaque-1",
    TextGenerate,
    "workload-1",
    "request-1",
    9000L,
    1003L,
  )
  @fs.mkdir(path + ".admissions.next")
  try directory.release_workload("workload-1", "request-1", 1004L) catch {
    _ => ()
  } noraise {
    _ => fail("release unexpectedly persisted")
  }
  @async.with_timeout(1000, () => {
    assert_true(
      directory.workload_owned_by(
        "workload-1", "subject-1", "tenant-opaque-1", 1005L,
      ),
    )
    assert_false(
      directory.workload_owned_by(
        "workload-1", "subject-other", "tenant-opaque-1", 1005L,
      ),
    )
  })
  @fs.rmdir(path + ".admissions.next")
  directory.release_workload("workload-1", "request-1", 1006L)
  let reopened = @directory.FileWorkspaceDirectory::open(path)
  // Released work retains its owner for authorized status and cancellation.
  assert_true(
    reopened.workload_owned_by(
      "workload-1", "subject-1", "tenant-opaque-1", 1007L,
    ),
  )
}
