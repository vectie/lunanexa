# Kubernetes whole-node reservation activation

The controller now reconciles Kubernetes reservation taints before publishing
model assignments or accepting workspace provisioning. A scheduler record alone
does not make a node usable. Failure leaves its logical reservation held and the
delivery pending/failed; it never falls back to a shared node.

## Deployment wiring

1. Render `deploy/reservation-host-rbac.yaml` with the control namespace. This
   grants node get/patch and cluster-wide Pod listing, not Pod creation/deletion
   or access to Secrets. Where node names are fixed, additionally restrict the
   node rule with `resourceNames` containing the configured Kubernetes names.
2. Prepare `deploy/reservation-host.example.json` with enrolled-node IDs mapped
   to actual Kubernetes names. Include both the model runtime and workspace
   namespaces in `workload_namespaces`.
3. Set `LUNANEXA_RESERVATION_HOST_JSON` to that JSON. Mount a projected token and
   the cluster CA in the **control container only**, matching `token_file` and
   `ca_file`. The default controller manifest has token automount disabled;
   merely setting the environment variable is insufficient.
4. List required infrastructure exemptions by exact namespace, service account,
   label key and label value. Do not exempt a whole namespace. Audit host-level
   GPU processes separately before authorizing an idle node; Kubernetes cannot
   detect processes outside its Pods.
5. Use the public Operator UI to authorize and reserve the node set. Model
   assignments carry signed reservation ownership; model and workspace Pods use
   the matching `lunanexa.io/reservation` label and NoSchedule toleration.

NoSchedule keeps ordinary unowned Pods from being scheduled; it does not evict
existing Pods or constrain a cluster administrator. Do not give tenants direct
node binding, arbitrary tolerations, or runtime-namespace Pod creation access.

## Lifecycle

The five-second controller loop re-observes reservations, reconciles delivery,
then checks release. Expiry or revoked authority begins draining. Scheduler locks
remain held until every service claim stops, assignments are absent, fresh node
heartbeats confirm no managed runtimes, and the Kubernetes adapter observes no
remaining customer Pods on every node. User PVCs are not deleted by release.

This wiring has mock-host integration coverage. Physical taint application,
tenant placement and expiry remain part of the live UI acceptance; no cluster
rollout is implied by this document.

## Delivery profiles

For GPU container IaaS, set controller `LUNANEXA_GPU_CONTAINER_OFFERING_JSON`
with `template_id`, `version`, `display_name`, `client_id`, `image_digest`,
`cpu_millis` and `memory_mib`. The client must also be an approved entry in the
launch catalog. Pair it with a terminal gateway whose
`LUNANEXA_WEBIDE_CONTAINER_FILE` names the deployment-owned image, command,
arguments, HTTP terminal port and the same CPU/memory limits, with `gpu: true`.
The image must be digest-pinned. The controller checks the reported memory budget
including 512 MiB of proxy overhead; the gateway checks the exact offering digest
and resource profile before creating workloads. No model alias is required for
this terminal-only grant, and it cannot be used for inference.

Both terminal and ComfyUI gateways use
`LUNANEXA_WEBIDE_REQUIRE_EXCLUSIVE=true` and the server-only
`LUNANEXA_WEBIDE_OBSERVATION_TOKEN`, shared with the controller. Deploy the updated
controller and gateways together: exclusive placement responses now carry the
delivery kind and expected runtime profile. Legacy non-exclusive mode is not
changed by merely upgrading binaries.

For ModelApi, a Ready delivery exposes
`POST /v1/portal/self/deliveries/{id}/access-key` with a fresh `request_id`.
The enterprise UI performs this call and shows the key once. The returned model,
public API URL, quota and expiry belong to that delivery; stopping it denies the
key instead of routing it to a shared deployment.

Delivery-bound workspace runtime IDs include client and delivery, while retained
volume IDs include client but not delivery. Reopening the same operation is
idempotent, new deliveries of the same application retain their data, and a
terminal cannot overwrite a ComfyUI runtime or volume. Node-local volumes still
require explicit migration before changing the assigned node.
