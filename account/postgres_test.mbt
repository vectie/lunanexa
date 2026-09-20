///|
/// The database these tests write to must be a disposable one. They overwrite
/// snapshot rows and truncate projection tables, so pointing them at a live
/// deployment silently destroys its state: that is exactly how the production
/// `accounts`, `commercial`, `commercial_integrations` and `client_handoffs`
/// snapshots were replaced with fixtures and the control plane refused to start.
///
/// Set `LUNANEXA_TEST_DATABASE_URL` to a database whose name ends in `_test`.
/// A URL that does not is refused loudly rather than damaging the deployment.
fn test_database_url() -> String? {
  let url = @env.get_env_var("LUNANEXA_TEST_DATABASE_URL")
  match url {
    None => None
    Some(value) => {
      // Database name: the last path segment, before any query string.
      let mut name = ""
      for segment in value.split("/") {
        name = segment.to_owned()
      }
      let mut base = ""
      let mut first = true
      for part in name.split("?") {
        if first {
          base = part.to_owned()
          first = false
        }
      }
      if !base.has_suffix("_test") {
        abort(
          "LUNANEXA_TEST_DATABASE_URL must name a *_test database; refusing to run against \{base}",
        )
      }
      Some(value)
    }
  }
}

///|
async test "invited account registration restores from PostgreSQL" {
  guard test_database_url() is Some(url) else { return }
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
