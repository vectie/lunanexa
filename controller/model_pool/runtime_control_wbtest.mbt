///|
async test "generic Kubernetes adoption and retries preserve the runtime specification" {
  let target : Target = {
    deployment: "existing",
    node_id: "node-a",
    kube_node: "node-a",
    cache_root: "/models",
  }
  let replicas = Ref(1)
  let writes : Array[Json] = []
  let identity = Ref("existing-uid")
  let transport : Transport = (verb, path, body) => {
    if path.has_suffix("/pods") {
      return (200, { "items": [] })
    }
    if verb == "PATCH" {
      guard body is Some(Array(patch)) &&
        patch.length() == 3 &&
        patch[0] ==
        { "op": "test", "path": "/metadata/uid", "value": "existing-uid" } &&
        patch[1] ==
        { "op": "test", "path": "/metadata/resourceVersion", "value": "1" } &&
        patch[2]
        is {
          "op": "replace",
          "path": "/spec/replicas",
          "value": Number(n, ..),
          ..
        } else {
        fail("adapter changed runtime settings")
      }
      writes.push(Json(patch))
      replicas.val = n.to_int()
    }
    (
      200,
      {
        "metadata": {
          "uid": identity.val,
          "resourceVersion": "1",
          "generation": 1,
        },
        "spec": {
          "selector": { "matchLabels": { "app": "existing" } },
          "replicas": replicas.val,
          "template": {
            "spec": {
              "nodeSelector": { "kubernetes.io/hostname": "node-a" },
              "containers": [{ "image": "unchanged", "args": ["unchanged"] }],
            },
          },
        },
        "status": {
          "observedGeneration": 1,
          "replicas": replicas.val,
          "readyReplicas": replicas.val,
          "availableReplicas": replicas.val,
        },
      },
    )
  }
  let control = kubernetes_runtime_control(
    transport, "models", target, "existing-uid",
  )
  assert_eq(control("status"), "Running")
  assert_true(writes.is_empty())
  assert_eq(control("start"), "Running")
  assert_true(writes.is_empty())
  assert_eq(control("stop"), "Stopped")
  assert_eq(control("stop"), "Stopped")
  assert_eq(writes.length(), 1)
  identity.val = "foreign-uid"
  try control("start") catch {
    _ => ()
  } noraise {
    _ => fail("foreign object was modified")
  }
  assert_eq(writes.length(), 1)
}

///|
test "terminating and pending runtime pods retain occupancy until termination" {
  let selector : Map[String, Json] = { "app": "model" }
  assert_true(
    runtime_pod_present(
      {
        "metadata": { "labels": { "app": "model" }, "deletionTimestamp": "now" },
        "status": { "phase": "Running" },
      },
      selector,
    ),
  )
  assert_true(
    runtime_pod_present(
      {
        "metadata": { "labels": { "app": "model" } },
        "status": { "phase": "Pending" },
      },
      selector,
    ),
  )
  assert_false(
    runtime_pod_present(
      {
        "metadata": { "labels": { "app": "model" } },
        "status": { "phase": "Succeeded" },
      },
      selector,
    ),
  )
  assert_false(
    runtime_pod_present(
      {
        "metadata": { "labels": { "app": "other" } },
        "status": { "phase": "Running" },
      },
      selector,
    ),
  )
}

///|
async test "generic transport accepts one reviewed target and never patches pod collections" {
  let target : Target = {
    deployment: "model",
    node_id: "node",
    kube_node: "node",
    cache_root: "/models",
  }
  let transport = authenticated_transport(
    "https://kubernetes.default.svc",
    "/token",
    "/ca",
    "models",
    [target],
  )
  try transport("PATCH", "/api/v1/namespaces/models/pods", Some([])) catch {
    PoolError::OutsideScope => ()
    _ => fail("unexpected transport result")
  } noraise {
    _ => fail("pod write authority expanded")
  }
}
