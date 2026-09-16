///|
// MasterLease admission compares UTC calendar days inclusively; a date-only
// contract must not be presented as expiring at the start of its last day.
fn contract_expiry_countdown(
  locale : @i18n.Locale,
  expiry : String?,
  now_unix_ms : Int64,
) -> String {
  match expiry {
    Some(date) =>
      match @contractdoc.calendar_date_days(date) {
        None => copy(locale, "Date unavailable", "日期不可用")
        Some(days) => {
          if now_unix_ms <= 0L {
            return copy(
              locale, "Refresh to see time remaining", "请刷新以查看剩余时间",
            )
          }
          let remaining = days - now_unix_ms / 86400000L
          if remaining < 0L {
            copy(locale, "Expired", "已到期")
          } else if remaining == 0L {
            copy(locale, "Expires today (UTC)", "今天到期（UTC）")
          } else if remaining == 1L {
            copy(locale, "1 day remaining", "剩余 1 天")
          } else {
            copy(
              locale,
              "\{remaining} days remaining",
              "剩余 \{remaining} 天",
            )
          }
        }
      }
    None => copy(locale, "Not yet recorded", "尚未登记")
  }
}
