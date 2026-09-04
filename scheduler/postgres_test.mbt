///|
async test "scheduler capacity and state restore from PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let scheduler = @scheduler.FileScheduler::open_postgres(database, 7)
  assert_eq(scheduler.snapshot().capacity, 7)
  let reopened = @scheduler.FileScheduler::open_postgres(database, 99)
  assert_eq(reopened.snapshot().capacity, 7)
  database.close()
}
