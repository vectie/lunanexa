///|
/// Money nulls and exact minor units follow the existing usage report contract.
pub fn UsageCorrelationReport::json_text(
  self : UsageCorrelationReport,
) -> String {
  let references = self.references.map(value => {
    let json : Json = {
      "external_ref": value.external_ref.to_json(),
      "links": value.links.to_json(),
      "report": value.report.usage_report_json(),
    }
    json
  })
  let json : Json = {
    "schema_version": "lunanexa.usage-correlation-report.v1",
    "association_policy": "analyst_supplied_event_links_adjustments_follow_original_charge",
    "missing_policy": "no_selected_row_is_unresolved_not_zero",
    "query": self.query.to_json(),
    "duplicate_link_count": self.duplicate_link_count.to_json(),
    "references": references.to_json(),
    "unassigned": self.unassigned.usage_report_json(),
  }
  json.stringify(indent=2)
}

///|
fn correlation_csv_line(output : StringBuilder, cells : Array[String]) -> Unit {
  output.write_string(cells.join(","))
  output.write_char('\n')
}

///|
/// Each selected source row appears exactly once; unresolved links are blank
/// data rows. The original event and linked charge IDs remain in the drilldown.
pub fn UsageCorrelationReport::rows_csv(
  self : UsageCorrelationReport,
) -> String {
  let output = StringBuilder()
  output.write_string(
    "correlation_status,external_ref,correlation_project_id,correlation_event_id,",
  )
  output.write_string(usage_rows_header)
  for reference in self.references {
    let row_links : Map[String, UsageCorrelationLink] = Map([])
    for value in reference.links {
      for id in value.source_row_ids {
        row_links[id] = value.link
      }
    }
    for row in reference.report.rows {
      let link = row_links[correlation_row_id(row)]
      let cells = [
        "assigned",
        csv_cell(reference.external_ref),
        csv_cell(link.project_id),
        csv_cell(link.event_id),
      ]
      cells.append(usage_row_cells(self.query, row))
      correlation_csv_line(output, cells)
    }
    for value in reference.links {
      if value.row_count != 0 {
        continue
      }
      let cells = [
        "not_observed_in_selection",
        csv_cell(reference.external_ref),
        csv_cell(value.link.project_id),
        csv_cell(value.link.event_id),
      ]
      cells.append(usage_query_cells(self.query))
      for i = 0; i < 23; i = i + 1 {
        cells.push("")
      }
      correlation_csv_line(output, cells)
    }
  }
  for row in self.unassigned.rows {
    let cells = ["unassigned", "", "", ""]
    cells.append(usage_row_cells(self.query, row))
    correlation_csv_line(output, cells)
  }
  output.to_string()
}

///|
/// Reference totals retain project/cost-center/meter grouping and never merge
/// unlike units, currencies, scales or unpriced usage. Missing links are rows.
pub fn UsageCorrelationReport::summary_csv(
  self : UsageCorrelationReport,
) -> String {
  let output = StringBuilder()
  output.write_string(
    "correlation_status,external_ref,missing_link_count,organization_id,window_start_unix_ms,window_end_unix_ms,group_by,group_id,meter,unit,quantity,minor_units,currency,scale,row_count,ledger_entry_count,unpriced_usage_count,missing_observation_count,crossing_window_count\n",
  )
  let groups = self.references +
    [{ external_ref: "", links: [], report: self.unassigned, }]
  for reference in groups {
    let missing = reference.links.filter(value => value.row_count == 0).length()
    for group in reference.report.groups {
      let cells = [
        if reference.external_ref == "" {
          "unassigned"
        } else {
          "assigned"
        },
        csv_cell(reference.external_ref),
        missing.to_string(),
      ]
      cells.append(usage_query_cells(self.query))
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
      correlation_csv_line(output, cells)
    }
    if missing > 0 {
      let cells = [
        "not_observed_in_selection",
        csv_cell(reference.external_ref),
        missing.to_string(),
      ]
      cells.append(usage_query_cells(self.query))
      for i = 0; i < 13; i = i + 1 {
        cells.push("")
      }
      correlation_csv_line(output, cells)
    }
  }
  output.to_string()
}
