///|
pub fn HistoryReport::json_text(self : HistoryReport) -> String {
  self.to_json().stringify(indent=2)
}

///|
pub fn HistoryReport::changes_csv(self : HistoryReport) -> String {
  let rows = [
    "from_capture,to_capture,from_captured_unix_ms,to_captured_unix_ms,node_id,device_id,scope,field,before,after,before_observed_unix_ms,after_observed_unix_ms",
  ]
  for c in self.changes {
    rows.push(
      [
        cell(c.from_capture),
        cell(c.to_capture),
        c.from_captured_unix_ms.to_string(),
        c.to_captured_unix_ms.to_string(),
        cell(c.node_id),
        c.device_id.map(cell).unwrap_or(""),
        cell(c.scope),
        cell(c.field),
        c.before.map(cell).unwrap_or(""),
        c.after.map(cell).unwrap_or(""),
        c.before_observed_unix_ms.map(v => v.to_string()).unwrap_or(""),
        c.after_observed_unix_ms.map(v => v.to_string()).unwrap_or(""),
      ].join(","),
    )
  }
  rows.join("\r\n") + "\r\n"
}

///|
pub fn HistoryReport::summary_csv(self : HistoryReport) -> String {
  let rows = [
    "from_capture,to_capture,newly_observed_nodes,absent_nodes,matched_nodes,repeated_heartbeat_nodes,regressed_heartbeat_nodes,total_change_count,selected_change_count",
  ]
  for c in self.transitions {
    rows.push(
      [
        cell(c.from_capture),
        cell(c.to_capture),
        c.newly_observed_nodes.to_string(),
        c.absent_nodes.to_string(),
        c.matched_nodes.to_string(),
        c.repeated_heartbeat_nodes.to_string(),
        c.regressed_heartbeat_nodes.to_string(),
        c.total_change_count.to_string(),
        c.selected_change_count.to_string(),
      ].join(","),
    )
  }
  rows.join("\r\n") + "\r\n"
}
