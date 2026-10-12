///|
fn UsagePriceStatus::label(self : UsagePriceStatus) -> String {
  match self {
    Compared => "Compared"
    EstimatedUnpriced => "EstimatedUnpriced"
    MissingObservation => "MissingObservation"
    NoCoveringRate => "NoCoveringRate"
    AmbiguousRate => "AmbiguousRate"
    MoneyUnitMismatch => "MoneyUnitMismatch"
    RecordedAdjustment => "RecordedAdjustment"
  }
}

///|
fn usage_price_output(text : String) -> String raise CommercialError {
  if text.length() > 16777216 {
    raise InvalidInput("price report exceeds 16 Mi characters")
  }
  text
}

///|
/// Hypothetical amounts are never emitted in the recorded-money columns.
pub fn UsagePriceReport::rows_csv(
  self : UsagePriceReport,
) -> String raise CommercialError {
  let output = StringBuilder()
  output.write_string(
    "analysis_mode,organization_id,window_start_unix_ms,window_end_unix_ms,cost_center_id,project_id,event_id,workload_id,entry_id,linked_entry_id,kind,meter,unit,quantity,started_unix_ms,ended_unix_ms,observation_available,crosses_window,status,matched_rate_count,recorded_rate_card_id,recorded_rate_card_version,candidate_rate_card_id,candidate_rate_card_version,recorded_minor_units,recorded_currency,recorded_scale,hypothetical_minor_units,hypothetical_currency,hypothetical_scale,delta_minor_units,delta_currency,delta_scale\n",
  )
  for row in self.rows {
    let source = row.recorded
    let cells = [csv_cell("hypothetical-not-ledger")]
    cells.append(usage_query_cells(self.query))
    cells.append(
      [
        source.cost_center_id,
        source.project_id,
        source.event_id,
        source.workload_id,
        source.entry_id,
        source.linked_entry_id,
        source.kind,
        source.meter,
        source.unit,
      ].map(csv_cell),
    )
    cells.append([
      source.quantity.to_string(),
      source.started_unix_ms.to_string(),
      source.ended_unix_ms.to_string(),
      source.observation_available.to_string(),
      source.crosses_window.to_string(),
      csv_cell(row.status.label()),
      row.matched_rate_count.to_string(),
      csv_cell(source.rate_card_id),
      csv_cell(source.rate_card_version),
      csv_cell(row.candidate_rate_card_id),
      csv_cell(row.candidate_rate_card_version),
    ])
    cells.append(usage_amount_cells(source.amount))
    cells.append(usage_amount_cells(row.hypothetical_amount))
    cells.append(usage_amount_cells(row.delta))
    output.write_string(cells.join(","))
    output.write_char('\n')
  }
  usage_price_output(output.to_string())
}

///|
pub fn UsagePriceReport::summary_csv(
  self : UsagePriceReport,
) -> String raise CommercialError {
  let output = StringBuilder()
  output.write_string(
    "analysis_mode,organization_id,window_start_unix_ms,window_end_unix_ms,group_by,group_id,meter,unit,status,row_count,quantity,crossing_window_count,recorded_minor_units,recorded_currency,recorded_scale,hypothetical_minor_units,hypothetical_currency,hypothetical_scale,delta_minor_units,delta_currency,delta_scale\n",
  )
  for group in self.groups {
    let cells = [csv_cell("hypothetical-not-ledger")]
    cells.append(usage_query_cells(self.query))
    cells.append(
      [
        self.query.group_by,
        group.group_id,
        group.meter,
        group.unit,
        group.status.label(),
      ].map(csv_cell),
    )
    cells.append([
      group.row_count.to_string(),
      group.quantity.to_string(),
      group.crossing_window_count.to_string(),
    ])
    cells.append(usage_amount_cells(group.recorded_amount))
    cells.append(usage_amount_cells(group.hypothetical_amount))
    cells.append(usage_amount_cells(group.delta))
    output.write_string(cells.join(","))
    output.write_char('\n')
  }
  usage_price_output(output.to_string())
}

///|
fn usage_price_money_json(amount : FixedMoney?) -> Json {
  amount.map(value => value.to_json()).unwrap_or(Json::null())
}

///|
/// JSON retains candidate rates and exact Int64 decimal strings. Null means
/// unavailable, including absent baseline prices and incomparable deltas.
pub fn UsagePriceReport::json_text(
  self : UsagePriceReport,
) -> String raise CommercialError {
  let rows = self.rows.map(row => {
    let json = row.to_json()
    if json is Object(fields) {
      fields["hypothetical_amount"] = usage_price_money_json(
        row.hypothetical_amount,
      )
      fields["delta"] = usage_price_money_json(row.delta)
      if fields.get("recorded") is Some(Object(recorded)) {
        recorded["amount"] = usage_price_money_json(row.recorded.amount)
      }
    }
    json
  })
  let groups = self.groups.map(group => {
    let json = group.to_json()
    if json is Object(fields) {
      fields["recorded_amount"] = usage_price_money_json(group.recorded_amount)
      fields["hypothetical_amount"] = usage_price_money_json(
        group.hypothetical_amount,
      )
      fields["delta"] = usage_price_money_json(group.delta)
    }
    json
  })
  let result : Json = {
    "schema_version": "lunanexa.usage-price-report.v1",
    "analysis_mode": "hypothetical-not-ledger",
    "window_policy": "intersecting records in full; no proration",
    "delta_policy": "candidate minus recorded charge; adjustments remain separate",
    "query": self.query.to_json(),
    "scenario": self.scenario.to_json(),
    "rows": rows.to_json(),
    "groups": groups.to_json(),
  }
  usage_price_output(result.stringify(indent=2))
}
