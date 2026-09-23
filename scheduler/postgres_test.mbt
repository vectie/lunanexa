///|
async test "scheduler capacity and state restore from PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let scheduler = @scheduler.FileScheduler::open_postgres(database, 7)
  assert_eq(scheduler.snapshot().capacity, 7)
  scheduler.set_quota({
    tenant_ref: "tenant",
    max_inflight: 1,
    max_accelerator_ms: 1000L,
    window_ms: 60000L,
  })
  let now = @async.now()
  let work = { ..request(), deadline_unix_ms: now + 60000L, }
  assert_eq(scheduler.admit(work, now), Accepted(queue_position=0))
  scheduler.mark_started(work.workload_id, now + 1L)
  let reservation = reservation_request("pg-reservation", "tenant", [
    "spark-a", "spark-b",
  ])
  ignore(
    scheduler.reserve_nodes(
      { ..reservation, starts_unix_ms: now, expires_unix_ms: now + 60000L, },
      ["spark-a", "spark-b"],
      now,
    ),
  )
  let before = scheduler.snapshot()
  database.close()
  for _ in 0..<2 {
    try scheduler.complete(work.workload_id, 125L) catch {
      @database.DatabaseError::ConnectionUnavailable(_) => ()
      error => fail("unexpected disconnected completion error: \{Repr(error)}")
    } noraise {
      _ => fail("closed database accepted completion")
    }
    assert_eq(scheduler.snapshot(), before)
  }
  let recovered_database = @database.PostgresDatabase::open(url)
  defer recovered_database.close()
  let reopened = @scheduler.FileScheduler::open_postgres(recovered_database, 99)
  assert_eq(reopened.snapshot().capacity, 7)
  assert_eq(reopened.snapshot(), before)
  assert_true(reopened.node_is_reserved("spark-a"))
  assert_eq(
    reopened.admit(work, now + 2L),
    Rejected(reason=WorkloadAlreadyActive),
  )
  reopened.complete(work.workload_id, 125L)
  reopened.complete(work.workload_id, 125L)
  let settled_database = @database.PostgresDatabase::open(url)
  defer settled_database.close()
  let settled = @scheduler.FileScheduler::open_postgres(settled_database, 99)
  assert_eq(settled.snapshot().active.length(), 0)
  assert_eq(settled.snapshot().usage[0].accelerator_ms, 125L)
  assert_eq(settled.snapshot().usage[0].completed_workloads, 1L)
  assert_eq(
    settled.admit({ ..work, workload_id: "after-recovery", }, now + 3L),
    Accepted(queue_position=0),
  )
}
