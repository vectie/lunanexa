///|
pub(all) struct HistorySnapshot {
  capture_id : String
  captured_unix_ms : Int64
  node_count : Int
  device_count : Int
  future_heartbeat_count : Int
} derive(Eq, ToJson)

///|
pub(all) struct HistoryChange {
  from_capture : String
  to_capture : String
  from_captured_unix_ms : Int64
  to_captured_unix_ms : Int64
  node_id : String
  device_id : String?
  scope : String
  field : String
  before : String?
  after : String?
  before_observed_unix_ms : Int64?
  after_observed_unix_ms : Int64?
} derive(Eq, ToJson)

///|
pub(all) struct HistoryTransition {
  from_capture : String
  to_capture : String
  newly_observed_nodes : Int
  absent_nodes : Int
  matched_nodes : Int
  repeated_heartbeat_nodes : Int
  regressed_heartbeat_nodes : Int
  total_change_count : Int
  selected_change_count : Int
} derive(Eq, ToJson)

///|
pub(all) struct HistoryReport {
  schema_version : String
  query : HistoryQuery
  captures : Array[HistorySnapshot]
  transitions : Array[HistoryTransition]
  changes : Array[HistoryChange]
} derive(Eq, ToJson)

///|
fn history_selected(change : HistoryChange, query : HistoryQuery) -> Bool {
  (query.node_id == "" || query.node_id == change.node_id) &&
  (query.scope == "all" || query.scope == change.scope) &&
  (query.field == "" || query.field == change.field)
}

///|
fn history_value_change(
  changes : Array[HistoryChange],
  context : HistoryChange,
  field : String,
  before : String,
  after : String,
) -> Unit {
  if before != after {
    changes.push({ ..context, field, before: Some(before), after: Some(after), })
  }
}

///|
fn history_runtime_names(names : Array[String]) -> String {
  let sorted = names.copy()
  sorted.sort()
  sorted.to_json().stringify()
}

///|
fn history_presence(
  context : HistoryChange,
  was_present : Bool,
) -> HistoryChange {
  {
    ..context,
    field: "presence",
    before: if was_present {
      Some("observed")
    } else {
      None
    },
    after: if was_present {
      None
    } else {
      Some("observed")
    },
  }
}

///|
/// Compare projections of adjacent captures, not the physical events between
/// them. A missing node is absent evidence, never inferred decommissioning.
pub fn explore_history(
  captures : Array[HistoryCapture],
  query : HistoryQuery,
) -> HistoryReport raise FleetError {
  validate_history_query(query)
  validate_capture_ids(captures.map(c => (c.capture_id, c.captured_unix_ms)))
  let projected : Array[Report] = []
  let snapshots : Array[HistorySnapshot] = []
  let mut all_nodes = 0
  let mut all_devices = 0
  // Every source is validated before filtering or generating any output.
  for capture in captures {
    all_nodes += capture.nodes.length()
    if all_nodes > 20000 {
      raise InvalidInput("history supports at most 20000 total node records")
    }
    let report = explore(capture.nodes, {
      now_unix_ms: capture.captured_unix_ms,
      maximum_age_ms: 0L,
      node_id: "",
      state: "",
      architecture: "",
      runtime: "",
      freshness: "all",
      health: "all",
    })
    all_devices += report.devices.length()
    if all_devices > 40000 {
      raise InvalidInput("history supports at most 40000 total device records")
    }
    snapshots.push({
      capture_id: capture.capture_id,
      captured_unix_ms: capture.captured_unix_ms,
      node_count: report.nodes.length(),
      device_count: report.devices.length(),
      future_heartbeat_count: report.nodes
      .filter(n => n.freshness == "future")
      .length(),
    })
    projected.push(report)
  }
  let transitions : Array[HistoryTransition] = []
  let selected : Array[HistoryChange] = []
  for i = 1; i < projected.length(); i = i + 1 {
    let before = projected[i - 1]
    let after = projected[i]
    let prior_nodes : Map[String, NodeRow] = Map([])
    let next_nodes : Map[String, NodeRow] = Map([])
    let node_ids : Map[String, Bool] = Map([])
    let prior_devices : Map[(String, String), DeviceRow] = Map([])
    let next_devices : Map[(String, String), DeviceRow] = Map([])
    let devices_by_node : Map[String, Map[String, Bool]] = Map([])
    for n in before.nodes {
      prior_nodes[n.node_id] = n
      node_ids[n.node_id] = true
    }
    for n in after.nodes {
      next_nodes[n.node_id] = n
      node_ids[n.node_id] = true
    }
    for d in before.devices {
      prior_devices[(d.node_id, d.device_id)] = d
      let ids = devices_by_node.get(d.node_id).unwrap_or(Map([]))
      ids[d.device_id] = true
      devices_by_node[d.node_id] = ids
    }
    for d in after.devices {
      next_devices[(d.node_id, d.device_id)] = d
      let ids = devices_by_node.get(d.node_id).unwrap_or(Map([]))
      ids[d.device_id] = true
      devices_by_node[d.node_id] = ids
    }
    let changes : Array[HistoryChange] = []
    let mut added = 0
    let mut absent = 0
    let mut matched = 0
    let mut repeated = 0
    let mut regressed = 0
    let keys = node_ids.keys().collect()
    keys.sort()
    for id in keys {
      let prior = prior_nodes.get(id)
      let next = next_nodes.get(id)
      let context : HistoryChange = {
        from_capture: captures[i - 1].capture_id,
        to_capture: captures[i].capture_id,
        from_captured_unix_ms: captures[i - 1].captured_unix_ms,
        to_captured_unix_ms: captures[i].captured_unix_ms,
        node_id: id,
        device_id: None,
        scope: "node",
        field: "",
        before: None,
        after: None,
        before_observed_unix_ms: prior.map(n => n.observed_unix_ms),
        after_observed_unix_ms: next.map(n => n.observed_unix_ms),
      }
      match (prior, next) {
        (None, Some(_)) => {
          added += 1
          changes.push(history_presence(context, false))
        }
        (Some(_), None) => {
          absent += 1
          changes.push(history_presence(context, true))
        }
        (Some(a), Some(b)) => {
          matched += 1
          if b.observed_unix_ms == a.observed_unix_ms {
            repeated += 1
          }
          if b.observed_unix_ms < a.observed_unix_ms {
            regressed += 1
          }
          history_value_change(changes, context, "state", a.state, b.state)
          history_value_change(
            changes,
            context,
            "agent_version",
            a.agent_version,
            b.agent_version,
          )
          history_value_change(
            changes,
            context,
            "runtime_names",
            history_runtime_names(a.runtime_names),
            history_runtime_names(b.runtime_names),
          )
          history_value_change(
            changes,
            context,
            "running_deployment_count",
            a.running_deployment_count.to_string(),
            b.running_deployment_count.to_string(),
          )
          let device_ids = devices_by_node.get(id).unwrap_or(Map([]))
          let devices = device_ids.keys().collect()
          devices.sort()
          for device_id in devices {
            let device_context = {
              ..context,
              device_id: Some(device_id),
              scope: "device",
            }
            match
              (
                prior_devices.get((id, device_id)),
                next_devices.get((id, device_id)),
              ) {
              (None, Some(_)) =>
                changes.push(history_presence(device_context, false))
              (Some(_), None) =>
                changes.push(history_presence(device_context, true))
              (Some(a), Some(b)) => {
                history_value_change(
                  changes,
                  device_context,
                  "architecture",
                  a.architecture,
                  b.architecture,
                )
                history_value_change(
                  changes,
                  device_context,
                  "healthy",
                  a.healthy.to_string(),
                  b.healthy.to_string(),
                )
                history_value_change(
                  changes,
                  device_context,
                  "observed_total_mib",
                  a.observed_total_mib.to_string(),
                  b.observed_total_mib.to_string(),
                )
                history_value_change(
                  changes,
                  device_context,
                  "observed_free_mib",
                  a.observed_free_mib.to_string(),
                  b.observed_free_mib.to_string(),
                )
              }
              _ => ()
            }
          }
        }
        _ => ()
      }
    }
    changes.sort_by_key(c => {
      (c.node_id, c.scope, c.device_id.unwrap_or(""), c.field)
    })
    let filtered = changes.filter(c => history_selected(c, query))
    transitions.push({
      from_capture: captures[i - 1].capture_id,
      to_capture: captures[i].capture_id,
      newly_observed_nodes: added,
      absent_nodes: absent,
      matched_nodes: matched,
      repeated_heartbeat_nodes: repeated,
      regressed_heartbeat_nodes: regressed,
      total_change_count: changes.length(),
      selected_change_count: filtered.length(),
    })
    selected.append(filtered)
  }
  {
    schema_version: "lunanexa.fleet.history-report.v1",
    query,
    captures: snapshots,
    transitions,
    changes: selected,
  }
}

///|
pub extend HistoryReport with ToJson::{to_json}

///|
pub extend HistoryReport with Eq::{equal, not_equal}

///|
pub extend HistorySnapshot with Eq::{equal, not_equal}

///|
pub extend HistorySnapshot with ToJson::{to_json}

///|
pub extend HistoryChange with Eq::{equal, not_equal}

///|
pub extend HistoryChange with ToJson::{to_json}

///|
pub extend HistoryTransition with Eq::{equal, not_equal}

///|
pub extend HistoryTransition with ToJson::{to_json}
