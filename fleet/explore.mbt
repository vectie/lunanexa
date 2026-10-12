///|
pub suberror FleetError {
  InvalidInput(String)
}

///|
/// Explicit local query. Empty identity filters mean all values.
pub(all) struct Query {
  now_unix_ms : Int64
  maximum_age_ms : Int64
  node_id : String
  state : String
  architecture : String
  runtime : String
  freshness : String
  health : String
} derive(Eq, ToJson, FromJson)

///|
pub(all) struct NodeRow {
  node_id : String
  state : String
  observed_unix_ms : Int64
  freshness : String
  age_ms : Int64?
  agent_version : String
  runtime_names : Array[String]
  reported_devices : Int
  matching_devices : Int
  running_deployment_count : Int
} derive(Eq, ToJson)

///|
pub(all) struct DeviceRow {
  node_id : String
  device_id : String
  architecture : String
  state : String
  freshness : String
  healthy : Bool
  observed_total_mib : Int
  observed_free_mib : Int
} derive(Eq, ToJson)

///|
pub(all) struct Group {
  architecture : String
  state : String
  freshness : String
  healthy : Bool
  device_count : Int
  summed_device_total_mib : Int64
  summed_device_free_mib : Int64
} derive(Eq, ToJson)

///|
pub(all) struct Report {
  schema_version : String
  query : Query
  source_node_count : Int
  nodes : Array[NodeRow]
  devices : Array[DeviceRow]
  groups : Array[Group]
} derive(Eq, ToJson)

///|
fn state_name(value : @contracts.NodeState) -> String {
  match value {
    Enrolling => "Enrolling"
    Active => "Active"
    Cordoned => "Cordoned"
    Draining => "Draining"
    Unreachable => "Unreachable"
    Retired => "Retired"
  }
}

///|
fn validate_query(query : Query) -> Unit raise FleetError {
  if query.now_unix_ms < 0L ||
    query.now_unix_ms > 9007199254740991L ||
    query.maximum_age_ms < 0L ||
    query.maximum_age_ms > 9007199254740991L {
    raise InvalidInput(
      "query time and maximum age must be nonnegative and at most 9007199254740991 ms",
    )
  }
  if ![
      "", "Enrolling", "Active", "Cordoned", "Draining", "Unreachable", "Retired",
    ].contains(query.state) {
    raise InvalidInput("unknown node state filter")
  }
  if !["all", "fresh", "stale", "future"].contains(query.freshness) ||
    !["all", "healthy", "unhealthy"].contains(query.health) {
    raise InvalidInput(
      "freshness must be all/fresh/stale/future; health must be all/healthy/unhealthy",
    )
  }
}

///|
pub fn import_query(text : String) -> Query raise {
  if text.length() > 16384 {
    raise InvalidInput("query exceeds 16 Ki characters")
  }
  let value = @json.parse(text)
  guard value is Object(fields) else {
    raise InvalidInput("query must be an object")
  }
  for key, _ in fields {
    if ![
        "now_unix_ms", "maximum_age_ms", "node_id", "state", "architecture", "runtime",
        "freshness", "health",
      ].contains(key) {
      raise InvalidInput("unknown query field: \{key}")
    }
  }
  let query : Query = @json.from_json(value)
  validate_query(query)
  query
}

///|
/// The existing operator GET /v1/nodes response, without a wrapper.
/// Signatures and endpoint details are decoded but never exported or authenticated.
pub fn import_nodes(text : String) -> Array[@contracts.NodeHeartbeat] raise {
  if text.length() > 8388608 {
    raise InvalidInput("snapshot exceeds 8 Mi characters")
  }
  let value = @json.parse(text)
  guard value is Array(rows) && rows.length() <= 10000 else {
    raise InvalidInput(
      "snapshot must be an array of at most 10000 node heartbeats",
    )
  }
  @json.from_json(value)
}

///|
pub fn explore(
  nodes : Array[@contracts.NodeHeartbeat],
  query : Query,
) -> Report raise FleetError {
  validate_query(query)
  if nodes.length() > 10000 {
    raise InvalidInput("at most 10000 nodes are supported")
  }
  let identities : Map[String, Bool] = Map([])
  let node_rows : Array[NodeRow] = []
  let devices : Array[DeviceRow] = []
  let grouped : Map[String, Group] = Map([])
  let mut device_count = 0
  for node in nodes {
    if node.node_id == "" ||
      node.node_id != node.inventory.node_id ||
      identities.contains(node.node_id) {
      raise InvalidInput("duplicate, empty or mismatched node identity")
    }
    identities[node.node_id] = true
    if node.timestamp_unix_ms < 0L || node.timestamp_unix_ms > 9007199254740991L {
      raise InvalidInput("heartbeat timestamp outside supported range")
    }
    device_count += node.inventory.accelerators.length()
    if device_count > 20000 {
      raise InvalidInput("at most 20000 accelerator records are supported")
    }
    let device_ids : Map[String, Bool] = Map([])
    for device in node.inventory.accelerators {
      if device.device_id == "" ||
        device.architecture == "" ||
        device_ids.contains(device.device_id) {
        raise InvalidInput(
          "duplicate or empty accelerator identity/architecture",
        )
      }
      device_ids[device.device_id] = true
      if device.memory_total_mib < 0 ||
        device.memory_free_mib < 0 ||
        device.memory_free_mib > device.memory_total_mib {
        raise InvalidInput("accelerator memory must satisfy 0 <= free <= total")
      }
    }
    let state = state_name(node.state)
    let age = query.now_unix_ms - node.timestamp_unix_ms
    let freshness = if age < 0L {
      "future"
    } else if age > query.maximum_age_ms {
      "stale"
    } else {
      "fresh"
    }
    if (query.node_id != "" && node.node_id != query.node_id) ||
      (query.state != "" && state != query.state) ||
      (
        query.runtime != "" &&
        !node.inventory.runtime_names.contains(query.runtime)
      ) ||
      (query.freshness != "all" && query.freshness != freshness) {
      continue
    }
    let matching = node.inventory.accelerators.filter(device => {
      (query.architecture == "" || query.architecture == device.architecture) &&
      (
        query.health == "all" ||
        (query.health == "healthy" && device.healthy) ||
        (query.health == "unhealthy" && !device.healthy)
      )
    })
    if matching.is_empty() &&
      (query.architecture != "" || query.health != "all") {
      continue
    }
    node_rows.push({
      node_id: node.node_id,
      state,
      observed_unix_ms: node.timestamp_unix_ms,
      freshness,
      age_ms: if age < 0L {
        None
      } else {
        Some(age)
      },
      agent_version: node.inventory.agent_version,
      runtime_names: node.inventory.runtime_names.copy(),
      reported_devices: node.inventory.accelerators.length(),
      matching_devices: matching.length(),
      running_deployment_count: node.running_deployments.length(),
    })
    for device in matching {
      devices.push({
        node_id: node.node_id,
        device_id: device.device_id,
        architecture: device.architecture,
        state,
        freshness,
        healthy: device.healthy,
        observed_total_mib: device.memory_total_mib,
        observed_free_mib: device.memory_free_mib,
      })
      let key = [
          device.architecture,
          state,
          freshness,
          device.healthy.to_string(),
        ]
        .to_json()
        .stringify()
      let prior = grouped
        .get(key)
        .unwrap_or({
          architecture: device.architecture,
          state,
          freshness,
          healthy: device.healthy,
          device_count: 0,
          summed_device_total_mib: 0L,
          summed_device_free_mib: 0L,
        })
      grouped[key] = {
        ..prior,
        device_count: prior.device_count + 1,
        summed_device_total_mib: prior.summed_device_total_mib +
        device.memory_total_mib.to_int64(),
        summed_device_free_mib: prior.summed_device_free_mib +
        device.memory_free_mib.to_int64(),
      }
    }
  }
  node_rows.sort_by_key(row => row.node_id)
  devices.sort_by_key(row => (row.node_id, row.device_id))
  let groups = grouped.values().collect()
  groups.sort_by_key(row => {
    (row.architecture, row.state, row.freshness, row.healthy.to_string())
  })
  {
    schema_version: "lunanexa.fleet.report.v1",
    query,
    source_node_count: nodes.length(),
    nodes: node_rows,
    devices,
    groups,
  }
}

///|
pub extend Query with Eq::{not_equal, equal}

///|
pub extend Query with ToJson::{to_json}

///|
pub extend NodeRow with Eq::{not_equal, equal}

///|
pub extend NodeRow with ToJson::{to_json}

///|
pub extend DeviceRow with Eq::{not_equal, equal}

///|
pub extend DeviceRow with ToJson::{to_json}

///|
pub extend Group with Eq::{not_equal, equal}

///|
pub extend Group with ToJson::{to_json}

///|
pub extend Report with Eq::{not_equal, equal}

///|
pub extend Report with ToJson::{to_json}

///|
pub extend Query with FromJson::{from_json}
