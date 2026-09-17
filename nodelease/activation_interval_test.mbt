///|
test "agent restart honors activated interval instead of preparation deadline" {
  let preparing : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "paid-interval",
      lease_id: "paid-interval",
      node_id: "node-test",
      subject_ref: "subject-test",
      unix_username: "tenant_test",
      access_credential_ref: "ssh-cert:paid-interval",
      starts_unix_ms: 1000L,
      expires_unix_ms: 11000L,
    },
    state: Provisioning,
    generation: 2L,
    created_unix_ms: 1000L,
    updated_unix_ms: 2000L,
    evidence_receipt: "test:drained",
    authority_receipt: "test:transport-verified",
  }
  let agent = @nodelease.LeaseAgentGuard::new("node-test")
  let provision = agent.observe_remote(Some(preparing), 8000L)
  assert_true(provision is ProvisionAccess(..))
  let receipt = @nodelease.helper_receipt(provision, 8000L)
  agent.record_success(provision, receipt)
  agent.acknowledge_observation(receipt)
  let activated = {
    ..preparing,
    intent: {
      ..preparing.intent,
      starts_unix_ms: 9000L,
      expires_unix_ms: 19000L,
    },
    state: Active,
    generation: 3L,
    updated_unix_ms: 9000L,
    evidence_receipt: receipt,
    authority_receipt: "test:activated-transport-verified",
  }
  assert_true(agent.observe_remote(Some(activated), 9500L) is NoAction)
  let restored = @nodelease.LeaseAgentGuard::from_snapshot(agent.snapshot())
  assert_true(restored.tick(11000L) is NoAction)
  assert_true(restored.tick(18999L) is NoAction)
  assert_true(restored.tick(19000L) is RevokeAccess(generation=3L, ..))
}
