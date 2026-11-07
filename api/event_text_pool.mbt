///|
/// Deployment-owned configuration for four independently operated replicas.
/// This does not claim that they are signed managed deployments. Each pinned
/// loopback proxy must target exactly one node, never a load-balanced service.
pub(all) struct EventTextReplica {
  node_id : String
  origin : String
} derive(FromJson)

///|
pub extend EventTextReplica with FromJson::{from_json}

///|
pub(all) struct EventTextPool {
  model_alias : String
  served_model : String
  runtime_version : String
  image_digest : String
  artifact_digest : String
  replicas : Array[EventTextReplica]
} derive(FromJson)

///|
pub extend EventTextPool with FromJson::{from_json}

///|
pub fn ApiService::with_event_text_pool(
  self : ApiService,
  pool : EventTextPool,
  credential : String,
) -> ApiService raise {
  let nodes : Map[String, Unit] = Map([])
  let origins : Map[String, Unit] = Map([])
  guard pool.replicas.length() == 4 && credential.trim() != "" else {
    raise Failure("event text pool requires four authenticated replicas")
  }
  let routes : Array[ExternalTextRoute] = []
  for replica in pool.replicas {
    guard !nodes.contains(replica.node_id) && !origins.contains(replica.origin) else {
      raise Failure("event text replicas must have distinct nodes and origins")
    }
    nodes[replica.node_id] = ()
    origins[replica.origin] = ()
    let configured = self.with_external_text_route(
      pool.model_alias,
      "event-pool",
      replica.node_id,
      replica.origin,
      pool.served_model,
      pool.runtime_version,
      pool.image_digest,
      pool.artifact_digest,
      credential~,
    )
    let route = configured.external_text_route.unwrap()
    routes.push({ ..route, runtime: route.runtime.with_thinking_disabled(), })
  }
  { ..self, event_text_routes: routes, }
}

///|
async fn ApiService::external_event_ready_nodes(
  self : ApiService,
  policy : @event_trial.Policy,
  now : Int64,
) -> Array[String] {
  self.external_event_readiness(policy, now).0
}

///|
/// Detailed reasons stay on the authenticated operator projection, not model
/// responses. A ready count alone must not hide a transient eligibility failure.
async fn ApiService::external_event_readiness(
  self : ApiService,
  policy : @event_trial.Policy,
  now : Int64,
) -> (Array[String], Array[String]) {
  guard self.scheduler is Some(scheduler) &&
    self.registry is Some(registry) &&
    !self.active_event_routes().is_empty() &&
    self
    .active_event_routes()
    .all(route => {
      route.model_alias == policy.allowed_models[0] &&
      policy.node_ids.contains(route.node_id)
    }) else {
    return ([], ["Event replica configuration does not match the policy."])
  }
  let held = scheduler.snapshot().node_reservations.unwrap_or([])
  let heartbeats = self.store.heartbeats()
  let now = now.max(@async.now())
  let ready : Array[String] = []
  let reasons : Map[String, String] = Map([])
  @async.with_task_group <| group => {
    for route in self.active_event_routes() {
      group.spawn_bg() <| () => {
        guard heartbeats.iter().find_first(h => h.node_id == route.node_id)
          is Some(heartbeat) else {
          reasons[route.node_id] = "heartbeat missing"
          return
        }
        if event_heartbeat_time_blocker(
            heartbeat.timestamp_unix_ms,
            now,
            self.global_settings.control_timing,
          )
          is Some(reason) {
          reasons[route.node_id] = reason
          return
        }
        if heartbeat.inventory.labels.get(machine_usage_pool_label) !=
          Some("trial") {
          reasons[route.node_id] = "node is not in the trial pool"
          return
        }
        if held.any(r => {
            r.state != Released && r.request.node_ids.contains(route.node_id)
          }) {
          reasons[route.node_id] = "node is reserved"
          return
        }
        let node = self.managed_scheduler_node(heartbeat, now)
        guard node.state == Active else {
          reasons[route.node_id] = "node is inactive or blocked by an exclusive lease"
          return
        }
        guard node.allowed_data_classes.contains(Confidential) else {
          reasons[route.node_id] = "node data policy is incompatible"
          return
        }
        let snapshot = registry.snapshot()
        guard snapshot.aliases
          .iter()
          .find_first(a => a.name == route.model_alias)
          is Some(selected) &&
          snapshot.models
          .iter()
          .find_first(m => {
            m.model_id == selected.model_id &&
            m.version == selected.version &&
            m.state == Approved &&
            m.artifact.digest == route.runtime.artifact_digest() &&
            m.compatible_architectures.contains(node.architecture)
          })
          is Some(_) else {
          reasons[route.node_id] = "approved model, artifact or architecture does not match"
          return
        }
        guard self.external_route_observation(route).0 else {
          reasons[route.node_id] = "runtime health or served model verification failed"
          return
        }
        ready.push(route.node_id)
      }
    }
  }
  // Keep configured order stable when concurrent health probes finish in a
  // different order, so equal-load rotation remains deterministic.
  (
    policy.node_ids.filter(node => ready.contains(node)),
    [
      for node in policy.node_ids if reasons.contains(node) => {
        "\{node}: \{reasons[node]}"
      }
    ],
  )
}

///|
async fn ApiService::admit_external_event(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  policy : @event_trial.Policy,
  nodes : Array[String],
  required_deployment_id : String?,
  dedicated : Bool,
) -> (HttpReply?, Array[String]) {
  guard self.scheduler is Some(scheduler) &&
    self.registry is Some(registry) &&
    required_deployment_id is None &&
    !dedicated else {
    return (
      Some(
        api_error(
          403, "EventScopeDenied", "event replicas cannot fulfill dedicated deployment requests",
          false,
        ),
      ),
      [],
    )
  }
  let snapshot = registry.snapshot()
  let selected = snapshot.aliases
    .iter()
    .find_first(a => a.name == request.model_selector)
  let fits = selected.map_or(false, a => {
    snapshot.models.any(m => {
      m.model_id == a.model_id &&
      m.version == a.version &&
      m.state == Approved &&
      m.minimum_memory_mib <=
      request.resource_ceiling.max_accelerator_memory_mib
    })
  })
  let eligible : Array[String] = []
  for heartbeat in self.store.heartbeats() {
    if nodes.contains(heartbeat.node_id) {
      let node = self.managed_scheduler_node(heartbeat, @async.now())
      if node.state == Active &&
        node.allowed_data_classes.contains(request.data_policy.classification) {
        eligible.push(node.node_id)
      }
    }
  }
  if !fits || eligible.is_empty() {
    return (
      Some(
        api_error(
          503, "EventCapacityNotReady", "no event replica satisfies this request",
          true,
        ),
      ),
      [],
    )
  }
  match scheduler.admit(request, @async.now()) {
    Rejected(reason~) =>
      (
        Some(
          api_error(
            if reason == WorkloadAlreadyActive {
              409
            } else {
              429
            },
            "EventAdmissionRejected",
            "event request admission was rejected; retry within the event limits",
            true,
          ),
        ),
        [],
      )
    Accepted(_) =>
      match
        self.event_trial_router.reserve(
          request.workload_id,
          eligible.filter(id => {
            self.model_pool.map_or(true, p => {
              p.selected_targets().any(t => t.node_id == id)
            })
          }),
          policy.per_node_concurrency,
          prefix=self.event_prefix_key(request),
          now=@async.now(),
        ) {
        Some(node) => (None, [node])
        None => {
          scheduler.complete(request.workload_id, 0L)
          (
            Some(
              api_error(
                429, "EventCapacityBusy", "event replicas are busy; retry shortly",
                true,
              ),
            ),
            [],
          )
        }
      }
  }
}

///|
async fn ApiService::external_event_route(
  self : ApiService,
  request : @contracts.WorkloadEnvelope,
  nodes : Array[String],
) -> ExternalTextRoute? {
  guard !self.event_text_routes.is_empty() &&
    self.account_store is Some(accounts) &&
    accounts.event_for_tenant(request.tenant_ref) is Some(policy) else {
    return None
  }
  guard nodes.length() == 1 &&
    policy.allowed_models.contains(request.model_selector) &&
    policy.within_window(@async.now()) &&
    self.external_event_ready_nodes(policy, @async.now()).contains(nodes[0]) &&
    self
    .active_event_routes()
    .iter()
    .find_first(r => {
      r.node_id == nodes[0] && r.model_alias == request.model_selector
    })
    is Some(route) else {
    raise Failure("event replica became unavailable")
  }
  Some(route)
}
