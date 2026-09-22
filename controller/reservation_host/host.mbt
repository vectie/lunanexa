///|
pub type Transport = async (String, String, Json?) -> (Int, Json)

///|
/// Exact infrastructure identity, never an entire namespace exemption.
pub(all) struct InfrastructurePod {
  namespace_name : String
  service_account : String
  label_key : String
  label_value : String
} derive(FromJson)

///|
pub extend InfrastructurePod with FromJson::{from_json}

///|
pub(all) enum ObservedState {
  Exclusive
  Released
} derive(Debug, Eq)

///|
pub extend ObservedState with Debug::{to_repr}

///|
pub extend ObservedState with Eq::{equal, not_equal}

///|
pub(all) suberror ReservationHostError {
  InvalidConfiguration
  InvalidObservation
  ApiUnavailable
  NodeOccupied
  ReservationConflict
} derive(Debug, Eq)

///|
pub extend ReservationHostError with Debug::{to_repr}

///|
pub extend ReservationHostError with Eq::{equal, not_equal}

///|
pub struct ReservationHost {
  transport : Transport
  workload_namespaces : Array[String]
  infrastructure : Array[InfrastructurePod]
}

///|
pub fn ReservationHost::new(
  transport : Transport,
  workload_namespace : String,
  infrastructure : Array[InfrastructurePod],
  workload_namespaces? : Array[String],
) -> ReservationHost raise ReservationHostError {
  let namespaces = workload_namespaces.unwrap_or([workload_namespace])
  if namespaces.is_empty() ||
    namespaces.any(value => !resource_name(value)) ||
    infrastructure.any(rule => {
      !resource_name(rule.namespace_name) ||
      !resource_name(rule.service_account) ||
      rule.label_key == "" ||
      rule.label_value == "" ||
      namespaces.contains(rule.namespace_name)
    }) {
    raise InvalidConfiguration
  }
  {
    transport,
    workload_namespaces: namespaces.copy(),
    infrastructure: infrastructure.copy(),
  }
}

///|
fn resource_name(value : String) -> Bool {
  value != "" &&
  value.length() <= 253 &&
  value.all(c => {
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.'
  })
}

///|
async fn ReservationHost::request(
  self : ReservationHost,
  verb : String,
  path : String,
  body : Json?,
) -> Json {
  let (status, value) = (self.transport)(verb, path, body)
  if status == 409 || status == 422 {
    raise ReservationConflict
  }
  if status < 200 || status >= 300 {
    raise ApiUnavailable
  }
  value
}

///|
fn ReservationHost::infrastructure_pod(
  self : ReservationHost,
  pod : Json,
) -> Bool {
  guard pod
    is {
      "metadata": {
        "namespace": String(namespace_name),
        "labels": Object(labels),
        ..
      },
      "spec": { "serviceAccountName": String(service_account), .. },
      ..
    } else {
    return false
  }
  self.infrastructure.any(rule => {
    rule.namespace_name == namespace_name &&
    rule.service_account == service_account &&
    labels.get(rule.label_key) == Some(rule.label_value.to_json())
  })
}

///|
async fn ReservationHost::check_pods(
  self : ReservationHost,
  node : String,
  reservation : String,
  releasing : Bool,
) -> Unit {
  let response = self.request(
    "GET",
    "/api/v1/pods?fieldSelector=spec.nodeName%3D\{node}",
    None,
  )
  guard response is { "items": Array(pods), .. } else {
    raise InvalidObservation
  }
  if response is { "metadata": { "continue": String(cursor), .. }, .. } &&
    cursor != "" {
    raise InvalidObservation
  }
  for pod in pods {
    guard pod is { "spec": { "nodeName": String(actual_node), .. }, .. } &&
      actual_node == node else {
      raise InvalidObservation
    }
    if self.infrastructure_pod(pod) {
      continue
    }
    if pod is { "status": { "phase": String("Succeeded" | "Failed"), .. }, .. } {
      continue
    }
    if !releasing &&
      pod
      is {
        "metadata": {
          "namespace": String(namespace_name),
          "labels": { "lunanexa.io/reservation": String(owner), .. },
          ..
        },
        ..
      } &&
      self.workload_namespaces.contains(namespace_name) &&
      owner == reservation {
      continue
    }
    raise NodeOccupied
  }
}

///|
/// Establish and re-observe scheduling exclusion. Partial multi-node failures
/// intentionally leave acquired taints in place for controller reconciliation.
pub async fn ReservationHost::reserve(
  self : ReservationHost,
  node : String,
  reservation : String,
) -> ObservedState {
  self.reconcile(node, reservation, false)
}

///|
/// This does not delete workloads or data. Running or terminating customer
/// pods must disappear (or become terminal) before the taint can be removed.
pub async fn ReservationHost::release(
  self : ReservationHost,
  node : String,
  reservation : String,
) -> ObservedState {
  self.reconcile(node, reservation, true)
}

///|
async fn ReservationHost::reconcile(
  self : ReservationHost,
  node : String,
  reservation : String,
  releasing : Bool,
) -> ObservedState {
  if !resource_name(node) ||
    !resource_name(reservation) ||
    reservation.length() > 63 {
    raise InvalidConfiguration
  }
  let path = "/api/v1/nodes/\{node}"
  let current = self.request("GET", path, None)
  guard current
    is {
      "metadata": {
        "name": String(name),
        "resourceVersion": String(version),
        ..
      },
      "spec": Object(spec),
      ..
    } &&
    name == node else {
    raise InvalidObservation
  }
  let taints = match spec.get("taints") {
    None | Some(Null) => []
    Some(Array(values)) => values
    _ => raise InvalidObservation
  }
  let preserved : Array[Json] = []
  let mut owned = false
  for taint in taints {
    guard taint is { "key": String(key), .. } else { raise InvalidObservation }
    if key == "lunanexa.io/reservation" {
      guard taint
        is { "value": String(owner), "effect": String("NoSchedule"), .. } &&
        owner == reservation &&
        !owned else {
        raise ReservationConflict
      }
      owned = true
    } else {
      preserved.push(taint)
    }
  }
  self.check_pods(node, reservation, releasing)
  if owned != !releasing {
    if !releasing {
      preserved.push({
        "key": "lunanexa.io/reservation",
        "value": reservation,
        "effect": "NoSchedule",
      })
    }
    ignore(
      self.request(
        "PATCH",
        path,
        Some([
          {
            "op": "test",
            "path": "/metadata/resourceVersion",
            "value": version,
          },
          { "op": "add", "path": "/spec/taints", "value": preserved.to_json() },
        ]),
      ),
    )
  }
  self.check_pods(node, reservation, releasing)
  let observed = self.request("GET", path, None)
  let present = match observed {
    {
      "metadata": { "name": String(actual), .. },
      "spec": { "taints": Array(values), .. },
      ..
    } if actual == node => {
      for value in values {
        if value is { "key": String("lunanexa.io/reservation"), .. } &&
          !(value
          is { "value": String(owner), "effect": String("NoSchedule"), .. } &&
          owner == reservation) {
          raise ReservationConflict
        }
      }
      values.any(value => {
        value is { "key": String("lunanexa.io/reservation"), .. }
      })
    }
    { "metadata": { "name": String(actual), .. }, "spec": Object(fields), .. } if actual ==
      node &&
      fields.get("taints") is None => false
    _ => raise InvalidObservation
  }
  if present != !releasing {
    raise ReservationConflict
  }
  if releasing {
    Released
  } else {
    Exclusive
  }
}
