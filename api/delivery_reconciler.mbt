///|
fn delivery_assignment_id(operation : @delivery.Operation) -> String {
  "\{operation.operation_id}-model"
}

///|
fn delivery_replica_id(operation : @delivery.Operation, index : Int) -> String {
  if index == 0 {
    delivery_assignment_id(operation)
  } else {
    "\{operation.operation_id}-model-\{index}"
  }
}

///|
fn delivery_model_claim(operation : @delivery.Operation, id : String) -> Bool {
  for index in 0..<operation.node_ids.length() {
    if delivery_replica_id(operation, index) == id {
      return true
    }
  }
  false
}

///|
fn delivery_replica_record(
  operation : @delivery.Operation,
  assignment : @contracts.DesiredAssignment,
) -> @delivery.ModelReplica {
  match
    operation.model_replicas
    .unwrap_or([])
    .iter()
    .find_first(replica => replica.assignment_id == assignment.assignment_id) {
    Some(replica) if replica.generation == assignment.generation => replica
    previous =>
      {
        assignment_id: assignment.assignment_id,
        node_id: assignment.node_id,
        generation: assignment.generation,
        prepared: previous.map_or(
          operation.stage == LoadingModel &&
          assignment.assignment_id == delivery_assignment_id(operation),
          value => value.prepared,
        ),
        ready: false,
        stopped: false,
      }
  }
}

///|
fn delivery_replica_terminated(
  operation : @delivery.Operation,
  replica : @delivery.ModelReplica,
  records : Array[@media_jobs.AcceptedTermination],
) -> Bool {
  replica.stopped ||
  records.any(record => {
    record.node_id == replica.node_id &&
    record.evidence.assignment_id == replica.assignment_id &&
    record.evidence.deployment_id == operation.operation_id &&
    record.evidence.generation == replica.generation &&
    record.evidence.observed_unix_ms >=
    operation.stop_requested_at_ms.unwrap_or(operation.updated_at_ms)
  })
}

///|
async fn ApiService::append_delivery_media_bindings(
  self : ApiService,
  bindings : Array[MediaBinding],
  templates : Array[MediaTemplateBinding],
) -> Unit {
  guard self.delivery_store is Some(deliveries) &&
    self.scheduler is Some(scheduler) else {
    return
  }
  let heartbeats = self.store.heartbeats()
  let now = @async.now()
  let physical : Array[@delivery.Operation] = []
  for service in deliveries.model_services() {
    physical.push(service.runtime)
  }
  for operation in deliveries.operations() {
    if !deliveries
      .model_services()
      .any(service => service.consumer_ids.contains(operation.operation_id)) {
      physical.push(operation)
    }
  }
  for operation in physical {
    if operation.stage is (Stopped | Expired | Stopping | Failed) {
      continue
    }
    guard operation.reservation_id is Some(id) &&
      scheduler.node_reservation(id) is Some(reservation) &&
      reservation.state == Reserved &&
      reservation.request.tenant_ref == operation.intent.tenant_id &&
      reservation.request.expires_unix_ms > now else {
      continue
    }
    for
      assignment in self.store
      .assignments()
      .filter(value => value.deployment_id == operation.operation_id) {
      if !self.delivery_runtime_observed(assignment, now) {
        continue
      }
      for template in templates {
        if template.template_id != operation.intent.template_id ||
          template.template_version != operation.intent.template_version ||
          template.node_id != assignment.node_id {
          continue
        }
        // Dynamic customer deployments never reuse a fixed shared-service origin.
        guard template.runtime_route is Some(policy) else { continue }
        for heartbeat in heartbeats {
          if heartbeat.node_id != assignment.node_id {
            continue
          }
          for endpoint in heartbeat.runtime_endpoints.unwrap_or([]) {
            if endpoint.matches(assignment, now) && policy.allows(endpoint) {
              bindings.push({
                deployment_id: operation.operation_id,
                deployment_generation: assignment.generation,
                node_id: assignment.node_id,
                origin: "http://\{endpoint.address}:\{endpoint.port}",
                bearer: template.bearer,
                profile: template.profile,
                instance_id: Some(endpoint.instance_id),
              })
            }
          }
        }
      }
    }
  }
}

///|
/// Reuse is considered only when the original physical assignment is still
/// present, every replica has live node evidence, and the model-specific probe
/// responds. The store repeats the scope check inside its durable transaction.
async fn ApiService::ready_reusable_model_service(
  self : ApiService,
  operation : @delivery.Operation,
  template : @deployment.ModelServiceTemplate,
) -> String? {
  guard self.delivery_store is Some(deliveries) else { return None }
  if operation.intent.model_digest != Some(template.artifact.digest) {
    return None
  }
  let now = @async.now()
  for service in deliveries.model_services() {
    let runtime = service.runtime
    if runtime.operation_id == operation.operation_id ||
      runtime.stage != Ready ||
      service.consumer_ids.is_empty() ||
      !@delivery.model_service_scope_matches(runtime, operation) ||
      runtime.model_replicas.map_or(true, replicas => {
        replicas.length() != runtime.node_ids.length() ||
        !replicas.all(replica => replica.ready && !replica.stopped)
      }) {
      continue
    }
    let mut all_ready = true
    for replica in runtime.model_replicas.unwrap_or([]) {
      guard self.store.assignment(replica.assignment_id) is Some(assignment) &&
        assignment.deployment_id == runtime.operation_id &&
        assignment.node_id == replica.node_id &&
        assignment.generation == replica.generation &&
        assignment.artifact.digest == template.artifact.digest &&
        assignment.reservation.map_or(false, value => {
          Some(value.reservation_id) == runtime.reservation_id &&
          value.tenant_ref == runtime.intent.tenant_id
        }) &&
        self.delivery_runtime_observed(assignment, now) &&
        self.delivery_model_ready(runtime, template, assignment) else {
        all_ready = false
        break
      }
    }
    if all_ready {
      return Some(runtime.operation_id)
    }
  }
  None
}

///|
/// Only the last consumer requests this physical stop. Desired assignments
/// disappear first; termination, node heartbeats, and scheduler claims then
/// prove it is safe to mark the service stopped.
async fn ApiService::reconcile_stopping_model_service(
  self : ApiService,
  service : @delivery.ModelService,
) -> Unit {
  guard self.delivery_store is Some(deliveries) &&
    self.scheduler is Some(scheduler) else {
    return
  }
  let mut runtime = service.runtime
  let now = @async.now()
  if runtime.stage != Stopping {
    return
  }
  for
    assignment in self.store
    .assignments()
    .filter(value => value.deployment_id == runtime.operation_id) {
    let replica = delivery_replica_record(runtime, assignment)
    if !runtime.model_replicas.unwrap_or([]).contains(replica) {
      runtime = deliveries.observe_model_service(
        runtime.operation_id,
        runtime.generation,
        ModelReplicaObserved(replica),
        now,
      )
    }
  }
  self.remove_deployment_assignments(runtime.operation_id)
  let reservation = match runtime.reservation_id {
    Some(id) => scheduler.node_reservation(id)
    None => None
  }
  if runtime.model_replicas is None && reservation is Some(value) {
    for claim in value.services {
      if claim.service_id == delivery_assignment_id(runtime) &&
        runtime.model_assignment_generation is Some(generation) {
        runtime = deliveries.observe_model_service(
          runtime.operation_id,
          runtime.generation,
          ModelReplicaObserved({
            assignment_id: claim.service_id,
            node_id: claim.node_id,
            generation,
            prepared: false,
            ready: false,
            stopped: false,
          }),
          now,
        )
      }
    }
  }
  let heartbeats = self.store.heartbeats()
  let stopped = runtime.node_ids.all(node_id => {
    heartbeats.any(heartbeat => {
      heartbeat.node_id == node_id &&
      heartbeat.timestamp_unix_ms >
      runtime.stop_requested_at_ms.unwrap_or(runtime.updated_at_ms) &&
      heartbeat.timestamp_unix_ms <= now &&
      now - heartbeat.timestamp_unix_ms <=
      self.global_settings.control_timing.heartbeat_timeout_ms &&
      !heartbeat.running_deployments.contains(runtime.operation_id)
    })
  })
  let terminations = match self.media {
    Some(media) => media.jobs.snapshot().terminations.unwrap_or([])
    None => []
  }
  let mut model_stopped = true
  for replica in runtime.model_replicas.unwrap_or([]) {
    if delivery_replica_terminated(runtime, replica, terminations) {
      if runtime.reservation_id is Some(id) {
        scheduler.confirm_node_service_stopped(id, replica.assignment_id, now)
      }
      if !replica.stopped {
        runtime = deliveries.observe_model_service(
          runtime.operation_id,
          runtime.generation,
          ModelReplicaObserved({ ..replica, stopped: true, }),
          now,
        )
      }
    } else {
      model_stopped = false
    }
  }
  if reservation is Some(value) &&
    value.services.any(claim => {
      delivery_model_claim(runtime, claim.service_id) &&
      !runtime.model_replicas
      .unwrap_or([])
      .any(replica => replica.assignment_id == claim.service_id)
    }) {
    model_stopped = false
  }
  if stopped && model_stopped {
    ignore(
      deliveries.observe_model_service(
        runtime.operation_id,
        runtime.generation,
        WorkloadsStopped,
        now,
      ),
    )
  }
}

///|
/// A controller restart changes the signing epoch. Republish each service
/// assignment and regain model-specific readiness before bound credentials can
/// route through it again.
async fn ApiService::reconcile_active_model_service(
  self : ApiService,
  service : @delivery.ModelService,
) -> Unit {
  guard self.delivery_store is Some(deliveries) &&
    self.deployment_store is Some(catalog) &&
    catalog.template({
      template_id: service.runtime.intent.template_id,
      version: service.runtime.intent.template_version,
    })
    is Some(template) else {
    return
  }
  let mut runtime = service.runtime
  if !(runtime.stage is (Ready | LoadingModel)) ||
    service.consumer_ids.is_empty() {
    return
  }
  for index in 0..<runtime.node_ids.length() {
    let assignment = self.prepare_delivery_assignment(runtime, template, index)
    let mut replica = delivery_replica_record(runtime, assignment)
    if !runtime.model_replicas.unwrap_or([]).contains(replica) {
      runtime = deliveries.observe_model_service(
        runtime.operation_id,
        runtime.generation,
        ModelReplicaObserved(replica),
        @async.now(),
      )
    }
    if runtime.stage == LoadingModel &&
      !replica.prepared &&
      delivery_metric(
        self,
        runtime,
        assignment.node_id,
        "artifact_preparation_stage",
        0L,
      ) ==
      Some(3.0) {
      replica = { ..replica, prepared: true, }
      runtime = deliveries.observe_model_service(
        runtime.operation_id,
        runtime.generation,
        ModelReplicaObserved(replica),
        @async.now(),
      )
    }
    if runtime.stage == LoadingModel &&
      replica.prepared &&
      !replica.ready &&
      self.delivery_model_ready(runtime, template, assignment) {
      runtime = deliveries.observe_model_service(
        runtime.operation_id,
        runtime.generation,
        ModelReplicaObserved({ ..replica, ready: true, }),
        @async.now(),
      )
    }
  }
  if runtime.stage == LoadingModel &&
    runtime.model_replicas.map_or(false, replicas => {
      replicas.length() == runtime.node_ids.length() &&
      replicas.all(replica => replica.ready && !replica.stopped)
    }) {
    ignore(
      deliveries.observe_model_service(
        runtime.operation_id,
        runtime.generation,
        ModelResponded(
          service_id=runtime.operation_id,
          digest=template.artifact.digest,
        ),
        @async.now(),
      ),
    )
  }
}

///|
/// Read authenticated materializer samples only for the exact deployment/node.
fn delivery_metric(
  service : ApiService,
  operation : @delivery.Operation,
  node_id : String,
  metric : String,
  since : Int64,
) -> Double? {
  guard service.telemetry is Some(telemetry) else { return None }
  let mut newest = since
  let mut result = None
  for sample in telemetry.snapshot().samples {
    if sample.node_id == node_id &&
      sample.deployment_id == operation.operation_id &&
      sample.metric == metric &&
      sample.timestamp_unix_ms >= newest {
      newest = sample.timestamp_unix_ms
      result = Some(sample.value)
    }
  }
  result
}

///|
async fn ApiService::prepare_delivery_assignment(
  self : ApiService,
  operation : @delivery.Operation,
  template : @deployment.ModelServiceTemplate,
  index : Int,
) -> @contracts.DesiredAssignment {
  guard operation.reservation_id is Some(reserved_id) else {
    raise Failure("delivery reservation unavailable")
  }
  {
    self.resource_mutex.acquire()
    defer self.resource_mutex.release()
    self.ensure_reservation_nodes(reserved_id)
  }
  let id = delivery_replica_id(operation, index)
  let existing = self.store.assignment(id)
  if existing is Some(existing) &&
    existing.controller_epoch == self.store.controller_epoch() {
    return existing
  }
  guard self.registry is Some(registry) &&
    self.scheduler is Some(scheduler) &&
    operation.reservation_id is Some(reservation_id) else {
    raise Failure("delivery authority unavailable")
  }
  if existing is Some(previous) {
    let refreshed = {
      ..previous,
      controller_epoch: self.store.controller_epoch(),
      generation: previous.generation + 1L,
      reservation: None,
      signature: "",
    }
    self.publish_planned_assignment(
      refreshed,
      reservation_id~,
      tenant_ref=operation.intent.tenant_id,
    )
    return self.store.assignment(id).unwrap()
  }
  let now = @async.now()
  // Preserve legacy first-replica placement; subsequent replicas use remaining
  // nodes in reservation order. Cache locality only selects the initial head.
  let preferred = @scheduler.cached_reserved_nodes(
    self.store.heartbeats(),
    operation.node_ids,
    template.artifact.digest,
    now,
    self.global_settings.control_timing.heartbeat_timeout_ms,
  )
  let first_node = self.store
    .assignment(delivery_assignment_id(operation))
    .map(value => value.node_id)
    .unwrap_or(preferred.get(0).unwrap_or(operation.node_ids[0]))
  let ordered_nodes = [first_node]
  for node in operation.node_ids {
    if node != first_node {
      ordered_nodes.push(node)
    }
  }
  let context : @deployment.PlanningContext = {
    registry: registry_evidence(
      registry.snapshot(),
      now,
      registry.requires_evaluation(),
    ),
    nodes: self.store
    .heartbeats()
    .filter(heartbeat => ordered_nodes[index] == heartbeat.node_id)
    .map(heartbeat => {
      management_node(
        heartbeat,
        now,
        self.global_settings.control_timing.heartbeat_timeout_ms,
      )
    }),
    available_secret_refs: self.available_secret_refs,
  }
  // Each reserved node runs an independent replica. This is not tensor parallel
  // inference: the template contract does not pin a distributed topology.
  let plan = @deployment.preflight(
    [template],
    {
      version: @contracts.contract_version,
      idempotency_key: operation.operation_id,
      deployment_id: operation.operation_id,
      template: {
        template_id: template.template_id,
        version: template.version,
      },
      replicas: 1,
      data_class: template.data_policy.classification,
      lease_duration_ms: operation.intent.expires_at_ms - now,
      promote_when_ready: false,
      topology_profile: None,
    },
    context,
  )
  if !plan.executable {
    raise Failure("delivery template preflight blocked")
  }
  let planned = @deployment.desired_assignments(
      plan,
      self.store.controller_epoch(),
      operation.model_replicas
      .unwrap_or([])
      .iter()
      .find_first(replica => replica.assignment_id == id)
      .map(value => value.generation + 1L)
      .unwrap_or(1L),
      now,
    )[0]
  let assignment = {
    ..planned,
    assignment_id: id,
    lease_expires_unix_ms: operation.intent.expires_at_ms,
  }
  ignore(
    scheduler.claim_node_service(
      reservation_id,
      operation.intent.tenant_id,
      {
        service_id: id,
        node_id: assignment.node_id,
        memory_mib: assignment.resources.memory_mib,
        gpu_memory_mib: assignment.resources.accelerator_memory_mib,
        concurrency: 1,
      },
      now,
    ),
  )
  errdefer (if self.store.assignment(id) is None {
    scheduler.confirm_node_service_stopped(reservation_id, id, @async.now())
  })
  self.publish_planned_assignment(
    assignment,
    reservation_id~,
    tenant_ref=operation.intent.tenant_id,
  )
  self.store.assignment(id).unwrap()
}

///|
async fn ApiService::delivery_runtime_observed(
  self : ApiService,
  assignment : @contracts.DesiredAssignment,
  now : Int64,
) -> Bool {
  self.store
  .heartbeats()
  .any(heartbeat => {
    heartbeat.node_id == assignment.node_id &&
    heartbeat.state == Active &&
    heartbeat.controller_epoch == assignment.controller_epoch &&
    heartbeat.observed_generation >= assignment.generation &&
    heartbeat.timestamp_unix_ms <= now &&
    now - heartbeat.timestamp_unix_ms <=
    self.global_settings.control_timing.heartbeat_timeout_ms &&
    heartbeat.running_deployments.contains(assignment.deployment_id)
  })
}

///|
/// Loaded-model discovery is readiness, not proof of a generated video. The
/// latter remains a separate real UI acceptance step. A generic HTTP 200 alone
/// cannot satisfy this probe: the provider must list the expected model.
async fn delivery_media_ready(binding : MediaBinding) -> Bool {
  @async.with_timeout(10000, () => {
    let headers : Map[String, String] = { "Accept": "application/json" }
    if binding.bearer is Some(token) {
      headers["Authorization"] = "Bearer \{token}"
    }
    let (health, health_body) = @http.get("\{binding.origin}/health", headers~)
    ignore(health_body)
    if health.code != 200 {
      return false
    }
    let (response, body) = @http.get("\{binding.origin}/v1/models", headers~)
    if response.code != 200 {
      return false
    }
    let raw = body.text()
    if raw.length() > 65536 {
      return false
    }
    match @json.parse(raw) {
      { "data": Array(models), .. } =>
        models.any(model => {
          model is { "id": String(id), .. } &&
          id == binding.profile.provider_model
        })
      _ => false
    }
  })
}

///|
async fn ApiService::delivery_model_ready(
  self : ApiService,
  operation : @delivery.Operation,
  template : @deployment.ModelServiceTemplate,
  assignment : @contracts.DesiredAssignment,
) -> Bool {
  if !self.delivery_runtime_observed(assignment, @async.now()) {
    return false
  }
  if template.capability == VideoGenerate {
    guard self.media is Some(media) else { return false }
    for binding in self.media_all_bindings(media.bindings, media.templates) {
      if binding.deployment_id == operation.operation_id &&
        binding.node_id == assignment.node_id &&
        binding.deployment_generation == assignment.generation {
        return delivery_media_ready(binding)
      }
    }
    return false
  }
  if template.capability != TextGenerate ||
    !self.runtime.uses_direct_node_routing() ||
    self.runtime.artifact_digest() != template.artifact.digest ||
    self.runtime.image_digest() != template.runtime.image_digest {
    return false
  }
  let result = self.runtime.invoke_at(
    {
      version: @contracts.contract_version,
      idempotency_key: "\{assignment.assignment_id}-\{assignment.generation}-readiness",
      workload_id: "\{assignment.assignment_id}-readiness",
      tenant_ref: operation.intent.tenant_id,
      credential_scope: "delivery-readiness",
      capability: TextGenerate,
      model_selector: template.model_selector,
      payload: { "input": "Reply OK." },
      data_policy: template.data_policy,
      deadline_unix_ms: @async.now() + 10000L,
      priority: Background,
      latency_class: Standard,
      resource_ceiling: {
        max_input_units: 128,
        max_output_units: 1,
        max_runtime_ms: 10000L,
        max_accelerator_memory_mib: template.resources.accelerator_memory_mib,
      },
      stream: false,
      output_format: "text",
      trace_token: operation.operation_id,
    },
    assignment.node_id,
  )
  result.artifact_digest == template.artifact.digest
}

///|
pub async fn ApiService::reconcile_deliveries(self : ApiService) -> Unit {
  guard self.delivery_store is Some(deliveries) &&
    self.scheduler is Some(scheduler) else {
    return
  }
  ignore(deliveries.expire_due(@async.now()))
  for service in deliveries.model_services() {
    if service.runtime.stage == Stopping {
      self.reconcile_stopping_model_service(service)
    } else if service.runtime.stage is (Ready | LoadingModel) {
      self.reconcile_active_model_service(service) catch {
        error => if @async.is_cancellation_error(error) { raise error }
        // Preserve the assignment for a later retry. Admission still needs
        // fresh epoch and node evidence and fails closed meanwhile.
      }
    }
  }
  for original in deliveries.operations() {
    let mut operation = original
    let now = @async.now()
    if operation.stage is (Stopped | Expired | Reserving) {
      continue
    }
    let reservation = match operation.reservation_id {
      Some(id) => scheduler.node_reservation(id)
      None => None
    }
    let authorized = match self.workspace_directory {
      None => false
      Some(directory) =>
        match
          directory.snapshot(now).leases
          .iter()
          .find_first(lease => {
            lease.lease_id == operation.intent.lease_id &&
            lease.tenant_ref == operation.intent.tenant_id
          }) {
          None => false
          Some(lease) =>
            try {
              let authority = directory.authorize_subject_for_tenant_lease(
                lease.subject_ref,
                lease.tenant_ref,
                operation.intent.lease_id,
                Developer,
                now,
                grant_id=operation.intent.authorization_ref,
              )
              authority.lease.lease_id == operation.intent.lease_id
            } catch {
              _ => false
            }
        }
    }
    let reservation_active = match reservation {
      Some(value) =>
        self.delivery_reservation_authorized(
          value,
          operation.intent.tenant_id,
          operation.intent.organization_id,
          operation.intent.lease_id,
          operation.intent.authorization_ref,
          now,
        )
      None => false
    }
    if operation.stage != Stopping && (!authorized || !reservation_active) {
      operation = deliveries.stop(
        operation.operation_id,
        operation.generation,
        now,
      )
    }
    if operation.model_service_id is Some(service_id) &&
      deliveries.model_service(service_id) is Some(service) &&
      service.consumer_ids.contains(operation.operation_id) {
      if operation.stage == Stopping && operation.workspace_id is None {
        ignore(
          deliveries.release_model_service(
            operation.operation_id,
            operation.generation,
            now,
          ),
        )
      }
      continue
    }
    if operation.stage == Stopping {
      for
        assignment in self.store
        .assignments()
        .filter(value => value.deployment_id == operation.operation_id) {
        operation = deliveries.observe(
          operation.operation_id,
          operation.generation,
          ModelReplicaObserved(delivery_replica_record(operation, assignment)),
          now,
        )
      }
      self.remove_deployment_assignments(operation.operation_id)
      let heartbeats = self.store.heartbeats()
      let stopped = operation.node_ids.all(node_id => {
        heartbeats.any(heartbeat => {
          heartbeat.node_id == node_id &&
          heartbeat.timestamp_unix_ms >
          operation.stop_requested_at_ms.unwrap_or(operation.updated_at_ms) &&
          heartbeat.timestamp_unix_ms <= now &&
          now - heartbeat.timestamp_unix_ms <=
          self.global_settings.control_timing.heartbeat_timeout_ms &&
          !heartbeat.running_deployments.contains(operation.operation_id)
        })
      })
      let workspace_claimed = reservation.map_or(false, value => {
        value.services.any(service => {
          service.service_id.has_prefix(operation.operation_id) &&
          !delivery_model_claim(operation, service.service_id)
        })
      })
      // A legacy snapshot may have removed desired state before restart. Recover
      // its original single replica from the retained scheduler claim.
      if operation.model_replicas is None && reservation is Some(value) {
        for claim in value.services {
          if claim.service_id == delivery_assignment_id(operation) &&
            operation.model_assignment_generation is Some(generation) {
            operation = deliveries.observe(
              operation.operation_id,
              operation.generation,
              ModelReplicaObserved({
                assignment_id: claim.service_id,
                node_id: claim.node_id,
                generation,
                prepared: false,
                ready: false,
                stopped: false,
              }),
              now,
            )
          }
        }
      }
      let mut model_stopped = true
      let terminations = match self.media {
        Some(media) => media.jobs.snapshot().terminations.unwrap_or([])
        None => []
      }
      for replica in operation.model_replicas.unwrap_or([]) {
        let confirmed = delivery_replica_terminated(
          operation, replica, terminations,
        )
        if confirmed {
          if operation.reservation_id is Some(id) {
            scheduler.confirm_node_service_stopped(
              id,
              replica.assignment_id,
              now,
            )
          }
          if !replica.stopped {
            operation = deliveries.observe(
              operation.operation_id,
              operation.generation,
              ModelReplicaObserved({ ..replica, stopped: true, }),
              now,
            )
          }
        } else {
          model_stopped = false
        }
      }
      // Unknown retained claims are never silently treated as stopped.
      if reservation is Some(value) {
        if value.services.any(claim => {
            delivery_model_claim(operation, claim.service_id) &&
            !operation.model_replicas
            .unwrap_or([])
            .any(replica => replica.assignment_id == claim.service_id)
          }) {
          model_stopped = false
        }
      }
      if stopped &&
        model_stopped &&
        operation.workspace_id is None &&
        !workspace_claimed {
        ignore(
          deliveries.observe(
            operation.operation_id,
            operation.generation,
            WorkloadsStopped,
            now,
          ),
        )
      }
      continue
    }
    if operation.stage is (Ready | StartingWorkspace) &&
      operation.intent.model_digest is Some(_) &&
      operation.model_replicas.map_or(false, replicas => {
        replicas.length() == operation.node_ids.length() &&
        replicas.all(replica => replica.ready && !replica.stopped)
      }) {
      ignore(
        deliveries.bind_model_service(
          operation.operation_id,
          operation.generation,
          now,
        ),
      )
      continue
    }
    if operation.stage is (Failed | Ready | StartingWorkspace) {
      continue
    }
    guard self.deployment_store is Some(catalog) &&
      catalog.template({
        template_id: operation.intent.template_id,
        version: operation.intent.template_version,
      })
      is Some(template) else {
      continue
    }
    try {
      if operation.stage == PreparingModel &&
        self.ready_reusable_model_service(operation, template)
        is Some(service_id) {
        ignore(
          deliveries.bind_model_service(
            operation.operation_id,
            operation.generation,
            now,
            reuse_service_id=service_id,
          ),
        )
        continue
      }
      let assignments : Array[@contracts.DesiredAssignment] = []
      for index in 0..<operation.node_ids.length() {
        let assignment = self.prepare_delivery_assignment(
          operation, template, index,
        )
        let replica = delivery_replica_record(operation, assignment)
        if !operation.model_replicas.unwrap_or([]).contains(replica) {
          operation = deliveries.observe(
            operation.operation_id,
            operation.generation,
            ModelReplicaObserved(replica),
            now,
          )
        }
        assignments.push(assignment)
      }
      if operation.stage == PreparingModel {
        let mut all_prepared = true
        let mut all_cached = true
        let mut present = 0L
        let mut total = 0L
        let mut total_known = true
        for assignment in assignments {
          let stage = delivery_metric(
            self,
            operation,
            assignment.node_id,
            "artifact_preparation_stage",
            0L,
          )
          if stage == Some(4.0) {
            operation = deliveries.observe(
              operation.operation_id,
              operation.generation,
              Failure(code="ModelPreparationFailed"),
              now,
            )
            break
          }
          if stage == Some(3.0) {
            let replica = delivery_replica_record(operation, assignment)
            if !replica.prepared {
              operation = deliveries.observe(
                operation.operation_id,
                operation.generation,
                ModelReplicaObserved({ ..replica, prepared: true, }),
                now,
              )
            }
            all_cached = all_cached &&
              delivery_metric(
                self,
                operation,
                assignment.node_id,
                "artifact_cache_hit",
                0L,
              ) ==
              Some(1.0)
          } else {
            all_prepared = false
            all_cached = false
          }
          present += delivery_metric(
              self,
              operation,
              assignment.node_id,
              "artifact_bytes_present",
              0L,
            )
            .unwrap_or(0.0)
            .to_int64()
          match
            delivery_metric(
              self,
              operation,
              assignment.node_id,
              "artifact_bytes_total",
              0L,
            ) {
            Some(value) => total += value.to_int64()
            None => total_known = false
          }
        }
        if operation.stage == Failed {
          continue
        }
        if all_prepared {
          operation = deliveries.observe(
            operation.operation_id,
            operation.generation,
            ModelPrepared(digest=template.artifact.digest, cache_hit=all_cached),
            now,
          )
        } else {
          let total_bytes = if total_known { Some(total) } else { None }
          if operation.transferred_bytes != present ||
            operation.total_bytes != total_bytes {
            operation = deliveries.observe(
              operation.operation_id,
              operation.generation,
              TransferProgress(transferred_bytes=present, total_bytes~),
              now,
            )
          }
          continue
        }
      }
      if operation.stage == LoadingModel {
        for assignment in assignments {
          let mut replica = delivery_replica_record(operation, assignment)
          if !replica.prepared &&
            delivery_metric(
              self,
              operation,
              assignment.node_id,
              "artifact_preparation_stage",
              0L,
            ) ==
            Some(3.0) {
            replica = { ..replica, prepared: true, }
            operation = deliveries.observe(
              operation.operation_id,
              operation.generation,
              ModelReplicaObserved(replica),
              @async.now(),
            )
          }
          if replica.prepared &&
            !replica.ready &&
            self.delivery_model_ready(operation, template, assignment) {
            operation = deliveries.observe(
              operation.operation_id,
              operation.generation,
              ModelReplicaObserved({ ..replica, ready: true, }),
              @async.now(),
            )
          }
        }
      }
      if operation.stage == LoadingModel &&
        operation.model_replicas.unwrap_or([]).all(replica => replica.ready) {
        operation = deliveries.observe(
          operation.operation_id,
          operation.generation,
          ModelResponded(
            service_id=operation.operation_id,
            digest=template.artifact.digest,
          ),
          @async.now(),
        )
        ignore(
          deliveries.bind_model_service(
            operation.operation_id,
            operation.generation,
            @async.now(),
          ),
        )
      } else if operation.stage == LoadingModel &&
        now - operation.updated_at_ms > template.rollout.readiness_timeout_ms {
        ignore(
          deliveries.observe(
            operation.operation_id,
            operation.generation,
            Failure(code="ModelReadinessTimeout"),
            now,
          ),
        )
      }
    } catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        // Preserve stage while a runtime is loading; template publication errors
        // are actionable and retryable from the same resource reservation.
        if operation.stage == PreparingModel {
          ignore(
            deliveries.observe(
              operation.operation_id,
              operation.generation,
              Failure(code="ModelDeploymentBlocked"),
              @async.now(),
            ),
          )
        } else if operation.stage == LoadingModel &&
          now - operation.updated_at_ms > template.rollout.readiness_timeout_ms {
          ignore(
            deliveries.observe(
              operation.operation_id,
              operation.generation,
              Failure(code="ModelReadinessTimeout"),
              @async.now(),
            ),
          )
        }
      }
    }
  }
}
