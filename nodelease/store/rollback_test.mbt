///|
async test "failed lease reservation transition and expiry writes preserve placement authority" {
  let directory = @fs.tmpdir(prefix="lunanexa-lease-rollback-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/leases.json"
  let store = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let intent = {
    ..lease_intent("rollback-lease", "rollback-node", "rollback-request"),
    starts_unix_ms: 1000L,
    expires_unix_ms: 10000L,
  }
  let request : @nodelease.ExclusiveLeaseTransitionRequest = {
    expected_generation: 1L,
    state: Provisioning,
    evidence_receipt: "fixture:provisioning",
  }
  for stage in 0..<3 {
    let before = store.leases()
    let disk = @fs.read_file(path).text()
    let blocked = store.node_blocks_managed_placement(intent.node_id)
    @fs.mkdir(path + ".next")
    for _ in 0..<2 {
      try {
        match stage {
          0 => ignore(store.issue(intent, 1000L))
          1 => ignore(store.transition(intent.lease_id, request, 2000L))
          _ => ignore(store.reconcile_expired(10000L))
        }
      } catch {
        _ => ()
      } noraise {
        _ => fail("lease write unexpectedly succeeded")
      }
      assert_eq(@async.with_timeout(1000, () => store.leases()), before)
      assert_eq(@fs.read_file(path).text(), disk)
      assert_eq(store.node_blocks_managed_placement(intent.node_id), blocked)
    }
    @fs.rmdir(path + ".next")
    @async.with_timeout(1000, () => {
      match stage {
        0 => ignore(store.issue(intent, 1000L))
        1 => ignore(store.transition(intent.lease_id, request, 2000L))
        _ => assert_true(store.reconcile_expired(10000L))
      }
      assert_eq(
        @store.FileExclusiveLeaseStore::open(path, "lease-secret").leases(),
        store.leases(),
      )
      assert_eq(store.leases().length(), 1)
      assert_true(store.node_blocks_managed_placement(intent.node_id))
    })
  }
  let reopened = @store.FileExclusiveLeaseStore::open(path, "lease-secret")
  let expired = reopened.lease(intent.lease_id).unwrap()
  assert_eq(expired.state, Expiring)
  assert_eq(expired.generation, 3L)
  assert_false(reopened.reconcile_expired(10001L))
  assert_eq(reopened.lease(intent.lease_id), Some(expired))
  assert_true(reopened.node_blocks_managed_placement(intent.node_id))
}
