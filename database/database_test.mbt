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
    "accounts",
    "account-test-v1",
    "{\"accounts\":[],\"sessions\":[]}",
  )
  database.save_opaque_snapshot(
    "client_handoffs",
    "client-handoff-test-v1",
    "{\"handoffs\":[],\"credentials\":[]}",
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
