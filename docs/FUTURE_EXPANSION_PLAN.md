# LunaNexa future expansion plan

Date: 2026-08-21  
Planning horizon: four DGX Spark nodes first, then a private GPU cloud for
approximately 4–100 machines

## Executive decision

The current repository is sufficient to **begin** a controlled deployment and
acceptance campaign on one management node plus four DGX Spark nodes. It is not
yet evidence that the cluster is safe to sell or expose to customers.

Use these terms precisely:

| Term | Meaning | Current status |
| --- | --- | --- |
| Repository-ready | The source, typed contracts, local simulations, restart tests, UI projections, security scans and release gate pass. | Yes |
| Deployment candidate | The installer, manifests and runbooks are ready to be exercised against the named environment. | Yes, subject to site-specific configuration |
| Internal-pilot ready | Real DGX enrollment, runtime serving, failure, backup/restore, identity and named operator acceptance have passed on the deployed environment. | Not yet |
| Managed-inference offering ready | Authorized customers can reliably invoke approved model endpoints under production identity, quota, metering, support and service objectives. | Not yet |
| Dedicated-workspace offering ready | A customer can receive and lose time-bounded non-root whole-machine access, and the machine is demonstrably reclaimed and sanitized before reuse. | Not yet |
| Broad private-GPU-cloud ready | Tenants receive coherent identity, capacity, network, storage, image, billing, audit and support lifecycles. | Future P1 |

A local simulator, demo UI transition or disabled button is never a substitute
for a physical, legal, financial, credential, runtime or sanitization receipt.
The 50-scenario browser evidence and its blockers are recorded in
[`UI_PRODUCTION_VALIDATION_50_SCENARIOS.md`](UI_PRODUCTION_VALIDATION_50_SCENARIOS.md).

## Product offerings for the next major version

### Offering A — Managed inference

Customers call approved model endpoints. LunaNexa owns authentication,
admission, model policy, placement, runtime routing, streaming, cancellation,
usage evidence and service operations. Customers do not receive a DGX shell,
node address, model-store credential or arbitrary runtime control.

This is the nearer production offering because the repository already contains
the canonical workload contract, scheduler, admission, streaming, durable
ownership, runtime adapter, workspace authority, API credentials, model
registry and operator/customer interfaces.

Launch still requires:

- four physical nodes enrolled under production mTLS and per-node identity;
- at least one licensed model and digest-pinned ARM64/NVIDIA runtime image;
- measured concurrency, saturation, cold-start, long-stream, cancellation,
  drain, failover and restart evidence;
- production IdP/SSO/MFA, credential revocation and tenant membership mapping;
- a highly available or explicitly accepted single-site PostgreSQL authority,
  encrypted backups and a successful clean restore with measured RPO/RTO;
- real monitoring, paging and notification delivery with recent-success proof;
- quota, usage, pricing and support ownership appropriate to the customer
  promise; and
- named security, operations, model-license and release acceptance.

### Offering B — Dedicated GPU workspace

One customer receives time-bounded, non-root access to one whole machine. The
node is fenced out of managed inference before access is issued. Expiry or
early termination must revoke access, stop customer processes, sanitize the
approved writable boundary and quarantine on any uncertain result.

The repository implements the typed lease authority, scheduler exclusion,
generation fencing, local expiry guard, credential-handoff metadata, fixed
helper actions, termination workflow and customer/operator projections. It is
not launch-ready until the deployment supplies and proves:

- an approved SSH certificate authority or credential broker;
- exact issuer-origin and one-time redemption behavior with recovery after a
  lost browser response;
- reviewed Linux accounts, SSH configuration, writable paths, rootless
  container policy, process ownership and filesystem boundaries;
- a root-owned helper or protected local IPC path installed on the exact DGX
  host image;
- independent session revocation, process termination and network lockout;
- destructive sanitization tests, generation-bound receipts and quarantine;
- a physical reclaim drill proving that no customer credential, process,
  writable data or container remains before managed scheduling resumes; and
- customer support, incident and dispute procedures for failed access or
  cleanup.

The two offerings share identity, contracts, metering, audit, notifications and
support, but their access authorities remain separate. A managed-inference
workspace lease must never become a machine login, and a dedicated-machine
lease must never silently expose management credentials or another tenant's
model/data state.

## Code-size planning model

The tracked implementation is currently about 120,000 lines across MoonBit,
JavaScript, HTML/CSS, deployment YAML, shell automation and JSON contracts.
Approximately 108,000 lines are MoonBit, including about 29,000 test lines and
generated interfaces.

Lines of code are a planning signal, not an acceptance criterion. A lean
P0-plus-P1 program should reuse Kubernetes and established identity, network,
storage, database, secret, telemetry and finance systems rather than rebuilding
them.

| Scope | Estimated net-new repository lines, including tests | Expected total repository size | Typical delivery shape |
| --- | ---: | ---: | --- |
| P0: real four-node operation and the two offering foundations | 50k–100k | 170k–220k | 5–8 engineers for 6–10 months, plus infrastructure/security/operations owners |
| Focused P1: coherent private GPU cloud for 4–100 machines | additional 60k–120k | 230k–340k | 10–16 engineers for another 9–18 months |
| Selective P2: multi-site and advanced cloud products | additional 300k–700k+ | 530k–1M+ | 25–50 engineers over 2–4+ years, plus permanent service teams |

If LunaNexa attempts to implement its own identity provider, object/block
storage, virtual network, secret manager, metrics database or payment gateway,
the upper ranges will be exceeded. The preferred boundary is to own GPU and
lease policy while consuming those systems through narrow, verified adapters.

## Where the expansion code belongs

Across P0 and focused P1, approximately 30–40% of net-new code should be tests,
fault injection, recovery and acceptance evidence. Within production code, the
largest share belongs to durable resource controllers—not UI ornament.

| Area | Approximate share of net-new work | Likely repository ownership |
| --- | ---: | --- |
| Tests, long-horizon simulation, fault injection, physical acceptance and evidence | 30–40% | package tests, `testsupport/`, `scripts/`, deployment acceptance fixtures |
| Capacity, quota, network, storage and image controllers plus durable state | 25–30% | focused new packages, `api/`, controller reconciliation and PostgreSQL adapters |
| Identity, policy, approval and audit | 10–15% | access/portal/workspace authorities, API middleware and immutable audit |
| Metering, pricing, billing and commercial reconciliation | 10–15% | `commercial/`, usage evidence, provider adapters and customer projections |
| External adapters, upgrades, backup/restore and operations | 10–15% | `cmd/control/`, `deploy/`, notification/observability workers and runbooks |
| Console, enterprise portal, CLI and SDK | 8–12% | Rabbita UI packages, `cmd/console`, `cmd/enterprise`, clients and extensions |

Every public resource should have one backend authority and expose the same
lifecycle through API, UI and CLI. UI state is a projection; it does not own
quotas, billing, lease transitions or recovery decisions.

## Phase-by-phase delivery plan

### Phase 0 — Preserve the repository baseline

Status: substantially implemented.

Keep the complete release gate green while the deployment work proceeds. Do
not weaken structural isolation, typed contracts, secret separation, demo
labelling, response redaction or generation fencing to make a physical test
easier.

Exit evidence:

- strict native and JavaScript checks/tests;
- restart, stale-epoch, isolation, secret and response scans;
- four-node functional simulation and exclusive-cleanup simulation;
- 50-scenario UI ledger with demo and blocked evidence kept distinct; and
- one signed repository release bundle.

Estimated new code: 0–5k, mainly corrections and acceptance tooling.

### Phase 1 — Prove the four-node internal pilot

Status: next required phase.

Deploy one management node and four physical DGX Spark nodes. Exercise the real
runtime, artifact, identity, network and storage paths without customer access.

Required work:

1. Provision production DNS, CA/mTLS, secret references, OCI registry,
   `/data/models`, PostgreSQL and telemetry destinations.
2. Enroll each DGX with a unique node identity and verify inventory, heartbeat,
   assignment and credential rotation.
3. Qualify at least one small model, then one representative production model,
   on a pinned serving runtime.
4. Measure cold start, saturation, queueing, long streams, cancellation,
   runtime loss, drain, node restart and controller restart.
5. Restore the complete management authority onto a clean management host.
6. Scan live containers, assignments, responses and node filesystems for
   forbidden credentials, paths and product identities.
7. Obtain named operator, security and license acceptance.

Exit decision: internal pilot only. No external customer SLA is implied.

Estimated new code: 10k–25k, mostly site adapters, acceptance automation and
defects revealed by physical evidence. Much of this phase is infrastructure and
operational work rather than source code.

### Phase 2 — Complete shared production foundations

Status: required before either offering launches.

Deliver:

- production SSO/MFA and tenant/role mapping with short-lived scoped authority;
- secret rotation and authority-separation drills;
- HA PostgreSQL or a formally accepted single-site design, migrations,
  backups, restore, fencing and RPO/RTO;
- live notification, paging, metrics/log export and readiness based on recent
  successful delivery rather than configured booleans;
- tenant-visible quotas, request/capacity limits and support escalation;
- stable API/CLI compatibility, deprecation policy and audit export; and
- SLOs, error budgets, maintenance windows, incident command, status
  communication and postmortem ownership.

Exit evidence: dependency-loss and restart drills prove fail-closed behavior,
customers cannot exceed or cross tenant authority, and on-call responders can
diagnose and recover the system from retained evidence.

Estimated new code: 20k–40k.

### Phase 3 — Launch managed inference

Status: nearer offering, but not currently launch-ready.

Deliver:

- approved model/runtime catalog with measured service profiles;
- production API credentials, workspace admission, ownership and revocation;
- unary and streaming invocation, cancellation, deadline, rate and concurrency
  behavior against real runtimes;
- versioned usage line items, pricing, cost allocation and customer export;
- canary, promotion, rollback, drain and capacity-reservation operations;
- customer documentation, SDK/CLI examples, support cases and error guidance;
  and
- a complete UI-to-runtime-to-audit journey under production identity.

Exit evidence: at least two tenant identities complete the same workload
lifecycle without cross-tenant visibility; saturation and dependency failures
stay within the published service objective; usage and receipts reconcile; a
named release board accepts the offering.

Estimated new code: 20k–35k.

### Phase 4 — Launch dedicated GPU workspace

Status: implemented authority baseline, but physical access/reclaim proof is
missing.

Deliver:

- production credential issuer/SSH CA and recoverable redemption flow;
- reviewed host account, SSH, rootless container, writable-path and process
  policies;
- protected root-helper/IPC installation, watchdog and independent network
  lockout;
- exact-generation activate, expire, terminate, revoke, sanitize, quarantine
  and reclaim operations;
- live countdown, customer/operator notifications and support receipts;
- renewal, early termination, contract expiry and dispute handling; and
- destructive physical cleanup plus node-return-to-service drills.

Exit evidence: a test customer receives access, loses it on expiry while the
controller is unavailable, cannot reconnect, leaves no approved writable data
or process, and the node becomes schedulable only after independently verified
current-generation sanitization. Any uncertainty produces quarantine.

Estimated new code: 25k–45k.

### Phase 5 — Complete focused P1 private-cloud capabilities

Status: future product expansion.

Deliver only the primitives required by the two offerings:

- organization/project hierarchy, delegated IAM and policy simulation;
- tenant-visible capacity inventory, reservations, waitlists and quota-change
  workflow;
- explicit network profiles, egress policy, private endpoints, DNS and flow
  evidence through an established Kubernetes networking provider;
- approved persistent-storage profiles, snapshots, restore, encryption, quota
  and deletion evidence through an established storage provider;
- runtime/model image lifecycle, vulnerability policy, signing, rollback,
  deprecation and emergency revocation;
- immutable usage, pricing versions, invoices, credits, refunds, disputes and
  finance reconciliation through approved providers;
- tags, search, bulk operations, SDKs, support cases, maintenance history and
  customer audit export; and
- capacity and cost forecasts suitable for procurement decisions.

Exit evidence: every customer-visible resource has consistent API/UI/CLI
behavior, tenant ownership, quota, audit, billing, notification, recovery and
deletion semantics.

Estimated new code: 60k–120k after P0.

### Phase 6 — Selective P2, not a single release

Status: defer until P0/P1 evidence is repeatable and demand is proven.

Candidate independent programs:

- multi-site failure domains and disaster-recovery routing;
- autoscaling and forecast-driven procurement;
- spot/preemptible capacity;
- managed training and checkpoint lifecycles;
- marketplace and publisher entitlement;
- organization federation and delegated enterprise administration;
- advanced FinOps, commitments and reservation trading; and
- additional GPU families and topology-aware distributed workloads.

Each program needs its own product contract, security boundary, service
objective, operations owner and acceptance campaign. Do not combine them into
one “AWS parity” milestone.

Estimated new code: 300k–700k+ across multiple programs.

## Buy, integrate and build boundaries

| Capability | Preferred approach | LunaNexa responsibility |
| --- | --- | --- |
| Workload orchestration | Kubernetes | GPU-specific desired state, placement, admission and lifecycle reconciliation |
| Identity/MFA | Enterprise IdP such as OIDC/SAML provider | Map verified identities into typed tenant and operator authority |
| Secrets/keys | Vault, KMS or deployment secret manager | Narrow references, rotation evidence and least-privilege delivery |
| Networking | Cilium, Calico or approved cluster provider | Offer bounded network profiles and verify enforced state |
| Storage | Approved S3 plus Ceph/Longhorn/managed storage where required | Assignment-bound model transfer and tenant storage policy/evidence |
| Metrics/logs | Prometheus/OpenTelemetry and established backend | Typed low-cardinality events, receipts, SLOs and export proof |
| Database | Managed PostgreSQL or reviewed HA operator | Schemas, transactions, migrations, fencing and reconciliation |
| Payment/invoice/signature | Approved enterprise providers | Provider-neutral intent/evidence state and durable reconciliation |
| Model serving | Pinned vLLM, SGLang or other qualified runtime | Adapter lifecycle, routing, health, policy and measured qualification |

LunaNexa should not become an identity provider, object store, virtual-network
implementation, payment gateway, general container engine or metrics database.

## Release sequence and commercial promise

The recommended release sequence is:

1. four-node internal pilot;
2. shared production foundations;
3. managed inference limited availability;
4. managed inference general availability for the accepted site and models;
5. dedicated workspace limited availability;
6. dedicated workspace general availability only after repeated physical
   reclaim evidence; and
7. focused P1 cloud primitives driven by observed customer needs.

Until Phase 3 is accepted, describe LunaNexa as a deployment candidate and
internal platform—not an available managed-inference service. Until Phase 4 is
accepted, do not issue customer machine credentials. A contract, invoice or UI
status cannot override these operational gates.

## Completion rule

A phase completes only when its listed behavior is exercised through the same
production-facing UI/API boundary, its external effects are independently
observed, restart and adversarial cases pass, retained evidence identifies the
environment and acceptors, and the protected readiness projection reports no
blocker. Code completion or a green local release gate alone is insufficient.
