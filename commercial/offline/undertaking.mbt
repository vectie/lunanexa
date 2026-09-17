///|
/// Duration of the fixed-price device undertaking, or None for a negotiated
/// quote. Quantity is the number of devices, never a discount multiplier.
pub fn undertaking_tariff(unit : String) -> Int64? {
  match unit {
    "day" => Some(4900L)
    "week" => Some(32200L)
    "month" => Some(129000L)
    "quarter" => Some(360000L)
    "year" => Some(1387000L)
    _ => None
  }
}

///|
pub fn undertaking_quote_term(order : CommercialOrder) -> Int64? {
  guard order.quote is Some(quote) && quote.lines.length() == 1 else {
    return None
  }
  let line = quote.lines[0]
  let days : Int64 = match line.unit {
    "day" => 1L
    "week" => 7L
    "month" => 30L
    "quarter" => 90L
    "year" => 365L
    _ => return None
  }
  guard undertaking_tariff(line.unit) is Some(price) else { return None }
  guard line.quantity > 0L &&
    line.quantity <= 10000L &&
    line.unit_price.currency == "CNY" &&
    line.unit_price.scale == 2 &&
    line.unit_price.minor_units == price &&
    quote.total.currency == "CNY" &&
    quote.total.scale == 2 &&
    quote.total.minor_units == price * line.quantity &&
    line.line_total == quote.total &&
    quote.subtotal == quote.total &&
    quote.tax.currency == "CNY" &&
    quote.tax.scale == 2 &&
    quote.tax.minor_units == 0L else {
    return None
  }
  Some(days)
}
