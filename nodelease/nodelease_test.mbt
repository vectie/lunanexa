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
    InvalidIntent(_) => ()
    _ => fail("expected exhausted generation rejection")
  } noraise {
    _ => fail("generation overflow was accepted")
  }
}

///|
fn nodelease_intent_is_valid(
  candidate : @nodelease.ExclusiveNodeLeaseIntent,
) -> Bool {
  try @nodelease.validate_intent(candidate) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
test "exclusive lease username and credential mutation fuzz fails closed" {
  let base = intent()
  for length in 0..<=40 {
    assert_eq(
      nodelease_intent_is_valid({ ..base, unix_username: "a".repeat(length) }),
      length > 0 && length <= 32,
    )
  }
  for position in 0..<=31 {
    for mutation in ["/", "\\", " ", "\n", "\r", ":", ".", "%", "服务"] {
      let username = "a".repeat(position) + mutation + "b".repeat(31 - position)
      assert_false(
        nodelease_intent_is_valid({ ..base, unix_username: username }),
      )
    }
  }
  for length in 0..<=500 {
    let reference = "ssh-cert:" + "a".repeat(length)
    assert_eq(
      nodelease_intent_is_valid({ ..base, access_credential_ref: reference }),
      length > 0 && length <= 480,
    )
  }
  for
    reference in [
      "ssh-cert:../root", "secret:lease/child", "SSH-CERT:lease", "password:lease",
      "ssh-cert:lease\nforged", "ssh-cert:服务",
    ] {
    assert_false(
      nodelease_intent_is_valid({ ..base, access_credential_ref: reference }),
    )
  }
}

///|
test "helper receipt timestamp mutation fuzz rejects framing and zero time" {
  let action = @nodelease.LeaseAgentAction::SanitizeLease(
    lease_id="lease-1",
    username="user_1",
    generation=7L,
  )
  let prefix = "lunanexa-helper-v1:sanitize:lease-1:7:verified:"
  assert_eq(@nodelease.helper_receipt_timestamp(action, "\{prefix}1"), Some(1L))
  for
    suffix in [
      "",
      "0",
      "-1",
      "+1",
      " 1",
      "1 ",
      "1:forged",
      "1\nforged",
      "9223372036854775808",
      "1".repeat(21),
    ] {
    assert_eq(
      @nodelease.helper_receipt_timestamp(action, "\{prefix}\{suffix}"),
      None,
    )
  }
}
