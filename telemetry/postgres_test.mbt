///|
async test "telemetry snapshot restores from PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let telemetry = @telemetry.FileTelemetry::open_postgres(database)
  assert_eq(telemetry.snapshot().schema_version, "lunanexa.telemetry.v1")
  telemetry.record_sample({
    node_id: "fixture-node",
    deployment_id: "fixture-deployment",
    metric: "accelerator_utilization_per_mille",
    value: 321.0,
    timestamp_unix_ms: 1000L,
  })
  let before = telemetry.snapshot()
  database.close()
  // The original connection is definitively closed before the write, not an
  // ambiguous COMMIT result. Failed writes must not leak into memory or disk.
  for value in [654.0, 987.0] {
    try
      telemetry.record_sample({
        node_id: "fixture-node",
        deployment_id: "fixture-deployment",
        metric: "accelerator_utilization_per_mille",
        value,
        timestamp_unix_ms: 2000L,
      })
    catch {
      @database.DatabaseError::QueryFailed(_) => ()
      error => fail("unexpected disconnected-write error: \{Repr(error)}")
    } noraise {
      _ => fail("closed database accepted telemetry")
    }
    assert_eq(telemetry.snapshot(), before)
  }
  let recovered_database = @database.PostgresDatabase::open(url)
  defer recovered_database.close()
  let reopened = @telemetry.FileTelemetry::open_postgres(recovered_database)
  assert_eq(reopened.snapshot(), before)
  assert_eq(reopened.snapshot().samples.length(), 1)
  assert_eq(reopened.snapshot().samples[0].value, 321.0)
}
