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
fn pod(phase? : String = "Running", ready? : Bool = true) -> Json {
  let expected = identity()
  {
    "metadata": {
      "namespace": expected.namespace_name.to_json(),
      "name": expected.pod_name.to_json(),
      "uid": expected.uid.to_json(),
      "labels": { "lunanexa.io/assignment": expected.assignment_id.to_json() },
      "annotations": {
        "lunanexa.io/generation": "1",
        "lunanexa.io/artifact-digest": expected.artifact_digest.to_json(),
      },
    },
    "spec": {
      "nodeName": expected.node_name.to_json(),
      "containers": [
        { "name": "runtime", "image": expected.image_ref.to_json() },
      ],
    },
    "status": {
      "phase": phase.to_json(),
      "conditions": [{ "type": "Ready", "status": "True" }],
      "containerStatuses": [
        {
          "name": "runtime",
          "ready": ready.to_json(),
          "imageID": expected.image_ref.to_json(),
          "state": { "running": {} },
        },
      ],
    },
  }
}

///|
test "ready requires a running ready container, not just the Pod phase" {
  assert_eq(observe_pod(identity(), pod()), Ready)
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
