///|
fn cell(text : String) -> String {
  let safe = if text.trim_start().has_prefix("=") ||
    text.trim_start().has_prefix("+") ||
    text.trim_start().has_prefix("-") ||
    text.trim_start().has_prefix("@") ||
    text.has_prefix("\t") ||
    text.has_prefix("\r") {
    "'" + text
  } else {
    text
  }
  "\"" + safe.replace_all(old="\"", new="\"\"") + "\""
}

///|
fn bounded(text : String) -> String raise ReportError {
  if text.length() > 8388608 {
    raise InvalidInput("output exceeds 8 Mi UTF-16 characters")
  }
  text
}

///|
fn csv(rows : Array[Json], columns : Array[String]) -> String raise ReportError {
  let lines = [columns.join(",")]
  for row in rows {
    guard row is Object(fields) else {
      raise InvalidInput("invalid report row")
    }
    let cells = columns.map(key => {
      match fields.get(key) {
        None | Some(Null) => ""
        Some(String(text)) => cell(text)
        Some(value) => cell(value.stringify())
      }
    })
    lines.push(cells.join(","))
  }
  bounded(lines.join("\r\n") + "\r\n")
}

///|
pub fn Report::json_text(self : Report) -> String raise ReportError {
  bounded(self.to_json().stringify(indent=2))
}

///|
pub fn Report::deployments_csv(self : Report) -> String raise ReportError {
  csv(self.deployments.map(r => r.to_json()), [
    "operation_id", "deployment_id", "generation", "recorded_operation_state", "template_id",
    "template_version", "model_id", "model_version", "artifact_digest", "runtime_name",
    "runtime_version", "runtime_image_digest", "requested_replicas", "planned_replicas",
    "selected_placements", "created_unix_ms", "updated_unix_ms",
  ])
}

///|
pub fn Report::placements_csv(self : Report) -> String raise ReportError {
  csv(self.placements.map(r => r.to_json()), [
    "operation_id", "deployment_id", "generation", "replica_id", "planned_node_id",
    "planned_device_ids", "node_deployment_membership", "observed_node_state", "observed_unix_ms",
    "freshness", "age_ms",
  ])
}
