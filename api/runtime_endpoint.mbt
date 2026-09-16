///|
/// Node authority is checked by the heartbeat route before this validation.
async fn ApiService::heartbeat_runtime_endpoints_valid(
  self : ApiService,
  heartbeat : @contracts.NodeHeartbeat,
  now_unix_ms : Int64,
) -> Bool {
  let endpoints = heartbeat.runtime_endpoints.unwrap_or([])
  if endpoints.length() > 128 ||
    (
      !endpoints.is_empty() &&
      (
        heartbeat.state != Active ||
        heartbeat.inventory.node_id != heartbeat.node_id
      )
    ) {
    return false
  }
  let assignments = self.store.assignments()
  let seen : Map[String, Bool] = Map([])
  let incarnations : Map[String, Bool] = Map([])
  for endpoint in endpoints {
    if seen.contains(endpoint.assignment_id) ||
      incarnations.contains(endpoint.instance_id) ||
      endpoint.observed_unix_ms > heartbeat.timestamp_unix_ms ||
      !heartbeat.running_deployments.contains(endpoint.deployment_id) ||
      heartbeat.controller_epoch != endpoint.controller_epoch ||
      heartbeat.observed_generation < endpoint.generation ||
      !assignments.any(assignment => {
        assignment.node_id == heartbeat.node_id &&
        endpoint.matches(assignment, now_unix_ms)
      }) {
      return false
    }
    seen[endpoint.assignment_id] = true
    incarnations[endpoint.instance_id] = true
  }
  true
}
