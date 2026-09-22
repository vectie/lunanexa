///|
test "customization recomputes stale formula caches before signing source" {
  let source = @opc.open(xlsx_fixture(cached_value="999"))
  let formula = source.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\"><f>B1*2</f><v>999</v></c><c r=\"B1\"><v>10</v></c></row></sheetData></worksheet>",
  )
  let bytes = @opc.save(formula)
  let replacements : Array[@worker.CellReplacement] = [
    { sheet_name: "Quote", row: 1, column: 2, value: "25", },
  ]
  let first = @worker.customize_xlsx_template(bytes, replacements)
  let second = @worker.customize_xlsx_template(bytes, replacements)
  assert_eq(first.bytes, second.bytes)
  assert_true(
    @opc.open(first.bytes)
    .text("xl/worksheets/sheet1.xml")
    .contains("<v>50</v>"),
  )
  assert_false(
    @opc.open(first.bytes).text("xl/worksheets/sheet1.xml").contains("999"),
  )
  assert_eq(first.verification.formula_error_count, 0)
}

///|
test "customization rejects formula overwrite and unsupported formula engines" {
  try
    @worker.customize_xlsx_template(xlsx_fixture(), [
      { sheet_name: "Quote", row: 1, column: 1, value: "0", },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("formula overwrite accepted")
  }
  let original = @opc.open(xlsx_fixture())
  let unsupported = original.replace_text(
    "xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\"><f>WEBSERVICE(1)</f><v>42</v></c></row></sheetData></worksheet>",
  )
  try
    @worker.customize_xlsx_template(@opc.save(unsupported), [
      { sheet_name: "Quote", row: 2, column: 1, value: "order-1", },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("unsupported formula accepted on cached value")
  }
}

///|
async test "bundled quote template recalculates real numeric inputs and totals" {
  let bytes = @fs.read_file("assets/contracts/offline/quote-v1/quote.xlsx")
    .binary()
    .to_fixedarray()
  let replacements : Array[@worker.CellReplacement] = [
    { sheet_name: "Quote", row: 2, column: 2, value: "order-template-test", },
    { sheet_name: "Quote", row: 3, column: 2, value: "org-template-test", },
    { sheet_name: "Quote", row: 4, column: 2, value: "quote-template-test", },
    { sheet_name: "Quote", row: 5, column: 2, value: "CNY", },
    { sheet_name: "Quote", row: 6, column: 2, value: "72000", },
    { sheet_name: "Quote", row: 7, column: 2, value: "4320", },
    { sheet_name: "Quote", row: 9, column: 2, value: "2", },
  ]
  let first = @worker.customize_xlsx_template(bytes, replacements)
  let second = @worker.customize_xlsx_template(bytes, replacements)
  assert_eq(first.bytes, second.bytes)
  let cells = @xlsx.inspect(@opc.open(first.bytes))
  let by_ref : Map[Int, @xlsx.InspectedCell] = Map([])
  for cell in cells {
    if cell.column == 2 {
      by_ref[cell.row] = cell
    }
  }
  assert_eq(by_ref[7].raw_value, Some("4320"))
  assert_eq(by_ref[7].resolved_text, None)
  assert_eq(by_ref[8].cached_value, Some("76320"))
  assert_true(first.verification.moonleaf_verified)
  assert_eq(first.verification.formula_error_count, 0)
  try
    @worker.customize_xlsx_template(bytes, [
      { sheet_name: "Quote", row: 9, column: 2, value: "not a price", },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("invalid numeric price accepted")
  }
}
