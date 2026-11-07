///|
/// Generic existing-object lifecycle adapter. Resource ownership is checked by
/// the deployment authority before this function is called. UID, placement and
/// resourceVersion checks bind a request to the adopted object, not its name.
pub fn kubernetes_runtime_control(
  transport : Transport,
  namespace_name : String,
  target : Target,
  expected_uid : String,
) -> async (String) -> String {
  action => {
    let path = "/apis/apps/v1/namespaces/" +
      namespace_name +
      "/deployments/" +
      target.deployment
    let (code, value) = transport("GET", path, None)
    guard code == 200 &&
      value
      is {
        "metadata": {
          "uid": String(uid),
          "resourceVersion": String(version),
          ..
        },
        "spec": {
          "replicas": Number(replicas, ..),
          "template": {
            "spec": {
              "nodeSelector": { "kubernetes.io/hostname": String(node), .. },
              ..
            },
            ..
          },
          ..
        },
        ..
      } &&
      uid == expected_uid &&
      node == target.kube_node else {
      raise PoolError::Conflict
    }
    let desired = if action == "start" {
      1
    } else if action == "stop" {
      0
    } else if action == "status" {
      replicas.to_int()
    } else {
      raise PoolError::InvalidConfiguration
    }
    if desired.to_double() != replicas {
      let (status, _) = transport(
        "PATCH",
        path,
        Some([
          { "op": "test", "path": "/metadata/uid", "value": uid },
          {
            "op": "test",
            "path": "/metadata/resourceVersion",
            "value": version,
          },
          { "op": "replace", "path": "/spec/replicas", "value": desired },
        ]),
      )
      if status != 200 {
        raise PoolError::Unavailable
      }
    }
    let (code, observed) = if desired.to_double() != replicas {
      transport("GET", path, None)
    } else {
      (code, value)
    }
    guard code == 200 &&
      observed is { "metadata": { "uid": String(actual), .. }, .. } &&
      actual == expected_uid else {
      raise PoolError::Unavailable
    }
    match observed {
      { "spec": { "replicas": 0, .. }, "status": Object(status), .. } if status.get(
          "replicas",
        )
        is None ||
        status.get("replicas") == Some(0) => {
        // A scaled-to-zero Deployment can still have terminating pods holding
        // the accelerator. Release only after the owned selector is empty.
        guard observed
          is {
            "spec": { "selector": { "matchLabels": Object(selector), .. }, .. },
            ..
          } &&
          !selector.is_empty() else {
          return "Partial"
        }
        let (status, pods) = transport(
          "GET",
          "/api/v1/namespaces/" + namespace_name + "/pods",
          None,
        )
        guard status == 200 && pods is { "items": Array(pods), .. } else {
          raise PoolError::Unavailable
        }
        if pods.any(pod => runtime_pod_present(pod, selector)) {
          "Partial"
        } else {
          "Stopped"
        }
      }
      {
        "metadata": { "generation": Number(generation, ..), .. },
        "spec": { "replicas": 1, .. },
        "status": {
          "observedGeneration": Number(seen, ..),
          "replicas": 1,
          "readyReplicas": 1,
          "availableReplicas": 1,
          ..
        },
        ..
      } if seen >= generation => "Running"
      _ => "Partial"
    }
  }
}

///|
fn runtime_pod_present(pod : Json, selector : Map[String, Json]) -> Bool {
  guard pod is { "metadata": { "labels": Object(labels), .. }, .. } &&
    selector.iter().all(entry => labels.get(entry.0) == Some(entry.1)) else {
    return false
  }
  match pod {
    { "status": { "phase": "Succeeded" | "Failed", .. }, .. } => false
    _ => true
  }
}
