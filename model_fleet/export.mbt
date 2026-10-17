///|
fn bounded_output(text : String) -> String raise CompatibilityError {
  if text.length() > 16777216 {
    raise InvalidInput("report exceeds 16 Mi characters; narrow the query")
  }
  text
}

///|
pub fn Report::json_text(self : Report) -> String raise CompatibilityError {
  bounded_output(self.to_json().stringify(indent=2))
}

///|
fn cell(value : String) -> String {
  let trimmed = value.trim_start()
  let safe = if trimmed.has_prefix("=") ||
    trimmed.has_prefix("+") ||
    trimmed.has_prefix("-") ||
    trimmed.has_prefix("@") ||
    value.has_prefix("\t") ||
    value.has_prefix("\r") {
    "'" + value
  } else {
    value
  }
  "\"" + safe.replace_all(old="\"", new="\"\"") + "\""
}

///|
fn optional_int(value : Int?) -> String {
  match value {
    Some(n) => n.to_string()
    None => ""
  }
}

///|
fn optional_bool(value : Bool?) -> String {
  match value {
    Some(n) => n.to_string()
    None => ""
  }
}

///|
pub fn Report::matrix_csv(self : Report) -> String raise CompatibilityError {
  let lines = [
    "scope,model_id,version,artifact_digest,recorded_model_state,declared_architectures_json,declared_minimum_memory_mib,memory_reserve_mib,required_with_reserve_mib,node_id,recorded_node_state,observed_unix_ms,freshness,device_id,device_architecture,recorded_device_healthy,observed_total_mib,observed_free_mib,memory_margin_mib,architecture_matches,memory_matches,declaration_comparison,cautions_json",
  ]
  for row in self.rows {
    let state = match row.recorded_model_state.to_json() {
      String(s) => s
      _ => ""
    }
    lines.push(
      [
        cell(self.scope),
        cell(row.model_id),
        cell(row.version),
        cell(row.artifact_digest),
        cell(state),
        cell(row.declared_architectures.to_json().stringify()),
        row.declared_minimum_memory_mib.to_string(),
        self.query.memory_reserve_mib.to_string(),
        row.required_with_reserve_mib.to_string(),
        cell(row.node_id),
        cell(row.recorded_node_state),
        row.observed_unix_ms.to_string(),
        cell(row.freshness),
        cell(row.device_id.unwrap_or("")),
        cell(row.device_architecture.unwrap_or("")),
        optional_bool(row.recorded_device_healthy),
        optional_int(row.observed_total_mib),
        optional_int(row.observed_free_mib),
        match row.memory_margin_mib {
          Some(n) => n.to_string()
          None => ""
        },
        optional_bool(row.architecture_matches),
        optional_bool(row.memory_matches),
        cell(row.declaration_comparison),
        cell(row.cautions.to_json().stringify()),
      ].join(","),
    )
  }
  bounded_output(lines.join("\r\n") + "\r\n")
}
