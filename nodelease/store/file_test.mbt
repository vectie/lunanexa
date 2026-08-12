///|
fn lease_intent(
  lease_id : String,
  node_id : String,
  idempotency_key : String,
) -> @nodelease.ExclusiveNodeLeaseIntent {
  let now = @async.now()
  {
    version: @nodelease.contract_version,
    idempotency_key,
    lease_id,
    node_id,
    subject_ref: "subject-1",
    unix_username: "user_1",
    access_credential_ref: "ssh-cert:\{lease_id}",
    starts_unix_ms: now - 1000L,
    expires_unix_ms: now + 60000L,
  }
}

///|
async test "exclusive lease store is durable, idempotent, and node exclusive" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-store-")
  let path = "\{directory}/leases.json"
  let store = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let intent = lease_intent("lease-1", "node-1", "request-1")
  let first = store.issue(intent, 1000L)
  let replay = store.issue(intent, 1100L)
  assert_eq(first, replay)
  assert_true(store.node_blocks_managed_placement("node-1"))
  let mut conflict_rejected = false
  ignore(store.issue(lease_intent("lease-2", "node-1", "request-2"), 1200L)) catch {
    _ => conflict_rejected = true
  }
  assert_true(conflict_rejected)
  let reopened = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  assert_eq(reopened.lease("lease-1"), Some(first))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "completed lease releases managed placement" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-complete-")
  let path = "\{directory}/leases.json"
  let store = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let mut lease = store.issue(
    lease_intent("lease-1", "node-1", "request-1"),
    1000L,
  )
  for
    state in [
      @nodelease.ExclusiveLeaseState::Provisioning,
      Active,
      Draining,
      RevokingAccess,
      Sanitizing,
      Completed,
    ] {
    lease = store.transition(
      "lease-1",
      {
        expected_generation: lease.generation,
        state,
        evidence_receipt: "evidence:\{lease.generation}",
      },
      lease.updated_unix_ms + 1L,
    )
  }
  assert_false(store.node_blocks_managed_placement("node-1"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "expiry never releases a possibly provisioned node" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-expiry-")
  let path = "\{directory}/leases.json"
  let store = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let expiring_intent = {
    ..lease_intent("lease-1", "node-1", "request-1"),
    starts_unix_ms: 1000L,
    expires_unix_ms: 10000L,
  }
  let reserved = store.issue(expiring_intent, 1000L)
  let provisioning = store.transition(
    "lease-1",
    {
      expected_generation: reserved.generation,
      state: Provisioning,
      evidence_receipt: "node:provisioning",
    },
    2000L,
  )
  assert_true(store.reconcile_expired(10000L))
  let expired = store.lease("lease-1").unwrap()
  assert_eq(expired.state, Expiring)
  assert_eq(expired.generation, provisioning.generation + 1L)
  assert_true(store.node_blocks_managed_placement("node-1"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "expiry keeps even a reserved lease fenced until sanitization" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-reserved-expiry-")
  let store = @store.FileExclusiveLeaseStore::open(
    "\{directory}/leases.json",
    "lease-secret",
  )
  let intent = {
    ..lease_intent("lease-reserved", "node-reserved", "request-reserved"),
    starts_unix_ms: 1000L,
    expires_unix_ms: 2000L,
  }
  let reserved = store.issue(intent, 1000L)
  assert_eq(reserved.state, Reserved)
  assert_true(store.reconcile_expired(2000L))
  let expiring = store.lease(intent.lease_id).unwrap()
  assert_eq(expiring.state, Expiring)
  assert_true(store.node_blocks_managed_placement(intent.node_id))
  @fs.rmdir(directory, recursive=true)
}
