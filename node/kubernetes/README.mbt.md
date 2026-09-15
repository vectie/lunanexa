# Kubernetes runtime adapter

This package implements authenticated Pod lifecycle operations, durable recovery
and strict observation. `cmd/node` selects it with
`LUNANEXA_RUNTIME_BACKEND=kubernetes`; the host-systemd OCI backend remains
available. The repository DaemonSet now selects Kubernetes without an engine
socket. This source change has **not yet switched the running cluster agent**.

- `PodManager.create` uses POST and refuses adoption on conflict.
- Callers must persist the creation UID before observing readiness.
- `observe_pod` binds namespace, Pod name/UID, node, assignment, generation,
  artifact and pinned image; Running alone is insufficient.
- `stop` sends a UID precondition. Accepted deletion is Draining, not Stopped.
- `authenticated_transport` reloads projected service-account tokens, uses an
  explicit CA, imposes a 10-second deadline and a 4-MiB response limit, and
  excludes error response bodies from returned errors.
- `render_runtime` generates a pinned, non-root, read-only Pod with a verified
  cache-file mount and a deny-egress/explicit-controller-ingress NetworkPolicy.
  GPU requests use a DRA claim template with an exact UUID and minimum memory
  selector. Node affinity keeps the Kubernetes scheduler in the allocation path.
  Zero-accelerator fixtures have no DRA claim; no synthetic device is inserted.
- Auxiliary policy/template creation and deletion are also namespace/UID scoped.
  Keep the policy until the runtime Pod is confirmed absent.
- The supervisor saves creation intent before mutation, then binds returned UIDs.
  Recovery from a lost creation response requires the durable owner/intent and
  submitted resource fields to match. A recorded UID is never silently replaced.
- The journal uses an exclusive file lock, flushed temporary file, atomic rename
  and directory flush. Closing the journal does not delete workloads.
- Cleanup is durable and ordered Pod → claim template → network policy. Model
  files stay retained until cleanup is confirmed, including after restart.
- The node runs expiry cleanup independently of controller HTTP calls. Fresh
  controller intent is compared directly with the runtime journal, not only the
  NodeAgent's in-memory assignment map.

Remaining integration work: observe actual DRA allocation, inject image-bound
runtime secret references, exercise the new agent on the real cluster and route
the complete test-inference pipeline through it. Node-agent/API failure fencing
still needs acceptance: the expiry annotation is metadata, **not a
Kubernetes-enforced deadline**. The periodic reaper cannot guarantee process
termination while both the agent and Kubernetes control path are unavailable.
In particular, an external Pod or synthetic GPU inventory must never be adopted
as proof of a successfully reconciled signed assignment.

The caller must use a dedicated namespace and a service account whose Role
permits only runtime Pod, NetworkPolicy and ResourceClaimTemplate operations
there. See `deploy/node-kubernetes-rbac.yaml`. The namespace needs permission for
the node-owned cache hostPath; this does not grant users Kubernetes access or
permit privileged serving containers. This package does not request Secret read
permissions or access a containerd socket.

Install a reviewed per-node copy of `deploy/kubernetes-runtime.example.json`
at `/etc/lunanexa/kubernetes-runtime.json`. Node ID and cache root must match
the existing agent configuration. Use the node agent's numeric UID for
`run_as_user`: verified cache files are private to that UID. Configure only
the actual controller source addresses. Journal files require a private,
deployment-owned directory. Fresh journals use `/usr/bin/openssl rand` for an
OS-backed ownership nonce; an existing journal does not regenerate its owner.
The nonce is a correlation marker, not a substitute for Kubernetes RBAC.

`moon run cmd/node-runtime-plan -- INPUT.json` is a diagnostic renderer for
server-side dry-run. It does **not** verify a signature or model file and cannot
deploy resources. Its output must not be treated as readiness evidence.

The 2026-09-15 acceptance dry-run on the existing K3s 1.34 cluster accepted the
generated policy, ResourceClaimTemplate and Pod with strict schema validation.
It created no objects and allocated no GPU. This validates API compatibility,
not scheduler execution, model materialization, inference or expiry behavior.
The DRA shape follows the [NVIDIA allocation guide](https://dra-driver-nvidia-gpu.sigs.k8s.io/docs/guides/gpu-allocation/allocating-gpus/)
and was checked against that cluster's `resource.k8s.io/v1` schema.
