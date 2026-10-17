///|
/// Compare declared requirements against each individual observed device.
/// Matching declarations never establishes placement, approval or readiness.
pub fn explore(
  models : Array[@contracts.ModelRecord],
  nodes : Array[@contracts.NodeHeartbeat],
  query : Query,
) -> Report raise {
  validate_query(query)
  validate_models(models)
  // The existing fleet validator checks every source row before filtering.
  let fleet = @fleet.explore(nodes, {
    now_unix_ms: query.now_unix_ms,
    maximum_age_ms: query.maximum_age_ms,
    node_id: query.node_id,
    state: "",
    architecture: "",
    runtime: "",
    freshness: "all",
    health: "all",
  })
  for node in nodes {
    bounded_text(node.node_id, "node ID", allow_empty=false)
    for device in node.inventory.accelerators {
      bounded_text(device.device_id, "device ID", allow_empty=false)
      bounded_text(
        device.architecture,
        "device architecture",
        allow_empty=false,
      )
    }
  }
  let selected = models.filter(model => {
    (query.model_id == "" || model.model_id == query.model_id) &&
    (query.version == "" || model.version == query.version)
  })
  selected.sort_by_key(model => (model.model_id, model.version))
  let mut rows_per_model = fleet.devices.length()
  for node in fleet.nodes {
    if node.reported_devices == 0 {
      rows_per_model += 1
    }
  }
  if selected.length().to_int64() * rows_per_model.to_int64() > 50000L {
    raise InvalidInput(
      "comparison exceeds 50000 rows; select a model/version or node",
    )
  }
  let by_node : Map[String, Array[@fleet.DeviceRow]] = Map([])
  for device in fleet.devices {
    let entries = by_node.get(device.node_id).unwrap_or([])
    entries.push(device)
    by_node[device.node_id] = entries
  }
  let rows : Array[Row] = []
  let summaries : Array[ModelSummary] = []
  for model in selected {
    let mut matches = 0
    let mut without_devices = 0
    let required = model.minimum_memory_mib.to_int64() +
      query.memory_reserve_mib.to_int64()
    let architectures = model.compatible_architectures.copy()
    architectures.sort()
    for node in fleet.nodes {
      let cautions : Array[String] = []
      if model.state != Approved {
        cautions.push("model-not-recorded-approved")
      }
      if node.state != "Active" {
        cautions.push("node-not-recorded-active")
      }
      if node.freshness != "fresh" {
        cautions.push(node.freshness + "-heartbeat")
      }
      let base : Row = {
        model_id: model.model_id,
        version: model.version,
        artifact_digest: model.artifact.digest,
        recorded_model_state: model.state,
        declared_architectures: architectures.copy(),
        declared_minimum_memory_mib: model.minimum_memory_mib,
        required_with_reserve_mib: required,
        node_id: node.node_id,
        recorded_node_state: node.state,
        observed_unix_ms: node.observed_unix_ms,
        freshness: node.freshness,
        device_id: None,
        device_architecture: None,
        recorded_device_healthy: None,
        observed_total_mib: None,
        observed_free_mib: None,
        memory_margin_mib: None,
        architecture_matches: None,
        memory_matches: None,
        declaration_comparison: "no-device-observation",
        cautions,
      }
      let devices = by_node.get(node.node_id).unwrap_or([])
      if devices.is_empty() {
        without_devices += 1
        let warnings = cautions.copy()
        warnings.push("no-accelerator-observation")
        rows.push({ ..base, cautions: warnings, })
      }
      for device in devices {
        let architecture = architectures.contains(device.architecture)
        let margin = device.observed_free_mib.to_int64() - required
        let memory = margin >= 0L
        let comparison = match (architecture, memory) {
          (true, true) => "matches-declarations"
          (false, true) => "architecture-mismatch"
          (true, false) => "memory-shortfall"
          (false, false) => "architecture-and-memory-mismatch"
        }
        if architecture && memory {
          matches += 1
        }
        let warnings = cautions.copy()
        if !device.healthy {
          warnings.push("device-recorded-unhealthy")
        }
        rows.push({
          ..base,
          device_id: Some(device.device_id),
          device_architecture: Some(device.architecture),
          recorded_device_healthy: Some(device.healthy),
          observed_total_mib: Some(device.observed_total_mib),
          observed_free_mib: Some(device.observed_free_mib),
          memory_margin_mib: Some(margin),
          architecture_matches: Some(architecture),
          memory_matches: Some(memory),
          declaration_comparison: comparison,
          cautions: warnings,
        })
      }
    }
    summaries.push({
      model_id: model.model_id,
      version: model.version,
      compared_devices: fleet.devices.length(),
      devices_matching_declarations: matches,
      nodes_without_devices: without_devices,
    })
  }
  {
    schema_version: "lunanexa.model-fleet.report.v1",
    scope: "single-device-declarations-only",
    query,
    source_model_count: models.length(),
    source_node_count: nodes.length(),
    selected_model_count: selected.length(),
    selected_node_count: fleet.nodes.length(),
    unassessed: [
      "measurement-authenticity", "runtime-compatibility-and-readiness", "license-and-verification",
      "data-policy", "reservation-and-entitlement", "topology-and-sharding", "workload-memory-overhead",
      "performance-and-service-objective",
    ],
    models: summaries,
    rows,
  }
}
