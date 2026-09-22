///|
/// Internal placement resolved by the controller from a live whole-node
/// reservation. Never populate this record from customer-selected node names.
pub(all) struct ExclusivePlacement {
  reservation_id : String
  tenant_ref : String
  organization_id : String
  project_id : String
  node_name : String
} derive(FromJson, ToJson, Eq, Debug)

///|
pub extend ExclusivePlacement with FromJson::{from_json}

///|
pub extend ExclusivePlacement with ToJson::{to_json}

///|
pub extend ExclusivePlacement with Eq::{equal, not_equal}

///|
pub extend ExclusivePlacement with Debug::{to_repr}

///|
/// Deployment-owned pinned HTTP/WebSocket terminal or editor adapter.
/// The adapter runs as UID 1000; its HOME and work directory are persistent.
pub(all) struct ExclusiveContainer {
  image : String
  command : Array[String]
  args : Array[String]
  port : Int
  cpu_millis : Int
  memory_mib : Int
  gpu : Bool
} derive(FromJson, ToJson, Eq, Debug)

///|
pub extend ExclusiveContainer with FromJson::{from_json}

///|
pub extend ExclusiveContainer with ToJson::{to_json}

///|
pub extend ExclusiveContainer with Eq::{equal, not_equal}

///|
pub extend ExclusiveContainer with Debug::{to_repr}

///|
fn WorkspaceHost::place_exclusive(
  _self : WorkspaceHost,
  deployment : Json,
  grant : @webide.Grant,
  placement : ExclusivePlacement,
  runtime : ExclusiveContainer?,
) -> Unit raise HostError {
  if placement.tenant_ref != grant.tenant_ref ||
    placement.organization_id != grant.organization_id ||
    placement.project_id != grant.project_id ||
    !dns_label(placement.reservation_id) ||
    !dns_label(placement.node_name) {
    raise ControllerRejected
  }
  guard deployment is Object(root) &&
    root.get("spec") is Some(Object(spec)) &&
    spec.get("template") is Some(Object(template)) &&
    template.get("metadata") is Some(Object(meta)) &&
    template.get("spec") is Some(Object(pod)) else {
    raise InvalidConfiguration
  }
  if meta.get("labels") is Some(Object(labels)) {
    labels["lunanexa.io/reservation"] = placement.reservation_id.to_json()
  }
  pod["nodeSelector"] = { "kubernetes.io/hostname": placement.node_name }
  pod["tolerations"] = [
    {
      "key": "lunanexa.io/reservation",
      "operator": "Equal",
      "value": placement.reservation_id,
      "effect": "NoSchedule",
    },
  ]
  if runtime is Some(container) {
    pod["initContainers"] = []
    if !pinned_image(container.image) ||
      container.port < 1024 ||
      container.port > 65535 ||
      container.cpu_millis < 100 ||
      container.memory_mib < 512 ||
      container.command.is_empty() {
      raise InvalidConfiguration
    }
    let limits : Map[String, Json] = {
      "cpu": "\{container.cpu_millis}m".to_json(),
      "memory": "\{container.memory_mib}Mi".to_json(),
    }
    if container.gpu {
      limits["nvidia.com/gpu"] = (1).to_json()
    }
    let app : Json = {
      "name": "workspace",
      "image": container.image,
      "imagePullPolicy": "IfNotPresent",
      "command": container.command,
      "args": container.args,
      "workingDir": "/workspace",
      "env": [{ "name": "HOME", "value": "/workspace" }],
      "securityContext": security_context(),
      "resources": { "requests": limits.to_json(), "limits": limits.to_json() },
      "volumeMounts": [
        { "name": "workspace", "mountPath": "/workspace" },
        { "name": "tmp", "mountPath": "/tmp" },
      ],
      "ports": [{ "name": "workspace", "containerPort": container.port }],
      "readinessProbe": {
        "httpGet": { "path": "/", "port": container.port },
        "periodSeconds": 5,
      },
    }
    guard pod.get("containers") is Some(Array(containers)) else {
      raise InvalidConfiguration
    }
    // Keep only the platform model proxy alongside the customer adapter.
    pod["containers"] = [
      app,
      ..containers.filter(value => {
        value is { "name": String("model-proxy"), .. }
      }),
    ].to_json()
    if container.gpu {
      pod["runtimeClassName"] = "nvidia"
    }
  }
}

///|
/// Stop this workspace only; retain its PVC for reopen/rebuild. The reservation
/// owner must wait for this call before making the node available again.
pub async fn WorkspaceHost::stop(self : WorkspaceHost, id : String) -> Unit {
  let name = resource_name(id)
  let lock = self.workspace_lock(name)
  lock.acquire()
  defer lock.release()
  self.scale_down(name)
  if self.require_exclusive {
    self.report_delivery_stopped(id)
  }
}
