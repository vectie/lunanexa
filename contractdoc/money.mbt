///|
/// Parses a persisted `MoneyAmount` value into CNY scale-2 minor units. The
/// source document records a plain decimal such as `1234.56`; the tolerated
/// decorations are the `¥`/`￥` currency marks and `,` grouping separators.
/// Anything else is rejected so an unreadable amount can never silently
/// reconcile against the commercial ledger.
pub fn parse_cny_minor_units(value : String) -> Int64? {
  let cleaned = value
    .replace_all(old="¥", new="")
    .replace_all(old="￥", new="")
    .replace_all(old=",", new="")
  let trimmed = cleaned.trim().to_owned()
  if trimmed == "" {
    return None
  }
  let (whole, fraction) = match trimmed.find(".") {
    Some(dot) => (trimmed[:dot].to_owned(), trimmed[dot + 1:].to_owned())
    None => (trimmed, "")
  }
  if whole == "" ||
    whole.length() > 15 ||
    !whole.all(character => character.is_ascii_digit()) ||
    fraction.length() > 2 ||
    !fraction.all(character => character.is_ascii_digit()) {
    return None
  }
  let units = @string.parse_int64(whole) catch { _ => return None }
  let cents = if fraction == "" {
    0L
  } else {
    let parsed = @string.parse_int64(fraction) catch { _ => return None }
    if fraction.length() == 1 {
      parsed * 10L
    } else {
      parsed
    }
  }
  Some(units * 100L + cents)
}

///|
/// Renders CNY scale-2 minor units as a plain decimal, used in operator
/// audit receipts and reconciliation messages.
pub fn format_cny_minor_units(minor_units : Int64) -> String {
  let sign = if minor_units < 0L { "-" } else { "" }
  let magnitude = minor_units.abs()
  let cents = magnitude % 100L
  let padded = if cents < 10L { "0\{cents}" } else { cents.to_string() }
  "\{sign}\{magnitude / 100L}.\{padded}"
}
