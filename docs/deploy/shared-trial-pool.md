# Organization-scoped shared trial pool

The customer portal can show a deployment-owned shared trial pool separately
from exclusive company reservations. A trial slot is visible only to an active
Developer in the exact configured organization and tenant. The controller
requires a fresh, active node heartbeat carrying
`lunanexa.io/usage-pool=trial`; it then probes the configured internal service
health URL for at most two seconds. The UI distinguishes an offline node, an
online node with no responding service, and a responding health check. A health
check is **not** an inference acceptance result. The same card appears in the
customer portal's Machines and Models sections; dedicated reservations remain
a separate card.

Set the optional `shared-trial-offerings` key on `lunanexa-control-config` to a
JSON array like this (identities and URLs are placeholders):

```json
[
  {
    "organization_id": "organization-example",
    "tenant_ref": "tenant-example",
    "node_id": "trial-node-video",
    "node_label": "Shared Spark 1",
    "model_alias": "video.minimax-h3",
    "model_name": "MiniMax H3",
    "kind": "Video",
    "health_url": "http://video-service.internal:8000/health",
    "public_url": "https://example.test/comfyui/"
  },
  {
    "organization_id": "organization-example",
    "tenant_ref": "tenant-example",
    "node_id": "trial-node-text",
    "node_label": "Shared Spark 2",
    "model_alias": "text.qwen3.8-27b",
    "model_name": "Qwen3.8-27B",
    "kind": "Text",
    "health_url": "http://text-service.internal:8000/health",
    "public_url": "https://example.test/user/"
  }
]
```

This configuration is **not** a node reservation and cannot convert an
exclusive node into shared capacity. For a `Text` offering, an active Developer
in the exact organization and tenant can issue a model-scoped API key with no
request-count cap. The same authorization is rechecked on every API call;
revoking the offering or membership closes access. Usage is still recorded,
but no commercial rate is applied only when the workload receipt names the
configured trial node. A mismatched node is rejected rather than silently
charged or treated as free. Keys still have a bounded lifetime and must be
renewed.

An offering alone does not deploy a model or create a runtime route. For text
inference, configure `LUNANEXA_SHARED_TRIAL_TEXT_ROUTE_JSON` on the controller
with the exact `model_alias`, `tenant_ref`, `node_id`, controller-loopback
`origin`, `served_model`, `runtime_version`, `image_digest`, and
`artifact_digest`. Supply `LUNANEXA_SHARED_TRIAL_TEXT_CREDENTIAL` from the
runtime's existing Kubernetes Secret, never from a ConfigMap. The controller
will admit this route only for the matching offering and only while its
registered artifact, live model listing, node heartbeat, and trial credential
agree. This is separate from any dedicated company model route. The controller
loopback proxy must forward only to the intended in-cluster runtime.
For MoonDesk, also include the same alias in the `desktop-workspace` client
model policy. Otherwise the service can be healthy yet remain absent from the
PaaS selector. Keep dedicated model aliases alongside it, not in the shared
trial route.

`Video` offerings are launch links only; ComfyUI authentication and resource
control remain with its existing gateway. If a service is not responding, the
customer portal does not offer its link.
