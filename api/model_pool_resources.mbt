///|
/// The Kubernetes pool is an execution adapter, not a resource authority.
/// Its historical API delegates admission to the same service ledger used by
/// portal lifecycle actions and signed node assignments.
async fn ApiService::claim_pool_services(
  self : ApiService,
  pool : @model_pool.Pool,
  nodes : Array[String],
  running : Bool,
) -> Unit {
  guard self.deployment_store is Some(store) else {
    raise Failure("model service authority unavailable")
  }
  let services = store.services()
  let selected : Array[@deployment.ModelServiceInstance] = []
  for node in nodes {
    guard pool.targets().iter().find_first(t => t.node_id == node)
      is Some(target) &&
      services
      .iter()
      .find_first(s => {
        s.runtime_kind == Kubernetes &&
        s.binding_ref == target.deployment &&
        s.node_ids == [node]
      })
      is Some(service) else {
      raise Failure("existing runtime must be adopted before deployment")
    }
    if running {
      self.check_service_resources(service)
    }
    selected.push(service)
  }
  // Validate the complete set before recording any desired state or adapter
  // mutation. A partial external write still retains all requested claims.
  for service in selected {
    ignore(
      store.set_service_desired(
        service.service_id,
        service.generation,
        running,
        @async.now(),
      ),
    )
  }
}
