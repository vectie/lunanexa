///|
fn validate_usage_price_scenario(
  scenario : UsagePriceScenario,
) -> Unit raise CommercialError {
  if scenario.schema_version != 1 ||
    scenario.rates.is_empty() ||
    scenario.rates.length() > 128 {
    raise InvalidInput("price scenario requires version 1 and 1..128 rates")
  }
  let identities : Map[String, Bool] = Map([])
  for rate in scenario.rates {
    validate_rate_card(rate)
    let key = [rate.rate_card_id, rate.version].to_json().stringify()
    if identities.contains(key) {
      raise InvalidInput("duplicate candidate rate-card identity/version")
    }
    identities[key] = true
  }
}

///|
pub fn import_usage_price_scenario(
  text : String,
) -> UsagePriceScenario raise CommercialError {
  if text.length() > 65536 {
    raise InvalidInput("price scenario exceeds 64 Ki characters")
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidInput("invalid price scenario JSON")
  }
  let scenario : UsagePriceScenario = @json.from_json(json) catch {
    _ =>
      raise InvalidInput(
        "invalid price scenario; Int64 values use decimal strings",
      )
  }
  if scenario.to_json() != json {
    raise InvalidInput(
      "price scenario has unsupported fields or value encodings",
    )
  }
  validate_usage_price_scenario(scenario)
  scenario
}

///|
fn usage_price_row(
  row : UsageReportRow,
  rates : Array[RateCard],
) -> UsagePriceRow raise CommercialError {
  let empty : UsagePriceRow = {
    recorded: row,
    status: NoCoveringRate,
    matched_rate_count: 0,
    candidate_rate_card_id: "",
    candidate_rate_card_version: "",
    hypothetical_amount: None,
    delta: None,
  }
  if row.kind != "charge" && row.kind != "unpriced_usage" {
    return { ..empty, status: RecordedAdjustment, }
  }
  if !row.observation_available {
    return { ..empty, status: MissingObservation, }
  }
  let matching = rates.filter(rate => {
    row.meter == rate.meter &&
    row.unit == rate.unit &&
    row.started_unix_ms >= rate.effective_from_unix_ms &&
    row.ended_unix_ms <= rate.effective_until_unix_ms
  })
  if matching.is_empty() {
    return empty
  }
  if matching.length() != 1 {
    return {
      ..empty,
      status: AmbiguousRate,
      matched_rate_count: matching.length(),
    }
  }
  let rate = matching[0]
  let amount = estimate_cost(row.quantity, rate.unit_price)
  let (status, delta) = match row.amount {
    None => (EstimatedUnpriced, None)
    Some(recorded) =>
      if recorded.currency != amount.currency || recorded.scale != amount.scale {
        (MoneyUnitMismatch, None)
      } else {
        (Compared, Some(amount.add(recorded.negate())))
      }
  }
  {
    ..empty,
    status,
    matched_rate_count: 1,
    candidate_rate_card_id: rate.rate_card_id,
    candidate_rate_card_version: rate.version,
    hypothetical_amount: Some(amount),
    delta,
  }
}

///|
fn usage_price_group_key(group : UsagePriceGroup) -> String {
  [
    group.group_id,
    group.meter,
    group.unit,
    group.status.to_json().stringify(),
    group.recorded_amount.map(a => a.currency).unwrap_or(""),
    group.recorded_amount.map(a => a.scale.to_string()).unwrap_or(""),
    group.hypothetical_amount.map(a => a.currency).unwrap_or(""),
    group.hypothetical_amount.map(a => a.scale.to_string()).unwrap_or(""),
  ]
  .to_json()
  .stringify()
}

///|
fn usage_price_add(
  left : FixedMoney?,
  right : FixedMoney?,
) -> FixedMoney? raise CommercialError {
  match (left, right) {
    (Some(a), Some(b)) => Some(a.add(b))
    (None, None) => None
    _ => raise InvalidInput("inconsistent price comparison group")
  }
}

///|
/// Compare candidate rates against the existing saved-usage explorer. No store
/// is constructed or changed. Full intersecting events retain their quantity;
/// covering rates use the same meter/unit/time semantics as ledger rating.
pub fn explore_usage_prices(
  snapshot : CommercialSnapshot,
  query : UsageQuery,
  scenario : UsagePriceScenario,
) -> UsagePriceReport raise CommercialError {
  validate_usage_price_scenario(scenario)
  let recorded = explore_usage(snapshot, query)
  let rates = scenario.rates.copy()
  rates.sort_by((a, b) => {
    let by_id = a.rate_card_id.compare(b.rate_card_id)
    if by_id != 0 {
      by_id
    } else {
      a.version.compare(b.version)
    }
  })
  let rows = recorded.rows.map(row => usage_price_row(row, rates))
  let by_key : Map[String, UsagePriceGroup] = Map([])
  for row in rows {
    let candidate : UsagePriceGroup = {
      group_id: usage_group_id(query, row.recorded),
      meter: row.recorded.meter,
      unit: row.recorded.unit,
      status: row.status,
      row_count: 1,
      quantity: row.recorded.quantity,
      crossing_window_count: if row.recorded.crosses_window {
        1
      } else {
        0
      },
      recorded_amount: row.recorded.amount,
      hypothetical_amount: row.hypothetical_amount,
      delta: row.delta,
    }
    let key = usage_price_group_key(candidate)
    by_key[key] = match by_key.get(key) {
      None => candidate
      Some(group) =>
        {
          ..group,
          row_count: group.row_count + 1,
          quantity: checked_add_int64(group.quantity, candidate.quantity),
          crossing_window_count: group.crossing_window_count +
          candidate.crossing_window_count,
          recorded_amount: usage_price_add(
            group.recorded_amount,
            candidate.recorded_amount,
          ),
          hypothetical_amount: usage_price_add(
            group.hypothetical_amount,
            candidate.hypothetical_amount,
          ),
          delta: usage_price_add(group.delta, candidate.delta),
        }
    }
  }
  let keys = by_key.keys().to_array()
  keys.sort()
  {
    query,
    scenario: { ..scenario, rates, },
    rows,
    groups: keys.map(key => by_key[key]),
  }
}
