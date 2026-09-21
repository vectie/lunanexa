///|
/// Expected immutable identity of a runtime Pod created for a signed assignment.
/// The Kubernetes UID must be bound when creation succeeds, never inferred from
/// a later unrelated Pod that happens to reuse the same name.
pub(all) struct PodIdentity {
  namespace_name : String
  pod_name : String
  uid : String
  node_name : String
  assignment_id : String
  generation : Int64
  artifact_digest : String
  image_ref : String
  image_digest : String
  container_name : String
} derive(Debug, Eq)

///|
pub(all) suberror ObservationError {
  InvalidIdentity
  IdentityMismatch
  InvalidObservation
} derive(Debug, Eq)

///|
/// Classify an authenticated Kubernetes API observation. Running alone is not
/// readiness; require the assigned node, pinned image, exact Pod incarnation,
/// assignment labels, Pod Ready condition and a running ready container.
pub fn observe_pod(
  expected : PodIdentity,
  pod : Json,
) -> @contracts.DeploymentState raise ObservationError {
  if expected.namespace_name == "" ||
    expected.pod_name == "" ||
    expected.uid == "" ||
    expected.node_name == "" ||
    expected.assignment_id == "" ||
    expected.container_name == "" ||
    expected.generation < 0L ||
    !@contracts.valid_sha256_digest(expected.artifact_digest) ||
    !@contracts.valid_sha256_digest(expected.image_digest) ||
    !expected.image_ref.has_suffix("@" + expected.image_digest) {
    raise InvalidIdentity
  }
  guard pod
    is {
      "metadata": {
        "namespace": String(namespace_name),
        "name": String(name),
        "uid": String(uid),
        "labels": { "lunanexa.io/assignment": String(assignment), .. },
        "annotations": {
          "lunanexa.io/generation": String(generation),
          "lunanexa.io/artifact-digest": String(artifact),
          ..
        },
        ..
      },
      "spec": { "containers": Array(containers), .. },
      ..
    } else {
    raise InvalidObservation
  }
  if namespace_name != expected.namespace_name ||
    name != expected.pod_name ||
    uid != expected.uid ||
    assignment != expected.assignment_id ||
    generation != expected.generation.to_string() ||
    artifact != expected.artifact_digest {
    raise IdentityMismatch
  }
  if containers.length() != 1 ||
    !(containers[0] is { "name": String(container), "image": String(image), .. } &&
    container == expected.container_name &&
    image == expected.image_ref) {
    raise IdentityMismatch
  }
  if pod is { "metadata": { "deletionTimestamp": String(_), .. }, .. } {
    return Draining
  }
  match pod {
    { "spec": { "nodeName": String(node), .. }, .. } =>
      if node != expected.node_name {
        raise IdentityMismatch
      }
    _ => return Pending
  }
  guard pod is { "status": { "phase": String(phase), .. }, .. } else {
    return Pending
  }
  match phase {
    "Failed" | "Succeeded" => return Failed
    "Pending" => return Starting
    "Running" => ()
    _ => return Degraded
  }
  guard pod
    is {
      "status": {
        "conditions": Array(conditions),
        "containerStatuses": Array(statuses),
        ..
      },
      ..
    } else {
    return Starting
  }
  if statuses.length() != 1 {
    return Degraded
  }
  guard statuses[0]
    is {
      "name": String(container),
      "imageID": String(image_id),
      "ready": True,
      "state": { "running": Object(_), .. },
      ..
    } else {
    return Starting
  }
  if container != expected.container_name ||
    !image_id.has_suffix("@" + expected.image_digest) {
    raise IdentityMismatch
  }
  let ready = conditions.filter(condition => {
    condition is { "type": "Ready", .. }
  })
  if ready.length() == 1 && ready[0] is { "status": "True", .. } {
    Ready
  } else {
    Starting
  }
}
