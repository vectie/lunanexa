///|
test "heartbeat ages use hours and days without changing freshness" {
  assert_eq(heartbeat_age_label(English, 59999L), "Just now")
  assert_eq(heartbeat_age_label(English, 60000L), "1 min ago")
  assert_eq(heartbeat_age_label(ChineseSimplified, 3600000L), "1 小时前")
  assert_eq(
    heartbeat_age_label(ChineseSimplified, 98400000L),
    "1 天 3 小时前",
  )
  assert_eq(heartbeat_age_label(English, 98400000L), "1d 3h ago")
}
