///|
/// Days since 1970-01-01 for a proleptic Gregorian calendar date, using
/// Howard Hinnant's `days_from_civil`. The pure arithmetic lets the contract
/// expiry scan compute day deltas without a wall-clock dependency inside this
/// package.
pub fn days_from_civil(year : Int, month : Int, day : Int) -> Int64 {
  let adjusted = if month <= 2 { year - 1 } else { year }
  let era = adjusted / 400
  let year_of_era = adjusted - era * 400
  let month_shifted = if month > 2 { month - 3 } else { month + 9 }
  let day_of_year = (153 * month_shifted + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  (era * 146097 + day_of_era - 719468).to_int64()
}

///|
/// Strictly parses a `YYYY-MM-DD` calendar date into a day number. The check
/// is structural (month 01-12, day 01-31), matching the source-field
/// validation of `CalendarDate` values.
pub fn calendar_date_days(value : String) -> Int64? {
  let characters = value.to_array()
  if characters.length() != 10 || characters[4] != '-' || characters[7] != '-' {
    return None
  }
  for index, character in characters {
    if index != 4 && index != 7 && !character.is_ascii_digit() {
      return None
    }
  }
  let zero = '0'.to_int()
  let year = (characters[0].to_int() - zero) * 1000 +
    (characters[1].to_int() - zero) * 100 +
    (characters[2].to_int() - zero) * 10 +
    characters[3].to_int() -
    zero
  let month = (characters[5].to_int() - zero) * 10 +
    characters[6].to_int() -
    zero
  let day = (characters[8].to_int() - zero) * 10 + characters[9].to_int() - zero
  if month < 1 || month > 12 || day < 1 || day > 31 {
    return None
  }
  Some(days_from_civil(year, month, day))
}

///|
/// Whole UTC days remaining until `date_value` relative to `now_unix_ms`.
/// Unparseable dates and non-positive timestamps yield `None` so callers can
/// skip rather than guess.
pub fn days_until(date_value : String, now_unix_ms : Int64) -> Int64? {
  guard now_unix_ms > 0L else { return None }
  match calendar_date_days(date_value) {
    Some(end_day) => Some(end_day - now_unix_ms / 86400000L)
    None => None
  }
}
