///|
test "order expiry uses a readable explicit UTC date instead of milliseconds" {
  assert_eq(order_expiry_label(ChineseSimplified, 0L), "未设置")
  assert_eq(order_expiry_label(English, -1L), "Not set")
  let label = order_expiry_label(English, 1790158800000L)
  assert_true(label.contains("2026-09-23"))
  assert_false(label.contains("1790158800000"))
  assert_true(label.contains("Z") || label.contains("+00:00"))
}
