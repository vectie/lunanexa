///|
async test "exclusive lease PostgreSQL restart preserves expiry fence and generation" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  database.save_opaque_snapshot(
    "exclusive_node_leases",
    @nodelease.snapshot_schema_version,
    @nodelease.ExclusiveLeaseSnapshot::{
      schema_version: @nodelease.snapshot_schema_version,
      leases: [],
    }
    .to_json()
    .stringify(),
  )
  let secret = "postgres-exclusive-lease-signing-secret-more-than-32-bytes"
  let now = @async.now()
  let store = @store.FileExclusiveLeaseStore::open_postgres(database, secret)
  let lease = store.issue(
    {
      version: @nodelease.contract_version,
      idempotency_key: "postgres-exclusive-request",
      lease_id: "postgres-exclusive-lease",
      node_id: "postgres-node",
      subject_ref: "postgres-subject",
      unix_username: "postgres_user",
      access_credential_ref: "ssh-cert:postgres-exclusive-lease",
      starts_unix_ms: now - 1000L,
      expires_unix_ms: now + 2L,
    },
    now,
  )
  let active = store.transition(
    lease.intent.lease_id,
    {
      expected_generation: lease.generation,
      state: Provisioning,
      evidence_receipt: "postgres:provisioning",
    },
    now + 1L,
  )
  let reopened = @store.FileExclusiveLeaseStore::open_postgres(database, secret)
  assert_eq(reopened.lease(lease.intent.lease_id), Some(active))
  assert_true(reopened.reconcile_expired(now + 2L))
  let expired = reopened.lease(lease.intent.lease_id).unwrap()
  assert_eq(expired.state, Expiring)
  assert_true(reopened.node_blocks_managed_placement("postgres-node"))
  let restarted = @store.FileExclusiveLeaseStore::open_postgres(
    database, secret,
  )
  assert_eq(restarted.lease(lease.intent.lease_id), Some(expired))
  let paid = restarted.issue(
    {
      ..lease.intent,
      idempotency_key: "postgres-paid-request",
      lease_id: "postgres-paid-lease",
      node_id: "postgres-paid-node",
      starts_unix_ms: now,
      expires_unix_ms: now + 10000L,
    },
    now,
  )
  let preparing = restarted.transition(
    paid.intent.lease_id,
    {
      expected_generation: paid.generation,
      state: Provisioning,
      evidence_receipt: "postgres:paid-preparing",
    },
    now + 1000L,
  )
  let activation : @nodelease.ExclusiveLeaseTransitionRequest = {
    expected_generation: preparing.generation,
    state: Active,
    evidence_receipt: "postgres:paid-active",
  }
  let activated = restarted.transition(
    paid.intent.lease_id,
    activation,
    now + 9000L,
    activation_duration_ms=10000L,
  )
  assert_eq(activated.intent.starts_unix_ms, now + 9000L)
  assert_eq(activated.intent.expires_unix_ms, now + 19000L)
  let recovered = @store.FileExclusiveLeaseStore::open_postgres(
    database, secret,
  )
  assert_eq(recovered.lease(paid.intent.lease_id), Some(activated))
  try
    recovered.transition(
      paid.intent.lease_id,
      activation,
      now + 9500L,
      activation_duration_ms=10000L,
    )
  catch {
    @nodelease.ExclusiveLeaseError::StaleGeneration => ()
    error => fail("unexpected replay error: \{error}")
  } noraise {
    _ => fail("stale activation must not extend the paid interval")
  }
  assert_eq(recovered.lease(paid.intent.lease_id), Some(activated))
  ignore(recovered.reconcile_expired(now + 10000L))
  assert_eq(recovered.lease(paid.intent.lease_id), Some(activated))
  assert_true(recovered.reconcile_expired(now + 19000L))
  let final_store = @store.FileExclusiveLeaseStore::open_postgres(
    database, secret,
  )
  let final_lease = final_store.lease(paid.intent.lease_id).unwrap()
  assert_eq(final_lease.state, Expiring)
  assert_eq(final_lease.intent.expires_unix_ms, now + 19000L)
  database.close()
}
