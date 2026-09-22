///|
test "renderer filenames deny path escapes" {
  for bad_path in ["../font.ttf", "/font.ttf", "..", "a/b", "a\\b", "", "a b"] {
    try filename(bad_path) catch {
      _ => ()
    } noraise {
      _ => fail("unsafe path accepted")
    }
  }
  assert_eq(filename("font-01.ttf"), "font-01.ttf")
}

///|
/// Explicit opt-in real-font visual probe, never marks production readiness.
async test "real embedded font PDF raster probe" {
  guard @env.get_env_var("MOONLEAF_TEST_FONT") is Some(font_path) else {
    return
  }
  let output = required("MOONLEAF_TEST_OUTPUT")
  let font = @fs.read_file(font_path).binary()
  let document_xml =
    #|<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="36"/></w:rPr><w:t>MoonLeaf legal rendering</w:t></w:r></w:p><w:p><w:r><w:t>Agreement fixture: real embedded font, selectable text and deterministic layout.</w:t></w:r></w:p><w:tbl><w:tblGrid><w:gridCol w:w="4300"/><w:gridCol w:w="4300"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Resource</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>DGX Spark</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:p><w:r><w:t>Duration</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>24 hours</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:r><w:br w:type="page"/></w:r></w:p><w:p><w:r><w:t>Second page: retained evidence.</w:t></w:r></w:p></w:body></w:document>
  let p : @opc.Package = {
    parts: [
      {
        name: "word/document.xml",
        content: @utf8.encode(document_xml).to_fixedarray(),
      },
    ],
  }
  let result = @render.render_docx_pdf(
    p,
    [{ family: "Noto Sans", bytes: font, }],
    default_family="Noto Sans",
  )
  assert_eq(result.page_count, 2)
  @fs.write_file(
    output,
    result.bytes,
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  assert_true(result.bytes.find(b"/FontFile2") is Some(_))
  assert_true(result.bytes.find(b"/ToUnicode") is Some(_))
}

///|
/// Explicitly altered-font structural probe, never legal-template certification.
async test "undertaking original geometry with explicitly substituted test font" {
  guard @env.get_env_var("MOONLEAF_TEST_CJK_FONT") is Some(font_path) else {
    return
  }
  let source_path = required("MOONLEAF_TEST_UNDERTAKING")
  let output = required("MOONLEAF_TEST_CJK_OUTPUT")
  let source = @fs.read_file(source_path).binary()
  let p = @opc.open(source.to_fixedarray())
  let parts = p.parts.map(part => {
    if part.name.has_suffix(".xml") {
      let text = @xml.serialize(
        @xml.parse(@utf8.decode(Bytes::from_array(part.content))),
      )
      let changed = text
        .replace_all(old="仿宋_GB2312", new="Noto Sans SC")
        .replace_all(old="方正小标宋简体", new="Noto Sans SC")
        .replace_all(old="黑体", new="Noto Sans SC")
        .replace_all(old="Times New Roman", new="Noto Sans SC")
      { ..part, content: @utf8.encode(changed).to_fixedarray(), }
    } else {
      part
    }
  })
  let font = @fs.read_file(font_path).binary()
  let result = @render.render_docx_pdf(
    { parts, },
    [{ family: "Noto Sans SC", bytes: font, }],
    default_family="Noto Sans SC",
  ) catch {
    @render.PdfError::InvalidFont(message)
    | @render.PdfError::Unsupported(message)
    | @render.PdfError::LayoutOverflow(message) => raise Failure(message)
    error => raise error
  }
  @fs.write_file(
    output,
    result.bytes,
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  assert_true(result.page_count > 0)
}

///|
async test "recalculated workbook creates actual visual cell proof" {
  guard @env.get_env_var("MOONLEAF_TEST_FONT") is Some(font_path) else {
    return
  }
  let files : Array[(String, String)] = [
    (
      "xl/workbook.xml", "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Quote\" sheetId=\"1\" r:id=\"r1\"/></sheets></workbook>",
    ),
    (
      "xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"r1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
    ),
    (
      "xl/styles.xml", "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cellXfs count=\"1\"><xf numFmtId=\"0\"/></cellXfs></styleSheet>",
    ),
    (
      "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Price</t></is></c><c r=\"B1\" t=\"inlineStr\"><is><t>Days</t></is></c><c r=\"C1\" t=\"inlineStr\"><is><t>Total</t></is></c></row><row r=\"2\"><c r=\"A2\"><v>49</v></c><c r=\"B2\"><v>7</v></c><c r=\"C2\"><f>A2*B2</f><v>999</v></c></row></sheetData></worksheet>",
    ),
  ]
  let p : @opc.Package = {
    parts: files.map(pair => {
      name: pair.0,
      content: @utf8.encode(pair.1).to_fixedarray(),
    }),
  }
  let calculated = @xlsx.recalculate(p)
  let font = @fs.read_file(font_path).binary()
  let result = @render.render_xlsx_proof_pdf(
    calculated,
    [{ family: "Noto Sans", bytes: font, }],
    default_family="Noto Sans",
  )
  assert_eq(result.page_count, 1)
  @fs.write_file(
    required("MOONLEAF_TEST_OUTPUT") + ".quote.pdf",
    result.bytes,
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  assert_eq(@xlsx.inspect(calculated)[5].cached_value, Some("343"))
}

///|
/// The registered OFL-v2 edition uses its real declared font without substitutions.
async test "official open-font undertaking source and filled copy render four pages" {
  guard @env.get_env_var("MOONLEAF_OFL_TEMPLATE_FONT") is Some(font_path) else {
    return
  }
  let root = required("MOONLEAF_OFL_TEMPLATE_ROOT")
  let output = required("MOONLEAF_OFL_OUTPUT")
  let font = @fs.read_file(font_path).binary()
  assert_eq(
    digest(font),
    "sha256:c7763f454946833081cc90e73186615f8e1189de9c5e5a5a8752871fd79fddbc",
  )
  for
    (filename, suffix, expected) in [
      (
        "device-use-undertaking.ofl-v2.docx", ".source.pdf", "sha256:bae42968028bc491455dca0463f4ce16018134bb9a06e90b3b05e88fd8aae117",
      ),
      (
        "device-use-undertaking.ofl-v2.fillable.docx", ".filled.pdf", "sha256:92f0041e2752d684ced68dd09f793ed0aafd795dc92c2f9522ca25c0af4542f7",
      ),
    ] {
    let bytes = @fs.read_file(root + "/" + filename).binary()
    assert_eq(digest(bytes), expected)
    let mut p = @opc.open(bytes.to_fixedarray())
    if suffix == ".filled.pdf" {
      for
        (marker, value) in [
          ("{{lessee.name}}", "示例使用单位"),
          ("{{undertaking.signed_date.year}}", "2026"),
          ("{{undertaking.signed_date.month}}", "09"),
          ("{{undertaking.signed_date.day}}", "22"),
        ] {
        p = @docx.replace_text(p, marker, value)
      }
    }
    let result = @render.render_docx_pdf(
      p,
      [{ family: "Noto Sans SC", bytes: font, }],
      default_family="Noto Sans SC",
    )
    assert_eq(result.page_count, 4)
    @fs.write_file(
      output + suffix,
      result.bytes,
      create_mode=CreateOrTruncate,
      permission=0o600,
    )
  }
}
