///|
async test "related opaque snapshots commit and restore as one database operation" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
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
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
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
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
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
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
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
