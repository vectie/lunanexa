///|
async test "PostgreSQL handoffs recover redemption quota and revocation through fresh connections" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let issuer = "postgres-handoff-fixture-secret-more-than-32-bytes"
  let database = @database.PostgresDatabase::open(url)
  let store = ClientHandoffStore::open_postgres(database, issuer)
  let issued = store.issue(handoff_intent(100000L), 100000L)
  let redeemed = store.redeem(issued.handoff_code, "desktop-client", 100001L)
  ignore(
    store.authorize(
      redeemed.api_secret,
      Inference,
      model="model-a",
      100002L,
      true,
    ),
  )
  let before = store.snapshot()
  database.close()
  for _ in 0..<2 {
    try
      store.revoke_for_subject(
        issued.handoff_id,
        "tenant-1",
        "subject-1",
        100003L,
      )
    catch {
      @database.DatabaseError::QueryFailed(_) => ()
      error => fail("unexpected disconnected write error: \{Repr(error)}")
    } noraise {
      _ => fail("closed database accepted revocation")
    }
    assert_eq(store.snapshot(), before)
  }
  let recovered_database = @database.PostgresDatabase::open(url)
  defer recovered_database.close()
  let recovered = ClientHandoffStore::open_postgres(recovered_database, issuer)
  assert_eq(recovered.snapshot(), before)
  assert_eq(recovered.snapshot().credentials[0].consumed_requests, 1L)
  try recovered.redeem(issued.handoff_code, "desktop-client", 100004L) catch {
    @handoff.ClientHandoffError::AlreadyRedeemed => ()
    error => fail("unexpected replay error: \{Repr(error)}")
  } noraise {
    _ => fail("redeemed code replayed after database reconnect")
  }
  ignore(
    recovered.revoke_for_subject(
      issued.handoff_id,
      "tenant-1",
      "subject-1",
      100005L,
    ),
  )
  let third_database = @database.PostgresDatabase::open(url)
  defer third_database.close()
  let revoked = ClientHandoffStore::open_postgres(third_database, issuer)
  try revoked.authorize(redeemed.api_secret, ModelList, 100006L, false) catch {
    @handoff.ClientHandoffError::Unauthorized => ()
    error => fail("unexpected revoked error: \{Repr(error)}")
  } noraise {
    _ => fail("revoked credential survived fresh connection")
  }
}
