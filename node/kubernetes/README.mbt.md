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

Remaining integration work: signed-assignment-to-Pod rendering, verified model
volume mapping, GPU/DRA allocation binding, network policy, durable UID recovery,
lease-expiry reconciliation, node backend selection, scoped RBAC, and live
cluster acceptance. In particular, an external Pod or synthetic GPU inventory
must never be adopted as proof of a successfully reconciled signed assignment.

The caller must use a dedicated namespace and a service account whose Role
permits only Pod create/get/delete there. This package does not request Secret
read permissions or access a containerd socket.
