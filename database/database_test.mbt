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
