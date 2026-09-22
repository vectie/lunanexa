# Exclusive delivery implementation checkpoint

This records source implementation, not physical delivery acceptance. The live
inventory is in `exclusive-node-live-inventory-20260923.md`. No new resource
grant, existing GPU task stop, or live service switch is implied by this file.
The separately authorized H3/GLM pause is recorded in
`model-pause-20260923.md`; it does not renew a customer grant.

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
- The Kubernetes reservation host now participates in the controller loop,
  signed model publication and workspace startup. It preserves unrelated taints,
  refuses foreign Pods and observes removal before scheduler release. Model
  assignments carry signed owner metadata; runtime Pods use the matching label
  and toleration. Actual cluster configuration/rollout is still required.

## Deliberately unproven / remaining work

1. Deploy the now-connected reservation host configuration and restricted RBAC,
   projected controller token, explicit namespace/infrastructure allowlists and
   node mappings; verify physical node fencing in the actual cluster.
2. Publish component H3 manifests and approved digest-pinned patched runtime
   images. The existing whole-model manifest lists about 498 GB; do not silently
   replace a 144 GB component transfer with this full bundle.
3. Configure actual node hostname mapping, gateway observation credential,
   public launch catalog and the exclusive gateway deployment. Test outside the
   current client's VPN path before claiming public port 5000 is repaired.
4. Deploy the now-implemented GPU-container offering/catalog with a verified
   browser terminal image, package mirror egress, and user-approved read-only
   weight mounting. Source support does not establish a runnable live offering.
5. Multi-node reservations are atomic. The current integration adds independent
   model replicas across the reserved set, with per-replica preparation/readiness
   and termination evidence. This is not tensor parallelism or a distributed
   model topology. New source gate and live multi-node acceptance remain pending.
6. Shared-storage profile and single-writer ownership are implemented in the
   current worktree. The NFS CSI backend is being prepared, not installed;
   cross-node reopen is still unproven. Existing local-path data needs explicit
   migration; neither local-path nor management-host NFS is HA storage.
7. Physically verify gateway restart and stop recovery. The gateway now persists
   a recovery Secret before claiming startup capacity. Runtime identity includes
   the delivery and client; retained volume identity includes the client but not
   delivery, avoiding ComfyUI/terminal collisions. Cross-node data migration is
   still required for node-local PVCs.
8. H3 loaded-model health/discovery is readiness evidence, not proof of video
   generation. Actual generation/download, workflow/file reopen, IaaS terminal,
   MaaS invocation, tenant isolation and expiry still require the public UI
   campaign under newly confirmed bounded resource authority.

## Validation scope

Completed source gates at commit `74e9c80` (before the next integration batch):

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

## Subsequent integration batch

The H3 patched ARM64 image has now been physically packaged and pushed to the
internal registry. TLS-verified HEAD confirms manifest
`sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c`.
See `../deploy/h3-patched-runtime-packaging.md` for the receipt and exact four
code patches. This is not an H3 workload rollout or inference acceptance.

Component manifest derivation ran against the real source metadata and produced
separate 81-file FL2VA and Ref2VA manifests, each about 144 GB. The script's
self-test passed. Per-file checksums were retained, not re-certified by rereading
weights during metadata derivation. Registry/model admission remains required.

GPU container offerings now come from deployment-owned pinned configuration;
customers cannot select arbitrary images. Model-free terminal credentials may
discover the gateway but cannot infer. ModelApi operations now issue their own
delivery-bound keys rather than sending users to the shared API-key flow.
Enterprise UI includes catalog-driven terminal launch and one-time MaaS key
display. After the workspace identity/recovery changes, the batch gate passed:

- `moon info`, `moon fmt`, native `moon check --deny-warn`.
- Full native tests: **1197/1197 passed**.
- Operator/enterprise and browser entry JavaScript tests: **239/239 passed**.
- Release dependency/image/contract/secret/response checks, including **27**
  isolation fixtures and **12** secret scanner fixtures.
- GPU offering integration covers authenticated selection, model-free handoff,
  persisted delivery binding on redemption, and revocation without a model
  catalog. Workspace tests cover runtime/volume identity separation and a
  persisted recovery marker before startup capacity is claimed.

An initial integration run caught a missing authentication header in the new
GPU test fixture; the fixture was corrected, its targeted test passed, and the
full native suite was then rerun to the totals above. These tests use fixtures,
not a newly authorized physical customer lease. No existing GPU workload or
public frontend Deployment was switched by this batch.

## Shared storage and multi-replica integration gate

The subsequent batch implements independent replicas across the reserved node
set, cache-local placement preference, per-replica preparation/readiness/stop
accounting, and sticky video-job retries. Public delivery responses expose
aggregate replica progress without physical node/assignment identifiers.
Shared workspace claims have a configured RWX profile and Kubernetes CAS
single-writer ownership; existing local-path claims are not silently migrated.
The gateway now has a separate least-privilege storage-read RBAC artifact.

Validation completed on 2026-09-23:

- `moon info`, `moon fmt`, native `moon check --deny-warn` passed.
- Full native suite: **1204/1204 passed**.
- Operator/enterprise UI and browser entry JavaScript suite: **240/240 passed**.
- Release scans passed, including **27** isolation and **12** secret-scanner
  fixtures.
- The initial targeted media test used an invalid runtime-instance ID; corrected
  to the contract's 64-character hexadecimal representation before the full
  native rerun above. No failing test is waived.

The UI batch removes a commercial-readiness restriction on browsing the catalog,
not on actual deployment authorization. Global acceptance remains separately
visible. The overview no longer promises allocation of exactly one node.

Eight pinned CSI image archives have been cached and verified on management;
see `shared-workspace-storage-prep-20260923.md`. NFS/CSI installation and updated
application rollout are still pending. Management root SSH and the supplied
old sudo credential failed authentication; no host protection was bypassed.
New customer test authorization remains unconfirmed. These source/packaging
gates therefore do not satisfy the remaining physical/UI acceptance items.
