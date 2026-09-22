///|
/// One fixed-price tier of the device undertaking.
///
/// The customer picks a tier and the operator quotes the same tier back, so
/// there is exactly one list. Two lists -- one per side -- is how a customer
/// ends up asking for a term the operator cannot quote.
pub(all) struct UndertakingTermTier {
  /// The stored unit code, which is what a quote line carries.
  unit : String
  /// The tier's length in days, which is what the document states.
  days : Int64
  /// The tier's price for one device, in minor currency units.
  minor_units : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend UndertakingTermTier with Debug::{to_repr}

///|
pub extend UndertakingTermTier with Eq::{not_equal, equal}

///|
pub extend UndertakingTermTier with ToJson::{to_json}

///|
pub extend UndertakingTermTier with FromJson::{from_json}

///|
/// The undertaking's tiers, shortest first. This is the single definition both
/// sides render: `ui/offline_commerce` builds the operator's tariff picker from
/// it, and the enterprise portal builds the customer's term picker from it.
pub let undertaking_term_tiers : Array[UndertakingTermTier] = [
  { unit: "day", days: 1L, minor_units: 4900L, },
  { unit: "week", days: 7L, minor_units: 32200L, },
  { unit: "month", days: 30L, minor_units: 129000L, },
  { unit: "quarter", days: 90L, minor_units: 360000L, },
  { unit: "year", days: 365L, minor_units: 1387000L, },
]

///|
pub fn undertaking_term_tier(unit : String) -> UndertakingTermTier? {
  undertaking_term_tiers.iter().find_first(tier => tier.unit == unit)
}

///|
/// Duration of the fixed-price device undertaking, or None for a negotiated
/// quote. Quantity is the number of devices, never a discount multiplier.
pub fn undertaking_tariff(unit : String) -> Int64? {
  undertaking_term_tier(unit).map(tier => tier.minor_units)
}

///|
/// The tier's length in days, or None when the unit is not a fixed tier.
pub fn undertaking_term_days(unit : String) -> Int64? {
  undertaking_term_tier(unit).map(tier => tier.days)
}

///|
pub fn undertaking_quote_term(order : CommercialOrder) -> Int64? {
  guard order.quote is Some(quote) && quote.lines.length() == 1 else {
    return None
  }
  let line = quote.lines[0]
  let tier : UndertakingTermTier = match undertaking_term_tier(line.unit) {
    Some(tier) => tier
    None => return None
  }
  let price = tier.minor_units
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
  Some(tier.days)
}
