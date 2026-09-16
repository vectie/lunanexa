///|
/// Copy the durable pending evidence for authenticated delivery. Reading does
/// not acknowledge it; cleanup of Kubernetes resources cannot erase this outbox.
pub async fn RuntimeSupervisor::pending_terminations(
  self : RuntimeSupervisor,
) -> Array[@contracts.RuntimeTermination] {
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise LifecycleError::InvalidResource
  }
  self.journal.pending_terminations.unwrap_or([]).copy()
}

///|
/// Retire only evidence durably accepted through an authenticated controller
/// response. The caller must verify that response; an HTTP transport success
/// without an exact accepted record is not an acknowledgement. Replays are safe.
pub async fn RuntimeSupervisor::acknowledge_terminations(
  self : RuntimeSupervisor,
  accepted : Array[@contracts.RuntimeTermination],
) -> Unit {
  if accepted.length() > 4096 {
    raise LifecycleError::InvalidResource
  }
  self.mutex.acquire()
  defer self.mutex.release()
  if self.closed {
    raise LifecycleError::InvalidResource
  }
  let previous = self.journal.pending_terminations
  let entries = previous.unwrap_or([])
  let next = entries.filter(entry => !accepted.contains(entry))
  if next.length() == entries.length() {
    return
  }
  self.journal.pending_terminations = Some(next)
  errdefer {
    self.journal.pending_terminations = previous
  }
  self.persist()
}

///|
/// Inspect an authenticated Kubernetes observation for the original container's
/// explicit exit. Absence, Pod phase and deletion intent are not evidence.
/// lastState is accepted only when it explicitly identifies the expected old
/// container, and the current container has a different identity.
/// The caller must persist and authenticate any resulting
/// evidence before using it to settle jobs; this parser grants no authority.
pub fn observe_container_termination(
  expected : PodIdentity,
  container_id : String,
  pod : Json,
) -> Bool raise ObservationError {
  if container_id == "" || container_id.length() > 256 {
    raise InvalidIdentity
  }
  // Reuse the immutable Pod/assignment/image-spec checks. Readiness itself is
  // irrelevant here, and deletionTimestamp must not bypass node validation.
  ignore(observe_pod(expected, pod))
  guard pod is { "spec": { "nodeName": String(node), .. }, .. } else {
    return false
  }
  if node != expected.node_name {
    raise IdentityMismatch
  }
  if pod
    is {
      "status": {
        "containerStatuses": [
          {
            "name": String(name),
            "imageID": String(image),
            "containerID": String(current),
            "lastState": Object(previous),
            ..
          },
        ],
        ..
      },
      ..
    } &&
    current != container_id {
    if name != expected.container_name ||
      !image.has_suffix("@" + expected.image_digest) {
      raise IdentityMismatch
    }
    return previous.length() == 1 &&
      previous.get("terminated")
      is Some(
        {
          "containerID": String(old),
          "exitCode": Number(_),
          "finishedAt": String(finished),
          ..
        }
      ) &&
      old == container_id &&
      finished != ""
  }
  guard pod
    is {
      "status": {
        "containerStatuses": [
          {
            "name": String(name),
            "imageID": String(image),
            "containerID": String(current_id),
            "ready": False,
            "state": Object(state),
            ..
          },
        ],
        ..
      },
      ..
    } else {
    return false
  }
  if name != expected.container_name ||
    !image.has_suffix("@" + expected.image_digest) {
    raise IdentityMismatch
  }
  if current_id != container_id {
    return false
  }
  // Reject contradictory states and require the terminated record itself to
  // identify the same container, not a predecessor from a restart.
  if state.length() != 1 {
    return false
  }
  match state.get("terminated") {
    Some(
      {
        "containerID": String(terminated_id),
        "exitCode": Number(_),
        "finishedAt": String(finished),
        ..
      }
    ) => terminated_id == container_id && finished != ""
    _ => false
  }
}
