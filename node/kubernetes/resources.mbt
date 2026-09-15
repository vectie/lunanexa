///|
/// Deployment-owned settings, not fields accepted from an inference client.
pub(all) struct RuntimeSettings {
  namespace_name : String
  node_name : String
  node_id : String
  model_cache_root : String
  runtime_port : Int
  run_as_user : Int
  device_class_name : String
  controller_addresses : Array[String]
  runtime_secrets : Array[RuntimeSecretBinding]?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Resources must be installed in order: network policy, claim template, Pod.
/// Artifact verification and assignment signature verification precede rendering.
pub(all) struct RuntimeResources {
  name : String
  pod : Json
  claim_template : Json?
  network_policy : Json
} derive(Debug, Eq)

///|
fn safe_path(value : String) -> Bool {
  value.length() > 1 &&
  value.length() <= 4096 &&
  value.has_prefix("/") &&
  !value.has_suffix("/") &&
  !value.contains("//") &&
  value.split("/").all(part => part != "." && part != "..") &&
  value.all(c => c >= ' ' && c != '\u{7f}')
}

///|
fn private_address(value : String) -> Bool {
  let parts = value.split(".").collect()
  if parts.length() != 4 {
    return false
  }
  let numbers : Array[Int] = []
  for part in parts {
    let number = @string.parse_int(part) catch { _ => return false }
    if number < 0 || number > 255 || number.to_string() != part.to_owned() {
      return false
    }
    numbers.push(number)
  }
  numbers[0] == 10 ||
  (numbers[0] == 192 && numbers[1] == 168) ||
  (numbers[0] == 172 && numbers[1] >= 16 && numbers[1] <= 31)
}

///|
fn gpu_uuid(value : String) -> Bool {
  if value.length() != 40 || !value.has_prefix("GPU-") {
    return false
  }
  let groups = value[4:].split("-").collect()
  if groups.length() != 5 {
    return false
  }
  let lengths = [8, 4, 4, 4, 12]
  for i, group in groups {
    if group.length() != lengths[i] ||
      !group
      .to_owned()
      .all(c => {
        (c >= '0' && c <= '9') ||
        (c >= 'a' && c <= 'f') ||
        (c >= 'A' && c <= 'F')
      }) {
      return false
    }
  }
  true
}

///|
fn metadata(
  settings : RuntimeSettings,
  assignment : @contracts.DesiredAssignment,
  name : String,
) -> Json {
  {
    "namespace": settings.namespace_name.to_json(),
    "name": name.to_json(),
    "labels": {
      "app.kubernetes.io/managed-by": "lunanexa-node",
      "lunanexa.io/assignment": assignment.assignment_id.to_json(),
      "lunanexa.io/runtime": name.to_json(),
    },
    "annotations": {
      "lunanexa.io/generation": assignment.generation.to_string().to_json(),
      "lunanexa.io/controller-epoch": assignment.controller_epoch
      .to_string()
      .to_json(),
      "lunanexa.io/artifact-digest": assignment.artifact.digest.to_json(),
      "lunanexa.io/lease-expires-unix-ms": assignment.lease_expires_unix_ms
      .to_string()
      .to_json(),
    },
  }
}

///|
/// Render only a previously verified signed assignment and materialized blob.
/// CPU-only assignments are represented honestly with zero accelerators, not
/// fabricated GPU inventory. This function does not verify signatures or files.
pub fn render_runtime(
  settings : RuntimeSettings,
  assignment : @contracts.DesiredAssignment,
  artifact_path : String,
  verified_digest : String,
  verified_size : Int64,
  now_unix_ms : Int64,
) -> RuntimeResources raise LifecycleError {
  if !dns_label(settings.namespace_name) ||
    !dns_label(settings.node_name) ||
    settings.node_id != assignment.node_id ||
    !safe_path(settings.model_cache_root) ||
    !safe_path(artifact_path) ||
    !artifact_path.has_prefix(settings.model_cache_root + "/") ||
    settings.runtime_port < 1 ||
    settings.runtime_port > 65535 ||
    settings.run_as_user < 1 ||
    settings.device_class_name != "gpu.nvidia.com" ||
    settings.controller_addresses.is_empty() ||
    !settings.controller_addresses.all(private_address) ||
    !dns_label(assignment.assignment_id) ||
    assignment.signature == "" ||
    assignment.generation < 0L ||
    assignment.controller_epoch < 0L ||
    assignment.lease_expires_unix_ms <= now_unix_ms ||
    now_unix_ms < 0L ||
    !@contracts.valid_sha256_digest(assignment.artifact.digest) ||
    !@contracts.valid_sha256_digest(assignment.runtime.image_digest) ||
    verified_digest != assignment.artifact.digest ||
    verified_size <= 0L ||
    verified_size != assignment.artifact.size_bytes ||
    assignment.runtime.name == "" ||
    assignment.runtime.name.contains("@") ||
    !assignment.runtime.name.all(c => c > ' ' && c < '\u{7f}') ||
    assignment.resources.cpu_millis <= 0 ||
    assignment.resources.memory_mib <= 0 ||
    assignment.resources.accelerator_count < 0 ||
    assignment.resources.accelerator_count != assignment.devices.length() ||
    (
      assignment.resources.accelerator_count > 0 &&
      assignment.resources.accelerator_memory_mib <= 0
    ) ||
    !assignment.devices.all(gpu_uuid) ||
    assignment.network.allowed_egress.length() > 0 ||
    !assignment.health.readiness_path.has_prefix("/") ||
    assignment.health.readiness_path.has_prefix("//") ||
    assignment.health.readiness_path.contains("?") ||
    !assignment.health.readiness_path.all(c => c >= '!' && c <= '~') ||
    assignment.health.interval_ms < 1000 ||
    assignment.health.failure_threshold < 1 ||
    assignment.health.termination_grace_ms < 0 {
    raise InvalidResource
  }
  let seen : Map[String, Bool] = Map([])
  for device in assignment.devices {
    if seen.contains(device) {
      raise InvalidResource
    }
    seen[device] = true
  }
  let hash = @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode(
        assignment.assignment_id +
        ":" +
        assignment.generation.to_string() +
        ":" +
        assignment.controller_epoch.to_string(),
      ),
    ),
  )
  let name = "lunanexa-" + hash[:40].to_owned()
  let resource_metadata = metadata(settings, assignment, name)
  let requests : Array[Json] = [
    for i, device in assignment.devices => {
      {
        "name": ("gpu-" + i.to_string()).to_json(),
        "exactly": {
          "deviceClassName": settings.device_class_name.to_json(),
          "allocationMode": "ExactCount",
          "count": 1,
          "selectors": [
            {
              "cel": {
                "expression": ("device.driver == 'gpu.nvidia.com' && device.attributes['gpu.nvidia.com'].uuid == '" +
                device +
                "' && device.capacity['gpu.nvidia.com'].memory.compareTo(quantity('" +
                assignment.resources.accelerator_memory_mib.to_string() +
                "Mi')) >= 0").to_json(),
              },
            },
          ],
        },
      }
    }
  ]
  let claim_template : Json? = if requests.is_empty() {
    None
  } else {
    Some({
      "apiVersion": "resource.k8s.io/v1",
      "kind": "ResourceClaimTemplate",
      "metadata": resource_metadata,
      "spec": { "spec": { "devices": { "requests": requests.to_json() } } },
    })
  }
  let claims : Array[Json] = if requests.is_empty() {
    []
  } else {
    [{ "name": "accelerators" }]
  }
  let pod_claims : Array[Json] = if requests.is_empty() {
    []
  } else {
    [{ "name": "accelerators", "resourceClaimTemplateName": name.to_json() }]
  }
  let limits : Json = {
    "cpu": canonical_cpu_quantity(assignment.resources.cpu_millis).to_json(),
    "memory": canonical_memory_quantity(assignment.resources.memory_mib).to_json(),
  }
  let pod : Json = {
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": resource_metadata,
    "spec": {
      "automountServiceAccountToken": false,
      "hostNetwork": false,
      "hostPID": false,
      "hostIPC": false,
      "enableServiceLinks": false,
      "restartPolicy": "Never",
      "terminationGracePeriodSeconds": (assignment.health.termination_grace_ms /
      1000).to_json(),
      "affinity": {
        "nodeAffinity": {
          "requiredDuringSchedulingIgnoredDuringExecution": {
            "nodeSelectorTerms": [
              {
                "matchFields": [
                  {
                    "key": "metadata.name",
                    "operator": "In",
                    "values": [settings.node_name.to_json()],
                  },
                ],
              },
            ],
          },
        },
      },
      "tolerations": [
        {
          "key": "lunanexa.io/role",
          "operator": "Equal",
          "value": "gpu",
          "effect": "NoSchedule",
        },
        {
          "key": "node.kubernetes.io/not-ready",
          "operator": "Exists",
          "effect": "NoExecute",
          "tolerationSeconds": 300,
        },
        {
          "key": "node.kubernetes.io/unreachable",
          "operator": "Exists",
          "effect": "NoExecute",
          "tolerationSeconds": 300,
        },
      ],
      "securityContext": {
        "runAsNonRoot": true,
        "runAsUser": settings.run_as_user.to_json(),
        "runAsGroup": settings.run_as_user.to_json(),
        "seccompProfile": { "type": "RuntimeDefault" },
      },
      "resourceClaims": pod_claims.to_json(),
      "containers": [
        {
          "name": "runtime",
          "image": (assignment.runtime.name +
          "@" +
          assignment.runtime.image_digest).to_json(),
          "imagePullPolicy": "IfNotPresent",
          "resources": {
            "requests": limits,
            "limits": limits,
            "claims": claims.to_json(),
          },
          "securityContext": {
            "privileged": false,
            "allowPrivilegeEscalation": false,
            "readOnlyRootFilesystem": true,
            "capabilities": { "drop": ["ALL"], "add": [] },
          },
          "ports": [
            {
              "name": "runtime",
              "containerPort": settings.runtime_port.to_json(),
            },
          ],
          "readinessProbe": {
            "httpGet": {
              "path": assignment.health.readiness_path.to_json(),
              "port": settings.runtime_port.to_json(),
            },
            "periodSeconds": (assignment.health.interval_ms / 1000).to_json(),
            "timeoutSeconds": 1,
            "failureThreshold": assignment.health.failure_threshold.to_json(),
          },
          "env": runtime_environment(settings, assignment).to_json(),
          "volumeMounts": [
            {
              "name": "model",
              "mountPath": "/var/lib/lunanexa/model/model",
              "readOnly": true,
            },
          ],
        },
      ],
      "volumes": [
        {
          "name": "model",
          "hostPath": { "path": artifact_path.to_json(), "type": "File" },
        },
      ],
    },
  }
  let peers : Array[Json] = [
    for address in settings.controller_addresses => {
      { "ipBlock": { "cidr": (address + "/32").to_json() } }
    }
  ]
  let network_policy : Json = {
    "apiVersion": "networking.k8s.io/v1",
    "kind": "NetworkPolicy",
    "metadata": resource_metadata,
    "spec": {
      "podSelector": {
        "matchLabels": { "lunanexa.io/runtime": name.to_json() },
      },
      "policyTypes": ["Ingress", "Egress"],
      "ingress": [
        {
          "from": peers.to_json(),
          "ports": [
            { "protocol": "TCP", "port": settings.runtime_port.to_json() },
          ],
        },
      ],
      "egress": [],
    },
  }
  { name, pod, claim_template, network_policy, }
}
