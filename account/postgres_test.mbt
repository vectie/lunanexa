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
  let before = store.snapshot()
  database.close()
  for _ in 0..<2 {
    try
      store.set_state(registered.account.account_id, Suspended, 100002L)
    catch {
      @database.DatabaseError::QueryFailed(_) => ()
      error => fail("unexpected disconnected write: \{Repr(error)}")
    } noraise {
      _ => fail("closed database accepted suspension")
    }
    assert_eq(store.snapshot(), before)
  }
  let recovered_database = @database.PostgresDatabase::open(url)
  defer recovered_database.close()
  let reopened = @account.AccountStore::open_postgres(
    recovered_database, "postgres-account-invitation-secret-more-than-32-bytes",
  )
  assert_eq(reopened.snapshot(), before)
  assert_eq(reopened.views().length(), 1)
  assert_eq(
    reopened.invitation_views()[0].consumed_account_id,
    Some(registered.account.account_id),
  )
  ignore(
    reopened.authorize(
      registered.session.secret,
      100003L,
      required_role=EnterpriseUser,
    ),
  )
  ignore(reopened.set_state(registered.account.account_id, Suspended, 100004L))
  let third_database = @database.PostgresDatabase::open(url)
  defer third_database.close()
  let suspended = @account.AccountStore::open_postgres(
    third_database, "postgres-account-invitation-secret-more-than-32-bytes",
  )
  try
    suspended.authorize(
      registered.session.secret,
      100005L,
      required_role=EnterpriseUser,
    )
  catch {
    @account.AccountError::Unauthorized => ()
    error => fail("unexpected suspension error: \{Repr(error)}")
  } noraise {
    _ => fail("suspended session survived fresh database connection")
  }
}
