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
  /// The extended resource a cluster exposes its GPUs through when it uses the
  /// device plugin rather than DRA, e.g. "nvidia.com/gpu". Absent means devices
  /// are allocated through the device class above.
  device_plugin_resource : String?
  /// The RuntimeClass the container runtime needs in order to hand the pod its
  /// GPUs, e.g. "nvidia". Only meaningful with `device_plugin_resource`.
  runtime_class_name : String?
  /// The namespace the controller runs in. When set, a runtime accepts traffic
  /// from that namespace by selector instead of by address, which is what makes
  /// the policy stable across controller pod restarts.
  controller_namespace : String?
  runtime_secrets : Array[RuntimeSecretBinding]?
  /// This node's own address on the private fabric between a pair. Absent on a
  /// node that is not part of one; a paired assignment on such a node is
  /// refused rather than started unable to reach its peer.
  fabric_address : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RuntimeSettings with Debug::{to_repr}

///|
pub extend RuntimeSettings with Eq::{not_equal, equal}

///|
pub extend RuntimeSettings with ToJson::{to_json}

///|
pub extend RuntimeSettings with FromJson::{from_json}

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
pub extend RuntimeResources with Debug::{to_repr}

///|
pub extend RuntimeResources with Eq::{not_equal, equal}

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
/// The member's view of its pair, or nothing when this is a single-machine
/// assignment. A paired pod is only rendered for a node that declares its own
/// fabric address: without it the two containers cannot find each other, and
/// half a pair is worse than none.
fn paired_group(
  settings : RuntimeSettings,
  assignment : @contracts.DesiredAssignment,
) -> @contracts.AssignmentGroup? raise LifecycleError {
  let group = assignment.group
  guard group is Some(group) else { return None }
  let self_address = settings.fabric_address.unwrap_or("")
  if !dns_label(group.group_id) ||
    group.rank < 0 ||
    group.rank >= group.world_size ||
    group.world_size != @contracts.cx7_pair_member_count ||
    !private_address(group.peer_endpoint) ||
    !private_address(self_address) ||
    self_address == group.peer_endpoint {
    raise InvalidResource
  }
  Some(group)
}

///|
/// An extended resource name as Kubernetes accepts it: an optional DNS
/// subdomain, a slash, and a lowercase name, e.g. "nvidia.com/gpu".
fn extended_resource_name(value : String) -> Bool {
  let parts = value.split("/").collect()
  if parts.length() != 2 {
    return false
  }
  let (domain, resource) = (parts[0].to_owned(), parts[1].to_owned())
  // The domain is a DNS subdomain, so it carries dots; each of its labels is a
  // plain DNS label.
  domain.length() <= 253 &&
  domain.split(".").all(label => dns_label(label.to_owned())) &&
  resource != "" &&
  resource.length() <= 63 &&
  resource.all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '.' ||
    c == '_'
  }) &&
  !resource.has_prefix("-") &&
  !resource.has_suffix("-")
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
    (
      settings.controller_addresses.is_empty() &&
      settings.controller_namespace is None
    ) ||
    !settings.controller_addresses.all(private_address) ||
    (settings.controller_namespace is Some(name) && !dns_label(name)) ||
    (
      settings.device_plugin_resource is Some(resource) &&
      !extended_resource_name(resource)
    ) ||
    (settings.runtime_class_name is Some(name) && !dns_label(name)) ||
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
  let group = paired_group(settings, assignment)
  let paired = group is Some(_)
  // Two ways a cluster can hand a pod its GPUs, and they are mutually
  // exclusive. DRA allocates an exact device through a device class, which is
  // what the selectors below pin. The device plugin instead counts extended
  // resources, so the exact device is pinned through the environment the
  // container runtime reads -- see the container's NVIDIA_VISIBLE_DEVICES.
  let device_plugin = settings.device_plugin_resource
  let requests : Array[Json] = if device_plugin is Some(_) {
    []
  } else {
    [
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
  }
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
  if device_plugin is Some(resource) &&
    assignment.resources.accelerator_count > 0 {
    // The device plugin allocates by count of an extended resource, which is
    // the only thing the scheduler can see. `devices` still decides which
    // physical GPUs the container may open, through NVIDIA_VISIBLE_DEVICES.
    guard limits is Object(fields) else { raise InvalidResource }
    fields[resource] = assignment.resources.accelerator_count.to_json()
  }
  let volumes : Array[Json] = [
    {
      "name": "model",
      "hostPath": { "path": artifact_path.to_json(), "type": "File" },
    },
  ]
  let mounts : Array[Json] = [
    {
      "name": "model",
      "mountPath": "/var/lib/lunanexa/model/model",
      "readOnly": true,
    },
  ]
  let added_capabilities : Array[String] = []
  // Half of a TP group is not isolated from its peer: it must reach the peer's
  // private-fabric address on the same port, so the peer is named explicitly
  // rather than the policy being dropped.
  let peer_rules : Array[Json] = []
  if group is Some(group) {
    volumes.push({
      "name": "infiniband",
      "hostPath": { "path": "/dev/infiniband" },
    })
    volumes.push({ "name": "shm", "emptyDir": { "medium": "Memory" } })
    mounts.push({ "name": "infiniband", "mountPath": "/dev/infiniband" })
    mounts.push({ "name": "shm", "mountPath": "/dev/shm" })
    // Registering the GPU buffers that NCcl hands to the HCA needs the locked
    // memory allowance, which is what this capability grants the runtime.
    added_capabilities.push("IPC_LOCK")
    peer_rules.push({
      "ipBlock": { "cidr": (group.peer_endpoint + "/32").to_json() },
    })
  }
  let pod : Json = {
    "apiVersion": "v1",
    "kind": "Pod",
    "metadata": resource_metadata,
    "spec": {
      "automountServiceAccountToken": false,
      "hostNetwork": paired,
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
            "capabilities": {
              "drop": ["ALL"],
              "add": added_capabilities.to_json(),
            },
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
          "volumeMounts": mounts.to_json(),
        },
      ],
      "volumes": volumes.to_json(),
    },
  }
  if paired {
    // A host-networked pod that cannot resolve cluster DNS cannot reach the
    // controller it takes its lease from.
    match pod {
      Object(root) =>
        match root.get("spec") {
          Some(Object(spec)) =>
            spec["dnsPolicy"] = "ClusterFirstWithHostNet".to_json()
          _ => raise InvalidResource
        }
      _ => raise InvalidResource
    }
  }
  if settings.runtime_class_name is Some(runtime_class) {
    // Which handler the container runtime uses to hand the pod its GPUs is a
    // host fact: this cluster exposes them through the `nvidia` RuntimeClass,
    // and a pod that asks for a GPU without it never gets the device nodes.
    match pod {
      Object(root) =>
        match root.get("spec") {
          Some(Object(spec)) =>
            spec["runtimeClassName"] = runtime_class.to_json()
          _ => raise InvalidResource
        }
      _ => raise InvalidResource
    }
  }
  let peers : Array[Json] = [
    for address in settings.controller_addresses => {
      { "ipBlock": { "cidr": (address + "/32").to_json() } }
    }
  ]
  let policy_peers : Array[Json] = []
  // A namespace peer outlives the controller pod that happens to be running
  // now, which is the whole reason to prefer it to an address.
  if settings.controller_namespace is Some(namespace_name) {
    policy_peers.push({
      "namespaceSelector": {
        "matchLabels": {
          "kubernetes.io/metadata.name": namespace_name.to_json(),
        },
      },
    })
  }
  for peer in peers {
    policy_peers.push(peer)
  }
  for peer in peer_rules {
    policy_peers.push(peer)
  }
  let egress_rules : Array[Json] = []
  if paired {
    // Rank coordination is the only thing this member is allowed to open.
    egress_rules.push({
      "to": peer_rules.to_json(),
      "ports": [{ "protocol": "TCP", "port": settings.runtime_port.to_json() }],
    })
  }
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
          "from": policy_peers.to_json(),
          "ports": [
            { "protocol": "TCP", "port": settings.runtime_port.to_json() },
          ],
        },
      ],
      "egress": egress_rules.to_json(),
    },
  }
  { name, pod, claim_template, network_policy, }
}
