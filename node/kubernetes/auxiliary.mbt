///|
pub(all) enum AuxiliaryKind {
  NetworkPolicy
  ClaimTemplate
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AuxiliaryIdentity {
  kind : AuxiliaryKind
  namespace_name : String
  name : String
  uid : String
} derive(Debug, Eq, ToJson, FromJson)

///|
fn AuxiliaryKind::collection(
  self : AuxiliaryKind,
  namespace_name : String,
) -> String {
  match self {
    NetworkPolicy =>
      "/apis/networking.k8s.io/v1/namespaces/\{namespace_name}/networkpolicies"
    ClaimTemplate =>
      "/apis/resource.k8s.io/v1/namespaces/\{namespace_name}/resourceclaimtemplates"
  }
}

///|
/// Create an immutable ancillary resource and bind its UID for later cleanup.
/// No patch, force, broad selector deletion or foreign-resource adoption.
pub async fn PodManager::create_auxiliary(
  self : PodManager,
  resource : Json,
) -> AuxiliaryIdentity {
  let kind : AuxiliaryKind = match resource {
    { "apiVersion": "networking.k8s.io/v1", "kind": "NetworkPolicy", .. } =>
      NetworkPolicy
    { "apiVersion": "resource.k8s.io/v1", "kind": "ResourceClaimTemplate", .. } =>
      ClaimTemplate
    _ => raise LifecycleError::InvalidResource
  }
  guard resource
    is {
      "metadata": {
        "namespace": String(namespace_name),
        "name": String(name),
        "labels": { "app.kubernetes.io/managed-by": "lunanexa-node", .. },
        ..
      },
      ..
    } &&
    namespace_name == self.namespace_name &&
    dns_label(name) else {
    raise LifecycleError::InvalidResource
  }
  let (status, response) = (self.transport)(
    "POST",
    kind.collection(namespace_name),
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
  { kind, namespace_name, name, uid, }
}

///|
/// Delete only a recorded resource incarnation. Keep the network policy until
/// Pod disappearance is confirmed, or shutdown could briefly reopen traffic.
pub async fn PodManager::remove_auxiliary(
  self : PodManager,
  expected : AuxiliaryIdentity,
) -> @contracts.DeploymentState {
  if expected.namespace_name != self.namespace_name ||
    expected.uid == "" ||
    !dns_label(expected.name) {
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
    expected.kind.collection(self.namespace_name) + "/" + expected.name,
    Some(body),
  )
  match status {
    404 => Stopped
    200 | 202 => Draining
    409 => raise LifecycleError::OwnershipConflict
    _ => raise LifecycleError::ApiRejected(status)
  }
}

///|
fn allowed_resource_path(path : String) -> Bool {
  let segments = path.split("/").collect()
  if segments.length() >= 6 &&
    segments.length() <= 7 &&
    segments[0] == "" &&
    segments[1] == "api" &&
    segments[2] == "v1" &&
    segments[3] == "namespaces" &&
    dns_label(segments[4].to_owned()) &&
    segments[5] == "pods" {
    return segments.length() == 6 || dns_label(segments[6].to_owned())
  }
  if segments.length() >= 7 &&
    segments.length() <= 8 &&
    segments[0] == "" &&
    segments[1] == "apis" &&
    segments[3] == "v1" &&
    segments[4] == "namespaces" &&
    dns_label(segments[5].to_owned()) &&
    (
      (segments[2] == "networking.k8s.io" && segments[6] == "networkpolicies") ||
      (
        segments[2] == "resource.k8s.io" &&
        segments[6] == "resourceclaimtemplates"
      )
    ) {
    return segments.length() == 7 || dns_label(segments[7].to_owned())
  }
  false
}
