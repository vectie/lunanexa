///|
async test "schema selects lz4 without rewriting existing snapshot values" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let name = url.split("/").to_array().last().unwrap().split("?").to_array()[0]
  guard name.has_suffix("_test") else {
    fail("compression regression requires an isolated *_test database")
  }
  let database = PostgresDatabase::open(url)
  defer database.close()
  let operation = database.begin_operation()
  defer operation.release()
  let compression = run(
    operation, "SELECT attcompression::text FROM pg_attribute WHERE attrelid = 'lunanexa.snapshots'::regclass AND attname = 'payload'",
  )
  assert_eq(compression.value(0, 0), Some("l"))
  let version = run(
    operation, "SELECT max(version)::text FROM lunanexa.schema_migrations",
  )
  assert_eq(version.value(0, 0), Some("7"))
  // A large value exercises TOAST, not just an inline uncompressed fixture.
  ignore(
    run(
      operation, "INSERT INTO lunanexa.snapshots(domain, schema_version, payload) VALUES ('compression-test', 'test-v1', jsonb_build_object('text', repeat('round-trip-content-', 20000))) ON CONFLICT(domain) DO UPDATE SET payload = EXCLUDED.payload",
    ),
  )
  let stored = run(
    operation, "SELECT pg_column_compression(payload), payload->>'text' = repeat('round-trip-content-', 20000) FROM lunanexa.snapshots WHERE domain = 'compression-test'",
  )
  assert_eq(stored.value(0, 0), Some("lz4"))
  assert_eq(stored.value(0, 1), Some("t"))
}
