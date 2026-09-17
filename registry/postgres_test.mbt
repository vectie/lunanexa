///|
async test "model registry uses PostgreSQL in the production adapter" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let standby = @database.PostgresDatabase::open(url)
  defer standby.close()
  guard database.try_acquire_controller_leadership("registry-primary")
    is Some(token) else {
    fail("registry primary could not acquire leadership")
  }
  assert_eq(standby.try_acquire_controller_leadership("registry-standby"), None)
  let registry = @registry.FileRegistry::open_postgres(database)
  registry.register_model(candidate("postgres-v1"))
  assert_eq(registry.snapshot().schema_version, "lunanexa.registry.v1")
  let reopened = @registry.FileRegistry::open_postgres(database)
  assert_eq(reopened.snapshot(), registry.snapshot())
  let before = registry.snapshot()
  database.close()
  guard standby.try_acquire_controller_leadership("registry-standby")
    is Some(next_token) else {
    fail("registry standby could not acquire released leadership")
  }
  assert_true(next_token > token)
  for _ in 0..<2 {
    try registry.register_model(candidate("postgres-uncommitted")) catch {
      _ => ()
    } noraise {
      _ => fail("disconnected registry accepted a write")
    }
    assert_eq(registry.snapshot(), before)
  }
  let successor = @registry.FileRegistry::open_postgres(standby)
  assert_eq(successor.snapshot(), before)
  successor.register_model(candidate("postgres-v2"))
  assert_eq(
    @registry.FileRegistry::open_postgres(standby).snapshot(),
    successor.snapshot(),
  )
}
