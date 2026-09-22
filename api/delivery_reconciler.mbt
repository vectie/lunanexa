///|
fn delivery_assignment_id(operation : @delivery.Operation) -> String {
  "\{operation.operation_id}-model"
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
  for operation in deliveries.operations() {
    if operation.stage is (Stopped | Expired | Stopping | Failed) {
      continue
    }
    guard operation.reservation_id is Some(id) &&
      scheduler.node_reservation(id) is Some(reservation) &&
      reservation.state == Reserved &&
      reservation.request.tenant_ref == operation.intent.tenant_id &&
      reservation.request.expires_unix_ms > now &&
      self.store.assignment(delivery_assignment_id(operation))
      is Some(assignment) &&
      self.delivery_runtime_observed(assignment, now) else {
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
) -> @contracts.DesiredAssignment {
  guard operation.reservation_id is Some(reserved_id) else {
    raise Failure("delivery reservation unavailable")
  }
  {
    self.resource_mutex.acquire()
    defer self.resource_mutex.release()
    self.ensure_reservation_nodes(reserved_id)
  }
  let id = delivery_assignment_id(operation)
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
  let context : @deployment.PlanningContext = {
    registry: registry_evidence(
      registry.snapshot(),
      now,
      registry.requires_evaluation(),
    ),
    nodes: self.store
    .heartbeats()
    .filter(heartbeat => operation.node_ids.contains(heartbeat.node_id))
    .map(heartbeat => {
      management_node(
        heartbeat,
        now,
        self.global_settings.control_timing.heartbeat_timeout_ms,
      )
    }),
    available_secret_refs: self.available_secret_refs,
  }
  // The order may hold several nodes. This template starts one model replica
  // within that set; distributed templates require their topology-specific plan.
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
      1L,
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
      idempotency_key: "\{operation.operation_id}-readiness",
      workload_id: "\{operation.operation_id}-readiness",
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
              let authority = directory.authorize_subject_for_tenant(
                lease.subject_ref,
                lease.tenant_ref,
                Developer,
                now,
              )
              authority.lease.lease_id == operation.intent.lease_id
            } catch {
              _ => false
            }
        }
    }
    if operation.stage != Stopping &&
      (
        !authorized ||
        !reservation.map_or(false, value => {
          value.state == Reserved &&
          value.request.tenant_ref == operation.intent.tenant_id &&
          value.request.organization_id == operation.intent.organization_id &&
          value.request.lease_id == operation.intent.lease_id &&
          value.request.expires_unix_ms > now
        })
      ) {
      operation = deliveries.stop(
        operation.operation_id,
        operation.generation,
        now,
      )
    }
    if operation.stage == Stopping {
      if self.store.assignment(delivery_assignment_id(operation))
        is Some(assignment) &&
        operation.model_assignment_generation != Some(assignment.generation) {
        operation = deliveries.observe(
          operation.operation_id,
          operation.generation,
          ModelAssignmentPublished(generation=assignment.generation),
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
          service.service_id != delivery_assignment_id(operation)
        })
      })
      let model_claimed = reservation.map_or(false, value => {
        value.services.any(service => {
          service.service_id == delivery_assignment_id(operation)
        })
      })
      let model_stopped = if !model_claimed {
        true
      } else {
        match self.media {
          None => false
          Some(media) =>
            media.jobs.snapshot().terminations
            .unwrap_or([])
            .any(record => {
              record.evidence.assignment_id == delivery_assignment_id(operation) &&
              record.evidence.deployment_id == operation.operation_id &&
              operation.model_assignment_generation ==
              Some(record.evidence.generation) &&
              record.evidence.observed_unix_ms >=
              operation.stop_requested_at_ms.unwrap_or(operation.updated_at_ms)
            })
        }
      }
      if stopped &&
        model_stopped &&
        operation.workspace_id is None &&
        !workspace_claimed {
        if operation.reservation_id is Some(id) {
          scheduler.confirm_node_service_stopped(
            id,
            delivery_assignment_id(operation),
            now,
          )
        }
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
      let assignment = self.prepare_delivery_assignment(operation, template)
      if operation.model_assignment_generation != Some(assignment.generation) {
        operation = deliveries.observe(
          operation.operation_id,
          operation.generation,
          ModelAssignmentPublished(generation=assignment.generation),
          now,
        )
      }
      if operation.stage == PreparingModel {
        let stage = delivery_metric(
          self,
          operation,
          assignment.node_id,
          "artifact_preparation_stage",
          0L,
        )
        if delivery_metric(
            self,
            operation,
            assignment.node_id,
            "artifact_preparation_stage",
            operation.updated_at_ms,
          ) ==
          Some(4.0) {
          ignore(
            deliveries.observe(
              operation.operation_id,
              operation.generation,
              Failure(code="ModelPreparationFailed"),
              now,
            ),
          )
          continue
        }
        if stage == Some(3.0) {
          operation = deliveries.observe(
            operation.operation_id,
            operation.generation,
            ModelPrepared(
              digest=assignment.artifact.digest,
              cache_hit=delivery_metric(
                  self,
                  operation,
                  assignment.node_id,
                  "artifact_cache_hit",
                  0L,
                ) ==
                Some(1.0),
            ),
            now,
          )
        } else {
          let present = delivery_metric(
              self,
              operation,
              assignment.node_id,
              "artifact_bytes_present",
              0L,
            )
            .unwrap_or(0.0)
            .to_int64()
          let total = delivery_metric(
            self,
            operation,
            assignment.node_id,
            "artifact_bytes_total",
            0L,
          ).map(value => value.to_int64())
          if operation.transferred_bytes != present ||
            operation.total_bytes != total {
            ignore(
              deliveries.observe(
                operation.operation_id,
                operation.generation,
                TransferProgress(transferred_bytes=present, total_bytes=total),
                now,
              ),
            )
          }
          continue
        }
      }
      if operation.stage == LoadingModel &&
        self.delivery_model_ready(operation, template, assignment) {
        ignore(
          deliveries.observe(
            operation.operation_id,
            operation.generation,
            ModelResponded(
              service_id=operation.operation_id,
              digest=assignment.artifact.digest,
            ),
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
