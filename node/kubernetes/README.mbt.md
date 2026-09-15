# Kubernetes runtime adapter foundation

This package implements authenticated Pod lifecycle operations and strict
observation. It is **not yet wired into `cmd/node`** and does not replace the
active OCI supervisor. No running cluster changes are implied by these tests.

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

Remaining integration work: connect signed-assignment verification and the
materializer to the renderer, apply resources with durable UID recovery, observe
actual DRA allocation, enforce absolute lease expiry, inject image-bound runtime
secret references, select the node backend, and run live lifecycle acceptance.
The expiry annotation is metadata, **not a Kubernetes-enforced deadline**.
In particular, an external Pod or synthetic GPU inventory must never be adopted
as proof of a successfully reconciled signed assignment.

The caller must use a dedicated namespace and a service account whose Role
permits only runtime Pod, NetworkPolicy and ResourceClaimTemplate operations
there. See `deploy/node-kubernetes-rbac.yaml`. The namespace needs permission for
the node-owned cache hostPath; this does not grant users Kubernetes access or
permit privileged serving containers. This package does not request Secret read
permissions or access a containerd socket.

`moon run cmd/node-runtime-plan -- INPUT.json` is a diagnostic renderer for
server-side dry-run. It does **not** verify a signature or model file and cannot
deploy resources. Its output must not be treated as readiness evidence.

The 2026-09-15 acceptance dry-run on the existing K3s 1.34 cluster accepted the
generated policy, ResourceClaimTemplate and Pod with strict schema validation.
It created no objects and allocated no GPU. This validates API compatibility,
not scheduler execution, model materialization, inference or expiry behavior.
The DRA shape follows the [NVIDIA allocation guide](https://dra-driver-nvidia-gpu.sigs.k8s.io/docs/guides/gpu-allocation/allocating-gpus/)
and was checked against that cluster's `resource.k8s.io/v1` schema.
