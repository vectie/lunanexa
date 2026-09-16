///|
test "contract expiry respects inclusive UTC calendar day and missing clock" {
  let date = Some("2026-09-01")
  let start = @contractdoc.calendar_date_days("2026-09-01").unwrap() * 86400000L
  assert_eq(
    contract_expiry_countdown(English, date, start - 1L),
    "1 day remaining",
  )
  assert_eq(
    contract_expiry_countdown(English, date, start),
    "Expires today (UTC)",
  )
  assert_eq(
    contract_expiry_countdown(English, date, start + 86399999L),
    "Expires today (UTC)",
  )
  assert_eq(
    contract_expiry_countdown(English, date, start + 86400000L),
    "Expired",
  )
  assert_eq(
    contract_expiry_countdown(ChineseSimplified, date, start),
    "今天到期（UTC）",
  )
  assert_eq(
    contract_expiry_countdown(English, date, 0L),
    "Refresh to see time remaining",
  )
  assert_eq(
    contract_expiry_countdown(ChineseSimplified, date, -1L),
    "请刷新以查看剩余时间",
  )
  assert_eq(contract_expiry_countdown(English, None, start), "Not yet recorded")
  assert_eq(
    contract_expiry_countdown(English, Some("invalid"), start),
    "Date unavailable",
  )
}
