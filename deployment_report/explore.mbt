///|
/// Joins supplied node-level membership only; no individual replica readiness inference.
pub fn explore(
  operations : Array[@deployment.DeploymentOperation],
  nodes : Array[@contracts.NodeHeartbeat],
  query : Query,
) -> Report raise ReportError {
  validate_query(query)
  if operations.length() > 1000 || nodes.length() > 10000 {
    raise InvalidInput("operation/node collection bound exceeded")
  }
  let by_node : Map[String, @contracts.NodeHeartbeat] = Map([])
  let mut memberships = 0
  for node in nodes {
    identity(node.node_id)
    if node.node_id != node.inventory.node_id || by_node.contains(node.node_id) {
      raise InvalidInput("duplicate or mismatched node identity")
    }
    time(node.timestamp_unix_ms)
    memberships += node.running_deployments.length()
    if memberships > 20000 {
      raise InvalidInput("at most 20000 node membership references")
    }
    for id in node.running_deployments {
      identity(id)
    }
    by_node[node.node_id] = node
  }
  let seen : Map[String, Bool] = Map([])
  let deployments : Array[DeploymentRow] = []
  let placements : Array[PlacementRow] = []
  let mut replicas = 0
  let mut devices = 0
  for op in operations {
    identity(op.operation_id)
    identity(op.deployment_id)
    identity(op.plan.intent.template.template_id)
    identity(op.plan.intent.template.version)
    if seen.contains(op.operation_id) ||
      op.deployment_id != op.plan.intent.deployment_id {
      raise InvalidInput(
        "duplicate operation or mismatched intent deployment identity",
      )
    }
    seen[op.operation_id] = true
    if op.generation < 0L || op.plan.intent.replicas < 0 {
      raise InvalidInput("negative generation or requested replica count")
    }
    time(op.created_unix_ms)
    time(op.updated_unix_ms)
    if op.plan.template is Some(t) {
      if t.template_id != op.plan.intent.template.template_id ||
        t.version != op.plan.intent.template.version {
        raise InvalidInput("resolved template does not match intent")
      }
      for
        value in [
          t.model_id,
          t.model_version,
          t.artifact.digest,
          t.runtime.name,
          t.runtime.version,
          t.runtime.image_digest,
        ] {
        identity(value)
      }
    }
    replicas += op.plan.replicas.length()
    if replicas > 5000 {
      raise InvalidInput("at most 5000 planned replicas")
    }
    let replica_ids : Map[String, Bool] = Map([])
    for replica in op.plan.replicas {
      identity(replica.replica_id)
      identity(replica.node_id)
      if replica_ids.contains(replica.replica_id) {
        raise InvalidInput("duplicate replica identity within operation")
      }
      replica_ids[replica.replica_id] = true
      devices += replica.devices.length()
      if devices > 20000 {
        raise InvalidInput("at most 20000 planned device references")
      }
      let device_ids : Map[String, Bool] = Map([])
      for device in replica.devices {
        identity(device)
        if device_ids.contains(device) {
          raise InvalidInput("duplicate device identity within replica")
        }
        device_ids[device] = true
      }
    }
    let state = state_name(op.state)
    if (query.deployment_id != "" && query.deployment_id != op.deployment_id) ||
      (query.operation_state != "" && query.operation_state != state) ||
      (
        query.model_id != "" &&
        !op.plan.template
        .map(t => t.model_id == query.model_id)
        .unwrap_or(false)
      ) {
      continue
    }
    let selected = op.plan.replicas.filter(r => {
      query.node_id == "" || r.node_id == query.node_id
    })
    if query.node_id != "" && selected.is_empty() {
      continue
    }
    deployments.push({
      operation_id: op.operation_id,
      deployment_id: op.deployment_id,
      generation: op.generation,
      recorded_operation_state: state,
      template_id: op.plan.intent.template.template_id,
      template_version: op.plan.intent.template.version,
      model_id: op.plan.template.map(t => t.model_id),
      model_version: op.plan.template.map(t => t.model_version),
      artifact_digest: op.plan.template.map(t => t.artifact.digest),
      runtime_name: op.plan.template.map(t => t.runtime.name),
      runtime_version: op.plan.template.map(t => t.runtime.version),
      runtime_image_digest: op.plan.template.map(t => t.runtime.image_digest),
      requested_replicas: op.plan.intent.replicas,
      planned_replicas: op.plan.replicas.length(),
      selected_placements: selected.length(),
      created_unix_ms: op.created_unix_ms,
      updated_unix_ms: op.updated_unix_ms,
    })
    for replica in selected {
      let node = by_node.get(replica.node_id)
      let age = node.map(n => query.now_unix_ms - n.timestamp_unix_ms)
      let freshness = match age {
        None => "missing-node"
        Some(v) =>
          if v < 0L {
            "future"
          } else if v > query.maximum_age_ms {
            "stale"
          } else {
            "fresh"
          }
      }
      let device_ids = replica.devices.copy()
      device_ids.sort()
      placements.push({
        operation_id: op.operation_id,
        deployment_id: op.deployment_id,
        generation: op.generation,
        replica_id: replica.replica_id,
        planned_node_id: replica.node_id,
        planned_device_ids: device_ids,
        node_deployment_membership: match node {
          None => "missing-node"
          Some(n) =>
            if n.running_deployments.contains(op.deployment_id) {
              "listed"
            } else {
              "not-listed"
            }
        },
        observed_node_state: node.map(n => node_state(n.state)),
        observed_unix_ms: node.map(n => n.timestamp_unix_ms),
        freshness,
        age_ms: match age {
          Some(v) if v >= 0L => Some(v)
          _ => None
        },
      })
    }
  }
  deployments.sort_by_key(r => r.operation_id)
  placements.sort_by_key(r => (r.operation_id, r.replica_id))
  {
    schema_version: "lunanexa.deployment.report.v1",
    query,
    source_operation_count: operations.length(),
    source_node_count: nodes.length(),
    deployments,
    placements,
  }
}
