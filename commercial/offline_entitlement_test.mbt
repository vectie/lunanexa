///|
test "offline commitment execution preserves procurement and tenant authority" {
  let store = base_store()
  store.add_commitment({
    commitment_id: "offline-capacity",
    organization_id: "org-a",
    cluster_id: "cluster-a",
    gpu_class: "dgx-spark",
    service_mode: "managed",
    capacity_units: 1L,
    effective_from_unix_ms: 2000L,
    effective_until_unix_ms: 9000L,
    created_by: "buyer-a",
    approved_by: None,
    state: Proposed,
  })
  try
    store.activate_offline_commitment(
      "org-a", "offline-capacity", "buyer-a", 2100L,
    )
  catch {
    SeparationOfDuties(_) => ()
    error => fail("unexpected authority error: \{Repr(error)}")
  } noraise {
    _ => fail("self approval succeeded")
  }
  try
    store.activate_offline_commitment(
      "org-b", "offline-capacity", "approver-a", 2100L,
    )
  catch {
    TenantMismatch => ()
    error => fail("unexpected tenant error: \{Repr(error)}")
  } noraise {
    _ => fail("cross tenant activation succeeded")
  }
  let active = store.activate_offline_commitment(
    "org-a", "offline-capacity", "approver-a", 2100L,
  )
  assert_eq(active.state, ActiveCommitment)
  assert_eq(
    store.activate_offline_commitment(
      "org-a", "offline-capacity", "approver-a", 2200L,
    ),
    active,
  )
  let restored = @commercial.CommercialStore::from_durable_snapshot(
    store.durable_snapshot(),
  )
  let revoked = restored.revoke_offline_commitment("org-a", "offline-capacity")
  assert_eq(revoked.state, CancelledCommitment)
  assert_eq(
    restored.revoke_offline_commitment("org-a", "offline-capacity"),
    revoked,
  )
  try
    restored.activate_offline_commitment(
      "org-a", "offline-capacity", "approver-a", 2300L,
    )
  catch {
    InvalidTransition(_) => ()
    error => fail("unexpected revoked target error: \{Repr(error)}")
  } noraise {
    _ => fail("revoked commitment reactivated")
  }
}
