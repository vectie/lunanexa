///|
fn intent() -> @nodelease.ExclusiveNodeLeaseIntent {
  {
    version: @nodelease.contract_version,
    idempotency_key: "lease-request-1",
    lease_id: "lease-1",
    node_id: "dgx-spark-2",
    subject_ref: "subject-1",
    unix_username: "user_1",
    access_credential_ref: "ssh-cert:lease-1",
    starts_unix_ms: 1000L,
    expires_unix_ms: 5000L,
  }
}

///|
test "exclusive lease validates safe credential references" {
  @nodelease.validate_intent(intent())
  assert_false(
    @nodelease.valid_access_credential_ref("plaintext-password-value"),
  )
  assert_false(@nodelease.valid_access_credential_ref("ssh-cert:"))
  assert_false(@nodelease.valid_access_credential_ref("secret:"))
  assert_false(@nodelease.valid_unix_username("root"))
}

///|
test "exclusive lease lifecycle is generation fenced" {
  let reserved : @nodelease.ExclusiveNodeLease = {
    intent: intent(),
    state: Reserved,
    generation: 1L,
    created_unix_ms: 1000L,
    updated_unix_ms: 1000L,
    evidence_receipt: "lease:reserved",
    authority_receipt: "authority:one",
  }
  let provisioning = reserved.transition(
    Provisioning,
    1L,
    "node:provisioning",
    1100L,
  )
  assert_eq(provisioning.generation, 2L)
  assert_eq(provisioning.state, Provisioning)
  let mut rejected = false
  ignore(provisioning.transition(Active, 1L, "node:ready", 1200L)) catch {
    _ => rejected = true
  }
  assert_true(rejected)
}

///|
test "quarantine continues through cleanup and never enables placement" {
  assert_true(@nodelease.state_blocks_managed_placement(Quarantined))
  assert_true(@nodelease.transition_allowed(Quarantined, RevokingAccess))
  assert_false(@nodelease.transition_allowed(Quarantined, Completed))
  assert_false(@nodelease.state_blocks_managed_placement(Completed))
}

///|
test "generation exhaustion cannot wrap a lease back into a usable value" {
  let exhausted : @nodelease.ExclusiveNodeLease = {
    intent: intent(),
    state: Reserved,
    generation: 9223372036854775807L,
    created_unix_ms: 1000L,
    updated_unix_ms: 1000L,
    evidence_receipt: "lease:reserved",
    authority_receipt: "authority:max-generation",
  }
  try
    ignore(
      exhausted.transition(
        Provisioning,
        exhausted.generation,
        "controller:provisioning",
        1001L,
      ),
    )
  catch {
    @nodelease.ExclusiveLeaseError::InvalidIntent(_) => ()
    _ => fail("expected exhausted generation rejection")
  } noraise {
    _ => fail("generation overflow was accepted")
  }
}
