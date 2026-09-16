///|
/// Record only a freshly inspected ready incarnation of an accepted assignment.
pub fn NodeAgent::observe_runtime_endpoint(
  self : NodeAgent,
  endpoint : @contracts.RuntimeEndpoint,
  now_unix_ms : Int64,
) -> Bool {
  guard self.assignments.get(endpoint.assignment_id) is Some(assignment) &&
    self.ready_assignments.get(endpoint.assignment_id) == Some(true) &&
    endpoint.matches(assignment, now_unix_ms) else {
    return false
  }
  self.runtime_routes[endpoint.assignment_id] = endpoint
  true
}

///|
pub fn NodeAgent::runtime_endpoints(
  self : NodeAgent,
  now_unix_ms : Int64,
) -> Array[@contracts.RuntimeEndpoint] {
  let endpoints : Array[@contracts.RuntimeEndpoint] = []
  for assignment_id, endpoint in self.runtime_routes {
    if self.ready_assignments.get(assignment_id) == Some(true) &&
      self.assignments
      .get(assignment_id)
      .map_or(false, assignment => endpoint.matches(assignment, now_unix_ms)) {
      endpoints.push(endpoint)
    }
  }
  endpoints
}
