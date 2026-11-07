///|
/// The database these tests write to must be a disposable one. They overwrite
/// snapshot rows and truncate projection tables, so pointing them at a live
/// deployment silently destroys its state: that is exactly how the production
/// `accounts`, `commercial`, `commercial_integrations` and `client_handoffs`
/// snapshots were replaced with fixtures and the control plane refused to start.
///
/// Set `LUNANEXA_TEST_DATABASE_URL` to a database whose name ends in `_test`.
/// A URL that does not is refused loudly rather than damaging the deployment.
fn test_database_url() -> String? raise {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(value) else {
    return None
  }
  let tail = value.split("/").last().unwrap_or("")
  let name = match tail.split("?").to_array() {
    [] => tail.to_owned()
    [head, ..] => head.to_owned()
  }
  if !name.has_suffix("_test") {
    fail(
      "LUNANEXA_TEST_DATABASE_URL must name a *_test database; refusing to run against \{name}",
    )
  }
  Some(value)
}

///|
async test "core control state restores from PostgreSQL under leadership fencing" {
  guard test_database_url() is Some(url) else { return }
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

///|
async test "incremental workload commits restore both indexes and audit atomically" {
  guard test_database_url() is Some(url) else { return }
  let database = @database.PostgresDatabase::open(url)
  database.save_opaque_snapshot(
    "control",
    "lunanexa.store.v1",
    @store.MemoryStore::new().snapshot(),
  )
  let token = database
    .try_acquire_controller_leadership("workload-delta-test")
    .unwrap()
  let store = @store.FileStore::open_postgres(
    database, "workload-delta-test", token,
  )
  store.fence_controller(token)
  let response : @contracts.WorkloadResponse = {
    version: @contracts.contract_version,
    workload_id: "delta-one",
    state: Succeeded,
    output: None,
    error: None,
    usage: {
      input_units: 10,
      output_units: 512,
      accelerator_ms: 15000L,
      queue_ms: 0L,
    },
    artifact_digest: "sha256:" + "a".repeat(64),
    runtime_version: "test-only",
    execution_node_id: Some("test-node"),
    timing: {
      accepted_unix_ms: 1L,
      started_unix_ms: 2L,
      first_output_unix_ms: 3L,
      completed_unix_ms: 15002L,
    },
    retryable: false,
    audit_receipt: "receipt-delta",
  }
  store.commit_workload("delta-request", response, durable_event())
  let restored = @store.FileStore::open_postgres(
    database, "workload-delta-test", token,
  )
  assert_eq(restored.workload_result("delta-one"), Some(response))
  assert_eq(restored.idempotent_result("delta-request"), Some(response))
  assert_eq(restored.audit_events(), [durable_event()])
  // A later full snapshot must retain the incrementally committed receipt.
  store.append_audit({ ..durable_event(), sequence: 2L, event_id: "delta-two", })
  assert_eq(
    @store.FileStore::open_postgres(database, "workload-delta-test", token).workload_result(
      "delta-one",
    ),
    Some(response),
  )
  let before = store.backup_snapshot()
  database.close()
  try
    store.commit_workload(
      "delta-failure",
      { ..response, workload_id: "delta-two", },
      durable_event(),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("disconnected store acknowledged a receipt")
  }
  assert_eq(store.backup_snapshot(), before)
}
