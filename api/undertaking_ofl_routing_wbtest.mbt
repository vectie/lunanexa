///|
test "OFL undertaking routes separately while immutable legacy templates remain available" {
  let old = @contractdoc.undertaking_manifest()
  let current = @contractdoc.undertaking_ofl_manifest()
  assert_eq(
    contract_preview_template_path(old),
    "assets/contracts/youthpolicy/undertaking-v1/device-use-undertaking.fillable.docx",
  )
  assert_eq(
    contract_preview_template_path(current),
    "assets/contracts/youthpolicy/undertaking-ofl-v2/device-use-undertaking.ofl-v2.fillable.docx",
  )
  assert_true(old.sha256 != current.sha256)
  assert_true(old.fillable_sha256 != current.fillable_sha256)
  let catalog = contract_document_catalog()
  assert_eq(catalog.length(), 3)
  assert_true(catalog.contains(old))
  assert_true(catalog.contains(current))
  assert_eq(@contractdoc.manifest_for_template_id(old.template_id), old)
  assert_eq(@contractdoc.manifest_for_template_id(current.template_id), current)
}

///|
test "known undertaking quote digests bind editions without rewriting legacy admission" {
  let order = undertaking_test_order()
  let quote = order.quote.unwrap()
  let old = @contractdoc.undertaking_manifest()
  let current = @contractdoc.undertaking_ofl_manifest()
  let old_order = {
    ..order,
    quote: Some({ ..quote, terms_digest: old.sha256, }),
  }
  let new_order = {
    ..order,
    quote: Some({ ..quote, terms_digest: current.sha256, }),
  }
  assert_true(undertaking_quote_matches_template(old_order, old))
  assert_false(undertaking_quote_matches_template(old_order, current))
  assert_true(undertaking_quote_matches_template(new_order, current))
  assert_false(undertaking_quote_matches_template(new_order, old))
  // Historical third-party/unrecognized digests are not relabeled OFL.
  assert_true(undertaking_quote_matches_template(order, old))
  assert_true(undertaking_quote_matches_template(order, current))
  assert_false(
    undertaking_quote_matches_template({ ..order, quote: None, }, current),
  )
}

///|
async test "packaged OFL and legacy templates resolve from absolute asset root" {
  let temporary = @fs.tmpdir(prefix="lunanexa-packaged-contracts-")
  defer @fs.rmdir(temporary, recursive=true)
  for
    manifest in [
      @contractdoc.undertaking_manifest(),
      @contractdoc.undertaking_ofl_manifest(),
    ] {
    let relative = contract_preview_template_path(
      manifest,
      assets_root="assets/contracts",
    )
    let path = contract_preview_template_path(manifest, assets_root=temporary)
    assert_true(path.has_prefix(temporary + "/"))
    let directory = if @contractdoc.undertaking_manifest().template_id ==
      manifest.template_id {
      "\{temporary}/youthpolicy/undertaking-v1"
    } else {
      "\{temporary}/youthpolicy/undertaking-ofl-v2"
    }
    @fs.mkdir(directory, recursive=true)
    let bytes = @fs.read_file(relative).binary()
    @fs.write_file(path, bytes, create_mode=CreateOrTruncate)
    assert_eq(@fs.read_file(path).binary(), bytes)
    assert_eq(
      "sha256:" +
      @crypto.bytes_to_hex_string(@crypto.sha256(bytes.to_fixedarray())),
      manifest.fillable_sha256,
    )
  }
}
