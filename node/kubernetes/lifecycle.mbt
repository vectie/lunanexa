///|
pub(all) suberror LifecycleError {
  ApiRejected(Int)
  InvalidResource
  OwnershipConflict
  LeaseExpired
} derive(Debug, Eq)

///|
/// Transport implementations must authenticate the API server, bound response
/// sizes and deadlines, and never include Kubernetes response bodies in errors.
pub type Transport = async (String, String, Json?) -> (Int, Json)

///|
pub struct PodManager {
  transport : Transport
  namespace_name : String
}

///|
fn dns_label(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 63 &&
  !value.has_prefix("-") &&
  !value.has_suffix("-") &&
  value.all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')
}

///|
pub fn PodManager::new(
  namespace_name : String,
  transport : Transport,
) -> PodManager raise LifecycleError {
  if !dns_label(namespace_name) {
    raise InvalidResource
  }
  { namespace_name, transport, }
}

///|
fn PodManager::path(
  self : PodManager,
  name : String,
) -> String raise LifecycleError {
  if !dns_label(name) {
    raise InvalidResource
  }
  "/api/v1/namespaces/\{self.namespace_name}/pods/\{name}"
}

///|
/// Create, never patch or adopt, a Pod. A conflict requires reconciliation with
/// an already persisted UID; a same-name resource is not ownership evidence.
/// The caller must persist the returned UID before reporting the runtime ready.
pub async fn PodManager::create(self : PodManager, resource : Json) -> String {
  guard resource
    is {
      "apiVersion": "v1",
      "kind": "Pod",
      "metadata": {
        "namespace": String(namespace_name),
        "name": String(name),
        "labels": { "app.kubernetes.io/managed-by": "lunanexa-node", .. },
        ..
      },
      ..
    } &&
    namespace_name == self.namespace_name else {
    raise LifecycleError::InvalidResource
  }
  ignore(self.path(name))
  let (status, response) = (self.transport)(
    "POST",
    "/api/v1/namespaces/\{self.namespace_name}/pods",
    Some(resource),
  )
  if status == 409 {
    raise LifecycleError::OwnershipConflict
  }
  if status != 201 {
    raise LifecycleError::ApiRejected(status)
  }
  guard response
    is {
      "metadata": {
        "namespace": String(actual_namespace),
        "name": String(actual_name),
        "uid": String(uid),
        ..
      },
      ..
    } &&
    actual_namespace == namespace_name &&
    actual_name == name &&
    uid != "" else {
    raise LifecycleError::InvalidResource
  }
  uid
}

///|
/// A missing known Pod is stopped, not ready. Other API failures remain errors
/// so a controller outage cannot silently be interpreted as successful cleanup.
pub async fn PodManager::observe(
  self : PodManager,
  expected : PodIdentity,
) -> @contracts.DeploymentState {
  if expected.namespace_name != self.namespace_name || expected.uid == "" {
    raise LifecycleError::InvalidResource
  }
  let (status, response) = (self.transport)(
    "GET",
    self.path(expected.pod_name),
    None,
  )
  if status == 404 {
    return Stopped
  }
  if status != 200 {
    raise LifecycleError::ApiRejected(status)
  }
  observe_pod(expected, response)
}

///|
/// Conditional deletion cannot remove a replacement Pod, even if deletion
/// races with another actor. Accepted deletion is Draining until a later GET
/// proves absence; this method deliberately does not report Stopped.
pub async fn PodManager::stop(
  self : PodManager,
  expected : PodIdentity,
) -> @contracts.DeploymentState {
  if expected.namespace_name != self.namespace_name || expected.uid == "" {
    raise LifecycleError::InvalidResource
  }
  let body : Json = {
    "apiVersion": "v1",
    "kind": "DeleteOptions",
    "preconditions": { "uid": expected.uid.to_json() },
    "propagationPolicy": "Foreground",
  }
  let (status, _) = (self.transport)(
    "DELETE",
    self.path(expected.pod_name),
    Some(body),
  )
  match status {
    404 => Stopped
    200 | 202 => Draining
    409 => raise LifecycleError::OwnershipConflict
    _ => raise LifecycleError::ApiRejected(status)
  }
}
