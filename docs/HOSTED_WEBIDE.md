# Hosted ComfyUI WebIDE

This is an implementation and operator integration guide, not a production
acceptance certificate. See [media qualification status](MEDIA_GENERATION.md).

## Components

`cmd/webide-gateway` is the authenticated public HTTP/WebSocket bridge. Its
client ID must match one entry in `LUNANEXA_CLIENT_LAUNCH_CATALOG_JSON`; that
entry's launch URI is the gateway's `/connect` URL. Existing DNS and certificate
ownership are unchanged. A deployment can use a separate port in 5000–6000 on
its existing TLS edge, but must not publish raw ComfyUI port 8188.

The gateway accepts `LUNANEXA_WEBIDE_BIND`, `LUNANEXA_WEBIDE_CLIENT_ID`,
`LUNANEXA_WEBIDE_PUBLIC_ORIGIN`, and `LUNANEXA_WEBIDE_CONFIG_FILE`. The last names
a deployment-owned JSON document with the fields defined by
`workspace/webide/host.HostConfig`. Both container image references require
immutable SHA-256 digests. Kubernetes access requires HTTPS, a CA file and a
service-account token file; never put their contents in the configuration.

Each authority tuple (tenant, subject, organization, project) maps to one
deterministic opaque namespace-local resource name and PVC. Workspaces run on
nodes labelled `lunanexa.io/workspace-host=true`, not managed model-serving GPU
nodes. The CPU/memory/storage limits in HostConfig are validated server-side.

`cmd/webide-model-proxy` runs in the workspace pod and binds **only**
`127.0.0.1:8189`. Its configuration file is a Kubernetes Secret mounted in the
proxy container alone. It sends a scoped credential to the configured MoonGate
origin and rechecks controller authority for every request. Client-supplied
authorization, endpoints and identities do not override that binding.

The same binary runs initialization when `LUNANEXA_WEBIDE_INITIALIZE` names the
workspace root and `LUNANEXA_WEBIDE_INITIAL_MODEL` names its approved model.
The init container has no credential mount. It creates user/input/output
directories and a starter workflow, using no-replace publication and refusing
symlink directories. Existing user workflows/settings are never overwritten.

## Runtime image requirements

The pinned third-party ComfyUI image must contain `/opt/ComfyUI/main.py`, the
qualified frontend, and the reviewed `ComfyUI-vLLM-Omni` extension under the
image's `custom_nodes` directory. It must run as UID/GID 1000 with a read-only
root filesystem. Do not set `--base-directory /workspace`: that would make
custom-node code tenant-writable and remove the image-owned plugin from search.
Model weights are not included in either WebIDE image.

The native image must contain `/usr/local/bin/lunanexa-webide-model-proxy`;
the gateway image contains `/usr/local/bin/lunanexa-webide-gateway`.
Neither successful compilation nor a digest proves a qualified runtime image.

## Network and lifecycle requirements

The generated NetworkPolicy is applied before runnable resources. It permits
ingress only from `app.kubernetes.io/name=lunanexa-webide-gateway` in the same
namespace. Egress is limited to kube-dns, the same-namespace controller labelled
`app=lunanexa-control`, and MoonGate labelled `app.kubernetes.io/name=moongate`,
on the configured ports. Deployment service routing must match these selectors;
external or host-network gateways need a separately reviewed policy. A CNI that
does not enforce NetworkPolicy is not an acceptable isolation boundary.

The provisioning identity needs namespace-scoped get/list/patch on the managed
Secrets, PVCs, Services, Deployments and NetworkPolicies, plus get/update on
Deployment scale. Do not grant cluster-admin. Credentials must not be logged.

Every browser operation rechecks live authority. WebSockets recheck on a bounded
timer. The gateway reconciles expired/revoked workspaces to zero replicas while
retaining the PVC; storage deletion is a separate explicit retention operation.
Partial creation is repaired by reapplying deterministic desired state. Gateway
restart loses browser sessions, so users relaunch from the portal; files persist.

The first model proxy profile accepts text-only video forms. Image-reference
uploads to model providers, H3 audio controls, durable media jobs, cancellation
and provider qualification are not implicitly enabled by this gateway.

## Verification

Run `moon test workspace/webide workspace/webide/host --target native --deny-warn`
and check both native executable packages. The skipped browser fixture can be
run explicitly only with a real local ComfyUI on 127.0.0.1:5876; it is an offline
test authority on port 5875 and must never be used as a deployed gateway.

Before live catalog enrollment, verify image provenance, pod isolation, enforced
NetworkPolicy, cross-user denial, renewal/restart, account/lease revocation,
saved workflow persistence and actual MoonGate/provider inference. Do not mark
a client ready solely because `/system_stats` responds.
