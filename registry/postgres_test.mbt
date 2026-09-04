///|
async test "model registry uses PostgreSQL in the production adapter" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let registry = @registry.FileRegistry::open_postgres(database)
  assert_eq(registry.snapshot().schema_version, "lunanexa.registry.v1")
  let reopened = @registry.FileRegistry::open_postgres(database)
  assert_eq(reopened.snapshot(), registry.snapshot())
  database.close()
}
