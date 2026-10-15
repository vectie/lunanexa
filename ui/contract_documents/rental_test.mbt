///|
test "an unloaded rental never shows or previews another order and resolves after refresh" {
  let manifest = @contractdoc.undertaking_ofl_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "other-packet",
    "key",
    "tenant-b",
    "org-b",
    "subject-b",
    "other-order",
    None,
    [MasterLease],
    1000L,
  )
  let initial = {
    ..@contract_documents.default_state(English),
    actor_owner: CustomerMessenger,
    manifest: Some(manifest),
    available_manifests: [manifest],
    packets: [packet],
    selected_packet_id: Some(packet.packet_id),
  }
  let focused = initial.open_order("rental-a", "tenant-a", manifest.template_id)
  assert_eq(focused.selected_packet_id, None)
  assert_true(focused.preview_request() is None)
  assert_false(@contract_documents.render(focused).contains("other-packet"))
  let mine = {
    ..packet,
    packet_id: "mine",
    order_ref: "rental-a",
    tenant_ref: "tenant-a",
  }
  let loaded = { ..focused, packets: [packet, mine], }.restore_order_context()
  assert_eq(loaded.selected_packet_id, Some("mine"))
  assert_eq(loaded.creation_order_ref, "rental-a")
  let draft = loaded.update(
    FieldChanged("lessee.legal_name", "Unsaved company"),
  )
  assert_eq(
    draft.open_order("rental-a", "tenant-a", manifest.template_id).draft_values,
    draft.draft_values,
  )
}

///|
test "user access with no tenant contract does not fall back to another tenant" {
  let manifest = @contractdoc.undertaking_ofl_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "other-packet",
    "key",
    "other-tenant",
    "other-org",
    "other-subject",
    "other-order",
    None,
    [MasterLease],
    1000L,
  )
  let state = {
    ..@contract_documents.default_state(English),
    manifest: Some(manifest),
    available_manifests: [manifest],
    packets: [packet],
  }.update(SelectTenant("new-tenant"))
  assert_eq(state.selected_packet_id, None)
  assert_true(state.preview_request() is None)
  assert_eq(state.current_order(), None)
  assert_false(@contract_documents.render(state).contains("other-packet"))
}

///|
test "only one current passed scan is selected without inventing a signing date" {
  let manifest = @contractdoc.undertaking_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet",
    "key",
    "tenant",
    "org",
    "subject",
    "order",
    None,
    [MasterLease],
    1000L,
  )
  let state = {
    ..@contract_documents.default_state(English),
    packets: [packet],
    confirmation: Some(SubmitUndertaking("packet", 1L, "", "")),
    signed_artifacts: [("order", "scan", "v1", 2000L)],
  }
  assert_eq(
    state.select_only_signed_scan().confirmation,
    Some(SubmitUndertaking("packet", 1L, "scan", "")),
  )
  let ambiguous = {
    ..state,
    signed_artifacts: [
      ..state.signed_artifacts,
      ("order", "scan2", "v2", 3000L),
    ],
  }
  assert_eq(
    ambiguous.select_only_signed_scan().confirmation,
    state.confirmation,
  )
}
