///|
fn docx_fixture(active? : Bool = false) -> FixedArray[Byte] raise {
  let parts : Array[@opc.Part] = [
    {
      name: "[Content_Types].xml",
      content: (
        #|<?xml version="1.0" encoding="UTF-8"?>
        #|<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        #|  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        #|  <Default Extension="xml" ContentType="application/xml"/>
        #|  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        #|  <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
        #|  <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
        #|</Types>
      )
      |> @utf8.encode
      |> Bytes::to_fixedarray,
    },
    {
      name: "_rels/.rels",
      content: (
        #|<?xml version="1.0" encoding="UTF-8"?>
        #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        #|</Relationships>
      )
      |> @utf8.encode
      |> Bytes::to_fixedarray,
    },
    {
      name: "word/document.xml",
      content: (
        #|<?xml version="1.0" encoding="UTF-8"?>
        #|<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        #|  <w:body><w:p><w:r><w:t>{{ORDER_ID}}</w:t></w:r></w:p><w:sectPr/></w:body>
        #|</w:document>
      )
      |> @utf8.encode
      |> Bytes::to_fixedarray,
    },
    {
      name: "word/_rels/document.xml.rels",
      content: (
        #|<?xml version="1.0" encoding="UTF-8"?>
        #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        #|  <Relationship Id="rHeader" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
        #|  <Relationship Id="rFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
        #|</Relationships>
      )
      |> @utf8.encode
      |> Bytes::to_fixedarray,
    },
    {
      name: "word/header1.xml",
      content: "<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:r><w:t>Order {{ORDER_ID}}</w:t></w:r></w:p></w:hdr>"
      |> @utf8.encode
      |> Bytes::to_fixedarray,
    },
    {
      name: "word/footer1.xml",
      content: "<w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:r><w:t>{{ORDER_ID}} · page</w:t></w:r></w:p></w:ftr>"
      |> @utf8.encode
      |> Bytes::to_fixedarray,
    },
  ]
  if active {
    parts.push({ name: "word/vbaProject.bin", content: [0x01, 0x02] })
  }
  @opc.save(({ parts, } : @opc.Package))
}

///|
fn xlsx_fixture(cached_value? : String = "42") -> FixedArray[Byte] raise {
  let archive : @opc.Package = {
    parts: [
      {
        name: "[Content_Types].xml",
        content: (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          #|  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          #|  <Default Extension="xml" ContentType="application/xml"/>
          #|  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          #|  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          #|</Types>
        )
        |> @utf8.encode
        |> Bytes::to_fixedarray,
      },
      {
        name: "_rels/.rels",
        content: (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
          #|</Relationships>
        )
        |> @utf8.encode
        |> Bytes::to_fixedarray,
      },
      {
        name: "xl/workbook.xml",
        content: (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          #|  <sheets><sheet name="Quote" sheetId="1" r:id="rId1"/></sheets>
          #|</workbook>
        )
        |> @utf8.encode
        |> Bytes::to_fixedarray,
      },
      {
        name: "xl/_rels/workbook.xml.rels",
        content: (
          #|<?xml version="1.0" encoding="UTF-8"?>
          #|<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          #|  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          #|</Relationships>
        )
        |> @utf8.encode
        |> Bytes::to_fixedarray,
      },
      {
        name: "xl/worksheets/sheet1.xml",
        content: ("<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\"><f>40+2</f><v>" +
        cached_value +
        "</v></c></row></sheetData></worksheet>")
        |> @utf8.encode
        |> Bytes::to_fixedarray,
      },
    ],
  }
  @opc.save(archive)
}

///|
test "MoonLeaf verifies bounded DOCX and XLSX semantic reopen" {
  let docx = @worker.verify_ooxml(
    "contract.docx",
    EditableContractDocx,
    docx_fixture(),
  )
  assert_true(docx.moonleaf_verified)
  assert_false(docx.active_content_detected)
  assert_true(docx.reopened_byte_count > 0)
  let xlsx = @worker.verify_ooxml(
    "quote.xlsx",
    QuoteScheduleXlsx,
    xlsx_fixture(),
  )
  assert_true(xlsx.moonleaf_verified)
  assert_eq(xlsx.formula_error_count, 0)
}

///|
test "MoonLeaf performs bounded DOCX placeholder and XLSX cell edits" {
  let docx = @worker.customize_docx_template(docx_fixture(), [
    { placeholder: "{{ORDER_ID}}", value: "order-2026-001" },
  ])
  assert_eq(docx.replacement_count, 1)
  assert_true(docx.verification.moonleaf_verified)
  let reopened = @opc.open(docx.bytes)
  assert_true(reopened.text("word/document.xml").contains("order-2026-001"))
  assert_false(reopened.text("word/document.xml").contains("{{ORDER_ID}}"))
  assert_true(reopened.text("word/header1.xml").contains("order-2026-001"))
  assert_false(reopened.text("word/header1.xml").contains("{{ORDER_ID}}"))
  assert_true(reopened.text("word/footer1.xml").contains("order-2026-001"))
  assert_false(reopened.text("word/footer1.xml").contains("{{ORDER_ID}}"))
  let xlsx = @worker.customize_xlsx_template(xlsx_fixture(), [
    { sheet_name: "Quote", row: 2, column: 1, value: "order-2026-001" },
  ])
  assert_eq(xlsx.replacement_count, 1)
  assert_true(xlsx.verification.moonleaf_verified)
}

///|
test "MoonLeaf preserves unrelated DOCX parts byte-for-byte" {
  let bytes = docx_fixture()
  let original = @opc.open(bytes)
  let unrelated = original.replace_text(
    "word/footer1.xml", "<w:ftr xmlns:w=\"urn:w\"><w:p><w:r><w:t>固定页脚</w:t></w:r></w:p></w:ftr>",
  )
  let customized = @worker.customize_docx_template(@opc.save(unrelated), [
    { placeholder: "{{ORDER_ID}}", value: "order-2026-001" },
  ])
  let reopened = @opc.open(customized.bytes)
  assert_eq(
    reopened.part("word/footer1.xml").unwrap().content,
    unrelated.part("word/footer1.xml").unwrap().content,
  )
}

///|
test "exact DOCX customization rejects incomplete and unknown marker sets" {
  let bytes = docx_fixture()
  try @worker.customize_exact_docx_template(bytes, []) catch {
    InvalidInput(_) => ()
    error => fail("unexpected exact customization error: \{Repr(error)}")
  } noraise {
    _ => fail("empty exact replacement set must fail")
  }
  try
    @worker.customize_exact_docx_template(bytes, [
      { placeholder: "{{ORDER_ID}}", value: "order-1" },
      { placeholder: "{{UNKNOWN}}", value: "value" },
    ])
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected unknown-marker error: \{Repr(error)}")
  } noraise {
    _ => fail("unknown exact replacement must fail")
  }
}

///|
test "worker reports active OOXML parts and rejects cached formula errors" {
  let active = @worker.verify_ooxml(
    "contract.docx",
    EditableContractDocx,
    docx_fixture(active=true),
  )
  assert_true(active.active_content_detected)
  ignore(
    @worker.verify_ooxml(
      "quote.xlsx",
      QuoteScheduleXlsx,
      xlsx_fixture(cached_value="#REF!"),
    ),
  ) catch {
    @worker.WorkerVerificationError::FormulaErrors(1) => ()
    _ => fail("formula error was not rejected")
  }
}

///|
test "worker rejects mismatched kind and malformed OOXML" {
  ignore(
    @worker.verify_ooxml("contract.docx", QuoteScheduleXlsx, docx_fixture()),
  ) catch {
    @worker.WorkerVerificationError::MoonLeafRejected(_) => ()
    _ => fail("mismatched OOXML kind was accepted")
  }
  ignore(
    @worker.verify_ooxml("contract.docx", EditableContractDocx, [0x50, 0x4b]),
  ) catch {
    MoonLeafRejected(_) => ()
    _ => fail("malformed OOXML was accepted")
  }
}

///|
async test "embedded youthpolicy contract has a complete exact marker boundary" {
  let path = "assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx"
  let bytes = @fs.read_file(path).binary().to_fixedarray()
  let markers = @worker.exact_docx_markers(bytes)
  assert_eq(markers.length(), 152)
  let replacements = markers.map(marker => @worker.TextReplacement::{
    placeholder: marker,
    value: "",
  })
  let customized = @worker.customize_exact_docx_template(bytes, replacements)
  assert_eq(customized.replacement_count, 152)
  assert_true(customized.verification.moonleaf_verified)
  let reopened = @opc.open(customized.bytes)
  assert_false(reopened.text("word/document.xml").contains("{{"))
  try
    @worker.customize_exact_docx_template(
      bytes,
      replacements[0:replacements.length() - 1].to_owned(),
    )
  catch {
    InvalidInput(_) => ()
    error => fail("unexpected incomplete marker error: \{Repr(error)}")
  } noraise {
    _ => fail("incomplete youthpolicy marker set must fail")
  }
}
