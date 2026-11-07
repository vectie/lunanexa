///|
async test "receipt journal preserves checkpoints rolls back and restores after reopen" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let name = url.split("/").to_array().last().unwrap().split("?").to_array()[0]
  guard name.has_suffix("_test") else {
    fail("journal regression requires an isolated *_test database")
  }
  let db = PostgresDatabase::open(url)
  let initial : Json = {
    "controller_epoch": "7",
    "workload_results": [],
    "audits": [],
    "unchanged_history": "preserve-".repeat(50000),
  }
  db.save_opaque_snapshot("control", "lunanexa.store.v1", initial.stringify())
  db.commit_control_workload(
    7L, "one", "{\"idempotency_key\":\"key-one\",\"response\":{\"workload_id\":\"one\"}}",
    "{\"sequence\":1}",
  )
  let op = db.begin_operation()
  let untouched = run(
    op, "SELECT payload::text FROM lunanexa.snapshots WHERE domain='control'",
  )
  assert_eq(@json.parse(untouched.value(0, 0).unwrap()), initial)
  let count = run(
    op, "SELECT count(*)::text FROM lunanexa.control_workload_commits",
  )
  assert_eq(count.value(0, 0), Some("1"))
  op.release()
  let merged = db.load_snapshot("control", "lunanexa.store.v1").unwrap()
  let operation = db.begin_operation()
  try
    with_transaction(operation, op => {
      write_snapshot_row(op, "control", "lunanexa.store.v1", merged)
      raise QueryFailed("synthetic checkpoint interruption")
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("interrupted checkpoint succeeded")
  }
  assert_eq(db.load_snapshot("control", "lunanexa.store.v1"), Some(merged))
  db.close()
  let reopened = PostgresDatabase::open(url)
  defer reopened.close()
  assert_eq(
    reopened.load_snapshot("control", "lunanexa.store.v1"),
    Some(merged),
  )
  reopened.save_opaque_snapshot("control", "lunanexa.store.v1", merged)
  assert_eq(
    reopened.load_snapshot("control", "lunanexa.store.v1"),
    Some(merged),
  )
  let check = reopened.begin_operation()
  defer check.release()
  let remaining = run(
    check, "SELECT count(*)::text FROM lunanexa.control_workload_commits",
  )
  assert_eq(remaining.value(0, 0), Some("0"))
}
