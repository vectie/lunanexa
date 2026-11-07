///|
fn identity() -> @kubernetes.PodIdentity {
  {
    namespace_name: "runtime",
    pod_name: "assignment-1",
    uid: "uid-1",
    node_name: "compute-1",
    assignment_id: "assignment-1",
    generation: 1L,
    artifact_digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    image_ref: "registry/runtime@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    container_name: "runtime",
  }
}

///|
fn pod(phase~ : String = "Running", ready~ : Bool = true) -> Json {
  let expected = identity()
  {
    "metadata": {
      "namespace": Json(expected.namespace_name),
      "name": Json(expected.pod_name),
      "uid": Json(expected.uid),
      "labels": { "lunanexa.io/assignment": Json(expected.assignment_id) },
      "annotations": {
        "lunanexa.io/generation": "1",
        "lunanexa.io/artifact-digest": Json(expected.artifact_digest),
      },
    },
    "spec": {
      "nodeName": Json(expected.node_name),
      "containers": [{ "name": "runtime", "image": Json(expected.image_ref) }],
    },
    "status": {
      "phase": Json(phase),
      "conditions": [{ "type": "Ready", "status": "True" }],
      "containerStatuses": [
        {
          "name": "runtime",
          "ready": Json(ready),
          "imageID": Json(expected.image_ref),
          "state": { "running": {} },
        },
      ],
    },
  }
}

///|
test "ready requires a running ready container, not just the Pod phase" {
  assert_eq(@kubernetes.observe_pod(identity(), pod()), Ready)
  assert_eq(@kubernetes.observe_pod(identity(), pod(ready=false)), Starting)
  assert_eq(@kubernetes.observe_pod(identity(), pod(phase="Pending")), Starting)
  assert_eq(@kubernetes.observe_pod(identity(), pod(phase="Failed")), Failed)
  assert_eq(@kubernetes.observe_pod(identity(), pod(phase="Succeeded")), Failed)
  assert_eq(@kubernetes.observe_pod(identity(), pod(phase="Unknown")), Degraded)
}

///|
test "replacement pods and changed assignment bindings are rejected" {
  let original = identity()
  for
    expected in [
      { ..original, uid: "replacement", },
      { ..original, node_name: "compute-2", },
      { ..original, namespace_name: "other", },
      { ..original, pod_name: "other", },
      { ..original, assignment_id: "other", },
      { ..original, generation: 2L, },
      { ..original, container_name: "other", },
      { ..original, artifact_digest: original.image_digest, },
    ] {
    try @kubernetes.observe_pod(expected, pod()) catch {
      IdentityMismatch => ()
      _ => fail("wrong identity error")
    } noraise {
      _ => fail("mismatched Pod accepted")
    }
  }
}

///|
test "invalid expected identity and malformed observations fail closed" {
  let original = identity()
  try @kubernetes.observe_pod({ ..original, uid: "", }, pod()) catch {
    InvalidIdentity => ()
    _ => fail("wrong validation error")
  } noraise {
    _ => fail("empty UID accepted")
  }
  try @kubernetes.observe_pod(original, {}) catch {
    InvalidObservation => ()
    _ => fail("wrong observation error")
  } noraise {
    _ => fail("malformed Pod accepted")
  }
}
