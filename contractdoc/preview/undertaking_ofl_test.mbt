///|
async test "OFL undertaking changes typography and retains clauses slots and geometry" {
  let original_manifest = @contractdoc.undertaking_manifest()
  let manifest = @contractdoc.undertaking_ofl_manifest()
  let original_root = "assets/contracts/youthpolicy/undertaking-v1/"
  let root = "assets/contracts/youthpolicy/undertaking-ofl-v2/"
  let source = @fs.read_file(root + manifest.filename).binary().to_fixedarray()
  let fillable = @fs.read_file(root + manifest.fillable_filename)
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
  let original_source = @fs.read_file(
      original_root + original_manifest.filename,
    )
    .binary()
    .to_fixedarray()
  let original_fillable = @fs.read_file(
      original_root + original_manifest.fillable_filename,
    )
    .binary()
    .to_fixedarray()
  assert_eq(
    "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(original_source)),
    original_manifest.sha256,
  )
  let old = @opc.open(original_source)
  let current = @opc.open(source)
  assert_eq(@docx.read(old), @docx.read(current))
  assert_eq(
    @docx.read(@opc.open(original_fillable)),
    @docx.read(@opc.open(fillable)),
  )
  assert_eq(
    @docx.inspect_document(old).sections,
    @docx.inspect_document(current).sections,
  )
  assert_eq(
    @worker.exact_docx_markers(original_fillable),
    @worker.exact_docx_markers(fillable),
  )
  for part in old.parts {
    if ![
        "word/document.xml", "word/styles.xml", "word/numbering.xml", "word/fontTable.xml",
      ].contains(part.name) {
      assert_eq(current.part(part.name), Some(part))
    }
  }
  for p in @docx.inspect_document(current).paragraphs {
    if p.runs.map(run => run.text).join("").has_prefix("承诺单位：") {
      assert_eq(p.metadata.first_line_twips, Some(0))
      assert_eq(p.metadata.alignment, Some("right"))
    }
    for run in p.runs {
      if run.font_ascii is Some(font) {
        assert_eq(font, "Noto Sans SC")
      }
      if run.font_east_asia is Some(font) {
        assert_eq(font, "Noto Sans SC")
      }
    }
  }
  let preview = @preview.template(fillable, manifest)
  assert_eq(preview.template_id, manifest.template_id)
  assert_eq(preview.template_version, "v2")
}

///|
async test "generated OFL preview accepts exact current values without reopening edits" {
  let manifest = @contractdoc.undertaking_ofl_manifest()
  let template = @fs.read_file(
      "assets/contracts/youthpolicy/undertaking-ofl-v2/" +
      manifest.fillable_filename,
    )
    .binary()
    .to_fixedarray()
  let packet = {
    ..@contractdoc.new_packet(
      manifest,
      "preview-frozen",
      "preview-frozen-key",
      "tenant",
      "org",
      "subject",
      "order",
      None,
      [MasterLease],
      1L,
    ),
    state: @contractdoc.Generated,
    revision: 6L,
    values: [
      { field_id: "lessee.name", value: "技术验收样例", },
      { field_id: "undertaking.signed_date", value: "2026-09-22", },
    ],
  }
  let values = packet.values.copy()
  let baseline = @preview.render(
    template,
    manifest,
    packet,
    CustomerMessenger,
    MasterLease,
    [],
  )
  for
    state in [
      @contractdoc.GenerationRequested,
      Generated,
      GenerationFailed,
      Effective,
      Closed,
      Superseded,
    ] {
    let frozen = { ..packet, state, }
    let rendered = @preview.render(
      template,
      manifest,
      frozen,
      CustomerMessenger,
      MasterLease,
      values,
    )
    assert_eq(rendered.packet_revision, 6L)
    assert_eq(rendered.blocks, baseline.blocks)
    assert_eq(rendered.pages, baseline.pages)
    assert_eq(frozen.values, values)
  }
  let rejected : Array[Array[@contractdoc.ContractFieldValue]] = [
    [{ field_id: "lessee.name", value: "unauthorized change", }],
    [{ field_id: "lease.total_rent", value: "", }],
    [{ field_id: "unknown", value: "", }],
    [values[0], values[0]],
  ]
  for changes in rejected {
    try
      @preview.render(
        template,
        manifest,
        packet,
        CustomerMessenger,
        MasterLease,
        changes,
      )
    catch {
      @preview.ContractPreviewError::InvalidDraft(_) => ()
      error => fail("unexpected preview error: \{Repr(error)}")
    } noraise {
      _ => fail("frozen preview accepted an edit or foreign field")
    }
  }
}
