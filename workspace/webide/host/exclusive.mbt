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
  self : WorkspaceHost,
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
    self.place_container(deployment, grant, container)
  }
}

///|
/// A hosted personal application has its own pod and PVC but does not need a
/// whole-GPU reservation. Exclusive delivery applies placement separately.
fn WorkspaceHost::place_container(
  self : WorkspaceHost,
  deployment : Json,
  grant : @webide.Grant,
  container : ExclusiveContainer,
) -> Unit raise HostError {
  guard deployment is Object(root) &&
    root.get("spec") is Some(Object(spec)) &&
    spec.get("template") is Some(Object(template)) &&
    template.get("spec") is Some(Object(pod)) else {
    raise InvalidConfiguration
  }
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
  let app_env : Array[Json] = [
    { "name": "HOME", "value": "/workspace" },
    { "name": "MOONSUITE_WORKSPACE_ROOT", "value": "/workspace" },
  ]
  let private_mounts : Array[Json] = []
  let private_env : Array[Json] = []
  if grant.client_id == "desktop-workspace" {
    // MoonDesk verifies the MoonClaw PID recorded in its shared workspace.
    // These companion containers belong to one user's isolated pod.
    pod["shareProcessNamespace"] = true
    let name = resource_name(@webide.workspace_id(grant))
    app_env.push({
      "name": "MOONDESK_ALLOWED_HOSTS",
      "value": "\{name}.\{self.config.namespace_name}.svc.cluster.local:8188",
    })
    app_env.push({ "name": "MOONDESK_PUBLIC_SCHEME", "value": "http" })
    app_env.push({ "name": "MOONDESK_WORKSPACE_ROOT", "value": "/workspace" })
    app_env.push({
      "name": "MOONDESK_TRUSTED_WORKSPACE_GATEWAY",
      "value": "true",
    })
    app_env.push({
      "name": "MOONDESK_RUNTIME_ROOT",
      "value": "/workspace/.runtime",
    })
    private_env.push({
      "name": "LEPUSA_APP_DATA_DIR",
      "value": "/run/moondesk-private",
    })
    private_env.push({
      "name": "MOONDESK_EXECUTION_SANDBOX_CONFIG",
      "value": "/run/moondesk-private/control/execution-sandbox/config.json",
    })
    for entry in private_env {
      app_env.push(entry)
    }
    private_mounts.push({
      "name": "moondesk-private",
      "mountPath": "/run/moondesk-private",
    })
    guard pod.get("volumes") is Some(Array(volumes)) else {
      raise InvalidConfiguration
    }
    volumes.push({
      "name": "moondesk-private",
      "emptyDir": { "sizeLimit": "16Mi" },
    })
    volumes.push({
      "name": "moondesk-control-source",
      "secret": {
        "secretName": name,
        "defaultMode": 288,
        "items": [{ "key": "moondesk-control.json", "path": "config.json" }],
      },
    })
    pod["initContainers"] = [
      {
        "name": "initialize-desktop-control",
        "image": container.image,
        "imagePullPolicy": "IfNotPresent",
        "command": ["/bin/sh", "-ec"],
        "args": [
          "install -d -m 700 /run/moondesk-private/control/execution-sandbox && install -m 600 /run/moondesk-secret/config.json /run/moondesk-private/control/execution-sandbox/config.json",
        ],
        "securityContext": security_context(),
        "resources": {
          "requests": { "cpu": "50m", "memory": "64Mi" },
          "limits": { "cpu": "500m", "memory": "128Mi" },
        },
        "volumeMounts": [
          ..private_mounts,
          {
            "name": "moondesk-control-source",
            "mountPath": "/run/moondesk-secret",
            "readOnly": true,
          },
        ],
      },
    ]
  }
  let app : Json = {
    "name": "workspace",
    "image": container.image,
    "imagePullPolicy": "IfNotPresent",
    "command": container.command,
    "args": container.args,
    "workingDir": "/workspace",
    "env": app_env,
    "securityContext": security_context(),
    "resources": { "requests": limits.to_json(), "limits": limits.to_json() },
    "volumeMounts": [
      { "name": "workspace", "mountPath": "/workspace" },
      { "name": "tmp", "mountPath": "/tmp" },
      ..private_mounts,
    ],
    "ports": [{ "name": "workspace", "containerPort": container.port }],
    "readinessProbe": {
      "exec": {
        "command": [
          "/usr/bin/bash",
          "-c",
          "exec 3<>/dev/tcp/127.0.0.1/" + container.port.to_string(),
        ],
      },
      "periodSeconds": 5,
    },
  }
  guard pod.get("containers") is Some(Array(containers)) else {
    raise InvalidConfiguration
  }
  // Keep only the platform model proxy alongside the customer adapter.
  let platform_containers = containers.filter(value => {
    value is { "name": String("model-proxy"), .. }
  })
  for platform_container in platform_containers {
    if platform_container is Object(fields) {
      // The proxy intentionally listens only on pod loopback. Kubelet HTTP
      // probes target the pod IP and can never reach that listener.
      fields.remove("readinessProbe")
    }
  }
  let tenant_runtime : Array[Json] = if grant.client_id == "desktop-workspace" {
    let token_env : Json = {
      "name": "MOONGATE_CONTROL_TOKEN",
      "valueFrom": {
        "secretKeyRef": {
          "name": resource_name(@webide.workspace_id(grant)),
          "key": "moongate-control-token",
        },
      },
    }
    [
      {
        "name": "moongate",
        "image": container.image,
        "imagePullPolicy": "IfNotPresent",
        "command": ["/usr/local/bin/moongate"],
        "args": ["start", "--host", "127.0.0.1", "--port", "15721"],
        "workingDir": "/workspace",
        "env": [
          { "name": "HOME", "value": "/workspace" },
          { "name": "MOONSUITE_WORKSPACE_ROOT", "value": "/workspace" },
          token_env,
        ],
        "securityContext": security_context(),
        "resources": {
          "requests": { "cpu": "100m", "memory": "256Mi" },
          "limits": { "cpu": "1000m", "memory": "1024Mi" },
        },
        "volumeMounts": [
          { "name": "workspace", "mountPath": "/workspace" },
          { "name": "tmp", "mountPath": "/tmp" },
        ],
        "readinessProbe": {
          "exec": {
            "command": [
              "/usr/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/15721",
            ],
          },
          "periodSeconds": 5,
        },
      },
      {
        "name": "moonclaw",
        "image": container.image,
        "imagePullPolicy": "IfNotPresent",
        "command": ["/usr/local/bin/moonclaw"],
        "args": ["daemon", "--port", "8090", "--serve", "/workspace"],
        "workingDir": "/workspace",
        "env": [
          { "name": "HOME", "value": "/workspace" },
          { "name": "MOONSUITE_WORKSPACE_ROOT", "value": "/workspace" },
          {
            "name": "MOONCLAW_HOSTED_MODEL_ALIAS",
            "value": grant.allowed_models.get(0).unwrap_or(""),
          },
          token_env,
          ..private_env,
        ],
        "securityContext": security_context(),
        "resources": {
          "requests": { "cpu": "200m", "memory": "512Mi" },
          "limits": { "cpu": "2000m", "memory": "2048Mi" },
        },
        "volumeMounts": [
          { "name": "workspace", "mountPath": "/workspace" },
          { "name": "tmp", "mountPath": "/tmp" },
          ..private_mounts,
        ],
        "readinessProbe": {
          "exec": {
            "command": [
              "/usr/bin/bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8090",
            ],
          },
          "periodSeconds": 5,
        },
      },
    ]
  } else {
    []
  }
  pod["containers"] = [app, ..platform_containers, ..tenant_runtime].to_json()
  if container.gpu {
    pod["runtimeClassName"] = "nvidia"
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
    self.release_storage(id)
    self.report_delivery_stopped(id)
  }
}
