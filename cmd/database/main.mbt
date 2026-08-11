///|
fn required_database_url() -> String raise {
  guard @env.get_env_var("LUNANEXA_DATABASE_URL") is Some(value) &&
    value.trim() != "" else {
    raise Failure::Failure("LUNANEXA_DATABASE_URL is required")
  }
  value
}

///|
fn main raise {
  let database = @db.PostgresDatabase::open(required_database_url()) catch {
    error => fail("database migration failed: \{Repr(error)}")
  }
  if !database.ping() {
    database.close()
    fail("PostgreSQL migration completed but health check failed")
  }
  println("LunaNexa PostgreSQL schema v\{@db.schema_version} is ready")
  database.close()
}
