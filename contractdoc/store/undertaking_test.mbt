///|
async test "undertaking revision invalidates submission and order cannot be reused or renewed" {
  let dir = @fs.tmpdir(prefix="undertaking-revision-")
  let store = @store.ContractDocumentStore::open("\{dir}/state.json")
  let manifest = @contractdoc.undertaking_manifest()
  let digest = "sha256:" + "a".repeat(64)
  let packet = {
    ..@contractdoc.new_packet(
      manifest,
      "undertaking-a",
      "key-a",
      "tenant-a",
      "org-a",
      "subject-a",
      "order-a",
      None,
      [MasterLease],
      1000L,
    ),
    state: Generated,
    values_sha256: Some(digest),
    values: [{ field_id: "lease.total_rent", value: "49.00", }],
  }
  ignore(store.create_packet(packet, "subject-a"))
  let approval : @contractdoc.ContractApproval = {
    approval_id: "undertaking-approval",
    packet_id: packet.packet_id,
    action: "undertaking:execute",
    expected_revision: packet.revision,
    payload: {
      evidence_sha256: Some(digest),
      signed_on: Some("2026-09-16"),
      kind: None,
      reason: None,
      amount_minor_units: Some(4900L),
      packet_values_sha256: Some(digest),
    },
    initiator: "subject-a",
    created_unix_ms: 2000L,
    status: Pending,
    decided_by: None,
    decided_unix_ms: None,
    decision_reason: None,
  }
  ignore(store.create_approval(approval))
  try
    store.decide_and_apply_approval(
      approval.approval_id,
      "subject-a",
      false,
      2500L,
    )
  catch {
    @contractdoc.ContractDocumentError::ContractApprovalSelfDecision(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("submitter cannot approve")
  }
  try
    store.register_execution(
      packet.packet_id,
      1L,
      {
        evidence_sha256: digest,
        signed_on: "2026-09-16",
        registered_by: "operator",
        registered_unix_ms: 2500L,
      },
      2500L,
    )
  catch {
    @contractdoc.ContractDocumentError::InvalidTransition(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("direct execution must not bypass approval")
  }
  try store.revise_undertaking(packet.packet_id, 1L, "subject-b", 2500L) catch {
    @contractdoc.ContractDocumentError::NotFound(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("another subject cannot revise")
  }
  let revised = store.revise_undertaking(
    packet.packet_id,
    1L,
    "subject-a",
    3000L,
  )
  assert_eq(revised.values_sha256, None)
  assert_eq(revised.artifacts, [])
  assert_eq(store.get_approval(approval.approval_id).unwrap().status, Rejected)
  try
    store.decide_and_apply_approval(
      approval.approval_id,
      "operator",
      false,
      3500L,
    )
  catch {
    @contractdoc.ContractDocumentError::ContractApprovalAlreadyDecided(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("stale submission must remain rejected")
  }
  try
    store.create_packet(
      { ..packet, packet_id: "undertaking-b", idempotency_key: "key-b", },
      "subject-a",
    )
  catch {
    @contractdoc.ContractDocumentError::AlreadyExists(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("one payment cannot fund another packet")
  }
  let effective = { ..packet, state: Effective, }
  try effective.renewal_draft(manifest, "renewed", "renewed-key", 4000L) catch {
    ContractNotRenewable(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("undertaking renewal needs a new order")
  }
  let reopened = @store.ContractDocumentStore::open("\{dir}/state.json")
  assert_eq(reopened.packet(packet.packet_id), Some(revised))
  assert_eq(
    reopened.get_approval(approval.approval_id).unwrap().status,
    Rejected,
  )
}
