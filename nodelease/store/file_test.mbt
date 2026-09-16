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
async test "paid activation persists one full interval after delayed preparation" {
  let directory = @fs.tmpdir(prefix="lunanexa-paid-interval-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/leases.json"
  let store = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let intent = {
    ..lease_intent("paid-1", "node-1", "paid-request"),
    starts_unix_ms: 1000L,
    expires_unix_ms: 11000L,
  }
  let reserved = store.issue(intent, 1000L)
  let prepared = store.transition(
    "paid-1",
    {
      expected_generation: reserved.generation,
      state: Provisioning,
      evidence_receipt: "node:drained",
    },
    2000L,
  )
  for duration in [0L, -1L, 31536000001L] {
    try
      store.transition(
        "paid-1",
        {
          expected_generation: prepared.generation,
          state: Active,
          evidence_receipt: "node:ready",
        },
        9000L,
        activation_duration_ms=duration,
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid activation duration accepted")
    }
    assert_eq(store.lease("paid-1"), Some(prepared))
  }
  try
    store.transition(
      "paid-1",
      {
        expected_generation: prepared.generation,
        state: Active,
        evidence_receipt: "node:ready",
      },
      11000L,
      activation_duration_ms=10000L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expired preparation must not activate")
  }
  assert_eq(store.lease("paid-1"), Some(prepared))
  let active = store.transition(
    "paid-1",
    {
      expected_generation: prepared.generation,
      state: Active,
      evidence_receipt: "node:ready",
    },
    9000L,
    activation_duration_ms=10000L,
  )
  assert_eq(active.intent.starts_unix_ms, 9000L)
  assert_eq(active.intent.expires_unix_ms, 19000L)
  let view = @nodelease.customer_machine_view(
    active,
    Some(12000L),
    12000L,
    30000L,
  )
  assert_eq(view.expires_unix_ms, 19000L)
  assert_eq(view.credential_handoff.valid_until_unix_ms, 19000L)
  let reopened = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  assert_eq(reopened.lease("paid-1"), Some(active))
  try
    reopened.transition(
      "paid-1",
      {
        expected_generation: prepared.generation,
        state: Active,
        evidence_receipt: "node:ready",
      },
      10000L,
      activation_duration_ms=10000L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("stale activation must not extend the interval")
  }
  assert_eq(reopened.lease("paid-1"), Some(active))
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

///|
async test "subject query stays isolated and survives restart" {
  let directory = @fs.tmpdir(prefix="lunanexa-exclusive-subject-")
  let path = "\{directory}/leases.json"
  let store = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let first = lease_intent("lease-a", "node-a", "request-a")
  ignore(store.issue(first, 1000L))
  let second = {
    ..lease_intent("lease-b", "node-b", "request-b"),
    subject_ref: "subject-2",
  }
  ignore(store.issue(second, 1000L))
  let subject_one = store.leases_for_subject("subject-1")
  assert_eq(subject_one.length(), 1)
  assert_eq(subject_one[0].intent.lease_id, "lease-a")
  let reopened = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let subject_two = reopened.leases_for_subject("subject-2")
  assert_eq(subject_two.length(), 1)
  assert_eq(subject_two[0].intent.lease_id, "lease-b")
  @fs.rmdir(directory, recursive=true)
}
