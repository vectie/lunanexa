///|
fn RuntimeSupervisor::new_record(
  self : RuntimeSupervisor,
  assignment : @contracts.DesiredAssignment,
  plan : RuntimeResources,
) -> RuntimeRecord raise LifecycleError {
  let intent = digest_text(
    plan.pod.stringify() +
    plan.network_policy.stringify() +
    plan.claim_template.map(value => value.stringify()).unwrap_or(""),
  )
  let resources : Array[ResourceRecord] = [
    {
      collection: AuxiliaryKind::NetworkPolicy.collection(
        self.journal.settings.namespace_name,
      ),
      resource: stamp(plan.network_policy, self.journal.owner, intent),
      uid: None,
      gone: false,
    },
  ]
  if plan.claim_template is Some(template) {
    resources.push({
      collection: AuxiliaryKind::ClaimTemplate.collection(
        self.journal.settings.namespace_name,
      ),
      resource: stamp(template, self.journal.owner, intent),
      uid: None,
      gone: false,
    })
  }
  resources.push({
    collection: "/api/v1/namespaces/\{self.journal.settings.namespace_name}/pods",
    resource: stamp(plan.pod, self.journal.owner, intent),
    uid: None,
    gone: false,
  })
  {
    name: plan.name,
    assignment_id: assignment.assignment_id,
    generation: assignment.generation,
    image_ref: assignment.runtime.name + "@" + assignment.runtime.image_digest,
    image_digest: assignment.runtime.image_digest,
    artifact_digest: assignment.artifact.digest,
    lease_expires_unix_ms: assignment.lease_expires_unix_ms,
    intent,
    resources,
    stopping: false,
    observed_containers: None,
    original_assignment: Some(assignment),
  }
}

///|
async fn RuntimeSupervisor::ensure_resource(
  self : RuntimeSupervisor,
  record : RuntimeRecord,
  resource : ResourceRecord,
) -> Json {
  // The intent must be durable before GET/POST, including retries after a failed
  // previous checkpoint. No API-side object can precede its journal entry.
  self.persist()
  let (status, actual) = (self.transport)(
    "GET",
    resource.collection + "/" + record.name,
    None,
  )
  let observed = if status == 404 {
    // A known incarnation is gone. Persist that fact before allowing replacement.
    resource.uid = None
    self.persist()
    if record.lease_expires_unix_ms <= (self.clock)() {
      record.stopping = true
      self.persist()
      raise LifecycleError::LeaseExpired
    }
    let (created_status, created) = (self.transport)(
      "POST",
      resource.collection,
      Some(resource.resource),
    )
    if created_status == 409 {
      raise LifecycleError::OwnershipConflict
    }
    if created_status != 201 {
      raise LifecycleError::ApiRejected(created_status)
    }
    created
  } else if status == 200 {
    actual
  } else {
    raise LifecycleError::ApiRejected(status)
  }
  let uid = {
    errdefer {
      record.stopping = true
      self.persist()
    }
    validate_owned_resource(self.journal, record, resource, observed)
  }
  resource.uid = Some(uid)
  self.persist()
  observed
}

///|
/// Reconcile verified assignment/materializer output. The caller retains
/// signature, controller epoch and admission authority. This method cannot
/// turn an arbitrary existing Pod into a ready assignment.
pub async fn RuntimeSupervisor::ensure_started(
  self : RuntimeSupervisor,
  assignment : @contracts.DesiredAssignment,
  artifact_path : String,
  verified_digest : String,
  verified_size : Int64,
  now_unix_ms : Int64,
) -> RuntimeObservation {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise LifecycleError::InvalidResource
  }
  let plan = render_runtime(
    self.journal.settings,
    assignment,
    artifact_path,
    verified_digest,
    verified_size,
    now_unix_ms,
  )
  let candidate = self.new_record(assignment, plan)
  let older = self.journal.runtimes.filter(record => {
    record.assignment_id == assignment.assignment_id && record.name != plan.name
  })
  if !older.is_empty() {
    for record in older {
      ignore(self.stop_record(record))
    }
    return {
      assignment_id: assignment.assignment_id,
      pod_name: older[0].name,
      state: Draining,
      address: "",
      endpoint: None,
    }
  }
  let record = match
    self.journal.runtimes.iter().find_first(record => record.name == plan.name) {
    Some(record) => {
      if record.intent != candidate.intent {
        raise LifecycleError::OwnershipConflict
      }
      record
    }
    None => {
      if self.journal.runtimes.length() >= 1024 {
        raise LifecycleError::InvalidResource
      }
      self.journal.runtimes.push(candidate)
      candidate
    }
  }
  if record.original_assignment is None {
    record.original_assignment = Some(assignment)
    errdefer {
      record.original_assignment = None
    }
    self.persist()
  }
  if record.stopping {
    let state = self.stop_record(record)
    return {
      assignment_id: assignment.assignment_id,
      pod_name: record.name,
      state,
      address: "",
      endpoint: None,
    }
  }
  let mut pod : Json = Json::null()
  for resource in record.resources {
    pod = self.ensure_resource(record, resource)
  }
  if record.lease_expires_unix_ms <= (self.clock)() {
    let state = self.stop_record(record)
    return {
      assignment_id: record.assignment_id,
      pod_name: record.name,
      state,
      address: "",
      endpoint: None,
    }
  }
  self.observation(record, assignment, pod)
}

///|
async fn RuntimeSupervisor::observation(
  self : RuntimeSupervisor,
  record : RuntimeRecord,
  assignment : @contracts.DesiredAssignment,
  pod : Json,
) -> RuntimeObservation {
  let pod_resource = record.resources[record.resources.length() - 1]
  let expected : PodIdentity = {
    namespace_name: self.journal.settings.namespace_name,
    pod_name: record.name,
    uid: pod_resource.uid.unwrap(),
    node_name: self.journal.settings.node_name,
    assignment_id: record.assignment_id,
    generation: record.generation,
    artifact_digest: record.artifact_digest,
    image_ref: record.image_ref,
    image_digest: record.image_digest,
    container_name: "runtime",
  }
  let state = observe_pod(expected, pod)
  if record.observed_containers is Some(containers) &&
    pod
    is {
      "status": { "containerStatuses": [{ "containerID": String(_), .. }], .. },
      ..
    } {
    for i, container in containers {
      if container.pod_uid == expected.uid &&
        container.termination_observed_unix_ms is None &&
        observe_container_termination(expected, container.container_id, pod) {
        let previous_containers = record.observed_containers
        let next = previous_containers.unwrap_or([]).copy()
        let observed = (self.clock)()
        let previous_pending = self.journal.pending_terminations
        let pending = previous_pending.unwrap_or([]).copy()
        if pending.length() >= 4096 {
          raise LifecycleError::InvalidResource
        }
        pending.push({
          original_assignment: Some(assignment),
          assignment_id: assignment.assignment_id,
          deployment_id: assignment.deployment_id,
          generation: assignment.generation,
          controller_epoch: assignment.controller_epoch,
          instance_id: digest_text(
            "kubernetes:" + container.pod_uid + "|" + container.container_id,
          ),
          artifact_digest: assignment.artifact.digest,
          image_digest: assignment.runtime.image_digest,
          observed_unix_ms: observed,
        })
        next[i] = { ..container, termination_observed_unix_ms: Some(observed), }
        record.observed_containers = Some(next)
        self.journal.pending_terminations = Some(pending)
        errdefer {
          record.observed_containers = previous_containers
          self.journal.pending_terminations = previous_pending
        }
        self.persist()
      }
    }
  }
  let address = if state == Ready {
    guard pod is { "status": { "podIP": String(address), .. }, .. } &&
      private_address(address) else {
      raise LifecycleError::InvalidResource
    }
    address
  } else {
    ""
  }
  let endpoint : @contracts.RuntimeEndpoint? = if state == Ready {
    guard pod
      is {
        "status": {
          "containerStatuses": [{ "containerID": String(container_id), .. }],
          ..
        },
        ..
      } &&
      container_id.length() > 0 &&
      container_id.length() <= 256 else {
      raise LifecycleError::InvalidResource
    }
    let known : ObservedContainer = {
      pod_uid: pod_resource.uid.unwrap(),
      container_id,
      termination_observed_unix_ms: None,
    }
    let previous = record.observed_containers
    let containers = previous.unwrap_or([])
    if containers.any(container => {
        container.pod_uid == known.pod_uid &&
        container.container_id == known.container_id &&
        container.termination_observed_unix_ms is Some(_)
      }) {
      // A previously exited incarnation must never become a route again.
      raise LifecycleError::InvalidResource
    }
    if !containers.contains(known) {
      if containers.length() >= 1024 {
        raise LifecycleError::InvalidResource
      }
      let next = containers.copy()
      next.push(known)
      record.observed_containers = Some(next)
      errdefer {
        record.observed_containers = previous
      }
      // Never publish a route whose incarnation cannot survive a node restart.
      self.persist()
    }
    Some({
      assignment_id: assignment.assignment_id,
      deployment_id: assignment.deployment_id,
      generation: assignment.generation,
      controller_epoch: assignment.controller_epoch,
      instance_id: digest_text(
        "kubernetes:" + pod_resource.uid.unwrap() + "|" + container_id,
      ),
      address,
      port: self.journal.settings.runtime_port,
      artifact_digest: assignment.artifact.digest,
      image_digest: assignment.runtime.image_digest,
      observed_unix_ms: (self.clock)(),
    })
  } else {
    None
  }
  {
    assignment_id: record.assignment_id,
    pod_name: record.name,
    state,
    address,
    endpoint,
  }
}

///|
/// Keep model cache entries while any runtime or cleanup intent may still use
/// them. A successful DELETE response alone is not enough to release the file.
pub fn RuntimeSupervisor::retained_artifact_digests(
  self : RuntimeSupervisor,
) -> Array[String] {
  self.journal.runtimes.map(record => record.artifact_digest)
}

///|
async fn RuntimeSupervisor::stop_record(
  self : RuntimeSupervisor,
  record : RuntimeRecord,
) -> @contracts.DeploymentState {
  record.stopping = true
  self.persist()
  // Pod first, then its claim template, network policy last. A failed or
  // uncertain deletion must never reopen traffic or discard the cleanup intent.
  for offset in 0..<record.resources.length() {
    let resource = record.resources[record.resources.length() - 1 - offset]
    if resource.gone {
      continue
    }
    let path = resource.collection + "/" + record.name
    let (status, actual) = (self.transport)("GET", path, None)
    if status == 404 {
      if resource.collection.has_suffix("/pods") &&
        record.observed_containers
        .unwrap_or([])
        .any(container => container.termination_observed_unix_ms is None) {
        // A missing status object cannot prove a published instance exited.
        // Preserve its signed assignment and identities for later reconciliation.
        return Draining
      }
      resource.gone = true
      self.persist()
      continue
    }
    if status != 200 {
      raise LifecycleError::ApiRejected(status)
    }
    let uid = cleanup_uid(self.journal, record, resource, actual)
    resource.uid = Some(uid)
    self.persist()
    if resource.collection.has_suffix("/pods") {
      if !self.prepare_pod_deletion(record, actual, path, uid) {
        return Draining
      }
    }
    let options : Json = {
      "apiVersion": "v1",
      "kind": "DeleteOptions",
      "propagationPolicy": "Foreground",
      "preconditions": { "uid": uid.to_json() },
    }
    let (deleted_status, _) = (self.transport)("DELETE", path, Some(options))
    if deleted_status == 409 {
      raise LifecycleError::OwnershipConflict
    }
    if deleted_status != 200 && deleted_status != 202 && deleted_status != 404 {
      raise LifecycleError::ApiRejected(deleted_status)
    }
    return Draining
  }
  self.journal.runtimes = self.journal.runtimes.filter(entry => {
    entry.name != record.name
  })
  self.persist()
  Stopped
}

///|
pub async fn RuntimeSupervisor::stop(
  self : RuntimeSupervisor,
  assignment_id : String,
) -> @contracts.DeploymentState {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise LifecycleError::InvalidResource
  }
  let records = self.journal.runtimes.filter(record => {
    record.assignment_id == assignment_id
  })
  let mut state : @contracts.DeploymentState = Stopped
  for record in records {
    if self.stop_record(record) != Stopped {
      state = Draining
    }
  }
  state
}

///|
/// Invoke independently of controller requests so a controller outage does not
/// skip expiry cleanup. Kubernetes API outages remain failures, not success.
pub async fn RuntimeSupervisor::reap_expired(
  self : RuntimeSupervisor,
  now_unix_ms : Int64,
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise LifecycleError::InvalidResource
  }
  let expired = self.journal.runtimes.filter(record => {
    record.stopping || record.lease_expires_unix_ms <= now_unix_ms
  })
  let mut failed = false
  for record in expired {
    try self.stop_record(record) catch {
      error => {
        println(
          "LunaNexa runtime cleanup failed for " +
          record.name +
          ": " +
          Repr(error).to_string(),
        )
        failed = true
      }
    } noraise {
      _ => ()
    }
  }
  if failed {
    raise LifecycleError::ApiRejected(503)
  }
}

///|
/// Compare the journal itself with fresh controller intent. Cleanup cannot rely
/// only on NodeAgent's in-memory removed-assignment list surviving a crash.
pub async fn RuntimeSupervisor::remove_absent(
  self : RuntimeSupervisor,
  desired_ids : Array[String],
) -> Unit {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise LifecycleError::InvalidResource
  }
  let absent = self.journal.runtimes.filter(record => {
    !desired_ids.contains(record.assignment_id)
  })
  let mut failed = false
  for record in absent {
    try self.stop_record(record) catch {
      error => {
        println(
          "LunaNexa absent runtime cleanup failed for " +
          record.name +
          ": " +
          Repr(error).to_string(),
        )
        failed = true
      }
    } noraise {
      _ => ()
    }
  }
  if failed {
    raise LifecycleError::ApiRejected(503)
  }
}
