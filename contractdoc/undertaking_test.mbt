///|
test "undertaking exposes only two customer fields and distinct immutable source" {
  let manifest = @contractdoc.undertaking_manifest()
  @contractdoc.validate_manifest(manifest)
  assert_true(@contractdoc.is_undertaking_template(manifest.template_id))
  assert_false(@contractdoc.is_undertaking_template("unknown"))
  assert_eq(
    @contractdoc.manifest_for_template_id(manifest.template_id),
    manifest,
  )
  assert_eq(manifest.forms.length(), 1)
  assert_eq(manifest.forms[0].form, MasterLease)
  assert_eq(
    manifest.fields.filter(field => field.owner == CustomerMessenger).length(),
    2,
  )
  assert_eq(
    manifest.fields
    .filter(field => field.locator.has_prefix("admission/"))
    .length(),
    3,
  )
  assert_true(
    manifest.sha256 != @contractdoc.youthpolicy_remote_lease_manifest().sha256,
  )
  let packet = @contractdoc.new_packet(
    manifest,
    "undertaking-preview",
    "undertaking-preview-key",
    "tenant-preview",
    "org-preview",
    "subject-preview",
    "order-preview",
    None,
    [MasterLease],
    1000L,
  )
  assert_eq(packet.marker_value("{{undertaking.signed_date.year}}"), "")
  let filled = packet.update_information(
    manifest,
    1L,
    [
      { field_id: "lessee.name", value: "测试企业", },
      { field_id: "undertaking.signed_date", value: "2026-09-16", },
    ],
    CustomerMessenger,
    "subject-preview",
    "enterprise",
    2000L,
  )
  assert_eq(filled.marker_value("{{undertaking.signed_date.year}}"), "2026")
  assert_eq(filled.marker_value("{{undertaking.signed_date.month}}"), "09")
  assert_eq(filled.marker_value("{{undertaking.signed_date.day}}"), "16")
  assert_eq(filled.marker_value("{{lessee.name}}"), "测试企业")
}
