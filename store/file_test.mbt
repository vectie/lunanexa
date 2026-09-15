///|
fn durable_event() -> @contracts.AuditEvent {
  {
    sequence: 1L,
    event_id: "event-durable-1",
    timestamp_unix_ms: 10L,
    actor: "operator:local",
    policy_version: "policy-v1",
    action: "persist",
    target: "controller",
    prior_state: "starting",
    next_state: "ready",
    result: "accepted",
    correlation_receipt: "receipt-durable-1",
    previous_hash: "genesis",
    event_hash: "hash-durable-1",
  }
}

///|
async test "file store atomically survives process reconstruction" {
  let directory = @fs.tmpdir(prefix="lunanexa-store-test-")
  let path = "\{directory}/state.json"
  let first = @store.FileStore::open(path)
  first.append_audit(durable_event())
  let second = @store.FileStore::open(path)
  assert_eq(second.audit_events(), [durable_event()])
  assert_true(@fs.exists(path))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "durable controller epoch fences stale leaders across restart" {
  let directory = @fs.tmpdir(prefix="lunanexa-fence-test-")
  let path = "\{directory}/state.json"
  let first = @store.FileStore::open(path)
  first.fence_controller(2L)
  let restarted = @store.FileStore::open(path)
  assert_eq(restarted.controller_epoch(), 2L)
  try restarted.fence_controller(2L) catch {
    @store.DurableStoreError::InvalidState(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("restart reused an already acquired controller epoch")
  }
  try restarted.fence_controller(1L) catch {
    @store.DurableStoreError::InvalidState(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("stale controller epoch was accepted")
  }
  restarted.fence_controller(3L)
  assert_eq(restarted.controller_epoch(), 3L)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "new durable epoch rejects mutations from a still-running old process" {
  let directory = @fs.tmpdir(prefix="lunanexa-cross-process-fence-")
  let path = "\{directory}/state.json"
  let old_controller = @store.FileStore::open(path)
  old_controller.fence_controller(2L)
  let successor = @store.FileStore::open(path)
  successor.fence_controller(3L)
  try old_controller.append_audit(durable_event()) catch {
    @store.DurableStoreError::InvalidState(message) =>
      assert_true(message.contains("newer durable epoch"))
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("stale controller mutated state after successor fencing")
  }
  let inspected = @store.FileStore::open(path)
  assert_eq(inspected.controller_epoch(), 3L)
  assert_eq(inspected.audit_events().length(), 0)
  assert_false(old_controller.current_epoch_is_durable())
  try old_controller.append_audit(durable_event()) catch {
    @store.DurableStoreError::InvalidState(_) => ()
    error => fail("unexpected retry error: \{Repr(error)}")
  } noraise {
    _ =>
      fail(
        "a fenced controller regained authority after refreshing its snapshot",
      )
  }
  assert_eq(@store.FileStore::open(path).audit_events().length(), 0)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "failed durable writes publish neither directive nor audit and release the lock" {
  let directory = @fs.tmpdir(prefix="lunanexa-store-failure-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/state.json"
  let store = @store.FileStore::open(path)
  let initial = store.backup_snapshot()
  let directive : @contracts.NodeDirective = {
    node_id: "node-rollback",
    desired_state: Draining,
    generation: 1L,
    issued_unix_ms: 1000L,
    receipt: "directive-rollback",
  }
  @fs.mkdir(path + ".next")
  try store.commit_node_directive(directive, durable_event()) catch {
    _ => ()
  } noraise {
    _ => fail("write over directory unexpectedly succeeded")
  }
  @async.with_timeout(1000, () => {
    assert_eq(store.backup_snapshot(), initial)
    assert_eq(store.node_directive(directive.node_id), None)
    assert_eq(store.audit_events(), [])
    assert_eq(@store.FileStore::open(path).backup_snapshot(), initial)
  })
  try store.fence_controller(2L) catch {
    _ => ()
  } noraise {
    _ => fail("failed epoch persistence unexpectedly succeeded")
  }
  assert_eq(store.controller_epoch(), 1L)
  @fs.rmdir(path + ".next")
  store.fence_controller(2L)
  store.commit_node_directive(directive, durable_event())
  let restored = @store.FileStore::open(path)
  assert_eq(restored.node_directive(directive.node_id), Some(directive))
  assert_eq(restored.audit_events(), [durable_event()])
}

///|
async test "failed workload receipt does not poison either idempotency index" {
  let directory = @fs.tmpdir(prefix="lunanexa-workload-rollback-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/state.json"
  let store = @store.FileStore::open(path)
  let response : @contracts.WorkloadResponse = {
    version: @contracts.contract_version,
    workload_id: "workload-rollback",
    state: Succeeded,
    output: None,
    error: None,
    usage: {
      input_units: 1,
      output_units: 1,
      accelerator_ms: 0L,
      queue_ms: 0L,
    },
    artifact_digest: "sha256:" + "a".repeat(64),
    runtime_version: "test-only",
    execution_node_id: Some("test-node"),
    timing: {
      accepted_unix_ms: 1L,
      started_unix_ms: 2L,
      first_output_unix_ms: 3L,
      completed_unix_ms: 4L,
    },
    retryable: false,
    audit_receipt: "receipt-rollback",
  }
  @fs.mkdir(path + ".next")
  try
    store.commit_workload("request-rollback", response, durable_event())
  catch {
    _ => ()
  } noraise {
    _ => fail("workload write unexpectedly succeeded")
  }
  assert_eq(store.workload_result(response.workload_id), None)
  assert_eq(store.idempotent_result("request-rollback"), None)
  assert_eq(store.audit_events(), [])
  @fs.rmdir(path + ".next")
  store.commit_workload("request-rollback", response, durable_event())
  let restored = @store.FileStore::open(path)
  assert_eq(restored.workload_result(response.workload_id), Some(response))
  assert_eq(restored.idempotent_result("request-rollback"), Some(response))
  assert_eq(restored.audit_events(), [durable_event()])
}
