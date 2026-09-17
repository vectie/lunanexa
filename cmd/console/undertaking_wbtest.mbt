///|
test "undertaking tariff quote is accepted by the shared policy and binds source" {
  let order = @offline_commerce.demo_state(English, OperatorCommerce).orders[0]
  let quote = undertaking_quote(order, "month", "2", "quote-test", 1000L)
  assert_eq(quote.total.minor_units, 258000L)
  assert_eq(quote.lines[0].quantity, 2L)
  assert_eq(quote.terms_digest, @contractdoc.undertaking_manifest().sha256)
  assert_eq(
    @offline.undertaking_quote_term({ ..order, quote: Some(quote), }),
    Some(30L),
  )
}

///|
test "undertaking tariff quote rejects invalid device counts and units" {
  let order = @offline_commerce.demo_state(English, OperatorCommerce).orders[0]
  for count in ["0", "-1", "10001", "1.5", "no"] {
    try undertaking_quote(order, "month", count, "quote-test", 1000L) catch {
      _ => ()
    } noraise {
      _ => fail("invalid quantity accepted")
    }
  }
  try undertaking_quote(order, "discount", "1", "quote-test", 1000L) catch {
    _ => ()
  } noraise {
    _ => fail("invalid tariff accepted")
  }
}
