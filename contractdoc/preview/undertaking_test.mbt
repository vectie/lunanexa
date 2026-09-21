///|
async test "undertaking source integrity and complete MoonLeaf preview" {
  let manifest = @contractdoc.undertaking_manifest()
  let base = "assets/contracts/youthpolicy/undertaking-v1/"
  let source = @fs.read_file(base + manifest.filename).binary().to_fixedarray()
  let fillable = @fs.read_file(base + manifest.fillable_filename)
    .binary()
    .to_fixedarray()
  assert_eq(
    "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(source)),
    manifest.sha256,
  )
  assert_eq(
    "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(fillable)),
    manifest.fillable_sha256,
  )
  assert_eq(source.length().to_int64(), manifest.byte_count)
  let original = @opc.open(source)
  let marked = @opc.open(fillable)
  // Package fidelity: only the declared document slot part may change.
  for part in original.parts {
    if part.name != "word/document.xml" {
      assert_eq(marked.part(part.name), Some(part))
    }
  }
  let xml = original.text("word/document.xml")
  let restored = marked
    .text("word/document.xml")
    .replace_all(
      old="<w:t>{{lessee.name}}</w:t>",
      new="<w:t xml:space=\"preserve\">          </w:t>",
    )
    .replace_all(
      old="<w:t>{{undertaking.signed_date.year}}</w:t>",
      new="<w:t xml:space=\"preserve\">    </w:t>",
    )
    .replace_all(
      old="<w:t>{{undertaking.signed_date.month}}</w:t>",
      new="<w:t xml:space=\"preserve\">   </w:t>",
    )
    .replace_all(
      old="<w:t>{{undertaking.signed_date.day}}</w:t>",
      new="<w:t xml:space=\"preserve\">   </w:t>",
    )
  assert_eq(restored, xml)
  assert_false(xml.contains("请示事项"))
  assert_false(xml.contains("附件1"))
  assert_true(xml.contains("北京未来科学城产业发展有限公司"))
  for
    clause in [
      "全额预付制", "49元/天", "322元/周", "1290元/月", "3600元/季",
      "13870元/年", "不予退还", "本承诺函作为本次算力设备使用的有效约定文件",
    ] {
    assert_true(xml.contains(clause))
  }
  let markers = @worker.exact_docx_markers(fillable)
  assert_eq(markers.length(), 4)
  for
    marker in [
      "{{lessee.name}}", "{{undertaking.signed_date.year}}", "{{undertaking.signed_date.month}}",
      "{{undertaking.signed_date.day}}",
    ] {
    assert_true(markers.contains(marker))
  }
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
  let scene = render(
    fillable,
    manifest,
    packet,
    CustomerMessenger,
    MasterLease,
    [
      { field_id: "lessee.name", value: "承诺测试企业", },
      { field_id: "undertaking.signed_date", value: "2026-09-16", },
    ],
  )
  assert_eq(scene.engine, "moonleaf")
  assert_eq(scene.pages.length(), 4)
  let text = scene.to_json().stringify()
  assert_true(text.contains("承诺测试企业"))
  assert_true(text.contains("2026"))
  assert_true(text.contains("13870元/年"))
  assert_false(text.contains("{{"))
  assert_false(text.contains("使用开始日期"))
  let built = template(fillable, manifest)
  assert_eq(
    @fs.read_file(base + "moonleaf-preview-template.v1.json").text(),
    built.to_json().stringify(),
  )
  assert_eq(built.page_forms, [
    MasterLease,
    MasterLease,
    MasterLease,
    MasterLease,
  ])
}
