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
pub fn Report::json_text(self : Report) -> String {
  self.to_json().stringify(indent=2)
}

///|
pub fn Report::nodes_csv(self : Report) -> String {
  let lines = [
    "node_id,state,observed_unix_ms,freshness,age_ms,agent_version,runtime_names_json,reported_devices,matching_devices,running_deployment_count",
  ]
  for row in self.nodes {
    let age = match row.age_ms {
      Some(value) => value.to_string()
      None => ""
    }
    lines.push(
      [
        cell(row.node_id),
        cell(row.state),
        row.observed_unix_ms.to_string(),
        cell(row.freshness),
        age,
        cell(row.agent_version),
        cell(row.runtime_names.to_json().stringify()),
        row.reported_devices.to_string(),
        row.matching_devices.to_string(),
        row.running_deployment_count.to_string(),
      ].join(","),
    )
  }
  lines.join("\r\n") + "\r\n"
}

///|
pub fn Report::devices_csv(self : Report) -> String {
  let lines = [
    "node_id,device_id,architecture,state,freshness,healthy,observed_total_mib,observed_free_mib",
  ]
  for row in self.devices {
    lines.push(
      [
        cell(row.node_id),
        cell(row.device_id),
        cell(row.architecture),
        cell(row.state),
        cell(row.freshness),
        row.healthy.to_string(),
        row.observed_total_mib.to_string(),
        row.observed_free_mib.to_string(),
      ].join(","),
    )
  }
  lines.join("\r\n") + "\r\n"
}

///|
pub fn Report::summary_csv(self : Report) -> String {
  let lines = [
    "architecture,state,freshness,healthy,device_count,summed_device_total_mib,summed_device_free_mib",
  ]
  for row in self.groups {
    lines.push(
      [
        cell(row.architecture),
        cell(row.state),
        cell(row.freshness),
        row.healthy.to_string(),
        row.device_count.to_string(),
        row.summed_device_total_mib.to_string(),
        row.summed_device_free_mib.to_string(),
      ].join(","),
    )
  }
  lines.join("\r\n") + "\r\n"
}
