///|
test "source manifest covers seven long-horizon forms and keeps secrets offline" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  @contractdoc.validate_manifest(manifest)
  inspect(manifest.forms.length(), content="7")
  assert_true(manifest.fields.length() > 80)
  let password = manifest.field("access.initial_password").unwrap()
  assert_eq(password.collection_policy, CompleteOffline)
  assert_false(password.required)
}

///|
test "generation remains blocked until supplied information is confirmed" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-1",
    "packet-key-1",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    [MasterLease],
    1000L,
  )
  assert_true(
    @contractdoc.missing_required_fields(manifest, packet).length() > 0,
  )
  try
    packet.request_generation(
      1L, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      2000L,
    )
  catch {
    ConfirmationMismatch => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("unconfirmed packet must not generate")
  }
}

///|
test "secret-bearing offline fields cannot enter persisted packet data" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-access",
    "packet-key-access",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    [AccessConfirmation],
    1000L,
  )
  try
    packet.update_information(
      manifest,
      1L,
      [{ field_id: "access.initial_password", value: "do-not-store" }],
      CustomerMessenger,
      "subject-1",
      "enterprise-portal",
      2000L,
    )
  catch {
    ForbiddenSecret("access.initial_password") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("password must stay outside durable contract state")
  }
}

///|
test "physical choice markers use source glyphs and missing optional slots stay blank" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-choice",
    "packet-key-choice",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    [MasterLease],
    1000L,
  ).update_information(
    manifest,
    1L,
    [{ field_id: "lease.tier", value: "月租" }],
    ManagerOperator,
    "operator-1",
    "operator-console",
    2000L,
  )
  assert_eq(packet.marker_value("{{lease.month.mark}}"), "☒")
  assert_eq(packet.marker_value("{{lease.day.mark}}"), "□")
  assert_eq(packet.marker_value("{{lease.month.start}}"), "")
  assert_eq(packet.marker_value("{{reservation.operator_comment}}"), "")
}

///|
test "field ownership prevents cross-party edits and records provenance" {
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "packet-ownership",
    "packet-key-ownership",
    "tenant-1",
    "org-1",
    "subject-1",
    "order-1",
    [MasterLease, ReservationApplication, AccessConfirmation],
    1000L,
  )
  assert_eq(manifest.field("lessee.name").unwrap().owner, CustomerMessenger)
  assert_eq(manifest.field("lessor.name").unwrap().owner, ManagerOperator)
  assert_eq(
    manifest.field("access.order_number").unwrap().owner,
    PlatformDerived,
  )
  assert_eq(
    manifest.field("lessor.signatory").unwrap().owner,
    OfflineParticipant,
  )
  let customer = packet.update_information(
    manifest,
    1L,
    [{ field_id: "lessee.name", value: "星海科技" }],
    CustomerMessenger,
    "subject-1",
    "enterprise-portal",
    2000L,
  )
  let provenance = customer.assignment("lessee.name").unwrap()
  assert_eq(provenance.owner, CustomerMessenger)
  assert_eq(provenance.source_ref, "enterprise-portal")
  try
    customer.update_information(
      manifest,
      2L,
      [{ field_id: "lessor.name", value: "不应允许" }],
      CustomerMessenger,
      "subject-1",
      "enterprise-portal",
      3000L,
    )
  catch {
    InvalidInput("contract field is owned by another participant") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("customer must not edit manager-owned information")
  }
}
