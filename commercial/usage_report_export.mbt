///|
fn usage_amount_cells(amount : FixedMoney?) -> Array[String] {
  match amount {
    Some(value) =>
      [
        value.minor_units.to_string(),
        csv_cell(value.currency),
        value.scale.to_string(),
      ]
    None => ["", "", ""]
  }
}

///|
fn usage_query_cells(query : UsageQuery) -> Array[String] {
  [
    csv_cell(query.organization_id),
    query.started_unix_ms.to_string(),
    query.ended_unix_ms.to_string(),
  ]
}

///|
/// Spreadsheet-ready exact minor units. Empty money cells mean unpriced usage;
/// a numeric zero is present only when the source ledger actually records zero.
pub fn UsageReport::summary_csv(self : UsageReport) -> String {
  let output = StringBuilder()
  output.write_string(
    "organization_id,window_start_unix_ms,window_end_unix_ms,group_by,group_id,meter,unit,quantity,minor_units,currency,scale,row_count,ledger_entry_count,unpriced_usage_count,missing_observation_count,crossing_window_count\n",
  )
  for group in self.groups {
    let cells = usage_query_cells(self.query)
    cells.append([
      csv_cell(self.query.group_by),
      csv_cell(group.group_id),
      csv_cell(group.meter),
      csv_cell(group.unit),
      group.quantity.to_string(),
    ])
    cells.append(usage_amount_cells(group.amount))
    cells.append([
      group.row_count.to_string(),
      group.ledger_entry_count.to_string(),
      group.unpriced_usage_count.to_string(),
      group.missing_observation_count.to_string(),
      group.crossing_window_count.to_string(),
    ])
    output.write_string(cells.join(","))
    output.write_char('\n')
  }
  output.to_string()
}

///|
/// Joined drill-down, excluding node identity, actors and organization legal data.
pub fn UsageReport::rows_csv(self : UsageReport) -> String {
  let output = StringBuilder()
  output.write_string(usage_rows_header)
  for row in self.rows {
    output.write_string(usage_row_cells(self.query, row).join(","))
    output.write_char('\n')
  }
  output.to_string()
}

///|
let usage_rows_header : String = "organization_id,window_start_unix_ms,window_end_unix_ms,cost_center_id,cost_center_name,project_id,project_name,event_id,workload_id,entry_id,linked_entry_id,kind,meter,unit,quantity,minor_units,currency,scale,started_unix_ms,ended_unix_ms,recorded_unix_ms,rate_card_id,rate_card_version,reason,observation_available,crosses_window\n"

///|
fn usage_row_cells(query : UsageQuery, row : UsageReportRow) -> Array[String] {
  let cells = usage_query_cells(query)
  cells.append(
    [
      row.cost_center_id,
      row.cost_center_name,
      row.project_id,
      row.project_name,
      row.event_id,
      row.workload_id,
      row.entry_id,
      row.linked_entry_id,
      row.kind,
      row.meter,
      row.unit,
    ].map(csv_cell),
  )
  cells.push(row.quantity.to_string())
  cells.append(usage_amount_cells(row.amount))
  cells.append([
    row.started_unix_ms.to_string(),
    row.ended_unix_ms.to_string(),
    row.recorded_unix_ms.to_string(),
    csv_cell(row.rate_card_id),
    csv_cell(row.rate_card_version),
    csv_cell(row.reason),
    row.observation_available.to_string(),
    row.crosses_window.to_string(),
  ])
  cells
}

///|
/// Portable output uses JSON null for an unknown money value.
fn UsageReport::usage_report_json(self : UsageReport) -> Json {
  let rows = self.rows.map(row => {
    let json = row.to_json()
    if json is Object(fields) {
      fields["amount"] = row.amount
        .map(value => value.to_json())
        .unwrap_or(Json::null())
    }
    json
  })
  let groups = self.groups.map(group => {
    let json = group.to_json()
    if json is Object(fields) {
      fields["amount"] = group.amount
        .map(value => value.to_json())
        .unwrap_or(Json::null())
    }
    json
  })
  let result : Json = {
    "schema_version": "lunanexa.usage-report.v1",
    "source_schema_version": snapshot_schema_version.to_json(),
    "window_policy": "intersecting records in full; no proration",
    "query": self.query.to_json(),
    "rows": rows.to_json(),
    "groups": groups.to_json(),
  }
  result
}

///|
pub fn UsageReport::json_text(self : UsageReport) -> String {
  self.usage_report_json().stringify(indent=2)
}
