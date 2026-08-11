///|
test "offline expiry revokes, sanitizes, and quarantines on helper failure" {
  let lease_guard = @nodelease.LeaseAgentGuard::new("dgx-2")
  let lease : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "lease-key",
      lease_id: "lease-2",
      node_id: "dgx-2",
      subject_ref: "subject-2",
      unix_username: "tenant2",
      access_credential_ref: "secret:lease-2",
      starts_unix_ms: 1000L,
      expires_unix_ms: 2000L,
    },
    state: Active,
    generation: 3L,
    created_unix_ms: 900L,
    updated_unix_ms: 1000L,
    evidence_receipt: "controller:active",
    authority_receipt: "signed:lease-2",
  }
  let provision = lease_guard.observe_remote(Some(lease), 1100L)
  assert_true(provision is ProvisionAccess(..))
  lease_guard.record_success(provision, "helper:provisioned")
  let revoke = lease_guard.tick(2000L)
  assert_true(revoke is RevokeAccess(..))
  lease_guard.record_success(revoke, "helper:revoked")
  let sanitize = lease_guard.tick(2001L)
  assert_true(sanitize is SanitizeLease(..))
  let quarantine = lease_guard.record_failure(sanitize)
  assert_true(quarantine is QuarantineNode(..))
  assert_eq(lease_guard.snapshot().state, QuarantinedAgent)
}
