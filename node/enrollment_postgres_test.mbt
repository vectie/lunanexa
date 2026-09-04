///|
async test "node enrollment authority restores from PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let enrollment = @node.FileEnrollmentService::open_postgres(database)
  ignore(enrollment.issue_token("postgres-token", "secret", 1000L))
  let reopened = @node.FileEnrollmentService::open_postgres(database)
  let certificate = reopened.enroll(
    "node-postgres", "postgres-token", "secret", "node-auth", "pk-ref", 1L,
  )
  assert_eq(certificate.node_id, "node-postgres")
  database.close()
}
