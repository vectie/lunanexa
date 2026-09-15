///|
/// Refresh existing resources without materialization or mutation. The caller
/// supplies only assignments already accepted by the node verifier. This probe
/// runs independently of downloads; it cannot create or adopt Kubernetes objects.
pub async fn RuntimeSupervisor::probe_assignments(
  self : RuntimeSupervisor,
  assignments : Array[@contracts.DesiredAssignment],
) -> Array[RuntimeObservation] {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise LifecycleError::InvalidResource
  }
  let observations : Array[RuntimeObservation] = []
  for assignment in assignments {
    let unavailable : RuntimeObservation = {
      assignment_id: assignment.assignment_id,
      pod_name: "",
      state: Failed,
      address: "",
      endpoint: None,
    }
    guard self.journal.runtimes
      .iter()
      .find_first(record => record.assignment_id == assignment.assignment_id)
      is Some(record) &&
      !record.stopping &&
      record.generation == assignment.generation &&
      record.artifact_digest == assignment.artifact.digest &&
      record.image_digest == assignment.runtime.image_digest &&
      record.lease_expires_unix_ms == assignment.lease_expires_unix_ms &&
      record.lease_expires_unix_ms > (self.clock)() else {
      observations.push(unavailable)
      continue
    }
    try {
      let mut pod : Json = Json::null()
      for resource in record.resources {
        if resource.uid is None || resource.gone {
          raise LifecycleError::InvalidResource
        }
        let (status, actual) = (self.transport)(
          "GET",
          resource.collection + "/" + record.name,
          None,
        )
        if status != 200 {
          raise LifecycleError::ApiRejected(status)
        }
        ignore(validate_owned_resource(self.journal, record, resource, actual))
        pod = actual
      }
      if record.lease_expires_unix_ms <= (self.clock)() {
        raise LifecycleError::LeaseExpired
      }
      observations.push(self.observation(record, assignment, pod))
    } catch {
      _ => observations.push(unavailable)
    }
  }
  observations
}
