///|
test "audit graph is bounded while the full evidence table remains available" {
  let base = demo_state()
  let rows = [
    for i in 0..<35 => { ..base.audit[0], receipt: "receipt-fixture-\{i}", }
  ]
  let html = render({ ..base, route: Audit, audit: rows, })
  assert_true(html.contains("Decision paths · latest 20"))
  assert_true(html.contains("receipt-fixture-0"))
  assert_true(html.contains("receipt-fixture-34"))
  assert_eq(html.split("class=\"obs-audit-path\"").count() - 1, 20)
}
