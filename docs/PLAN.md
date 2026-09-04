# LunaNexa phased implementation plan

The post-audit implementation contract for durable notifications, operational
events, hybrid offline commerce, customer machine access and role-safe guide
diagnostics is [Operations, offline commerce, machine access and guide
diagnostics](OPERATIONS_COMMERCE_ACCESS_AND_GUIDE.md). Those phases are release
requirements; external providers and physical-DGX checks remain explicit gates.

The forward-looking P0/P1/P2 program, code-size model, named physical-pilot gate and
separate launch criteria for managed inference and dedicated GPU workspaces are
defined in [the future expansion plan](FUTURE_EXPANSION_PLAN.md). The phases
below remain the implementation history and repository acceptance contract;
the expansion plan prevents that repository evidence from being mistaken for
physical or commercial launch readiness.

## Working policy

Implement a meaningful phase, then run its phase gate. Avoid repeatedly running
the entire cluster and UI matrix after each small edit. The last phase performs
one consolidated end-to-end and failure campaign.

Every phase must preserve these invariants:

- no dependency on a MoonSuite repository;
- no MoonSuite product code or credential on a managed GPU node;
- typed, versioned northbound and southbound contracts;
- durable desired state and immutable audit events;
- first-party MoonBit backend/node code and a Rabbita operator UI;
- no silent payload retention or training reuse.

## Phase 0 — Freeze contracts and skeleton

Deliver:

- MoonBit package skeleton matching `ARCHITECTURE.md`;
- public v1 workload, response, deployment, node, telemetry and audit types;
- canonical JSON fixtures and compatibility policy;
- typed lifecycle states for model, deployment, node and workload;
- architecture dependency check that rejects imports from sibling MoonSuite
  workspaces;
- CLI and API process shells with health/version only.

Gate:

- native MoonBit check/test passes;
- every contract round-trips against golden fixtures;
- generated interfaces are reviewed;
- a dependency and response scan contains no forbidden product-specific terms.

## Phase 1 — One-node vertical slice

Deliver:

- controller identity, local operator authentication and durable metadata port;
- node enrollment with short-lived bootstrap token and certificate rotation;
- heartbeats, inventory, labels, taints, cordon and drain;
- signed desired-state assignments with generation and lease;
- one deterministic fake runtime adapter plus one real approved text runtime;
- register → deploy → ready → invoke → stop flow on one selected compute node.

Gate:

- UI/API enrolls one node and completes one streamed generic request;
- no remote arbitrary shell path exists;
- node restart resumes heartbeat and reconciles the assigned deployment.

## Phase 2 — Registry, evaluation and safe rollout

Deliver:

- model, artifact, runtime and license registry;
- digest verification, provenance and compatible-hardware declarations;
- evaluation suite and benchmark profile records;
- versioned aliases, canary rollout, promotion, rollback and immutable receipts;
- OCI image adapters and direct, resumable, SigV4-authenticated model pull from
  the Moongate S3-compatible endpoint;
- a least-privilege ModelScope adapter and the browse → download → verify →
  approve workflow defined in `MODELSCOPE_MODEL_ONBOARDING.md`;
- explicit payload retention and evaluation-capture consent.

Gate:

- an unlicensed, unverified or failed-evaluation artifact cannot deploy;
- approved artifact promotes through canary and rolls back deterministically;
- controller restart preserves registry and desired state.

## Phase 3 — Multi-node scheduler and traffic management

Deliver:

- hard filters for health, architecture, memory, runtime, license and data class;
- deterministic scoring for warm model, headroom, queue time and reliability;
- admission control, tenant quotas, priorities, deadlines and cancellation;
- streaming proxy, backpressure and bounded retry;
- node drain, failover, placement explanation and capacity forecast;
- topology-aware multi-node adapter interface, disabled until explicitly
  validated for a model/runtime/network profile.

Gate:

- every node in the named acceptance inventory appears with truthful capacity
  and health;
- the same snapshot and policy produce the same placement explanation;
- draining a node stops new assignments and moves eligible subsequent traffic;
- impossible workloads are rejected before runtime launch with a typed reason.

## Phase 4 — Rabbita operations console

Deliver one clean operator flow with these views:

- Overview: capacity, active models, queues, alerts and recent changes;
- Nodes: inventory, health, labels, workloads, cordon and drain;
- Models: artifact, license, evaluation, compatibility and aliases;
- Deployments: desired/observed state, rollout, rollback and placement reason;
- Requests: aggregate latency, throughput, errors and bounded request detail;
- Benchmarks: comparable profiles and regression evidence;
- Policies: quotas, data classes, retention and runtime allowlists;
- Audit: actor, decision, evidence, result and correlation receipt.

The management surface additionally exposes user access and capacity leases.
Access revocation and early lease termination are destructive operations with
explicit confirmation receipts and immutable audit evidence.

The UI reads the same typed contracts as automation. Destructive controls show
scope and require an explicit confirmation receipt.

Gate:

- UI-to-UI: enroll node → register model → approve → deploy → invoke → inspect
  receipt → drain → observe rerouting → roll back;
- keyboard navigation, empty/error states and narrow-screen layout are usable;
- no UI-only state or duplicate hard-coded lifecycle vocabulary exists.

## Phase 4b — Rabbita developer workbench and editor clients

Deliver a separately deployable individual-user surface:

- lease and quota status, expiration and bounded usage evidence;
- a browser editing shell with project navigation, tabs and local draft state;
- provider-neutral model selection, invocation and receipt inspection;
- scoped handoff metadata for VS Code and approved external developer tools;
- typed integration capability and connection states shared with automation.

The workbench does not expose node addresses, a DGX shell or managed-node
filesystem access. Repository checkout, editor agents and third-party product
credentials remain outside the GPU execution trust domain.

Gate:

- management UI grants access and issues a bounded lease; the user workbench
  reflects that authority without acquiring administrator permissions;
- an expired or revoked lease cannot start a new workload;
- Web IDE and external editor clients use the same scoped provider contract;
- keyboard navigation, empty/error/expired states and narrow-screen layout are
  usable in both browser components;
- node assignments and runtime environments contain no editor or integration
  product identity.

## Phase 5 — MoonGate integration without coupling

Deliver:

- a published LunaNexa client/contract package;
- a MoonGate-side provider adapter in the MoonGate repository;
- model capability discovery, streaming, cancellation, usage and typed errors;
- opaque tenant/workload correlation and explicit data policy translation;
- routing tests covering external-provider fallback and LunaNexa health.

Gate:

- MoonGate can choose LunaNexa or an external provider under the same caller
  workflow;
- LunaNexa builds and operates with MoonGate absent;
- LunaNexa source and deployment images contain no MoonSuite dependency;
- a MoonSuite product completes a request without any product identity reaching
  the node assignment or runtime environment.

## Phase 6 — Recovery and security

Deliver:

- controller restart reconciliation and leader fencing;
- expired lease handling, unreachable-node policy and orphan-runtime cleanup;
- certificate rotation, secret rotation and least-privilege roles;
- signed runtime/artifact verification and network-policy templates;
- payload-log redaction, retention expiry and deletion receipts;
- backup/restore and disaster-recovery runbooks;
- dependency, image, contract and public-response leak checks.

Gate:

- kill/restart controller, node agent and runtime at defined points and recover
  to the declared state;
- stale controller generation cannot mutate current assignments;
- malicious model metadata, malformed payloads and forged node messages remain
  isolated;
- backup restores registry, desired state and audit chain on a clean controller.

## Phase 7 — Consolidated performance and release validation

Deliver:

- named benchmark profiles for the initial approved models;
- concurrency, saturation, cold-start, long-stream and mixed-workload runs;
- p50/p95/p99 latency, throughput, queue, load, utilization and failure data;
- capacity and service-objective recommendations;
- install, upgrade, rollback and operator handoff documentation.

Final UI-to-UI scenario:

1. Start from a clean controller and every node in the named acceptance
   inventory; a failover-claiming profile includes at least two eligible nodes.
2. Register a digest-pinned, licensed model and its runtime.
3. Run evaluation and approve a versioned alias.
4. Deploy canary, inspect placement, promote and invoke through MoonGate.
5. Observe streaming output, usage and an audit receipt in the console.
6. Saturate one node, drain another and verify bounded queueing/failover.
7. Restart controller and one agent; verify reconciliation without duplicate
   execution or lost desired state.
8. Roll back the alias and export the evidence bundle.
9. Scan API responses, assignments, runtime environments and images for
   MoonSuite identifiers, secrets and internal paths.

Release gate:

- the complete scenario passes once on the named physical cluster profile;
- no structural-isolation violation is found;
- measured service objectives are published as evidence, not promises;
- a named human accepts security, operational and model-license reports.

## Later, only after v1 works

- high-availability controllers;
- topology-validated distributed inference;
- fine-tuning and distributed training queues;
- external customer accounts and billing;
- additional accelerator types and remote clusters;
- a separate training product only if it gains an independent customer,
  security boundary and release lifecycle.

## Phase 8 — Management intent and one-click model services

Deliver:

- controller-signed, immutable model-service catalog templates;
- compact idempotent deployment intents and deterministic dry-run plans;
- restart-safe deployment operations with typed preflight findings;
- intent-to-assignment reconciliation, readiness observation, fixed
  single-machine capacity, promotion, rollback and deletion;
- a Rabbita catalog and deployment workflow using the same public contracts;
- CLI coverage for catalog, plan, deploy, operation and rollback.

Gate:

- an approved template deploys through one API request without hand-authoring a
  node-specific assignment;
- a missing approval, verification, license, evaluation, secret reference,
  data-class capability, or capacity blocks before assignment publication;
- repeated idempotency keys never create duplicate operations or assignments;
- controller restart resumes a persisted operation and readiness converges from
  signed assignments plus live node heartbeats;
- rollback and deletion remove only the assignment owned by the named model
  service and emit immutable audit receipts;
- public plans, operations and endpoints contain no node credentials, runtime
  credentials, internal runtime URLs, filesystem paths or MoonSuite identity.

## Phase 9 — Assignment-scoped model materialization

Deliver:

- selected-node, pull-based management artifact and detached-signature download;
- resumable partial files and atomic content-addressed cache publication;
- node-local size, digest and Cosign verification before runtime launch;
- a fixed read-only model mount with no artifact credential in the runtime;
- removal of cache entries no longer referenced by any local assignment;
- node configuration and operator documentation for cache, endpoint and trust.

Gate:

- an assignment to node A downloads only on node A and starts only after local
  verification succeeds;
- a second assignment for the same digest reuses the verified local copy;
- truncated, oversized, digest-mismatched or signature-invalid downloads never
  reach the runtime supervisor;
- removing the final local assignment prunes that digest without affecting a
  copy still assigned on another node;
- node restart reverifies an existing cache entry and resumes a partial transfer;
- runtime arguments contain only a fixed read-only local model mount and never
  the artifact URI or artifact-store credential.

## Phase 10 — Exclusive compute-node leases

Deliver:

- separate typed contracts for workspace capacity and exclusive machine access;
- durable, idempotent lease authority with one non-terminal lease per node;
- immediate exclusion of reserved nodes from managed placement and assignment;
- signed node lease directives, observed generations and a local expiry fence;
- narrow account and short-lived SSH-certificate provisioning;
- scoped model/OCI pull grants for the selected node;
- access revocation, tenant-container drain, sanitization and quarantine;
- management API, CLI, Rabbita workflows and immutable audit receipts.

Gate:

- assigning subject A to one named compute node neither provisions nor
  transfers artifacts to any other node;
- a reserved or active exclusive node cannot receive managed placements even
  before its next heartbeat;
- no raw password, private key, node credential, model-store credential or
  registry token appears in lease state, logs, audit or public responses;
- local expiry disables access while the management node is unavailable;
- failed revocation or sanitization quarantines the node;
- successful sanitization is required before managed assignments resume;
- restart reconciliation preserves the lease generation and never creates a
  second active lease for the same node.

## Phase 11 — Technical hardening and commercial governance

### Contract-governance execution order

The contract-document work is implemented as a dependent slice of this phase:

1. operator token-to-identity attribution and restart-safe expiry closure;
2. threshold-based four-eyes approval for high-value execute/close actions;
3. Effective MasterLease admission before API-key issuance, with a shared
   admission projection for workspace and exclusive-machine consumers;
4. ledger-digested settlement drafts and violation-to-close proposals;
5. immutable amendment records materialized into a `preceding_packet_ref`
   version chain;
6. durable payment/acceptance obligations with overdue reconciliation;
7. tenant-scoped contract numbering and a deterministic operator business view.

The browser projection for this phase is task-first rather than document-list
first: one tenant-scoped inbox owns approval recovery, overdue obligations and
closure proposals; each packet uses the value-free durable event timeline; the
customer sees approval/obligation/expiry progress and may send a deduplicated
reminder without gaining operator controls. High-value approval decision and
execution are one atomic store mutation, and governance JSON exports are
tenant-scoped read-only evidence. Revision conflicts refresh the authoritative
snapshot before another action is offered.

The source DOCX, MoonLeaf preview, offline execution evidence, and all existing
privacy boundaries remain unchanged by this governance layer. The contract
store is the durable authority; browser views are projections only.

Deliver:

- deterministic prewarm, startup/readiness/liveness probe, cache,
  admission/backpressure, transfer-grant and reviewed-sidecar policy cores;
- operator-authenticated technical decision endpoints with lease-generation
  fencing and bounded transfer-grant validation;
- organization, cost-center and project hierarchy; exactly-once usage rating;
  immutable billing periods and adjustments; budgets, quotas and commitments;
- RBAC, versioned clickwrap and e-signature agreement state machines;
- provider-neutral normalized identity, payment, invoice and signature records;
- Rabbita cost-center, agreement and qualified-service evidence routes;
- LunaFide, an isolated `TestOnly` deterministic provider simulator.

Repository gate:

- adversarial unit and black-box suites cover money overflow, tenant mismatch,
  idempotency conflicts, replay, stale observations, invalid transitions,
  transfer expiry and generation fencing;
- every new API requires operator authority and emits bounded typed responses;
- browser routes are keyboard reachable, table content scrolls at narrow widths,
  hostile labels are escaped, and LunaFide is visibly non-production;
- no raw provider reference, credential, prompt, model payload, filesystem path
  or MoonSuite identity appears in public commercial or technical state.

Production gate still required:

- crash-test the implemented transactional commercial/integration snapshot
  adapter against the selected production PostgreSQL failover system;
- physically validate the implemented prewarm/nonce persistence and
  one-lease-one-machine behavior against the named acceptance inventory;
- connect node probe/cache telemetry and approved digest-pinned sidecar catalog;
- replace LunaFide with approved production identity, signature, payment and
  invoice providers and validate their real webhook trust and retention rules;
- pass real ingress, database, accelerator-fleet, security, finance, legal and
  operations acceptance for the selected deployment profile. Repository tests
  do not waive these external gates.

### Implemented self-service organization and machine commerce slice

- public OIDC first sign-in may create a LunaNexa account and bounded shared
  trial without granting machine access;
- authenticated users may create an individual or company customer organization
  with legal profile, default cost center/project and owner roles, or join an
  existing organization using a one-time email-bound invitation;
- identity-verification requests are durable provider records; organization
  activation requires an authenticated provider callback;
- the enterprise portal supports explicit multi-organization selection and
  propagates `X-LunaNexa-Organization` to every organization-scoped request;
- live regional bare-machine and dedicated-endpoint SKUs support immutable
  quotes, readable clickwrap or negotiated agreements, external checkout,
  payment-gated provisioning, cancellation/termination and refund compensation;
- physical node and accelerator identifiers remain absent from customer input
  and output; placement is internal and based on trusted fresh heartbeat labels;
- prepaid usage is recorded as evidence without creating a second payable
  ledger charge.

The repository includes a LunaNexa-operated Keycloak 26.7.3 public identity
profile with open registration, verified email, recovery, TOTP, exact PKCE
clients, external PostgreSQL and restricted ingress. The remaining production
work is operational rather than hidden product logic: deploy and smoke-test that
profile or an approved enterprise federation, configure
identity/payment/signature adapters, publish legally approved immutable terms,
seed approved SKUs, and complete the physical-cluster release evidence gate.
