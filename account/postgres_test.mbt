///|
async test "invited account registration restores from PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let store = @account.AccountStore::open_postgres(
    database, "postgres-account-invitation-secret-more-than-32-bytes",
  )
  let invitation = store.issue_invitation(
    {
      invitation_id: "invitation-postgres",
      email: "postgres-invited@example.invalid",
      organization_id: "organization-postgres",
      tenant_ref: "tenant-postgres",
      project_id: "project-postgres",
      created_by: "operator-postgres",
      expires_unix_ms: 200000L,
    },
    100000L,
  )
  let registered = store.register_with_invitation(
    invitation.secret,
    "https://identity.example/realms/lunanexa",
    "provider-subject-postgres",
    "postgres-invited@example.invalid",
    "assertion-postgres",
    "Postgres User",
    60000L,
    100001L,
  )
  let reopened = @account.AccountStore::open_postgres(
    database, "postgres-account-invitation-secret-more-than-32-bytes",
  )
  assert_eq(reopened.views().length(), 1)
  assert_eq(
    reopened.invitation_views()[0].consumed_account_id,
    Some(registered.account.account_id),
  )
  database.close()
}
