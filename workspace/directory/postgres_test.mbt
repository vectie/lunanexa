///|
async test "PostgreSQL workspace user registration survives restart" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) &&
    url.trim() != "" else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  defer database.close()
  let directory = @directory.FileWorkspaceDirectory::open_postgres(
    database,
    now_unix_ms=1000L,
  )
  ignore(
    directory.create_user({
      version: @workspace.contract_version,
      user_id: "user-postgres",
      subject_ref: "workspace-subject-postgres",
      display_name: "Database User",
      email: "database-user@example.test",
      state: UserActive,
      created_unix_ms: 100L,
      last_active_unix_ms: None,
      identity_receipt: "identity-postgres",
    }),
  )
  assert_eq(database.projection_count("workspace_users"), 1L)
  let reopened_database = @database.PostgresDatabase::open(url)
  defer reopened_database.close()
  let reopened = @directory.FileWorkspaceDirectory::open_postgres(
    reopened_database,
    now_unix_ms=1000L,
  )
  let snapshot = reopened.snapshot(1000L)
  assert_eq(snapshot.users.length(), 1)
  assert_eq(snapshot.users[0].subject_ref, "workspace-subject-postgres")
  ignore(
    reopened.issue_access_grant(
      access_grant("pg-grant", "user-postgres", Developer, 10000L),
      1001L,
    ),
  )
  ignore(
    reopened.issue_lease(
      workspace_lease(
        "pg-lease",
        "workspace-subject-postgres",
        Developer,
        500L,
        10000L,
        Active,
      ),
      1001L,
    ),
  )
  reopened.reserve_workload(
    "pg-lease",
    "workspace-subject-postgres",
    "tenant-opaque-1",
    TextGenerate,
    "pg-workload",
    "pg-request",
    9000L,
    1002L,
  )
  let resumed = @directory.FileWorkspaceDirectory::open_postgres(
    reopened_database,
    now_unix_ms=1003L,
  )
  assert_true(
    resumed.workload_owned_by(
      "pg-workload", "workspace-subject-postgres", "tenant-opaque-1", 1003L,
    ),
  )
  assert_false(
    resumed.workload_owned_by(
      "pg-workload", "other-subject", "tenant-opaque-1", 1003L,
    ),
  )
  resumed.release_workload("pg-workload", "pg-request", 1004L)
  ignore(resumed.revoke_access_grant("pg-grant", 1005L))
  let revoked = @directory.FileWorkspaceDirectory::open_postgres(
    reopened_database,
    now_unix_ms=1006L,
  )
  assert_eq(revoked.snapshot(1006L).access_grants[0].state, GrantRevoked)
  try
    revoked.reserve_workload(
      "pg-lease",
      "workspace-subject-postgres",
      "tenant-opaque-1",
      TextGenerate,
      "pg-denied",
      "pg-denied-request",
      9000L,
      1007L,
    )
  catch {
    @workspace.WorkspaceDirectoryError::AccessDenied(_) => ()
    _ => fail("unexpected revoked admission error")
  } noraise {
    _ => fail("revoked PostgreSQL grant admitted work")
  }
}
