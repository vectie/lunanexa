# Implementation status

## Repository implementation

The repository now implements the deployable LunaNexa baseline:

- typed and validated v1 workload, node, assignment, telemetry, audit, model,
  runtime and streaming contracts;
- native HTTP control and provider-neutral client transports with cancellation,
  bounded bodies, timeouts, idempotency scoping, pre-output bounded retry, SSE
  normalization and truncated-stream rejection;
- atomic durable state for controller, registry, enrollment, scheduler and
  telemetry snapshots, each with an explicit schema version;
- model/license/evaluation/alias lifecycle enforcement, S3 digest streaming,
  fixed-command Cosign verification adapters and digest-pinned OCI supervision;
- controller-signed model-service catalog templates, deterministic one-click
  deployment plans and restart-safe operations, plus selected-node resumable
  model download, local size/digest/Cosign verification, atomic cache
  publication and read-only runtime mounting;
- per-node hashed credentials, short-lived enrollment, certificate expiry and
  rotation, HMAC-authenticated/replay-fenced heartbeats, signed assignments,
  generation/epoch fencing, OCI identity/health inspection, truthful-ready
  heartbeat reporting, ready-assignment placement filtering and lease/orphan
  cleanup;
- deterministic hard-filter/scored placement, drain-aware routing hints,
  deterministic alternate-node failover before the first unary or streaming
  output, capacity forecasts, durable windowed quotas, a bounded observable
  runtime queue, deadlines and queued/running cancellation;
- canonical receipt-bearing terminal failures that distinguish caller
  cancellation, deadline expiry, retryable runtime loss and non-retryable
  upstream rejection;
- live Rabbita views for cluster, registry, assignments, policies, telemetry,
  benchmarks and audit, with confirmed cordon/drain/rollback controls and
  shared public read-contract DTOs used by both browser and automation clients;
- deterministic technical policy cores and authenticated decision endpoints for
  prewarm, probes, cache reconciliation, autoscaling, backpressure, transfer
  grants and reviewed sidecars;
- a commercial contract core for organizations, cost centers,
  projects, rating, ledger finalization, budgets, quotas, commitments, RBAC and
  digital agreements, plus normalized external-provider evidence records,
  with restart-complete PostgreSQL snapshots and atomic callback/business commits;
- Rabbita routes for cost-center posture, digital agreement evidence and
  qualified-service adapters, with explicit non-production marking for the
  LunaFide deterministic test simulator;
- durable workspace users, access grants and leases with restart-safe state,
  expiry/revocation enforcement, trusted-ingress subject derivation and
  immutable operator audit receipts;
- a separate signed, durable exclusive-node lease authority with validated
  username/credential references, generation-fenced cleanup states, one
  non-terminal lease per node, management API/CLI operations, node cordon/drain
  directives and immediate exclusion from managed assignment, placement,
  deployment-preflight and capacity calculations;
- a durable enterprise portal authority with tenant memberships and roles,
  immutable agreement projections, external-signature request/execution
  separation, agreement-gated lease submissions and generation-fenced operator
  review that reserves exactly one selected node without accepting a password;
- durable hashed API credentials with tenant/subject/model scopes, expiry,
  revocation, bounded request counters, one-time secret disclosure, model
  discovery and canonical/OpenAI-compatible non-streaming inference entry;
- a DGX-side exclusive-lease guard with local generation state, offline expiry,
  fixed helper actions, sanitization/quarantine fencing and authenticated
  lifecycle observations back to the controller;
- live Rabbita management views for workspace authority and enterprise lease
  approval, plus an enterprise portal for agreements, lease requests, costs and
  the shared model catalog, and a same-site individual workbench with browser-local editing, self-readiness,
  canonical inference transport, bounded receipts and typed
  VS Code/CodeBuddy/WorkBuddy/Trae/Qoder handoff states;
- shared native/JavaScript workspace user, grant, lease, session, capability
  and integration contracts, and a VS Code extension that stores a scoped
  token in SecretStorage and sends only explicitly selected text under
  ephemeral policy;
- a MoonBit benchmark driver for named concurrency, saturation, cold-start,
  long-stream and mixed-workload evidence with node-utilization joining;
- a native evidence exporter that binds named benchmark summaries to capacity
  and service-objective recommendations and atomically exports the final
  acceptance bundle; and
- Kubernetes templates, recovery/security/acceptance runbooks and automated
  structural-isolation and leak scans; and
- a simulation-only four-node process cluster covering enrollment, signed
  reconciliation, strict per-node routing, bounded queueing, runtime failure,
  drain rerouting, node restart, controller restart and response leak checks.

Controller fencing is durable and cross-process: a restarted controller must
acquire a strictly newer epoch, stale API mutations fail with the typed
`StaleControllerEpoch` response, and the durable store refuses a write if a
successor has advanced the epoch. Reconciliation-only controllers expose a
typed `GET /v1/recovery/plan` view for missing assignments, expired leases,
orphan runtimes, and unreachable nodes.

Run:

```sh
sh scripts/release-gate.sh
```

The gate formats and regenerates interfaces, checks/tests the native target,
checks/tests the JavaScript Rabbita UI, and runs isolation, dependency, image,
secret, contract, and response scans. It also runs the four-node functional
simulation and a local process recovery
drill: the compiled controller and node agent are killed and reconstructed from
durable state, a higher controller epoch enters reconciliation-only mode, and a
same-epoch controller is rejected. Third-party runtime process recovery remains
part of real deployment acceptance because LunaNexa does not ship a model
server.

The simulator is functional evidence only. Its summary always records
`hardware_performance_validated: false`; it does not reduce the physical DGX,
production-provider, measured-performance or human-acceptance requirements
below.

Enterprise membership, portal agreement/lease-request, workspace user/grant/
lease and admission state have a transactional PostgreSQL adapter with
normalized indexes and restart tests. Commercial ledger state, provider
callback history, API credentials, prewarm operations and transfer replay
nonces are now restart durable; commercial callback and business snapshots
commit atomically. LunaFide remains functional contract evidence, not
production trust infrastructure, and must be replaced by approved real
providers.

## External acceptance still required

The following are release acceptance work, not facts this repository can
truthfully manufacture without private deployment inventory and external
systems:

- enroll and exercise the four physical DGX Spark nodes;
- choose and run a licensed model with a signed upstream serving image;
- configure and verify production OCI, S3, metrics, CA/mTLS termination,
  identity, commercial database, qualified signature, payment, invoice,
  encrypted-retention and secret providers;
- implement and test the consumer-side adapter in its owning repository;
- collect real concurrency, saturation, cold-start, long-stream, mixed-load,
  restart, drain, and failover measurements;
- scan built images and live runtime environments;
- obtain named human security, operations, and license acceptance.

`EvidenceBundle.release_ready()` deliberately remains false until benchmark
evidence, report references, scenario success, isolation success, and a named
acceptor are all present.

The built-in controller targets one digest-pinned text adapter contract and can
resolve scheduler node IDs through a validated, strict per-node HTTPS endpoint
map. A deployment may instead configure one trusted node-aware gateway, in
which case the selected node is carried as an authenticated routing hint.
Additional adapter protocols and topology-validated multi-node serving remain
disabled until their deployment profiles are measured and approved.
Non-ephemeral workload retention is rejected unless an encrypted external
retention provider is added; LunaNexa never silently drops or stores a
retention request.

The durable workspace directory is not an identity provider: production still
requires an ingress or service-mesh identity mapping, credential issuance and
revocation operations. The workbench and VS Code extension are working
northbound transports; third-party developer-tool handoffs remain typed
integration points rather than bundled vendor runtimes.

Exclusive-node leasing implements the management authority, placement fence,
node-local offline-expiry watchdog, fixed provision/revoke/sanitize/quarantine
protocol and observation receipts. The root-owned host helper remains a
deployment component because account databases, SSH policy and container-engine
isolation are host-specific. Until that reviewed helper and its physical-DGX
tests exist, a lease must not be treated as production interactive access.
