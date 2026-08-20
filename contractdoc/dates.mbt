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

///|
fn two_digits(value : Int64) -> String {
  if value < 10L {
    "0\{value}"
  } else {
    value.to_string()
  }
}

///|
/// Formats a non-negative Unix millisecond timestamp as a stable UTC value for
/// operator/customer projections. This deliberately avoids locale-dependent
/// host formatting so screenshots, exports, and audit review agree.
pub fn format_unix_ms_utc(unix_ms : Int64) -> String {
  if unix_ms < 0L {
    return "—"
  }
  let days = unix_ms / 86400000L
  let day_ms = unix_ms % 86400000L
  // Inverse of Howard Hinnant's days_from_civil.
  let z = days + 719468L
  let era = if z >= 0L { z / 146097L } else { (z - 146096L) / 146097L }
  let day_of_era = z - era * 146097L
  let year_of_era = (
      day_of_era -
      day_of_era / 1460L +
      day_of_era / 36524L -
      day_of_era / 146096L
    ) /
    365L
  let mut year = year_of_era + era * 400L
  let day_of_year = day_of_era -
    (365L * year_of_era + year_of_era / 4L - year_of_era / 100L)
  let month_prime = (5L * day_of_year + 2L) / 153L
  let day = day_of_year - (153L * month_prime + 2L) / 5L + 1L
  let month = month_prime + (if month_prime < 10L { 3L } else { -9L })
  if month <= 2L {
    year += 1L
  }
  let hour = day_ms / 3600000L
  let minute = day_ms % 3600000L / 60000L
  let second = day_ms % 60000L / 1000L
  "\{year}-\{two_digits(month)}-\{two_digits(day)} \{two_digits(hour)}:\{two_digits(minute)}:\{two_digits(second)} UTC"
}
