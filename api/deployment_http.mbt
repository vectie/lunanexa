///|
fn deployment_management_path(path : String) -> Bool {
  path == "/v1/catalog/templates" ||
  path == "/v1/deployment-plans" ||
  path == "/v1/service-deployments" ||
  path.has_prefix("/v1/service-deployments/") ||
  path.has_prefix("/v1/operations/")
}

///|
fn decode_template(body : String) -> @deployment.ModelServiceTemplate? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_deployment_intent(body : String) -> @deployment.ModelServiceIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn accepted_license(
  snapshot : @registry.RegistrySnapshot,
  model : @contracts.ModelRecord,
  now_unix_ms : Int64,
) -> Bool {
  snapshot.licenses.any(license => {
    license.license_id == model.license_id &&
    license.model_id == model.model_id &&
    license.status == Accepted &&
    (
      license.expires_unix_ms is None ||
      (license.expires_unix_ms is Some(expiry) && expiry > now_unix_ms)
    )
  })
}

///|
fn verified_digest(
  snapshot : @registry.RegistrySnapshot,
  digest : String,
) -> Bool {
  snapshot.verifications.any(verification => {
    verification.digest == digest &&
    verification.signature_verified &&
    verification.provenance_verified
  })
}

///|
fn passed_evaluation(
  snapshot : @registry.RegistrySnapshot,
  model : @contracts.ModelRecord,
) -> Bool {
  snapshot.evaluations.any(evaluation => {
    evaluation.model_id == model.model_id &&
    evaluation.model_version == model.version &&
    evaluation.passed
  })
}

///|
fn registry_evidence(
  snapshot : @registry.RegistrySnapshot,
  now_unix_ms : Int64,
  require_evaluation : Bool,
) -> Array[@deployment.RegistryEvidence] {
  let evidence : Array[@deployment.RegistryEvidence] = []
  for model in snapshot.models {
    for alias_record in snapshot.aliases {
      if alias_record.model_id == model.model_id &&
        alias_record.version == model.version {
        for runtime in snapshot.runtimes {
          if runtime.architectures.any(architecture => {
              model.compatible_architectures.any(value => value == architecture)
            }) &&
            runtime.capabilities.length() > 0 {
            evidence.push({
              model_id: model.model_id,
              model_version: model.version,
              model_state: model.state,
              artifact_digest: model.artifact.digest,
              runtime_name: runtime.name,
              runtime_version: runtime.version,
              runtime_image_digest: runtime.image_digest,
              model_selector: alias_record.name,
              license_accepted: accepted_license(snapshot, model, now_unix_ms),
              artifact_verified: verified_digest(
                snapshot,
                model.artifact.digest,
              ),
              runtime_verified: verified_digest(snapshot, runtime.image_digest),
              // This field describes whether the configured gate is satisfied,
              // not whether a benchmark ran. Evaluation is optional by default;
              // real evaluation status and receipt IDs remain separate evidence.
              evaluation_passed: !require_evaluation ||
              passed_evaluation(snapshot, model),
              alias_points_to_model: true,
            })
          }
        }
      }
    }
  }
  evidence
}

///|
fn management_node(
  heartbeat : @contracts.NodeHeartbeat,
  now_unix_ms : Int64,
  heartbeat_timeout_ms : Int64,
  observed_available_memory_mib? : Int? = None,
) -> @deployment.ManagementNode {
  let healthy = heartbeat.inventory.accelerators.filter(value => value.healthy)
  let declared_memory_free_mib = healthy.fold(init=0, (total, accelerator) => {
    total + accelerator.memory_free_mib
  })
  let memory_free_mib = if heartbeat.inventory.labels.get("lunanexa.gpu.model") ==
    Some("NVIDIA GB10") {
    observed_available_memory_mib.map_or(0, available => {
      declared_memory_free_mib.min(available)
    })
  } else {
    declared_memory_free_mib
  }
  {
    node_id: heartbeat.node_id,
    state: if now_unix_ms - heartbeat.timestamp_unix_ms > heartbeat_timeout_ms {
      Unreachable
    } else {
      heartbeat.state
    },
    architecture: healthy
    .get(0)
    .map(accelerator => accelerator.architecture)
    .unwrap_or(""),
    memory_free_mib,
    runtime_names: heartbeat.inventory.runtime_names,
    device_ids: [
      for accelerator in healthy => accelerator.device_id
    ],
    allowed_data_classes: data_classes(heartbeat.inventory.labels),
    cx7_peer: label_values(
      heartbeat.inventory.labels,
      @contracts.cx7_peer_label,
    )
    .get(0)
    .unwrap_or(""),
    cx7_address: label_values(
      heartbeat.inventory.labels,
      @contracts.cx7_address_label,
    )
    .get(0)
    .unwrap_or(""),
  }
}

///|
fn observed_available_memory_mib(
  samples : Array[@contracts.TelemetrySample],
  node_id : String,
  now_unix_ms : Int64,
  maximum_age_ms : Int64,
) -> Int? {
  let mut latest : @contracts.TelemetrySample? = None
  for sample in samples {
    if sample.node_id == node_id &&
      sample.deployment_id == "" &&
      sample.metric == "host_memory_available_mib" &&
      sample.timestamp_unix_ms <= now_unix_ms &&
      now_unix_ms - sample.timestamp_unix_ms <= maximum_age_ms &&
      sample.value >= 0.0 &&
      sample.value <= 1_048_576.0 &&
      latest.map_or(true, previous => {
        sample.timestamp_unix_ms > previous.timestamp_unix_ms
      }) {
      latest = Some(sample)
    }
  }
  latest.map(sample => sample.value.to_int())
}

///|
async fn ApiService::deployment_planning_context(
  self : ApiService,
) -> @deployment.PlanningContext {
  guard self.registry is Some(registry) else {
    raise @deployment.DeploymentError::InvalidState("registry unavailable")
  }
  let now = @async.now()
  let snapshot = registry.snapshot()
  let telemetry_samples = self.telemetry.map_or([], telemetry => {
    telemetry.snapshot().samples
  })
  {
    registry: registry_evidence(snapshot, now, registry.requires_evaluation()),
    nodes: [
      for heartbeat in self.store.heartbeats() => {
        let node = management_node(
          heartbeat,
          now,
          self.global_settings.control_timing.heartbeat_timeout_ms,
          observed_available_memory_mib=observed_available_memory_mib(
            telemetry_samples,
            heartbeat.node_id,
            now,
            self.global_settings.control_timing.heartbeat_timeout_ms,
          ),
        )
        if self.scheduler is Some(scheduler) &&
          scheduler.node_is_reserved(heartbeat.node_id) {
          { ..node, state: Cordoned, }
        } else {
          match self.exclusive_lease_store {
            Some(leases) if leases.node_blocks_managed_placement(
                heartbeat.node_id,
              ) => { ..node, state: Cordoned, }
            _ => node
          }
        }
      }
    ],
    available_secret_refs: self.available_secret_refs,
  }
}

///|
async fn ApiService::deployment_plan(
  self : ApiService,
  intent : @deployment.ModelServiceIntent,
) -> @deployment.DeploymentPlan {
  guard self.deployment_store is Some(deployments) else {
    raise @deployment.DeploymentError::InvalidState(
      "deployment store unavailable",
    )
  }
  @deployment.preflight(
    deployments.templates(),
    intent,
    self.deployment_planning_context(),
  )
}

///|
async fn ApiService::publish_planned_assignment(
  self : ApiService,
  unsigned : @contracts.DesiredAssignment,
  reservation_id? : String,
  tenant_ref? : String,
) -> Unit {
  self.resource_mutex.acquire()
  defer self.resource_mutex.release()
  if self.assignment_signing_secret == "" {
    raise @deployment.DeploymentError::InvalidState("signer unavailable")
  }
  if unsigned.reservation is Some(_) {
    raise @deployment.DeploymentError::InvalidState(
      "reservation ownership is controller-derived",
    )
  }
  guard self.registry is Some(registry) else {
    raise @deployment.DeploymentError::InvalidState("registry unavailable")
  }
  let now = @async.now()
  if self.scheduler is Some(scheduler) &&
    scheduler.node_is_reserved(unsigned.node_id) {
    guard reservation_id is Some(id) &&
      tenant_ref is Some(tenant) &&
      scheduler.node_reservation(id) is Some(reservation) &&
      reservation.state == Reserved &&
      reservation.request.tenant_ref == tenant &&
      reservation.request.node_ids.contains(unsigned.node_id) &&
      reservation.request.starts_unix_ms <= now &&
      reservation.request.expires_unix_ms >= unsigned.lease_expires_unix_ms &&
      reservation.services.any(service => {
        service.node_id == unsigned.node_id &&
        service.service_id == unsigned.assignment_id
      }) else {
      raise @deployment.DeploymentError::InvalidState(
        "node is reserved for another resource authority",
      )
    }
  } else if reservation_id is Some(_) {
    raise @deployment.DeploymentError::InvalidState(
      "node reservation is unavailable",
    )
  }
  if !valid_assignment_shape(unsigned, now) ||
    unsigned.signature != "" ||
    unsigned.controller_epoch != self.store.controller_epoch() {
    raise @deployment.DeploymentError::InvalidState(unsigned.assignment_id)
  }
  if !registry.deployment_allowed(unsigned.artifact.digest, unsigned.runtime) {
    raise @deployment.DeploymentError::InvalidState(
      "registry rejected deployment",
    )
  }
  if self.exclusive_lease_store is Some(leases) &&
    leases.node_blocks_managed_placement(unsigned.node_id) {
    raise @deployment.DeploymentError::InvalidState(
      "node is reserved for an exclusive lease",
    )
  }
  let unsigned = match (reservation_id, tenant_ref) {
    (Some(id), Some(tenant)) => {
      self.ensure_reservation_nodes(id)
      {
        ..unsigned,
        reservation: Some({ reservation_id: id, tenant_ref: tenant, }),
      }
    }
    _ => unsigned
  }
  let signed = {
    ..unsigned,
    signature: @node.assignment_signature(
      unsigned,
      self.assignment_signing_secret,
    ),
  }
  match self.store.assignment(signed.assignment_id) {
    Some(current) if current.generation > signed.generation =>
      raise @deployment.DeploymentError::InvalidState("stale generation")
    Some(current) if current.generation == signed.generation => {
      if current != signed {
        raise @deployment.DeploymentError::InvalidState(
          "assignment generation conflict",
        )
      }
      return
    }
    _ => ()
  }
  let receipt = "assignment:\{signed.assignment_id}:\{signed.generation}"
  self.with_audit_lock(() => {
    let audit = self.next_audit(
      "management-plane",
      "assignment.publish",
      signed.assignment_id,
      "unknown",
      "desired",
      "accepted",
      receipt,
      now,
    )
    self.store.commit_assignment(signed, audit)
  })
}

///|
async fn ApiService::remove_deployment_assignments(
  self : ApiService,
  deployment_id : String,
  keep? : Array[String] = [],
) -> Unit {
  for assignment in self.store.assignments() {
    if assignment.deployment_id == deployment_id &&
      !keep.any(value => value == assignment.assignment_id) {
      let receipt = "assignment-stop:\{assignment.assignment_id}:\{@async.now()}"
      self.with_audit_lock(() => {
        let audit = self.next_audit(
          "management-plane",
          "assignment.stop",
          assignment.assignment_id,
          "desired",
          "stopped",
          "accepted",
          receipt,
          @async.now(),
        )
        ignore(
          self.store.commit_assignment_removal(assignment.assignment_id, audit),
        )
      })
    }
  }
}

///|
async fn ApiService::reconcile_deployment_operation(
  self : ApiService,
  operation : @deployment.DeploymentOperation,
) -> @deployment.DeploymentOperation {
  guard self.deployment_store is Some(deployments) else { return operation }
  let now = @async.now()
  let mut current = operation
  let readiness_lost = "runtime readiness lost or assignment lease expired"
  if current.state == Ready ||
    (current.state == Degraded && current.message == readiness_lost) {
    let ready = @controller.deployment_operation_ready(
      current,
      self.store.assignments(),
      self.store.heartbeats(),
      now,
    )
    if current.state == Ready && !ready {
      current = deployments.transition(
        current.operation_id,
        Degraded,
        readiness_lost,
        now,
      )
    } else if current.state == Degraded && ready {
      current = deployments.transition(
        current.operation_id,
        Ready,
        "all planned replicas report ready",
        now,
      )
    }
    return current
  }
  if current.state == Planned {
    let assignments = @controller.deployment_assignments(
      current,
      self.store.controller_epoch(),
      now,
    )
    try {
      for assignment in assignments {
        self.publish_planned_assignment(assignment)
      }
      self.remove_deployment_assignments(
        current.deployment_id,
        keep=current.assignment_ids,
      )
      current = deployments.transition(
        current.operation_id,
        Reconciling,
        "signed assignments published; waiting for runtime readiness",
        now,
      )
    } catch {
      _ => {
        self.remove_deployment_assignments(current.deployment_id)
        current = deployments.transition(
          current.operation_id,
          Failed,
          "assignment reconciliation failed",
          @async.now(),
        )
      }
    }
  }
  if current.state == Reconciling &&
    @controller.deployment_operation_ready(
      current,
      self.store.assignments(),
      self.store.heartbeats(),
      @async.now(),
    ) {
    current = deployments.transition(
      current.operation_id,
      Ready,
      "all planned replicas report ready",
      @async.now(),
    )
    if current.plan.intent.promote_when_ready &&
      current.plan.template is Some(template) &&
      template.rollout.automatic_promotion &&
      self.registry is Some(registry) {
      try
        registry.promote(
          template.model_selector,
          template.model_id,
          template.model_version,
          Stable,
          "management-plane",
          @async.now(),
        )
      catch {
        _ =>
          current = deployments.transition(
            current.operation_id,
            Degraded,
            "runtime is ready but automatic promotion failed",
            @async.now(),
          )
      } noraise {
        receipt =>
          self.operator_audit(
            "service-deployment.promote",
            current.deployment_id,
            receipt.receipt_id,
          )
      }
    }
  } else if current.state == Reconciling &&
    current.plan.template is Some(template) &&
    @async.now() >
    current.created_unix_ms + template.rollout.readiness_timeout_ms {
    if template.rollout.automatic_rollback {
      current = deployments.transition(
        current.operation_id,
        RollingBack,
        "readiness timeout triggered automatic rollback",
        @async.now(),
      )
      self.remove_deployment_assignments(current.deployment_id)
      current = deployments.transition(
        current.operation_id,
        RolledBack,
        "assignments removed after readiness timeout",
        @async.now(),
      )
    } else {
      current = deployments.transition(
        current.operation_id,
        Failed,
        "readiness timeout expired",
        @async.now(),
      )
    }
  }
  current
}

///|
async fn ApiService::refresh_deployment_operations(self : ApiService) -> Unit {
  guard self.deployment_store is Some(deployments) else { return }
  for operation in deployments.operations() {
    if operation.state == Planned ||
      operation.state == Reconciling ||
      operation.state == Ready ||
      operation.state == Degraded {
      ignore(self.reconcile_deployment_operation(operation))
    }
  }
}

///|
async fn ApiService::create_service_deployment(
  self : ApiService,
  intent : @deployment.ModelServiceIntent,
) -> HttpReply {
  guard self.deployment_store is Some(deployments) else {
    return api_error(
      503, "DeploymentUnavailable", "durable deployment management is unavailable",
      true,
    )
  }
  let plan = try self.deployment_plan(intent) catch {
    _ =>
      return api_error(
        409, "DeploymentRejected", "deployment preflight could not be completed",
        false,
      )
  } noraise {
    value => value
  }
  let operation = try deployments.create_operation(plan, @async.now()) catch {
    @deployment.DeploymentError::IdempotencyConflict(_) =>
      return api_error(
        409, "IdempotencyConflict", "idempotency key was already used for a different deployment intent",
        false,
      )
    _ =>
      return api_error(
        409, "DeploymentRejected", "deployment operation was rejected", false,
      )
  } noraise {
    value => value
  }
  let result = self.reconcile_deployment_operation(operation)
  self.operator_audit(
    "service-deployment.create",
    result.deployment_id,
    result.audit_receipt,
  )
  json_reply(202, result.to_json())
}

///|
async fn ApiService::stop_service_deployment(
  self : ApiService,
  deployment_id : String,
  deleted : Bool,
) -> HttpReply {
  guard self.deployment_store is Some(deployments) &&
    deployments.deployment(deployment_id) is Some(operation) else {
    return api_error(404, "NotFound", "service deployment was not found", false)
  }
  if operation.state == Deleted || (operation.state == RolledBack && !deleted) {
    return json_reply(200, operation.to_json())
  }
  if operation.state == RolledBack && deleted {
    let deleted_operation = deployments.transition(
      operation.operation_id,
      Deleted,
      "service deployment deleted",
      @async.now(),
    )
    self.operator_audit(
      "service-deployment.delete",
      deployment_id,
      deleted_operation.audit_receipt,
    )
    return json_reply(200, deleted_operation.to_json())
  }
  let rolling = try
    deployments.transition(
      operation.operation_id,
      RollingBack,
      if deleted {
        "deletion requested"
      } else {
        "rollback requested"
      },
      @async.now(),
    )
  catch {
    _ =>
      return api_error(
        409, "DeploymentRejected", "deployment cannot be stopped from its current state",
        false,
      )
  } noraise {
    value => value
  }
  self.remove_deployment_assignments(deployment_id)
  let stopped = deployments.transition(
    rolling.operation_id,
    if deleted {
      Deleted
    } else {
      RolledBack
    },
    if deleted {
      "service deployment deleted"
    } else {
      "service deployment rolled back"
    },
    @async.now(),
  )
  self.operator_audit(
    if deleted {
      "service-deployment.delete"
    } else {
      "service-deployment.rollback"
    },
    deployment_id,
    stopped.audit_receipt,
  )
  json_reply(200, stopped.to_json())
}

///|
async fn ApiService::promote_service_deployment(
  self : ApiService,
  deployment_id : String,
) -> HttpReply {
  guard self.deployment_store is Some(deployments) &&
    deployments.deployment(deployment_id) is Some(stored) else {
    return api_error(
      409, "DeploymentRejected", "only a ready service deployment can be promoted",
      false,
    )
  }
  let operation = self.reconcile_deployment_operation(stored)
  guard operation.state == Ready && operation.plan.template is Some(template) else {
    return api_error(
      409, "DeploymentRejected", "only a ready service deployment can be promoted",
      false,
    )
  }
  guard self.registry is Some(registry) else {
    return api_error(
      503, "RegistryUnavailable", "registry is unavailable", true,
    )
  }
  let snapshot = registry.snapshot()
  if snapshot.receipts.any(receipt => {
      receipt.alias_name == template.model_selector &&
      receipt.to_version == template.model_version &&
      receipt.stage == Stable
    }) {
    return json_reply(200, operation.to_json())
  }
  let receipt = try
    registry.promote(
      template.model_selector,
      template.model_id,
      template.model_version,
      Stable,
      "management-plane",
      @async.now(),
    )
  catch {
    _ =>
      return api_error(
        409, "RegistryRejected", "model promotion was rejected", false,
      )
  } noraise {
    value => value
  }
  self.operator_audit(
    "service-deployment.promote",
    deployment_id,
    receipt.receipt_id,
  )
  json_reply(200, { "operation": operation, "promotion": receipt })
}

///|
async fn ApiService::handle_deployment_management(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if !self.operator_authorized(headers) {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  guard self.deployment_store is Some(deployments) else {
    return api_error(
      503, "DeploymentUnavailable", "durable deployment management is unavailable",
      true,
    )
  }
  match (verb, path) {
    (Get, "/v1/catalog/templates") =>
      json_reply(200, deployments.templates().to_json())
    (Post, "/v1/catalog/templates") => {
      guard decode_template(body) is Some(template) else {
        return api_error(
          400, "InvalidRequest", "invalid catalog template", false,
        )
      }
      let accepted = try deployments.register_template(template) catch {
        _ =>
          return api_error(
            409, "TemplateRejected", "catalog template registration was rejected",
            false,
          )
      } noraise {
        value => value
      }
      self.operator_audit(
        "catalog-template.register",
        accepted.template_id,
        accepted.approval_receipt,
      )
      json_reply(201, accepted.to_json())
    }
    (Post, "/v1/deployment-plans") => {
      guard decode_deployment_intent(body) is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid deployment intent", false,
        )
      }
      let plan = try self.deployment_plan(intent) catch {
        _ =>
          return api_error(
            409, "DeploymentRejected", "deployment preflight could not be completed",
            false,
          )
      } noraise {
        value => value
      }
      json_reply(200, plan.to_json())
    }
    (Get, "/v1/service-deployments") => {
      self.refresh_deployment_operations()
      json_reply(200, deployments.operations().to_json())
    }
    (Post, "/v1/service-deployments") => {
      guard decode_deployment_intent(body) is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid deployment intent", false,
        )
      }
      self.create_service_deployment(intent)
    }
    (Get, _) if path.has_prefix("/v1/operations/") => {
      let operation_id = path["/v1/operations/".length():].to_owned()
      guard deployments.operation(operation_id) is Some(operation) else {
        return api_error(
          404, "NotFound", "deployment operation was not found", false,
        )
      }
      let refreshed = self.reconcile_deployment_operation(operation)
      json_reply(200, refreshed.to_json())
    }
    (Post, _) if path.has_prefix("/v1/service-deployments/") &&
      path.has_suffix("/promote") => {
      let prefix = "/v1/service-deployments/".length()
      let suffix = "/promote".length()
      self.promote_service_deployment(
        path[prefix:path.length() - suffix].to_owned(),
      )
    }
    (Post, _) if path.has_prefix("/v1/service-deployments/") &&
      path.has_suffix("/rollback") => {
      let prefix = "/v1/service-deployments/".length()
      let suffix = "/rollback".length()
      self.stop_service_deployment(
        path[prefix:path.length() - suffix].to_owned(),
        false,
      )
    }
    (Post, _) if path.has_prefix("/v1/service-deployments/") &&
      path.has_suffix("/delete") => {
      let prefix = "/v1/service-deployments/".length()
      let suffix = "/delete".length()
      self.stop_service_deployment(
        path[prefix:path.length() - suffix].to_owned(),
        true,
      )
    }
    (Delete, _) if path.has_prefix("/v1/service-deployments/") =>
      self.stop_service_deployment(
        path["/v1/service-deployments/".length():].to_owned(),
        true,
      )
    (Get, _) if path.has_prefix("/v1/service-deployments/") => {
      let deployment_id = path["/v1/service-deployments/".length():].to_owned()
      guard deployments.deployment(deployment_id) is Some(operation) else {
        return api_error(
          404, "NotFound", "service deployment was not found", false,
        )
      }
      let refreshed = self.reconcile_deployment_operation(operation)
      json_reply(200, refreshed.to_json())
    }
    _ =>
      api_error(404, "NotFound", "management-plane route was not found", false)
  }
}
