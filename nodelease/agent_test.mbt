///|
test "offline expiry revokes then quarantines on sanitization failure" {
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
  lease_guard.record_success(
    provision,
    @nodelease.helper_receipt(provision, 1100L),
  )
  let revoke = lease_guard.tick(2000L)
  assert_true(revoke is RevokeAccess(..))
  lease_guard.record_success(revoke, @nodelease.helper_receipt(revoke, 2000L))
  lease_guard.acknowledge_observation(lease_guard.snapshot().last_receipt)
  let revoking = {
    ..lease,
    state: RevokingAccess,
    generation: 5L,
    updated_unix_ms: 2001L,
    authority_receipt: "signed:lease-2:5",
  }
  let sanitize = lease_guard.observe_remote(Some(revoking), 2002L)
  assert_true(sanitize is SanitizeLease(..))
  let quarantine = lease_guard.record_failure(sanitize)
  assert_true(quarantine is QuarantineNode(..))
  assert_eq(lease_guard.snapshot().state, QuarantinedAgent)
}

///|
test "helper receipts are action lease and generation bound" {
  let revoke = @nodelease.LeaseAgentAction::RevokeAccess(
    lease_id="lease-2",
    username="tenant2",
    generation=4L,
  )
  let receipt = @nodelease.helper_receipt(revoke, 2000L)
  assert_true(@nodelease.valid_helper_receipt(revoke, receipt))
  assert_false(
    @nodelease.valid_helper_receipt(
      RevokeAccess(lease_id="lease-2", username="tenant2", generation=5L),
      receipt,
    ),
  )
  assert_false(@nodelease.valid_helper_receipt(revoke, "helper:accepted:2000"))
  assert_false(
    @nodelease.valid_helper_receipt(
      revoke,
      "\{@nodelease.helper_receipt(revoke, 2000L)}:forged",
    ),
  )
  assert_false(
    @nodelease.valid_helper_receipt(
      revoke,
      @nodelease.helper_receipt(revoke, -1L),
    ),
  )
}

///|
test "restart between revocation and sanitization resumes cleanup" {
  let active : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "lease-restart-key",
      lease_id: "lease-restart",
      node_id: "dgx-3",
      subject_ref: "subject-3",
      unix_username: "tenant3",
      access_credential_ref: "ssh-cert:lease-restart",
      starts_unix_ms: 1000L,
      expires_unix_ms: 2000L,
    },
    state: Active,
    generation: 3L,
    created_unix_ms: 900L,
    updated_unix_ms: 1000L,
    evidence_receipt: "controller:active",
    authority_receipt: "signed:lease-restart",
  }
  let lease_guard = @nodelease.LeaseAgentGuard::new("dgx-3")
  let provision = lease_guard.observe_remote(Some(active), 1100L)
  lease_guard.record_success(
    provision,
    @nodelease.helper_receipt(provision, 1100L),
  )
  let revoke = lease_guard.tick(2000L)
  lease_guard.record_success(revoke, @nodelease.helper_receipt(revoke, 2000L))
  let restored = @nodelease.LeaseAgentGuard::from_snapshot(
    lease_guard.snapshot(),
  )
  let revoking = {
    ..active,
    state: RevokingAccess,
    generation: 5L,
    updated_unix_ms: 2001L,
    authority_receipt: "signed:lease-restart:5",
  }
  let sanitize = restored.observe_remote(Some(revoking), 2002L)
  assert_true(sanitize is SanitizeLease(generation=5L, ..))
  restored.record_success(sanitize, @nodelease.helper_receipt(sanitize, 2002L))
  assert_eq(restored.snapshot().state, Sanitized)
  assert_true(restored.observe_remote(None, 2003L) is NoAction)
  assert_eq(restored.snapshot().state, Idle)
  assert_true(restored.snapshot().lease is None)
  let next_lease = {
    ..active,
    intent: {
      ..active.intent,
      idempotency_key: "lease-next-key",
      lease_id: "lease-next",
      subject_ref: "subject-next",
      unix_username: "tenant4",
      access_credential_ref: "ssh-cert:lease-next",
      starts_unix_ms: 3000L,
      expires_unix_ms: 4000L,
    },
    state: Provisioning,
    generation: 1L,
    updated_unix_ms: 3000L,
    authority_receipt: "signed:lease-next:1",
  }
  assert_true(
    restored.observe_remote(Some(next_lease), 3001L)
    is ProvisionAccess(generation=1L, ..),
  )
}

///|
test "offline expiry revocation is durable and waits for controller fencing" {
  let active : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "offline-expiry-key",
      lease_id: "offline-expiry",
      node_id: "dgx-offline",
      subject_ref: "subject-offline",
      unix_username: "tenant_offline",
      access_credential_ref: "ssh-cert:offline-expiry",
      starts_unix_ms: 1000L,
      expires_unix_ms: 2000L,
    },
    state: Active,
    generation: 3L,
    created_unix_ms: 900L,
    updated_unix_ms: 1000L,
    evidence_receipt: "controller:active",
    authority_receipt: "signed:offline-expiry",
  }
  let lease_guard = @nodelease.LeaseAgentGuard::new("dgx-offline")
  let provision = lease_guard.observe_remote(Some(active), 1100L)
  lease_guard.record_success(
    provision,
    @nodelease.helper_receipt(provision, 1100L),
  )
  lease_guard.acknowledge_observation(lease_guard.snapshot().last_receipt)
  let revoke = lease_guard.tick(2000L)
  assert_true(revoke is RevokeAccess(generation=3L, ..))
  lease_guard.record_success(revoke, @nodelease.helper_receipt(revoke, 2000L))
  guard lease_guard.pending_observation(2001L) is Some(pending) else {
    fail("offline revocation evidence must survive")
  }
  assert_eq(pending.action, "revoke")
  assert_true(lease_guard.tick(2100L) is NoAction)
  let restored = @nodelease.LeaseAgentGuard::from_snapshot(
    lease_guard.snapshot(),
  )
  assert_true(restored.pending_observation(2200L) is Some(_))
  let expiring = {
    ..active,
    state: Expiring,
    generation: 4L,
    updated_unix_ms: 2200L,
    authority_receipt: "signed:offline-expiry:4",
  }
  let repeated_revoke = restored.observe_remote(Some(expiring), 2201L)
  assert_true(repeated_revoke is RevokeAccess(generation=4L, ..))
  restored.record_success(
    repeated_revoke,
    @nodelease.helper_receipt(repeated_revoke, 2201L),
  )
  restored.acknowledge_observation(restored.snapshot().last_receipt)
  let revoking = {
    ..expiring,
    state: RevokingAccess,
    generation: 6L,
    updated_unix_ms: 2202L,
    authority_receipt: "signed:offline-expiry:6",
  }
  assert_true(
    restored.observe_remote(Some(revoking), 2203L)
    is SanitizeLease(generation=6L, ..),
  )
}

///|
test "termination before provisioning still enters verified cleanup" {
  let expiring : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "unprovisioned-key",
      lease_id: "unprovisioned",
      node_id: "dgx-unprovisioned",
      subject_ref: "subject-unprovisioned",
      unix_username: "tenant_unprovisioned",
      access_credential_ref: "ssh-cert:unprovisioned",
      starts_unix_ms: 1000L,
      expires_unix_ms: 4000L,
    },
    state: Expiring,
    generation: 2L,
    created_unix_ms: 900L,
    updated_unix_ms: 1100L,
    evidence_receipt: "operator:terminate",
    authority_receipt: "signed:unprovisioned",
  }
  let lease_guard = @nodelease.LeaseAgentGuard::new("dgx-unprovisioned")
  let reserved = {
    ..expiring,
    state: Reserved,
    generation: 1L,
    updated_unix_ms: 1000L,
    evidence_receipt: "controller:reserved",
    authority_receipt: "signed:unprovisioned:reserved",
  }
  assert_true(lease_guard.observe_remote(Some(reserved), 1050L) is NoAction)
  assert_true(
    lease_guard.observe_remote(Some(expiring), 1200L)
    is RevokeAccess(generation=2L, ..),
  )
}

///|
test "quarantine recovery resumes revoke instead of looping" {
  let quarantined : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "quarantine-key",
      lease_id: "quarantine-lease",
      node_id: "dgx-quarantine",
      subject_ref: "subject-quarantine",
      unix_username: "tenant_quarantine",
      access_credential_ref: "ssh-cert:quarantine-lease",
      starts_unix_ms: 1000L,
      expires_unix_ms: 4000L,
    },
    state: Quarantined,
    generation: 4L,
    created_unix_ms: 900L,
    updated_unix_ms: 1500L,
    evidence_receipt: "node:quarantine",
    authority_receipt: "signed:quarantine",
  }
  let lease_guard = @nodelease.LeaseAgentGuard::new("dgx-quarantine")
  let quarantine = lease_guard.observe_remote(Some(quarantined), 1600L)
  assert_true(quarantine is QuarantineNode(..))
  lease_guard.record_success(
    quarantine,
    @nodelease.helper_receipt(quarantine, 1600L),
  )
  lease_guard.acknowledge_observation(lease_guard.snapshot().last_receipt)
  assert_true(lease_guard.tick(1601L) is NoAction)
  let recovering = {
    ..quarantined,
    state: RevokingAccess,
    generation: 5L,
    updated_unix_ms: 1700L,
    authority_receipt: "signed:quarantine:recovery",
  }
  assert_true(
    lease_guard.observe_remote(Some(recovering), 1701L)
    is RevokeAccess(generation=5L, ..),
  )
}

///|
test "persisted lease guard rejects state without a lease" {
  let empty = @nodelease.LeaseAgentGuard::new("dgx-a").snapshot()
  try
    ignore(
      @nodelease.LeaseAgentGuard::from_snapshot({ ..empty, state: AccessActive }),
    )
  catch {
    InvalidIntent(_) => ()
    _ => fail("expected invalid persisted state")
  } noraise {
    _ => fail("missing lease was accepted")
  }
  let other_node_lease : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "cross-node-key",
      lease_id: "cross-node-lease",
      node_id: "dgx-b",
      subject_ref: "cross-node-subject",
      unix_username: "cross_node",
      access_credential_ref: "ssh-cert:cross-node-lease",
      starts_unix_ms: 1000L,
      expires_unix_ms: 2000L,
    },
    state: Active,
    generation: 1L,
    created_unix_ms: 900L,
    updated_unix_ms: 1000L,
    evidence_receipt: "controller:active",
    authority_receipt: "signed:cross-node",
  }
  try
    ignore(
      @nodelease.LeaseAgentGuard::from_snapshot({
        ..empty,
        lease: Some(other_node_lease),
        state: AccessActive,
        observed_generation: 1L,
      }),
    )
  catch {
    InvalidIntent(_) => ()
    _ => fail("expected cross-node persisted state rejection")
  } noraise {
    _ => fail("cross-node lease state was accepted")
  }
}
