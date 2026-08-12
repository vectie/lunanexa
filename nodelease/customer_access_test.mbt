///|
fn customer_lease(
  state : @nodelease.ExclusiveLeaseState,
) -> @nodelease.ExclusiveNodeLease {
  {
    intent: {
      version: @nodelease.contract_version,
      idempotency_key: "customer-request-1",
      lease_id: "customer-lease-1",
      node_id: "internal-node-172-20-0-14",
      subject_ref: "subject-customer",
      unix_username: "customer",
      access_credential_ref: "secret:never-expose-this-reference",
      starts_unix_ms: 1000L,
      expires_unix_ms: 10000L,
    },
    state,
    generation: 4L,
    created_unix_ms: 1000L,
    updated_unix_ms: 4000L,
    evidence_receipt: "node:active",
    authority_receipt: "controller:signed",
  }
}

///|
test "customer machine view exposes live handoff metadata without secrets" {
  let view = @nodelease.customer_machine_view(
    customer_lease(Active),
    Some(4900L),
    5000L,
    1000L,
  )
  assert_eq(view.reachability, Online)
  assert_eq(view.credential_handoff.state, Available)
  assert_eq(
    view.credential_handoff.handoff_ref,
    Some("lease-handoff:customer-lease-1:4"),
  )
  assert_false(view.credential_handoff.raw_secret_included)
  assert_eq(view.termination_confirmation, Some("TERMINATE customer-lease-1"))
  let public_json = view.to_json().stringify()
  assert_false(public_json.contains("internal-node-172-20-0-14"))
  assert_false(public_json.contains("never-expose-this-reference"))
  assert_false(public_json.contains("access_credential_ref"))
}

///|
test "customer machine view closes handoff after expiry or termination" {
  let expired = @nodelease.customer_machine_view(
    customer_lease(Active),
    Some(9000L),
    10001L,
    1000L,
  )
  assert_eq(expired.credential_handoff.state, Closed)
  assert_eq(expired.credential_handoff.handoff_ref, None)
  let draining = @nodelease.customer_machine_view(
    customer_lease(Draining),
    Some(4000L),
    5000L,
    1000L,
  )
  assert_eq(draining.credential_handoff.state, Closed)
  assert_false(draining.can_terminate)
  assert_eq(draining.termination_confirmation, None)
}

///|
test "customer machine reachability is deliberately coarse" {
  let delayed = @nodelease.customer_machine_view(
    customer_lease(Active),
    Some(3000L),
    5000L,
    1000L,
  )
  assert_eq(delayed.reachability, Delayed)
  let unknown = @nodelease.customer_machine_view(
    customer_lease(Provisioning),
    None,
    5000L,
    1000L,
  )
  assert_eq(unknown.reachability, Unknown)
  assert_eq(unknown.credential_handoff.state, Pending)
}

///|
test "customer termination targets are fail closed" {
  assert_eq(@nodelease.customer_termination_target(Requested), Some(Cancelled))
  assert_eq(@nodelease.customer_termination_target(Active), Some(Expiring))
  assert_eq(
    @nodelease.customer_termination_target(Quarantined),
    Some(RevokingAccess),
  )
  assert_eq(@nodelease.customer_termination_target(Expiring), None)
  assert_eq(@nodelease.customer_termination_target(Completed), None)
}
