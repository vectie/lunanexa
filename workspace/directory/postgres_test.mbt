///|
async test "PostgreSQL workspace user registration survives restart" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) &&
    url.trim() != "" else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
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
  let reopened = @directory.FileWorkspaceDirectory::open_postgres(
    reopened_database,
    now_unix_ms=1000L,
  )
  let snapshot = reopened.snapshot(1000L)
  assert_eq(snapshot.users.length(), 1)
  assert_eq(snapshot.users[0].subject_ref, "workspace-subject-postgres")
  reopened_database.close()
  database.close()
}
