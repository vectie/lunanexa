///|
async test "PostgreSQL transfer nonces survive reconnect and failed consumption remains retryable" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let store = @store.TechnicalStore::open_postgres(database)
  let grant : @technical.TransferGrant = {
    grant_id: "grant-postgres",
    nonce: "postgres-nonce-0123456789",
    node_id: "node-fixture",
    deployment_id: "deployment-fixture",
    model_digest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    scope: ModelRead,
    issued_unix_ms: 1000L,
    expires_unix_ms: 2000L,
  }
  let requested : @technical.TransferGrantUse = {
    node_id: grant.node_id,
    deployment_id: grant.deployment_id,
    model_digest: grant.model_digest,
    scope: ModelRead,
  }
  assert_true(
    store.validate_and_consume_transfer(
      grant,
      requested,
      Verified,
      1100L,
      900000L,
    )
    is Accepted(_),
  )
  let next = {
    ..grant,
    grant_id: "grant-next",
    nonce: "postgres-next-0123456789",
  }
  let before = store.snapshot()
  database.close()
  for _ in 0..<2 {
    try
      store.validate_and_consume_transfer(
        next,
        requested,
        Verified,
        1101L,
        900000L,
      )
    catch {
      @database.DatabaseError::QueryFailed(_) => ()
      error => fail("unexpected disconnected write error: \{Repr(error)}")
    } noraise {
      _ => fail("closed database consumed nonce")
    }
    assert_eq(store.snapshot(), before)
  }
  let recovered_database = @database.PostgresDatabase::open(url)
  defer recovered_database.close()
  let recovered = @store.TechnicalStore::open_postgres(recovered_database)
  assert_eq(recovered.snapshot(), before)
  assert_true(
    recovered.validate_and_consume_transfer(
      grant,
      requested,
      Verified,
      1102L,
      900000L,
    )
    is Rejected(NonceReplayed),
  )
  assert_true(
    recovered.validate_and_consume_transfer(
      next,
      requested,
      Verified,
      1102L,
      900000L,
    )
    is Accepted(_),
  )
  let third_database = @database.PostgresDatabase::open(url)
  defer third_database.close()
  let reopened = @store.TechnicalStore::open_postgres(third_database)
  assert_eq(reopened.snapshot().consumed_transfer_nonces.length(), 2)
  assert_true(
    reopened.validate_and_consume_transfer(
      next,
      requested,
      Verified,
      1103L,
      900000L,
    )
    is Rejected(NonceReplayed),
  )
}
