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
async test "related opaque snapshots commit and restore as one database operation" {
  guard test_database_url() is Some(url) else { return }
  let database = @database.PostgresDatabase::open(url)
  database.save_opaque_snapshots([
    ("commercial", "commercial-test-v1", "{\"revision\":1}"),
    (
      "commercial_integrations", "integration-test-v1", "{\"callback\":\"verified\"}",
    ),
  ])
  assert_eq(
    database.load_snapshot("commercial", "commercial-test-v1"),
    Some("{\"revision\": 1}"),
  )
  assert_eq(
    database.load_snapshot("commercial_integrations", "integration-test-v1"),
    Some("{\"callback\": \"verified\"}"),
  )
  database.close()
}

///|
async test "production account and client handoff snapshots are allowlisted" {
  guard test_database_url() is Some(url) else { return }
  let database = @database.PostgresDatabase::open(url)
  database.save_opaque_snapshot(
    "accounts", "account-test-v1", "{\"accounts\":[],\"sessions\":[]}",
  )
  database.save_opaque_snapshot(
    "client_handoffs", "client-handoff-test-v1", "{\"handoffs\":[],\"credentials\":[]}",
  )
  assert_eq(
    database.load_snapshot("accounts", "account-test-v1"),
    Some("{\"accounts\": [], \"sessions\": []}"),
  )
  assert_eq(
    database.load_snapshot("client_handoffs", "client-handoff-test-v1"),
    Some("{\"handoffs\": [], \"credentials\": []}"),
  )
  database.close()
}

///|
async test "failed PostgreSQL batch rolls back and releases its mutex" {
  guard test_database_url() is Some(url) else { return }
  let database = @database.PostgresDatabase::open(url)
  defer database.close()
  database.save_opaque_snapshot(
    "media_jobs", "rollback-test", "{\"revision\":1}",
  )
  let failed = try {
    database.save_opaque_snapshots([
      ("media_jobs", "rollback-test", "{\"revision\":2}"),
      // JSON permits an escaped NUL; PostgreSQL jsonb rejects it after BEGIN.
      ("accounts", "rollback-test", "{\"invalid\":\"\\u0000\"}"),
    ])
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(
    database.load_snapshot("media_jobs", "rollback-test"),
    Some("{\"revision\": 1}"),
  )
  database.save_opaque_snapshot(
    "media_jobs", "rollback-test", "{\"revision\":3}",
  )
  assert_eq(
    database.load_snapshot("media_jobs", "rollback-test"),
    Some("{\"revision\": 3}"),
  )
}

///|
async test "PostgreSQL leadership is exclusive and transfers after connection close" {
  guard test_database_url() is Some(url) else { return }
  let first = @database.PostgresDatabase::open(url)
  let second = @database.PostgresDatabase::open(url)
  defer second.close()
  let token = first
    .try_acquire_controller_leadership("media-test-first")
    .unwrap()
  assert_true(first.controller_leadership_is_current("media-test-first", token))
  assert_eq(second.try_acquire_controller_leadership("media-test-second"), None)
  first.close()
  let next = second
    .try_acquire_controller_leadership("media-test-second")
    .unwrap()
  assert_true(next > token)
  assert_true(
    second.controller_leadership_is_current("media-test-second", next),
  )
}
