///|
fn undertaking_quote(
  order : @offline.CommercialOrder,
  term : String,
  quantity_text : String,
  quote_id : String,
  now : Int64,
) -> @offline.ImmutableQuote raise {
  guard @offline.undertaking_tariff(term) is Some(price) else {
    fail("Unsupported undertaking tariff")
  }
  let quantity = @string.parse_int64(quantity_text)
  guard quantity > 0L && quantity <= 10000L else {
    fail("Device count must be between 1 and 10000")
  }
  let total : @commercial.FixedMoney = {
    minor_units: price * quantity,
    currency: "CNY",
    scale: 2,
  }
  let proposed = now + 604800000L
  {
    quote_id,
    version: "v1",
    service_code: order.selected_service_code,
    sla_code: order.selected_sla_code,
    currency: "CNY",
    lines: [
      {
        line_id: "undertaking-device-capacity",
        description: "Equipment undertaking fixed tariff",
        quantity,
        unit: term,
        unit_price: { minor_units: price, currency: "CNY", scale: 2, },
        line_total: total,
      },
    ],
    subtotal: total,
    tax: { minor_units: 0L, currency: "CNY", scale: 2, },
    total,
    valid_until_unix_ms: if proposed < order.expires_unix_ms {
      proposed
    } else {
      order.expires_unix_ms
    },
    terms_digest: @contractdoc.undertaking_manifest().sha256,
    created_unix_ms: now,
  }
}
