///|
test "metadata snapshot survives controller restart" {
  let store = @store.MemoryStore::new()
  let event : @contracts.AuditEvent = {
    sequence: 1L,
    event_id: "event-1",
    timestamp_unix_ms: 10L,
    actor: "operator:local",
    policy_version: "policy-v1",
    action: "enroll",
    target: "node-1",
    prior_state: "none",
    next_state: "active",
    result: "accepted",
    correlation_receipt: "receipt-1",
    previous_hash: "genesis",
    event_hash: "hash-1",
  }
  store.append_audit(event)
  let restored = @store.MemoryStore::restore(store.snapshot())
  assert_eq(restored.audit_events(), [event])
}
