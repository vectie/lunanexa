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
  database.close()
}
