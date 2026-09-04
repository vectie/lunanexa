///|
async test "telemetry snapshot restores from PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let telemetry = @telemetry.FileTelemetry::open_postgres(database)
  assert_eq(telemetry.snapshot().schema_version, "lunanexa.telemetry.v1")
  let reopened = @telemetry.FileTelemetry::open_postgres(database)
  assert_eq(reopened.snapshot(), telemetry.snapshot())
  database.close()
}
