///|
test "node lease envelope is node and credential scoped" {
  let lease : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "request-transport",
      lease_id: "lease-transport",
      node_id: "node-a",
      subject_ref: "subject-a",
      unix_username: "tenant_a",
      access_credential_ref: "credential-a",
      starts_unix_ms: 1000L,
      expires_unix_ms: 9000L,
    },
    state: Active,
    generation: 3L,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
    evidence_receipt: "controller:evidence",
    authority_receipt: "controller-only-authority-secret",
  }
  let envelope = @nodelease.node_transport_lease(
    lease, "node-a", "node-a-credential",
  )
  assert_false(envelope.authority_receipt.contains("controller-only"))
  assert_true(
    @nodelease.valid_node_transport_lease(
      envelope, "node-a", "node-a-credential",
    ),
  )
  assert_false(
    @nodelease.valid_node_transport_lease(
      envelope, "node-b", "node-a-credential",
    ),
  )
  assert_false(
    @nodelease.valid_node_transport_lease(
      envelope, "node-a", "node-b-credential",
    ),
  )
  assert_false(
    @nodelease.valid_node_transport_lease(
      { ..envelope, generation: 4L },
      "node-a",
      "node-a-credential",
    ),
  )
}

///|
test "node lease carries only exact controller-authorized helper actions" {
  let lease : @nodelease.ExclusiveNodeLease = {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "request-helper-transport",
      lease_id: "lease-helper-transport",
      node_id: "node-a",
      subject_ref: "subject-a",
      unix_username: "tenant_a",
      access_credential_ref: "ssh-cert:lease-helper-transport",
      starts_unix_ms: 1000L,
      expires_unix_ms: 9000L,
    },
    state: Active,
    generation: 3L,
    created_unix_ms: 1000L,
    updated_unix_ms: 1100L,
    evidence_receipt: "controller:evidence",
    authority_receipt: "controller-only-authority-secret",
  }
  let helper_secret = "root-helper-authorization-secret-more-than-32-bytes"
  let envelope = @nodelease.node_transport_lease_with_helper_authorizations(
    lease, "node-a", "node-a-credential", helper_secret, 2000L,
  )
  assert_true(
    @nodelease.valid_node_transport_lease(
      envelope, "node-a", "node-a-credential",
    ),
  )
  let action = @nodelease.LeaseAgentAction::ProvisionAccess(
    lease_id="lease-helper-transport",
    username="tenant_a",
    credential_ref="ssh-cert:lease-helper-transport",
    expires_unix_ms=9000L,
    generation=3L,
  )
  let authorization = @nodelease.helper_authorization_from_transport_lease(
    envelope, action, 2000L,
  ).unwrap()
  assert_true(
    @nodelease.valid_helper_authorization(
      action, authorization, helper_secret, 2000L,
    ),
  )
  let early_revoke = @nodelease.LeaseAgentAction::RevokeAccess(
    lease_id="lease-helper-transport",
    username="tenant_a",
    generation=3L,
  )
  assert_eq(
    @nodelease.helper_authorization_from_transport_lease(
      envelope, early_revoke, 2000L,
    ),
    None,
  )
  assert_true(
    @nodelease.helper_authorization_from_transport_lease(
      envelope, early_revoke, 9000L,
    )
    is Some(_),
  )
  assert_eq(
    @nodelease.helper_authorization_from_transport_lease(
      envelope,
      SanitizeLease(
        lease_id="lease-helper-transport",
        username="tenant_a",
        generation=3L,
      ),
      2000L,
    ),
    None,
  )
  for
    mutation in [
      @nodelease.LeaseAgentAction::ProvisionAccess(
        lease_id="lease-helper-transport",
        username="tenant_other",
        credential_ref="ssh-cert:lease-helper-transport",
        expires_unix_ms=9000L,
        generation=3L,
      ),
      RevokeAccess(
        lease_id="lease-helper-transport",
        username="tenant_a",
        generation=4L,
      ),
    ] {
    assert_eq(
      @nodelease.helper_authorization_from_transport_lease(
        envelope, mutation, 2000L,
      ),
      None,
    )
    assert_false(
      @nodelease.valid_helper_authorization(
        mutation, authorization, helper_secret, 2000L,
      ),
    )
  }
  assert_false(
    @nodelease.valid_helper_authorization(
      action, authorization, helper_secret, 86409000L,
    ),
  )
  assert_eq(
    @nodelease.helper_authorization_from_transport_lease(
      @nodelease.node_transport_lease(lease, "node-a", "node-a-credential"),
      action,
      2000L,
    ),
    None,
  )
}
