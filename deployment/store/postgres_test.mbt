///|
async test "deployment catalog and operations restore from PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let store = @store.FileDeploymentStore::open_postgres(
    database, "postgres-deployment-signing-secret",
  )
  assert_eq(store.snapshot().schema_version, "lunanexa.deployments.v2")
  let reopened = @store.FileDeploymentStore::open_postgres(
    database, "postgres-deployment-signing-secret",
  )
  assert_eq(reopened.snapshot(), store.snapshot())
  database.close()
}
