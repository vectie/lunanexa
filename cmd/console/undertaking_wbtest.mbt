///|
test "undertaking tariff quote is accepted by the shared policy and binds source" {
  let initial = @offline_commerce.demo_state(English, OperatorCommerce).orders[0]
  let order = { ..initial, quote: None, }
  let quote = undertaking_quote(order, "month", "2", "quote-test", 1000L)
  assert_eq(quote.total.minor_units, 258000L)
  assert_eq(quote.lines[0].quantity, 2L)
  assert_eq(quote.terms_digest, @contractdoc.undertaking_ofl_manifest().sha256)
  assert_eq(
    @offline.undertaking_quote_term({ ..order, quote: Some(quote), }),
    Some(30L),
  )
}

///|
test "new undertaking quotes use OFL edition without changing existing legacy order terms" {
  let initial = @offline_commerce.demo_state(English, OperatorCommerce).orders[0]
  let fresh = { ..initial, quote: None, }
  let new_quote = undertaking_quote(fresh, "month", "1", "new-quote", 1000L)
  assert_eq(
    new_quote.terms_digest,
    @contractdoc.undertaking_ofl_manifest().sha256,
  )
  let legacy = {
    ..new_quote,
    terms_digest: @contractdoc.undertaking_manifest().sha256,
  }
  let legacy_order = { ..fresh, quote: Some(legacy), }
  let requote = undertaking_quote(
    legacy_order, "week", "1", "legacy-requote", 2000L,
  )
  assert_eq(requote.terms_digest, legacy.terms_digest)
  let unknown_digest = "sha256:" + "e".repeat(64)
  let imported_order = {
    ..fresh,
    quote: Some({ ..new_quote, terms_digest: unknown_digest, }),
  }
  assert_eq(
    undertaking_quote(imported_order, "week", "1", "import-requote", 2000L).terms_digest,
    unknown_digest,
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
