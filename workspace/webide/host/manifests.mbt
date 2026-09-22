///|
/// Kubernetes labels/names cannot hold the full workspace digest (71 bytes).
/// 224 retained digest bits remain an opaque stable identity, never a user name.
fn resource_name(id : String) -> String raise HostError {
  if !id.has_prefix("webide-") ||
    id.length() != 71 ||
    !id[7:].all(c => (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9')) {
    raise InvalidConfiguration
  }
  id[:63].to_owned()
}

///|
fn metadata(name : String, namespace_name : String) -> Json {
  {
    "name": name,
    "namespace": namespace_name,
    "labels": {
      "app.kubernetes.io/managed-by": "lunanexa-webide",
      "lunanexa.io/workspace": name,
    },
  }
}

///|
fn security_context() -> Json {
  {
    "allowPrivilegeEscalation": false,
    "readOnlyRootFilesystem": true,
    "capabilities": { "drop": ["ALL"] },
  }
}

///|
/// This is server-side desired state. It includes one Kubernetes Secret and
/// must never be logged, put in a browser response, or committed as live state.
fn WorkspaceHost::resources(
  self : WorkspaceHost,
  id : String,
  grant : @webide.Grant,
  placement? : ExclusivePlacement,
  container? : ExclusiveContainer,
) -> Array[(String, Json)] raise HostError {
  let name = resource_name(id)
  if container is None && grant.allowed_models.is_empty() {
    raise ControllerRejected
  }
  let config = self.config
  let meta = metadata(name, config.namespace_name)
  let storage_name = resource_name(@webide.workspace_storage_id(grant))
  if meta is Object(fields) {
    fields["annotations"] = { "lunanexa.io/workspace-id": id }
  }
  let labels : Json = { "lunanexa.io/workspace": name }
  let trust_env : Array[Json] = match config.trusted_ca_config_map {
    Some(_) =>
      [
        {
          "name": "SSL_CERT_FILE",
          "value": "/run/platform-trust/ca-bundle.crt",
        },
      ]
    None => []
  }
  let trust_mounts : Array[Json] = match config.trusted_ca_config_map {
    Some(_) =>
      [
        {
          "name": "platform-trust",
          "mountPath": "/run/platform-trust",
          "readOnly": true,
        },
      ]
    None => []
  }
  let trust_volumes : Array[Json] = match config.trusted_ca_config_map {
    Some(name) =>
      [
        {
          "name": "platform-trust",
          "configMap": {
            "name": name,
            "items": [{ "key": "ca-bundle.crt", "path": "ca-bundle.crt" }],
          },
        },
      ]
    None => []
  }
  let proxy : ModelProxyConfig = {
    delivery_id: grant.delivery_id,
    client_id: grant.client_id,
    tenant_ref: grant.tenant_ref,
    subject_ref: grant.subject_ref,
    organization_id: grant.organization_id,
    project_id: grant.project_id,
    api_secret: grant.api_secret,
    allowed_models: grant.allowed_models,
    expires_unix_ms: grant.expires_unix_ms,
    controller_origin: config.controller_origin,
    model_gateway_origin: config.model_gateway_origin,
  }
  let persistence : Json = {
    "apiVersion": "v1",
    "kind": "PersistentVolumeClaim",
    "metadata": metadata(storage_name, config.namespace_name),
    "spec": {
      "accessModes": ["ReadWriteOnce"],
      "storageClassName": config.storage_class,
      "resources": { "requests": { "storage": "\{config.storage_gib}Gi" } },
    },
  }
  let secret : Json = {
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": meta,
    "type": "Opaque",
    "stringData": { "model-proxy.json": ToJson::to_json(proxy).stringify() },
  }
  let service : Json = {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": meta,
    "spec": {
      "type": "ClusterIP",
      "selector": labels,
      "ports": [{ "name": "comfyui", "port": 8188, "targetPort": 8188 }],
    },
  }
  let deployment : Json = {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": meta,
    "spec": {
      "replicas": 1,
      "strategy": { "type": "Recreate" },
      "selector": { "matchLabels": labels },
      "template": {
        "metadata": {
          "labels": {
            "lunanexa.io/workspace": name,
            "app.kubernetes.io/managed-by": "lunanexa-webide",
          },
        },
        "spec": {
          "automountServiceAccountToken": false,
          "nodeSelector": { "lunanexa.io/workspace-host": "true" },
          "securityContext": {
            "runAsNonRoot": true,
            "runAsUser": 1000,
            "runAsGroup": 1000,
            "fsGroup": 1000,
            "seccompProfile": { "type": "RuntimeDefault" },
          },
          "initContainers": [
            {
              "name": "initialize-workspace",
              "image": config.model_proxy_image,
              "imagePullPolicy": "IfNotPresent",
              "command": ["/usr/local/bin/lunanexa-webide-model-proxy"],
              "env": [
                { "name": "LUNANEXA_WEBIDE_INITIALIZE", "value": "/workspace" },
                {
                  "name": "LUNANEXA_WEBIDE_INITIAL_MODEL",
                  "value": grant.allowed_models.get(0).unwrap_or(""),
                },
              ],
              "securityContext": security_context(),
              "resources": {
                "requests": { "cpu": "100m", "memory": "64Mi" },
                "limits": { "cpu": "500m", "memory": "128Mi" },
              },
              "volumeMounts": [
                { "name": "workspace", "mountPath": "/workspace" },
              ],
            },
          ],
          "containers": [
            {
              "name": "comfyui",
              "image": config.comfyui_image,
              "imagePullPolicy": "IfNotPresent",
              "command": ["python3", "/opt/ComfyUI/main.py"],
              "args": [
                "--cpu", "--listen", "0.0.0.0", "--port", "8188", "--disable-auto-launch",
                "--disable-api-nodes", "--disable-all-custom-nodes", "--whitelist-custom-nodes",
                "ComfyUI-vLLM-Omni", "--user-directory", "/workspace/user", "--temp-directory",
                "/tmp/comfyui", "--input-directory", "/workspace/input", "--output-directory",
                "/workspace/output", "--enable-assets", "--database-url", "sqlite:////workspace/user/comfyui.db",
              ],
              "env": [
                { "name": "PYTHONDONTWRITEBYTECODE", "value": "1" },
                { "name": "HOME", "value": "/workspace" },
              ],
              "securityContext": security_context(),
              "resources": {
                "requests": {
                  "cpu": "\{config.cpu_millis}m",
                  "memory": "\{config.memory_mib}Mi",
                },
                "limits": {
                  "cpu": "\{config.cpu_millis}m",
                  "memory": "\{config.memory_mib}Mi",
                },
              },
              "volumeMounts": [
                { "name": "workspace", "mountPath": "/workspace" },
                { "name": "tmp", "mountPath": "/tmp" },
              ],
              "readinessProbe": {
                "httpGet": { "path": "/system_stats", "port": 8188 },
                "periodSeconds": 5,
              },
              "ports": [{ "containerPort": 8188, "name": "comfyui" }],
            },
            {
              "name": "model-proxy",
              "image": config.model_proxy_image,
              "imagePullPolicy": "IfNotPresent",
              "command": ["/usr/local/bin/lunanexa-webide-model-proxy"],
              "env": [
                {
                  "name": "LUNANEXA_MODEL_PROXY_CONFIG_FILE",
                  "value": "/run/model-proxy/model-proxy.json",
                },
                ..trust_env,
              ],
              "securityContext": security_context(),
              "resources": {
                "requests": { "cpu": "100m", "memory": "128Mi" },
                "limits": { "cpu": "500m", "memory": "512Mi" },
              },
              "volumeMounts": [
                {
                  "name": "model-credential",
                  "mountPath": "/run/model-proxy",
                  "readOnly": true,
                },
                ..trust_mounts,
              ],
            },
          ],
          "volumes": [
            {
              "name": "workspace",
              "persistentVolumeClaim": { "claimName": storage_name },
            },
            { "name": "tmp", "emptyDir": { "sizeLimit": "1Gi" } },
            {
              "name": "model-credential",
              "secret": { "secretName": name, "defaultMode": 288 },
            },
            ..trust_volumes,
          ],
        },
      },
    },
  }
  if placement is Some(assigned) {
    self.place_exclusive(deployment, grant, assigned, container)
  } else if container is Some(_) {
    raise InvalidConfiguration
  }
  let service = match container {
    Some(runtime) => {
      let value = service
      if value is Object(root) && root.get("spec") is Some(Object(spec)) {
        spec["ports"] = [
          { "name": "workspace", "port": 8188, "targetPort": runtime.port },
        ]
      }
      value
    }
    None => service
  }
  // Only the authenticated gateway reaches ComfyUI. No peers, public internet,
  // Kubernetes API, node metadata or direct GPU endpoint egress is permitted.
  let network : Json = {
    "apiVersion": "networking.k8s.io/v1",
    "kind": "NetworkPolicy",
    "metadata": meta,
    "spec": {
      "podSelector": { "matchLabels": labels },
      "policyTypes": ["Ingress", "Egress"],
      "ingress": [
        {
          "from": [
            {
              "podSelector": {
                "matchLabels": {
                  "app.kubernetes.io/name": "lunanexa-webide-gateway",
                },
              },
            },
          ],
          "ports": [{ "protocol": "TCP", "port": 8188 }],
        },
      ],
      "egress": [
        {
          "to": [
            {
              "namespaceSelector": {
                "matchLabels": { "kubernetes.io/metadata.name": "kube-system" },
              },
              "podSelector": { "matchLabels": { "k8s-app": "kube-dns" } },
            },
          ],
          "ports": [
            { "protocol": "UDP", "port": 53 },
            { "protocol": "TCP", "port": 53 },
          ],
        },
        {
          "to": [
            {
              "namespaceSelector": {
                "matchLabels": {
                  "kubernetes.io/metadata.name": config.controller_namespace,
                },
              },
              "podSelector": { "matchLabels": { "app": "lunanexa-control" } },
            },
          ],
          "ports": [{ "protocol": "TCP", "port": config.controller_port }],
        },
        {
          "to": [
            {
              "namespaceSelector": {
                "matchLabels": {
                  "kubernetes.io/metadata.name": config.model_gateway_namespace,
                },
              },
              "podSelector": {
                "matchLabels": { "lunanexa.io/model-gateway": "true" },
              },
            },
          ],
          "ports": [{ "protocol": "TCP", "port": config.model_gateway_port }],
        },
      ],
    },
  }
  if container is Some(runtime) &&
    network is Object(root) &&
    root.get("spec") is Some(Object(spec)) {
    spec["ingress"] = [
      {
        "from": [
          {
            "podSelector": {
              "matchLabels": {
                "app.kubernetes.io/name": "lunanexa-webide-gateway",
              },
            },
          },
        ],
        "ports": [{ "protocol": "TCP", "port": runtime.port }],
      },
    ]
  }
  let core = "/api/v1/namespaces/\{config.namespace_name}"
  let apps = "/apis/apps/v1/namespaces/\{config.namespace_name}"
  let networks = "/apis/networking.k8s.io/v1/namespaces/\{config.namespace_name}"
  // Apply deny-by-default networking before any runnable workload. Partial
  // failures are recoverable by reapplying these deterministic resource names.
  [
    ("\{networks}/networkpolicies/\{name}", network),
    ("\{core}/persistentvolumeclaims/\{storage_name}", persistence),
    ("\{core}/secrets/\{name}", secret),
    ("\{core}/services/\{name}", service),
    ("\{apps}/deployments/\{name}", deployment),
  ]
}
