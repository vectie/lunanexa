///|
test "audit graph is bounded and earlier evidence stays available through pagination" {
  let base = demo_state()
  let rows = [
    for i in 0..<35 => { ..base.audit[0], receipt: "receipt-fixture-\{i}", }
  ]
  let html = render({ ..base, route: Audit, audit: rows, })
  assert_true(html.contains("Decision paths · latest 20"))
  assert_false(html.contains("receipt-fixture-0"))
  assert_true(html.contains("receipt-fixture-34"))
  assert_eq(html.split("class=\"obs-audit-path\"").count() - 1, 20)
  let older = render({
    ..base,
    route: Audit,
    audit: rows,
    list_pages: Map([(AuditEvents, { query: "", page: 1, })]),
  })
  assert_true(older.contains("receipt-fixture-0"))
}
