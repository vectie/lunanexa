///|
/// Reuse cannot widen a tenant, project, grant, reservation or pinned template.
pub fn model_service_scope_matches(a : Operation, b : Operation) -> Bool {
  a.intent.tenant_id == b.intent.tenant_id &&
  a.intent.organization_id == b.intent.organization_id &&
  a.intent.project_id == b.intent.project_id &&
  a.intent.authorization_ref == b.intent.authorization_ref &&
  a.intent.lease_id == b.intent.lease_id &&
  a.reservation_id is Some(_) &&
  a.reservation_id == b.reservation_id &&
  a.intent.template_id == b.intent.template_id &&
  a.intent.template_version == b.intent.template_version &&
  a.intent.model_digest is Some(_) &&
  a.intent.model_digest == b.intent.model_digest &&
  a.node_ids.length() == b.node_ids.length() &&
  a.node_ids.all(node => b.node_ids.contains(node)) &&
  a.intent.expires_at_ms >= b.intent.expires_at_ms
}

///|
pub async fn DeliveryStore::model_services(
  self : DeliveryStore,
) -> Array[ModelService] {
  self.mutex.acquire()
  defer self.mutex.release()
  @json.from_json(self.model_services.to_json())
}

///|
pub async fn DeliveryStore::model_service(
  self : DeliveryStore,
  id : String,
) -> ModelService? {
  self
  .model_services()
  .iter()
  .find_first(service => service.runtime.operation_id == id)
}

///|
/// Caller verifies a Ready candidate's live model response before requesting
/// attachment. This transaction rechecks scope/state and persists both sides.
/// Without a candidate, adopt this delivery's existing assignment identity.
pub async fn DeliveryStore::bind_model_service(
  self : DeliveryStore,
  id : String,
  generation : Int64,
  now : Int64,
  reuse_service_id? : String,
) -> Operation {
  self.mutex.acquire()
  defer self.mutex.release()
  let index = self.index(id, generation)
  let operation = self.operations[index]
  if operation.intent.model_digest is None ||
    operation.reservation_id is None ||
    operation.stage is (Reserving | Stopped | Expired) {
    raise UnexpectedObservation
  }
  let services = self.model_services.copy()
  for service in services {
    if service.consumer_ids.contains(id) {
      return operation
    }
  }
  let operations = self.operations.copy()
  let next = match reuse_service_id {
    Some(service_id) => {
      if operation.stage != PreparingModel ||
        now >= operation.intent.expires_at_ms {
        raise UnexpectedObservation
      }
      let mut selected = None
      for i, service in services {
        if service.runtime.operation_id == service_id {
          selected = Some(i)
        }
      }
      guard selected is Some(service_index) else { raise NotFound }
      let service = services[service_index]
      if service.runtime.stage != Ready ||
        service.consumer_ids.is_empty() ||
        service.runtime.model_replicas.map_or(true, replicas => {
          replicas.length() != service.runtime.node_ids.length() ||
          !replicas.all(replica => replica.ready && !replica.stopped)
        }) ||
        !model_service_scope_matches(service.runtime, operation) {
        raise UnexpectedObservation
      }
      let members = service.consumer_ids.copy()
      members.push(id)
      services[service_index] = { ..service, consumer_ids: members, }
      {
        ..operation,
        model_service_id: Some(service_id),
        model_replicas: service.runtime.model_replicas,
        cache_hit: service.runtime.cache_hit,
        stage: if operation.intent.kind == ModelApi {
          Ready
        } else {
          StartingWorkspace
        },
        generation: generation + 1L,
        updated_at_ms: now,
      }
    }
    None => {
      if !(operation.stage is (Ready | StartingWorkspace)) ||
        operation.model_replicas.map_or(true, replicas => {
          replicas.length() != operation.node_ids.length() ||
          !replicas.all(replica => replica.ready && !replica.stopped)
        }) {
        raise UnexpectedObservation
      }
      services.push({
        runtime: {
          ..operation,
          intent: { ..operation.intent, kind: ModelApi, },
          stage: Ready,
          workspace_id: None,
          model_service_id: None,
        },
        consumer_ids: [id],
      })
      {
        ..operation,
        model_service_id: Some(id),
        generation: generation + 1L,
        updated_at_ms: now,
      }
    }
  }
  operations[index] = next
  self.commit(operations, model_services=services)
  next
}

///|
pub async fn DeliveryStore::observe_model_service(
  self : DeliveryStore,
  id : String,
  generation : Int64,
  observation : Observation,
  now : Int64,
) -> Operation {
  self.mutex.acquire()
  defer self.mutex.release()
  let services = self.model_services.copy()
  let mut selected = None
  for i, service in services {
    if service.runtime.operation_id == id {
      selected = Some(i)
    }
  }
  guard selected is Some(index) else { raise NotFound }
  let service = services[index]
  if service.runtime.generation != generation {
    raise StaleGeneration
  }
  let runtime = advance(service.runtime, observation, now)
  services[index] = { ..service, runtime, }
  let operations = self.operations.copy()
  for i, operation in operations {
    if !service.consumer_ids.contains(operation.operation_id) ||
      operation.stage is (Failed | Stopping | Stopped | Expired) {
      continue
    }
    let stage = if runtime.stage == Ready {
      if operation.stage == Ready ||
        operation.intent.kind == ModelApi ||
        operation.workspace_id is Some(_) {
        Ready
      } else {
        StartingWorkspace
      }
    } else {
      runtime.stage
    }
    operations[i] = {
      ..operation,
      stage,
      resume_stage: runtime.resume_stage,
      model_replicas: runtime.model_replicas,
      model_assignment_generation: runtime.model_assignment_generation,
      cache_hit: runtime.cache_hit,
      transferred_bytes: runtime.transferred_bytes,
      total_bytes: runtime.total_bytes,
      failure_code: runtime.failure_code,
      generation: operation.generation + 1L,
      updated_at_ms: now,
    }
  }
  self.commit(operations, model_services=services)
  runtime
}

///|
/// Called only after this delivery's workspace has actually stopped. Other
/// members retain the model; the last member waits for physical termination.
pub async fn DeliveryStore::release_model_service(
  self : DeliveryStore,
  id : String,
  generation : Int64,
  now : Int64,
) -> Operation {
  self.mutex.acquire()
  defer self.mutex.release()
  let index = self.index(id, generation)
  let operation = self.operations[index]
  if operation.stage != Stopping || operation.workspace_id is Some(_) {
    raise UnexpectedObservation
  }
  let services = self.model_services.copy()
  let mut attached = false
  for service_index, service in services {
    if !service.consumer_ids.contains(id) {
      continue
    }
    attached = true
    if service.consumer_ids.length() == 1 &&
      !(service.runtime.stage is (Stopped | Expired)) {
      if service.runtime.stage != Stopping {
        services[service_index] = {
          ..service,
          runtime: {
            ..service.runtime,
            stage: Stopping,
            stop_requested_at_ms: Some(now),
            failure_code: None,
            generation: service.runtime.generation + 1L,
            updated_at_ms: now,
          },
        }
        self.commit(self.operations, model_services=services)
      }
      return operation
    }
    services[service_index] = {
      ..service,
      consumer_ids: service.consumer_ids.filter(consumer => consumer != id),
    }
  }
  if !attached {
    raise UnexpectedObservation
  }
  let next = {
    ..operation,
    stage: if now >= operation.intent.expires_at_ms {
      Expired
    } else {
      Stopped
    },
    generation: generation + 1L,
    updated_at_ms: now,
  }
  let operations = self.operations.copy()
  operations[index] = next
  self.commit(operations, model_services=services)
  next
}
