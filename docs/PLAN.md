# LunaNexa phased implementation plan

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
- register → deploy → ready → invoke → stop flow on one DGX.

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
- OCI image and S3-compatible artifact-store adapters;
- explicit payload retention and evaluation-capture consent.

Gate:

- an unlicensed, unverified or failed-evaluation artifact cannot deploy;
- approved artifact promotes through canary and rolls back deterministically;
- controller restart preserves registry and desired state.

## Phase 3 — Four-node scheduler and traffic management

Deliver:

- hard filters for health, architecture, memory, runtime, license and data class;
- deterministic scoring for warm model, headroom, queue time and reliability;
- admission control, tenant quotas, priorities, deadlines and cancellation;
- streaming proxy, batching where supported, backpressure and bounded retry;
- node drain, failover, placement explanation and capacity forecast;
- topology-aware multi-node adapter interface, disabled until explicitly
  validated for a model/runtime/network profile.

Gate:

- all four nodes appear with truthful capacity and health;
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

The UI reads the same typed contracts as automation. Destructive controls show
scope and require an explicit confirmation receipt.

Gate:

- UI-to-UI: enroll node → register model → approve → deploy → invoke → inspect
  receipt → drain → observe rerouting → roll back;
- keyboard navigation, empty/error states and narrow-screen layout are usable;
- no UI-only state or duplicate hard-coded lifecycle vocabulary exists.

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

1. Start from a clean controller and four enrolled DGX nodes.
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

- the complete scenario passes once on the real four-node cluster;
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

