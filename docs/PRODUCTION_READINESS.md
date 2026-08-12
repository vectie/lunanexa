# Production readiness and adversarial test record

Date: 2026-08-11
Target topology: one management node, `/data/models`, and four DGX Spark nodes

## Decision

The repository is a **production candidate**, not an authorization to serve
production traffic. The deterministic software gates described below pass in a
local four-process DGX simulation. Production approval remains blocked on the
physical-cluster, transport, artifact, runtime, backup and human acceptance
evidence listed in this document.

The managed model-service path is the path under test. Interactive exclusive
node leasing remains non-production even though the node-local signed-generation
guard, automatic/offline expiry, early termination and a root-owned reference
helper are implemented: each deployment must still review its writable-path,
account/SSH/rootless-container policy and validate destructive cleanup on the
physical DGX image.

## Security and failure model

The test campaign assumes that callers, catalog documents, node heartbeats,
persisted state and browser inputs can be malicious or corrupted. It exercises:

- authentication confusion, missing credentials and wrong credential scopes;
- malformed JSON, invalid UTF-8 and oversized request bodies;
- path traversal, percent-encoded traversal, HTML/script text, control
  characters, Unicode and identifier boundary attacks;
- forged, expired, stale-generation, wrong-epoch and wrong-node heartbeats;
- duplicate node/device inventory intended to manufacture fake capacity;
- catalog artifacts, runtime names, health routes and egress settings intended
  to escape the approved execution boundary;
- concurrent retries, exact idempotent replay and same-key/different-intent
  conflicts;
- state-file tampering, wrong signing authority and controller/node process
  termination;
- node saturation, runtime failure, drain rerouting and controller recovery;
- response leakage of credentials, loopback addresses, node IDs and host paths;
- browser-side script injection, invalid deployment parameters, localization,
  disabled, empty and success states.

Out of scope for the local campaign are kernel/container breakouts, supply-chain
compromise of trusted build tools, volumetric network denial of service, real
NVIDIA hardware faults, and compromise of the external secret manager, CA,
S3-compatible service, registry or TLS proxy.

## Implemented hardening

### Public deployment boundary

- Native HTTP request bodies are streamed through a 1 MiB hard limit. The
  listener returns `413` without assembling an unbounded body and rejects
  invalid UTF-8 with `400`.
- Deployment identifiers, idempotency keys, the fixed `replicas = 1` invariant,
  and lease durations use the same checked contract at plan and mutation
  boundaries.
- Artifact references accept a constrained `s3://bucket/object` form and reject
  traversal, empty path segments, query fragments and percent-encoded escapes.
- Templates require controller and artifact-store connectivity, reject arbitrary
  egress, and bound resource, health, rollout and secret-reference fields.
- Runtime name, version, digest, architecture and capability declarations are
  checked for unsafe or inconsistent values and duplicate declarations.

### Placement and reconciliation

- Placement validates node and device identifiers, deduplicates node IDs and
  refuses duplicate-device inventory. Duplicate reports cannot satisfy the
  exclusive one-machine assignment.
- A deployment is ready only when its assignment is signed and unexpired and
  the node heartbeat is active, fresh, identity-consistent, on the controller's
  epoch, and has observed at least the assignment generation.
- Reconciliation remains `Reconciling` until the assigned node reports the new
  generation; an old heartbeat can no longer make a new generation appear
  ready.

### Durable state and retry safety

- `lunanexa.deployments.v2` signs the complete deployment snapshot, including
  catalog templates and operations, with the deployment signing authority.
  Tampered state or a wrong authority fails closed before loading.
- Thirty-two concurrent submissions using the same idempotency key produce one
  durable operation.
- Exact replay returns the original operation. Reusing the key with a changed
  desired state returns `409 IdempotencyConflict` and creates no assignment.

`lunanexa.deployments.v2` is not backward-readable as v1. Before upgrading an
existing installation, fence mutations, retain a verified v1 backup, and use a
reviewed migration or recreate the deployment-operation snapshot from an
authoritative source. Do not point the new controller at an unreviewed v1 file.

PostgreSQL schema v2 scopes enterprise lease-request idempotency to tenant and
subject. This prevents a tenant from colliding with another tenant's retry key.
Portal snapshot restore also rejects duplicate active subjects, cross-membership
lease records and duplicate scoped retry keys. Free-text limits are enforced on
the stored value before trimming and reject NUL/line controls, preventing
whitespace amplification and forged multiline audit/UI values.

### Operator console

- The one-click action is disabled until the service identifier matches the
  public contract and an approved template is selected. Capacity is displayed
  as one service on one assigned machine and cannot be edited in the UI.
- Inputs expose visible recovery text, `aria-describedby` and `aria-invalid`;
  all controls retain associated labels and a 44 px minimum height.
- Dynamic template/operator strings remain escaped. The controller remains the
  authoritative validator even after browser validation succeeds.

## Automated evidence

### Deterministic fuzz and adversarial corpus

`deployment/adversarial_test.mbt` executes more than 5,000 deterministic
mutations on every run:

- all deployment and idempotency-key lengths across and beyond their limits;
- every replica value from -128 through 128, proving that only `1` is accepted;
- lease-duration minimum, maximum, zero, negative and integer-extreme values;
- eleven forbidden character/Unicode mutations injected at every position of
  128- and 256-character identifier envelopes;
- malicious S3 paths, runtime names, egress, readiness paths, resource limits,
  duplicate secrets, architectures, capabilities, nodes and devices;
- placement input permutations to prove stable selection.

This is deterministic mutation and boundary fuzzing, not coverage-guided native
fuzzing. It is deliberately reproducible in the release gate. A future
coverage-guided harness should be added when the native MoonBit toolchain offers
a supported sanitizer/fuzzer integration suitable for the production build.

`portal/adversarial_test.mbt` adds more than 10,000 deterministic portal
mutations covering every identifier length through 300, injection bytes at
every position of 256-character identifiers, requested-model cardinality,
free-text length/control boundaries, reserved Unix accounts and extreme time
ranges. The PostgreSQL integration harness starts from schema v1, upgrades to
v2, round-trips SQL-injection payloads only as bound data, rejects dynamic table
names outside an allowlist, proves cross-tenant retry independence, and proves
that a duplicate active-identity constraint failure rolls back both snapshot
and projections.

### API and native transport

The API corpus verifies:

- absent, malformed, suffix-appended and wrong-scheme credentials return `401`
  without changing state;
- malformed JSON and wrong JSON types return `400` across catalog, plan and
  deployment routes;
- hostile templates and intents cannot create assignments;
- the native socket listener rejects a 1,048,577-byte body with `413` and
  invalid UTF-8 with `400`;
- exact replay produces one assignment and a conflicting replay produces
  `409`;
- hostile paths return `404` without echoing attacker text;
- responses are scanned for configured secrets, loopback/private addressing and
  host paths.

### Persistence, process and four-node behavior

The retained local campaign is at
`/tmp/lunanexa-production-simulation-20260810`. Its summary records passing:

- four unique node enrollments;
- one-click template registration, executable preflight and creation;
- assignment of the model service to `sim-dgx-1` only;
- exact-replay idempotency and changed-intent conflict rejection;
- signed assignment reconciliation and bounded queueing;
- runtime failover and draining-node rerouting;
- controller and node process restart;
- workspace revocation and post-revocation denial;
- public-response topology/authority leak scanning.

The simulator uses opaque local runtime/artifact doubles. Its
`hardware_performance_validated` field is intentionally `false`.

### Browser validation

The built Rabbita console was exercised in the in-app browser against demo and
empty states. The following checks pass:

- script-like service names are rendered as text, inject no script, receive
  `aria-invalid=true`, and disable deployment;
- 129-character names are rejected and 128-character names are accepted;
- the catalog has no replica input, displays the fixed-capacity policy, and the
  API rejects every non-one replica value;
- a valid submission produces a visible live success receipt and no fake
  controller operation in demo mode;
- Simplified Chinese updates the document title, route heading and form labels;
- semantic snapshots expose a skip link, labeled navigation, headings, labels,
  table captions, disabled state and a live status region;
- the established 390 × 844 responsive check has no document-level horizontal
  overflow. The CSS floor is 320 px and the release stylesheet includes a
  narrow-layout breakpoint and reduced-motion override.

Manual assistive-technology testing with VoiceOver/NVDA and physical touch
testing remain release-candidate acceptance tasks; semantic browser inspection
does not replace them.

### Consolidated gate and coverage baseline

After hardening, a focused four-node run and `scripts/release-gate.sh` passed
back-to-back. The consolidated result was:

- 228/228 native MoonBit tests;
- 51/51 MoonBit JavaScript tests across console, enterprise, workbench and workspace;
- 8/8 editor-client tests;
- process recovery, four-node simulation, isolation, dependency, image,
  contract, secret, response and evidence-export checks.

An earlier complete-gate run exposed an intermittent five-to-ten-second
reconciliation timeout even though the focused run passed. The harness now
allows a bounded 30-second controller-to-node-to-heartbeat window and emits
controller/node log tails on failure. The subsequent focused and complete runs
both passed; a timeout is still a gate failure, not a retry-to-green policy.

Instrumented coverage reports 5,148/7,848 lines (65.6%) across instrumented
MoonBit sources. The deployment planner is 158/188, deployment store 120/156,
deployment reconciler 11/12, and Rabbita console 1,200/1,265. Shell-spawned
command binaries appear as zero in this report even though their process paths
are exercised by the recovery and four-node scripts. Coverage is evidence, not
proof: uncovered management error/lifecycle branches and the absence of an
enforced coverage floor remain reasons to require the physical campaign and
review critical diffs before promotion.

## Reproducing the software campaign

From a clean reviewed checkout:

```sh
moon test deployment/adversarial_test.mbt --target native --deny-warn
moon test portal/adversarial_test.mbt --target native --deny-warn
moon test deployment/store --target native --deny-warn
moon test api/deployment_http_test.mbt --target native --deny-warn
sh scripts/postgres-integration-test.sh
moon test ui cmd/console --target js --deny-warn
sh scripts/four-node-simulation.sh /secure/evidence/lunanexa-simulation
sh scripts/release-gate.sh
```

To compose the hostile inputs, artifact/cache boundary, OCI policy, recovery
and four-node disruption into one retained synthetic evidence directory:

```sh
sh scripts/production-fault-simulation.sh /secure/evidence/lunanexa-faults
```

This is a rehearsal of production invariants, not a substitute for the physical
acceptance gates below. Its summary intentionally records the non-simulated
claims as `false`.

The 2026-08-10 campaign passed with retained evidence at
`/tmp/lunanexa-production-faults-20260810`. It verified selected-node-only
materialization across four independent cache roots, corrupt artifact
quarantine, assigned-cache preservation, hardened OCI arguments, generic
network rejection, control-plane attacks, restart fencing and four-node
disruption. The final repository gate then passed 228/228 native tests.

Run the process and four-node commands only on an isolated test host. The
explicit simulation path retains credentials and state generated for the test;
protect or destroy it according to the test environment's evidence policy.

## Physical production acceptance gates

Do not promote the release until each item has a named owner, timestamp and
immutable evidence reference:

1. **Transport:** real client-authenticated TLS from each DGX rejects an unknown
   CA, wrong node identity, expired certificate, replayed heartbeat and direct
   unauthenticated access.
2. **Artifact path:** a selected DGX downloads from the protected service backed
   by `/data/models`; the other three DGX caches remain unchanged. Wrong digest,
   size or detached signature must quarantine the artifact and prevent runtime
   launch.
3. **OCI/runtime:** approved images are digest pinned and signature checked;
   the container has no privileged mode, host network, engine socket, writeable
   model mount, artifact credential or unexpected capability.
4. **Network isolation:** default-deny policy permits only controller, artifact,
   registry and approved inference gateway paths. Cross-tenant and direct
   container access must fail.
5. **Four-node disruption:** repeat one-click placement, saturation, runtime
   death, cordon, drain, agent restart, controller restart and management-node
   reboot on the actual cluster.
6. **Storage pressure:** fill the node cache to its configured high-water mark,
   prove only unpinned artifacts are evicted, and verify an in-use model is not
   removed.
7. **Backup and restore:** restore all controller-owned snapshots and model
   metadata on a clean management node, reconcile with a higher epoch, and meet
   the declared RPO/RTO. The current core v2 backup bundle alone is incomplete
   for workspace, deployment and exclusive-lease state.
8. **Observability:** confirm metrics, alerts, audit export, clock-skew alerts,
   disk pressure and certificate-expiry alerts without prompt, output, token,
   internal path or node-address leakage.
9. **Capacity and safety:** record thermal soak, concurrent model load,
   throughput, latency, GPU-memory headroom and failure recovery on each DGX.
10. **Human approvals:** security, infrastructure, model-risk/license and
    operations owners sign the immutable image, model and runbook evidence.
11. **Lease reset:** exercise both natural expiry and operator termination with
    active SSH sessions, processes, rootless containers and volumes. Prove
    access material/account/home/runtime state are absent, the next lease starts
    clean, and any deliberately unkillable residue quarantines the node.

## Release blockers that must remain visible

- The DGX lease watchdog, fixed protocol and reference root helper are bundled;
  physical DGX validation and deployment-specific writable-path/SSH/container
  isolation remain required.
- LunaNexa relies on an external mTLS proxy/service mesh, OCI registry,
  certificate authority, secret manager and metrics backend. The artifact
  gateway itself is built in and still requires protected `/data/models`
  storage and backup.
- The base deployment templates contain placeholders and are not production
  overlays.
- The node supervisor does not publish the production inference gateway; the
  approved node-local HTTPS route must be supplied and tested externally.
- Real DGX performance, thermal behavior and NVIDIA/runtime compatibility have
  not been demonstrated by the local simulation.
- PostgreSQL plus signed controller-PVC backups cover the implemented stores;
  production WAL archiving, PITR and restore evidence are still external gates.
