///|
fn price_scenario(price : Int64) -> @commercial.UsagePriceScenario raise {
  { schema_version: 1, rates: [{ ..rate(price), rate_card_id: "candidate", }], }
}

///|
test "price scenario compares exact recorded charges keeps credits and estimates unpriced usage" {
  let snapshot = report_snapshot()
  let scenario = price_scenario(1L)
  let source_before = snapshot.to_json().stringify()
  let rates_before = scenario.to_json().stringify()
  let report = @commercial.explore_usage_prices(
    snapshot,
    report_query(),
    scenario,
  )
  assert_eq(report.rows.length(), 3)
  let charged = report.rows[0]
  assert_true(charged.status == Compared)
  assert_eq(charged.recorded.amount, Some(@commercial.money(6L, "CNY", 2)))
  assert_eq(charged.hypothetical_amount, Some(@commercial.money(3L, "CNY", 2)))
  assert_eq(charged.delta, Some(@commercial.money(-3L, "CNY", 2)))
  assert_eq(charged.recorded.rate_card_id, "lease-rate")
  assert_eq(charged.candidate_rate_card_id, "candidate")
  assert_true(report.rows[1].status == RecordedAdjustment)
  assert_eq(report.rows[1].recorded.linked_entry_id, "charge-one")
  assert_eq(
    report.rows[1].recorded.amount,
    Some(@commercial.money(-2L, "CNY", 2)),
  )
  assert_eq(report.rows[1].hypothetical_amount, None)
  assert_eq(report.rows[1].delta, None)
  assert_true(report.rows[2].status == EstimatedUnpriced)
  assert_eq(report.rows[2].recorded.amount, None)
  assert_eq(
    report.rows[2].hypothetical_amount,
    Some(@commercial.money(5L, "CNY", 2)),
  )
  assert_eq(report.rows[2].delta, None)
  assert_eq(report.groups.length(), 3)
  assert_eq(snapshot.to_json().stringify(), source_before)
  assert_eq(scenario.to_json().stringify(), rates_before)
  // This estimate agrees with actual existing local ledger rating arithmetic.
  let store = base_store()
  ignore(store.ingest_usage(usage("hypothetical-check", 3L)))
  let (entry, _) = store.rate_usage(
    "hypothetical-check",
    "comparison",
    rate(1L),
    3100L,
  )
  assert_eq(charged.hypothetical_amount, Some(entry.amount))
}

///|
test "rate coverage is whole event exact meter unit and half-open boundary without splitting" {
  let snapshot = report_snapshot()
  let base = price_scenario(1L)
  let exact = {
    ..base.rates[0],
    effective_from_unix_ms: 2000L,
    effective_until_unix_ms: 3000L,
  }
  let report = @commercial.explore_usage_prices(
    snapshot,
    { ..report_query(), started_unix_ms: 2500L, ended_unix_ms: 2800L, },
    { ..base, rates: [exact], },
  )
  assert_eq(report.rows.length(), 1)
  assert_true(report.rows[0].status == Compared)
  assert_eq(
    report.rows[0].hypothetical_amount,
    Some(@commercial.money(3L, "CNY", 2)),
  )
  assert_true(report.rows[0].recorded.crosses_window)
  assert_eq(report.groups[0].crossing_window_count, 1)
  for
    candidate in [
      { ..exact, effective_from_unix_ms: 2001L, },
      { ..exact, effective_until_unix_ms: 2999L, },
      { ..exact, meter: "different-meter", },
      { ..exact, unit: "minute", },
    ] {
    let result = @commercial.explore_usage_prices(snapshot, report_query(), {
      ..base,
      rates: [candidate],
    })
    assert_true(result.rows[0].status == NoCoveringRate)
    assert_eq(result.rows[0].hypothetical_amount, None)
    assert_eq(result.rows[0].delta, None)
  }
  let split = @commercial.explore_usage_prices(snapshot, report_query(), {
    ..base,
    rates: [
      { ..exact, version: "a", effective_until_unix_ms: 2500L, },
      { ..exact, version: "b", effective_from_unix_ms: 2500L, },
    ],
  })
  assert_true(split.rows[0].status == NoCoveringRate)
}

///|
test "ambiguous rates missing observations and money-unit differences are unresolved rather than zero" {
  let source = report_snapshot()
  let base = price_scenario(1L)
  let ambiguous = @commercial.explore_usage_prices(source, report_query(), {
    ..base,
    rates: base.rates + [{ ..base.rates[0], version: "other", }],
  })
  assert_true(ambiguous.rows[0].status == AmbiguousRate)
  assert_eq(ambiguous.rows[0].matched_rate_count, 2)
  assert_eq(ambiguous.rows[0].candidate_rate_card_id, "")
  assert_eq(ambiguous.rows[0].hypothetical_amount, None)
  let missing = @commercial.explore_usage_prices(
    { ..source, usage_observations: [], },
    report_query(),
    base,
  )
  assert_true(missing.rows[0].status == MissingObservation)
  assert_eq(missing.rows[0].hypothetical_amount, None)
  assert_eq(
    missing.rows[0].recorded.amount,
    Some(@commercial.money(6L, "CNY", 2)),
  )
  for
    price in [@commercial.money(1L, "USD", 2), @commercial.money(1L, "CNY", 3)] {
    let mismatch = @commercial.explore_usage_prices(source, report_query(), {
      ..base,
      rates: [{ ..base.rates[0], unit_price: price, }],
    })
    assert_true(mismatch.rows[0].status == MoneyUnitMismatch)
    assert_eq(mismatch.rows[0].delta, None)
    assert_eq(
      mismatch.rows[0].hypothetical_amount,
      Some(@commercial.estimate_cost(3L, price)),
    )
  }
  let zero = @commercial.explore_usage_prices(
    source,
    report_query(),
    price_scenario(0L),
  )
  assert_eq(
    zero.rows[0].hypothetical_amount,
    Some(@commercial.money(0L, "CNY", 2)),
  )
  assert_eq(zero.rows[0].delta, Some(@commercial.money(-6L, "CNY", 2)))
}

///|
test "price output preserves exact integers nulls context filters and source privacy" {
  let store = base_store()
  ignore(store.ingest_usage(usage("large", 9007199254740993L)))
  let snapshot = store.snapshot("org-a")
  let report = @commercial.explore_usage_prices(
    snapshot,
    report_query(),
    price_scenario(1L),
  )
  assert_eq(
    report.rows[0].hypothetical_amount,
    Some(@commercial.money(9007199254740993L, "CNY", 2)),
  )
  let json = report.json_text()
  assert_true(json.contains("hypothetical-not-ledger"))
  assert_true(json.contains("\"9007199254740993\""))
  assert_true(json.contains("\"delta\": null"))
  assert_true(json.contains("\"amount\": null"))
  assert_false(json.contains("dgx-1"))
  assert_false(json.contains("actor-a"))
  assert_true(report.rows_csv().contains(",9007199254740993,\"CNY\",2,,,"))
  let empty = @commercial.explore_usage_prices(
    snapshot,
    { ..report_query(), meter: "missing", },
    price_scenario(1L),
  )
  assert_eq(empty.rows.length(), 0)
  assert_eq(empty.groups.length(), 0)
  assert_eq(empty.rows_csv().split("\n").count(), 2)
  assert_eq(empty.summary_csv().split("\n").count(), 2)
}

///|
test "candidate edits reopen deterministically and scenario validation rejects unsupported input" {
  let scenario = price_scenario(1L)
  let text = scenario.to_json().stringify()
  let reopened = @commercial.import_usage_price_scenario(text)
  assert_true(reopened == scenario)
  let edited = @commercial.import_usage_price_scenario(
    text.replace_all(old="\"minor_units\":\"1\"", new="\"minor_units\":\"3\""),
  )
  let report = @commercial.explore_usage_prices(
    report_snapshot(),
    report_query(),
    edited,
  )
  assert_eq(report.rows[0].delta, Some(@commercial.money(3L, "CNY", 2)))
  let second = { ..scenario.rates[0], rate_card_id: "z", meter: "other", }
  let forward = { ..scenario, rates: scenario.rates + [second], }
  let backward = { ..scenario, rates: forward.rates.rev(), }
  assert_eq(
    @commercial.explore_usage_prices(report_snapshot(), report_query(), forward).json_text(),
    @commercial.explore_usage_prices(
      report_snapshot(),
      report_query(),
      backward,
    ).json_text(),
  )
  for
    invalid in [
      "{",
      "{}",
      text.replace_all(old="schema_version", new="typo"),
      text.replace_all(old="\"schema_version\":1", new="\"schema_version\":2"),
      text.replace_all(old="\"meter\":", new="\"extra\":1,\"meter\":"),
      text.replace_all(old="\"scale\":2", new="\"scale\":2,\"extra\":true"),
    ] {
    assert_true(
      try {
        ignore(@commercial.import_usage_price_scenario(invalid))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(@commercial.import_usage_price_scenario(" ".repeat(65537)))
      false
    } catch {
      _ => true
    },
  )
  for
    invalid in [
      { ..scenario, rates: [], },
      { ..scenario, rates: scenario.rates + scenario.rates, },
      {
        ..scenario,
        rates: [{ ..scenario.rates[0], effective_until_unix_ms: 1000L, }],
      },
      {
        ..scenario,
        rates: [
          { ..scenario.rates[0], unit_price: @commercial.money(-1L, "CNY", 2), },
        ],
      },
    ] {
    assert_true(
      try {
        ignore(
          @commercial.explore_usage_prices(
            report_snapshot(),
            report_query(),
            invalid,
          ),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let rates = Array::makei(128, i => {
    ..scenario.rates[0],
    rate_card_id: "rate-" + i.to_string(),
    meter: "unmatched",
  })
  assert_true(
    {
      ignore(
        @commercial.explore_usage_prices(report_snapshot(), report_query(), {
          ..scenario,
          rates,
        }),
      )
      true
    },
  )
  assert_true(
    try {
      ignore(
        @commercial.explore_usage_prices(report_snapshot(), report_query(), {
          ..scenario,
          rates: rates + [second],
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "price groups preserve currencies statuses and inherited source validation" {
  let store = base_store()
  ignore(add_rated_usage(store, "a", "charge-a", 3L))
  ignore(add_rated_usage(store, "b", "charge-b", 4L))
  let source = store.snapshot("org-a")
  let report = @commercial.explore_usage_prices(
    source,
    { ..report_query(), group_by: "cost-center", },
    price_scenario(3L),
  )
  assert_eq(report.groups.length(), 1)
  assert_eq(report.groups[0].quantity, 7L)
  assert_eq(
    report.groups[0].recorded_amount,
    Some(@commercial.money(14L, "CNY", 2)),
  )
  assert_eq(
    report.groups[0].hypothetical_amount,
    Some(@commercial.money(21L, "CNY", 2)),
  )
  assert_eq(report.groups[0].delta, Some(@commercial.money(7L, "CNY", 2)))
  let mixed = {
    ..source,
    ledger_entries: [
      source.ledger_entries[0],
      { ..source.ledger_entries[1], amount: @commercial.money(8L, "USD", 2), },
    ],
  }
  let groups = @commercial.explore_usage_prices(
      mixed,
      report_query(),
      price_scenario(3L),
    ).groups
  assert_eq(groups.length(), 2)
  assert_eq(groups.filter(g => g.status == MoneyUnitMismatch).length(), 1)
  let duplicate = {
    ..source,
    usage_observations: source.usage_observations +
    [source.usage_observations[0]],
  }
  assert_true(
    try {
      ignore(
        @commercial.explore_usage_prices(
          duplicate,
          { ..report_query(), meter: "missing", },
          price_scenario(3L),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  let other = {
    ..source,
    ledger_entries: source.ledger_entries +
    [{ ..source.ledger_entries[0], organization_id: "org-private", }],
  }
  assert_eq(
    @commercial.explore_usage_prices(other, report_query(), price_scenario(3L)).json_text(),
    @commercial.explore_usage_prices(source, report_query(), price_scenario(3L)).json_text(),
  )
}

///|
test "price arithmetic overflow is rejected for individual estimates and grouped totals" {
  let source = report_snapshot()
  assert_true(
    try {
      ignore(
        @commercial.explore_usage_prices(
          source,
          report_query(),
          price_scenario(9223372036854775807L),
        ),
      )
      false
    } catch {
      @commercial.ArithmeticOverflow => true
      _ => false
    },
  )
  let store = base_store()
  ignore(store.ingest_usage(usage("a", 1L)))
  ignore(store.ingest_usage(usage("b", 1L)))
  assert_true(
    try {
      ignore(
        @commercial.explore_usage_prices(
          store.snapshot("org-a"),
          report_query(),
          price_scenario(9223372036854775807L),
        ),
      )
      false
    } catch {
      @commercial.ArithmeticOverflow => true
      _ => false
    },
  )
}
