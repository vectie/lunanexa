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
  @fs.rmdir(directory, recursive=true)
}
