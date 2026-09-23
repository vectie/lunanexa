///|
fn advance(
  operation : Operation,
  observation : Observation,
  now : Int64,
) -> Operation raise DeliveryError {
  if now >= operation.intent.expires_at_ms && operation.stage != Stopping {
    raise AuthorizationExpired
  }
  let next = match (operation.stage, observation) {
    (Reserving, Reserved(reservation_id~, node_ids~)) => {
      if reservation_id == "" ||
        node_ids.length() != operation.intent.node_count {
        raise UnexpectedObservation
      }
      let unique : Map[String, Bool] = Map([])
      for node in node_ids {
        if node == "" || unique.contains(node) {
          raise UnexpectedObservation
        }
        unique[node] = true
      }
      {
        ..operation,
        reservation_id: Some(reservation_id),
        node_ids: node_ids.copy(),
        stage: if operation.intent.model_digest is Some(_) {
          PreparingModel
        } else {
          StartingWorkspace
        },
      }
    }
    (PreparingModel, TransferProgress(transferred_bytes~, total_bytes~)) => {
      if transferred_bytes < 0L ||
        (total_bytes is Some(total) && total < transferred_bytes) {
        raise UnexpectedObservation
      }
      { ..operation, transferred_bytes, total_bytes, }
    }
    (PreparingModel, ModelPrepared(digest~, cache_hit~)) => {
      if operation.model_replicas is Some(replicas) &&
        (
          replicas.length() != operation.node_ids.length() ||
          !replicas.all(replica => replica.prepared)
        ) {
        raise UnexpectedObservation
      }
      if operation.intent.model_digest != Some(digest) {
        raise UnexpectedObservation
      }
      {
        ..operation,
        cache_hit,
        stage: if operation.intent.kind == GpuContainer {
          StartingWorkspace
        } else {
          LoadingModel
        },
      }
    }
    (
      PreparingModel
      | LoadingModel
      | Stopping,
      ModelAssignmentPublished(generation~),
    ) => {
      if generation <= 0L {
        raise UnexpectedObservation
      }
      { ..operation, model_assignment_generation: Some(generation), }
    }
    (
      PreparingModel
      | LoadingModel
      | Ready
      | Stopping,
      ModelReplicaObserved(replica),
    ) => {
      if replica.assignment_id == "" ||
        replica.generation <= 0L ||
        !operation.node_ids.contains(replica.node_id) ||
        (replica.ready && !replica.prepared) ||
        (replica.stopped && operation.stage != Stopping) {
        raise UnexpectedObservation
      }
      let replicas = operation.model_replicas.unwrap_or([]).copy()
      let mut found = false
      for index, previous in replicas {
        if previous.assignment_id == replica.assignment_id {
          if previous.node_id != replica.node_id ||
            previous.generation > replica.generation {
            raise UnexpectedObservation
          }
          replicas[index] = replica
          found = true
        } else if previous.node_id == replica.node_id {
          raise UnexpectedObservation
        }
      }
      if !found {
        replicas.push(replica)
      }
      {
        ..operation,
        model_replicas: Some(replicas),
        stage: if operation.stage == Ready && !replica.ready {
          LoadingModel
        } else {
          operation.stage
        },
      }
    }
    (LoadingModel, ModelResponded(service_id~, digest~)) => {
      if operation.model_replicas is Some(replicas) &&
        (
          replicas.length() != operation.node_ids.length() ||
          !replicas.all(replica => replica.ready)
        ) {
        raise UnexpectedObservation
      }
      if service_id == "" || operation.intent.model_digest != Some(digest) {
        raise UnexpectedObservation
      }
      {
        ..operation,
        model_service_id: Some(service_id),
        stage: if operation.intent.kind == ModelApi {
          Ready
        } else {
          StartingWorkspace
        },
      }
    }
    (StartingWorkspace, WorkspaceResponded(workspace_id~)) => {
      if operation.intent.kind != Workspace || workspace_id == "" {
        raise UnexpectedObservation
      }
      { ..operation, workspace_id: Some(workspace_id), stage: Ready, }
    }
    (StartingWorkspace, WorkspaceStarting(workspace_id~)) => {
      if workspace_id == "" {
        raise UnexpectedObservation
      }
      { ..operation, workspace_id: Some(workspace_id), }
    }
    (Stopping, WorkspaceStopped) => { ..operation, workspace_id: None, }
    (StartingWorkspace, ContainerResponded(instance_id~)) => {
      if operation.intent.kind != GpuContainer || instance_id == "" {
        raise UnexpectedObservation
      }
      { ..operation, workspace_id: Some(instance_id), stage: Ready, }
    }
    (Stopping, WorkloadsStopped) => {
      if operation.model_replicas is Some(replicas) &&
        !replicas.all(replica => replica.stopped) {
        raise UnexpectedObservation
      }
      {
        ..operation,
        stage: if now >= operation.intent.expires_at_ms {
          Expired
        } else {
          Stopped
        },
      }
    }
    (
      Reserving
      | PreparingModel
      | LoadingModel
      | StartingWorkspace
      | Ready
      | Stopping,
      Failure(code~),
    ) => {
      if code == "" {
        raise UnexpectedObservation
      }
      {
        ..operation,
        stage: Failed,
        resume_stage: operation.stage,
        failure_code: Some(code),
      }
    }
    _ => raise UnexpectedObservation
  }
  { ..next, generation: operation.generation + 1L, updated_at_ms: now, }
}
