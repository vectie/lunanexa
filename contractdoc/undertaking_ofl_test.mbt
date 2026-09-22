///|
test "open-font undertaking is independent version with identical legal fields" {
  let original = @contractdoc.undertaking_manifest()
  let open_font = @contractdoc.undertaking_ofl_manifest()
  @contractdoc.validate_manifest(open_font)
  assert_eq(open_font.template_version, "v2")
  assert_eq(open_font.fields, original.fields)
  assert_eq(open_font.forms, original.forms)
  assert_true(open_font.sha256 != original.sha256)
  assert_true(open_font.fillable_sha256 != original.fillable_sha256)
  assert_true(@contractdoc.is_undertaking_template(open_font.template_id))
  assert_eq(
    @contractdoc.manifest_for_template_id(open_font.template_id),
    open_font,
  )
  assert_eq(
    @contractdoc.manifest_for_template_id(original.template_id),
    original,
  )
}
