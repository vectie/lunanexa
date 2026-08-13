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
    2000L,
  )
  assert_eq(packet.marker_value("{{lease.month.mark}}"), "☒")
  assert_eq(packet.marker_value("{{lease.day.mark}}"), "□")
  assert_eq(packet.marker_value("{{lease.month.start}}"), "")
  assert_eq(packet.marker_value("{{reservation.operator_comment}}"), "")
}
