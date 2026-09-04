///|
async test "core control state restores from PostgreSQL under leadership fencing" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let standby = @database.PostgresDatabase::open(url)
  let migrated = @store.MemoryStore::new()
  migrated.set_controller_epoch(41L)
  database.save_opaque_snapshot(
    "control",
    "lunanexa.store.v1",
    migrated.snapshot(),
  )
  guard database.try_acquire_controller_leadership("core-store-test")
    is Some(token) else {
    fail("test controller did not acquire leadership")
  }
  assert_true(token > 41L)
  assert_eq(
    standby.try_acquire_controller_leadership("core-store-standby"),
    None,
  )
  let store = @store.FileStore::open_postgres(
    database, "core-store-test", token,
  )
  store.fence_controller(token)
  assert_true(store.current_epoch_is_durable())
  assert_eq(store.controller_epoch(), token)
  let reopened = @store.FileStore::open_postgres(
    database, "core-store-test", token,
  )
  assert_eq(reopened.controller_epoch(), token)
  database.close()
  guard standby.try_acquire_controller_leadership("core-store-standby")
    is Some(next_token) else {
    fail("standby did not acquire leadership after session release")
  }
  assert_true(next_token > token)
  standby.close()
}
