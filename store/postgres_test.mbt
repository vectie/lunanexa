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
      let name = match value.split("/").last() {
        Some(segment) => {
          match segment.split("?") {
            Some(parts) => match parts.get(0) {
              Some(head) => head
              None => segment
            }
            None => segment
          }
        }
        None => ""
      }
      if !name.has_suffix("_test") {
        fail(
          "LUNANEXA_TEST_DATABASE_URL must name a *_test database; refusing to run against \{name}",
        )
      }
      Some(value)
    }
  }
}
///|
async test "core control state restores from PostgreSQL under leadership fencing" {
  guard test_database_url() is Some(url) else {
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
  let before = store.backup_snapshot()
  database.close()
  guard standby.try_acquire_controller_leadership("core-store-standby")
    is Some(next_token) else {
    fail("standby did not acquire leadership after session release")
  }
  assert_true(next_token > token)
  for _ in 0..<2 {
    try store.append_audit(durable_event()) catch {
      _ => ()
    } noraise {
      _ => fail("disconnected former PostgreSQL leader accepted a write")
    }
    assert_eq(store.backup_snapshot(), before)
  }
  let successor = @store.FileStore::open_postgres(
    standby, "core-store-standby", next_token,
  )
  successor.fence_controller(next_token)
  successor.append_audit(durable_event())
  assert_eq(successor.audit_events(), [durable_event()])
  assert_eq(
    @store.FileStore::open_postgres(standby, "core-store-standby", next_token).audit_events(),
    [durable_event()],
  )
  standby.close()
}
