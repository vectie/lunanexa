# Exclusive delivery implementation checkpoint

This records source implementation, not physical delivery acceptance. The live
inventory is in `exclusive-node-live-inventory-20260923.md`. No new resource
grant, existing GPU task stop, or live service switch is implied by this file.

## Connected source paths

- Scheduler snapshots now own atomic whole-node sets, owner service budgets and
  drain-before-release. Shared scheduler placement, assignment publication and
  legacy bare-machine admission check the same reservation authority.
- Node materialization retains idle public caches, protects live references and
  reports real preparation/transfer observations while downloading. Cache byte
  budgets are not whole-filesystem free-space percentages.
- Delivery operations persist authorization, project, template, node set,
  preparation, model readiness, workspace startup and stop observations.
  Controller startup restores this store and runs reconciliation periodically.
- Workspace gateway resolves exact delivery-bound credentials, starts retained
  per-user volumes on assigned nodes and reports startup/readiness/actual stop
  through a deployment-owned observation credential. Browser credentials alone
  cannot claim successful runtime readiness.
- Enterprise and operator sites project the same operation. Enterprise polling,
  published template selection, retry and public handoff are connected to API
  routes. Operator reservations bind existing effective grants and leases.
- The separate Kubernetes reservation host can preserve unrelated taints,
  refuse foreign pods and observe removal after cleanup. Its transport and
  state transitions have isolated tests; deployment/controller wiring remains
  required before this can claim physical node exclusivity.

## Deliberately unproven / remaining work

1. Wire the controller-owned Kubernetes reservation host and restricted RBAC
   into reservation activation/release. Runtime manifests need corresponding
   owner labels/tolerations; do not rely on GPU requests alone.
2. Publish component H3 manifests and approved digest-pinned patched runtime
   images. The existing whole-model manifest lists about 498 GB; do not silently
   replace a 144 GB component transfer with this full bundle.
3. Configure actual node hostname mapping, gateway observation credential,
   public launch catalog and the exclusive gateway deployment. Test outside the
   current client's VPN path before claiming public port 5000 is repaired.
4. Finish the dedicated GPU-container offering/catalog and browser terminal
   image, package mirror egress, and user-approved read-only weight mounting.
5. Multi-node reservations are atomic; the current model-service planner still
   launches one replica inside the set. Distributed topology and multi-service
   coverage need their own integration, not a claim inferred from node_count.
6. Same-node PVC persistence exists. Cross-node recovery requires a shared
   storage profile or explicit data migration; local-path is not HA storage.
7. A gateway process crash between startup claim and Kubernetes Secret creation
   requires controller-driven cleanup/retry. Final reservation release must
   wait for all model and workspace claims and actual stop evidence.
8. H3 loaded-model health/discovery is readiness evidence, not proof of video
   generation. Actual generation/download, workflow/file reopen, IaaS terminal,
   MaaS invocation, tenant isolation and expiry still require the public UI
   campaign under newly confirmed bounded resource authority.

## Validation scope

Completed source gates:

- `moon info`, `moon fmt`, native `moon check --deny-warn` passed.
- Full native suite: **1184/1184 passed**.
- Operator/enterprise UI and their browser entry packages: **236/236 passed**
  on JavaScript with warnings denied.
- Release dependency/image/contract/secret/response checks passed, including
  **27** isolation scan fixtures and **12** secret scanner fixtures. The scanner
  now excludes nested downloaded `.mooncakes` caches while still rejecting an
  owned nested manifest that imports a forbidden product.

Conditional PostgreSQL tests without a disposable test database do not prove
live database recovery. These results do not replace browser or physical-cluster
acceptance and do not close any remaining item listed above.

The implementation uses the MoonBit project conventions, native first-party
services, typed transitions and `.mbtx` metadata inspection. No new Python
service, host Docker dependency or MoonSuite source dependency was introduced.
