# LunaNexa architecture

## Bounded operator projections

Operator lists use the shared `operator_read` wire envelope and controller-owned
read projections. Filtering and the 25-row window precede expensive access-record
projection and JSON transfer. The browser keeps only the visible table window,
separate minimal personnel choices, and per-list cursor/search generations.
Parallel initial reads replace the previous account/workspace/access/audit full
snapshot downloads. Search is debounced; superseded search requests are aborted.

The underlying stores still expose in-memory snapshots: filtering/counting is
linear in source records, not an indexed database seek. There is no server-held
pagination session or additional polling. The ownership projection adds one cheap
ledger read to the existing core refresh without adapter health calls. Native
HTTP fixtures cover page bounds, cursor binding, append-stable audit traversal,
authority separation and reconciliation-only reads. These are distinct from
authenticated production-browser acceptance.

## Unified model-service authority (2026-11-07)

The active migration is specified in [unified model services](UNIFIED_MODEL_SERVICES.md).
Operator and tenant lifecycle requests must converge on the deployment service
ledger and the same reservation/conflict checks. Runtime adapters describe
execution mechanics; model-family names are not control-plane branches.
Existing process/Kubernetes instances are adopted without recreation. See the
migration document for acceptance and preservation requirements; this paragraph
does not assert that the deployed migration has completed.

## Exclusive delivery target

The 2026-09-23 [exclusive-node design](EXCLUSIVE_NODE_DELIVERY.md) is the current
implementation target. Legacy descriptions below document the existing managed
and bare-metal paths, not a one-node-per-order product restriction.

Delivery intent joins existing authorization with one durable whole-node
reservation and one resumable operation:

`authorized → reserving → preparing model → loading model → starting workspace → ready`

IaaS may omit model preparation; MaaS omits application startup. Readiness must
come from the appropriate runtime response, not handoff creation or Pod phase.
Failed operations keep their stable identity and completed resources for retry;
termination closes ingress before stopping workloads and releasing the node set.
Both browser sites project this same operation, not independent UI state.

Scheduler placement and runtime launch consume the same reservation authority.
Cache locality ranks only otherwise eligible nodes. Model cache retention is
independent from user-volume retention and allocation ownership. Public ingress
ends at the management-host workspace gateway; application/model backends remain
private. This design introduces no reverse MoonSuite dependency and no new
container engine or model server.

## System context

LunaNexa is a boundary between model consumers and hardware. The boundary is
more important than the initial four-node topology: application decisions stop
above it, while placement and runtime decisions start below it.

Management, compute and operator-network ingress are independent concerns.
Management and compute are logical roles that may be separated for production
failure isolation or explicitly co-located for a constrained lab profile. A
bastion/access node is optional operator-network infrastructure, not a
LunaNexa component, scheduler role or daily-use requirement. Direct routing,
VPN, private ingress and OpenSSH `ProxyJump` are deployment choices outside the
node protocol.

```mermaid
flowchart TB
    subgraph Consumers["Consumer trust domain"]
      MS["MoonSuite applications"]
      OC["Other authorized clients"]
      MG["MoonGate"]
      MS --> MG
      MG -->|"LunaNexa contract"| API
      OC -->|"LunaNexa contract"| API
    end

    subgraph Control["LunaNexa management trust domain"]
      API["Northbound API"]
      CTRL["Reconciliation controller"]
      SCH["Scheduler and admission"]
      REG["Model/runtime registry"]
      STORE["Metadata and audit store"]
      COM["Commercial control<br/>cost centers, ledger, agreements"]
      TECH["Technical policy<br/>prewarm, probes, cache"]
      QPORT["Qualified-service ports"]
      UI["Rabbita management console"]
      WB["Rabbita developer workbench"]
      API --> SCH
      CTRL <--> SCH
      CTRL <--> REG
      CTRL <--> STORE
      API --> COM
      CTRL --> TECH
      COM --> QPORT
      UI --> API
      WB --> API
    end

    subgraph External["External provider trust domains"]
      QSP["Approved identity, signature,<br/>payment and invoice providers"]
    end

    QPORT <-->|"signed normalized callbacks"| QSP

    subgraph Cluster["GPU execution trust domain"]
      N1["Node agent + runtimes · DGX 1"]
      N2["Node agent + runtimes · DGX 2"]
      N3["Node agent + runtimes · DGX 3"]
      N4["Node agent + runtimes · DGX 4"]
    end

    CTRL <-->|"mTLS desired state and heartbeat"| N1
    CTRL <-->|"mTLS desired state and heartbeat"| N2
    CTRL <-->|"mTLS desired state and heartbeat"| N3
    CTRL <-->|"mTLS desired state and heartbeat"| N4
```

## Plane separation

### Northbound provider plane

The API validates authentication, typed contracts, quotas, idempotency,
deadlines and data policy. It translates compatibility requests into the
canonical workload envelope and exposes streaming without revealing topology.

The native controller sits behind a trusted ingress or service mesh that
terminates TLS and validates client certificates. Southbound calls also carry
per-node hashed authority, HMAC-authenticated canonical heartbeats,
certificate-expiry checks and replay fences. These application checks do not
replace deployment mTLS; they limit damage if a trusted path is misrouted.

MoonGate remains responsible for deciding whether LunaNexa or an external
provider should satisfy a MoonSuite request. LunaNexa never calls back into a
MoonSuite product to make a scheduling decision.

The adopted four-replica model pool owns typed MTP, prefix-cache and chunked
prefill intent. UI actions persist that intent and compare the observed
Deployment arguments, image and generation before reporting readiness. A
routing-only update does not restart runtimes. The event router may use
tenant-scoped prefix-digest affinity with a bounded load skew; no GPU KV bytes
or raw prompts enter the router. The remote-text adapter derives authenticated
cache salts and returns only usage counters to evidence. Benchmarks enter via
the normal public MoonGate path with 32 separate, short-lived user credentials;
cache statistics, latency timings and quality checks are separate evidence.

Model-pool journals also retain a selected node subset and human display names.
Configured Kubernetes authority remains restricted to the four original
Deployment names. Routing uses the persisted subset even when the selected
model route is inactive, so rollback cannot silently reintroduce parked nodes.
An explicit UI scope action requires zero tracked in-flight streams before
scaling excluded adopted services to zero, with UID/resourceVersion checks.
Subsequent model/configuration actions touch only selected services. This is
resource selection, not a per-user or per-node concurrency limiter.

### Control plane

The controller stores desired state and continuously reconciles observed state.
Operations such as deploy, drain, promote, roll back and delete are
declarative state transitions rather than shell-command sequences.

The scheduler filters by hard requirements first—runtime, architecture,
memory, license, data locality and health—then scores remaining nodes by
available capacity, warm models, queue delay, reliability and operator policy.
Its decision is deterministic for the same state and policy version.

### Management intent plane

The management intent plane owns controller-signed catalog templates,
deterministic deployment preflight, durable model-service operations, and
provider-neutral service endpoints. A one-click deployment submits one compact,
idempotent intent; the controller expands an executable plan into the same
signed desired assignments used by existing automation.

This layer cannot waive registry, license, verification, alias,
data-class, secret-reference, or capacity requirements. Missing prerequisites
produce a durable blocked operation with typed findings. See
`docs/MANAGEMENT_PLANE.md`.

### Commercial and agreement plane

The commercial core owns an opaque organization → cost center → project
hierarchy, exactly-once usage rating, immutable finalized periods, linked
adjustments, budgets, quotas, capacity commitments, RBAC and versioned agreement
evidence. Provider-specific identity, payment, invoice and signature records
are normalized at the boundary; raw provider references are hashed in public
snapshots.

Commercial mutations are subject to the same authenticated operator boundary
as deployment control. Production state is restored from PostgreSQL snapshots,
and commercial plus integration callback state is committed together. Lease
approval calls commercial admission directly, so organization verification,
project ownership, quotas and hard budgets are not merely advisory UI checks.

`LunaFide` is an isolated deterministic test double for this external boundary.
Its callbacks are replay-, sequence-, tenant- and aggregate-checked, but its
test MAC is explicitly not a qualified signature. It cannot satisfy a
production trust, payment or tax requirement.

The machine-commerce authority is a separate durable aggregate layered on this
commercial plane. It owns active sellable SKUs, live-capacity projections,
HMAC-bound quotes, prepaid orders, lifecycle generations, reservations and usage
receipts. Public requests derive tenant, organization, project and purchaser
from the selected account membership. They cannot name physical infrastructure.
The supervised reconciler waits for authenticated settlement before it selects
a matching fresh heartbeat, creates either an exclusive lease or managed model
deployment, and advances the order. Its provider outbox has an explicit
`PaymentRefund` kind so compensation is observable, retryable and distinct from
a new checkout. File snapshots are a local fallback; the production profile
uses the PostgreSQL snapshot domain `machine_commerce`.

Dedicated endpoint access keys are recorded only as key identifiers in the
machine aggregate; raw secrets remain in the access authority and are shown once.
At inference admission the binding constrains eligible assignments to the exact
paid deployment and rejects serving adapters that cannot enforce direct-node
routing. Early termination immediately invalidates that binding. Dedicated
requests still create usage evidence, but skip shared-MaaS rating because the
capacity interval was prepaid.

### Technical decision plane

Prewarm transitions, health-probe evaluation, safe cache telemetry, bounded
admission, short-lived transfer grants and reviewed sidecar profiles are
deterministic decisions. Prewarm state and transfer nonces are durable, while
artifact bytes are served only after a live assignment and one-time grant pass.
The production profile intentionally excludes autoscaling and batch jobs.

### Browser experience plane

The hosted WebIDE bridge supports optional deployment-owned browser-principal
authorization and an authenticated request handler. These are generic callbacks,
not product schemas or reverse dependencies: consumers can bind their platform
identity to the existing controller-issued grant and serve redacted self views
on the trusted gateway. Browser identity is checked before provisioning, on
every HTTP request and during WebSocket renewal. Definite mismatches invalidate
that browser session; authority outages deny access without destroying saved
work. Browser credentials still never enter personal workspace backends.

A product may place its public read-only shell at its established product base
and mount the private execution gateway at that base plus `/workspace`.
The bridge accepts only those two product-scoped bases (or its standalone base),
never a sibling product's path. Ingress must strip the selected base exactly.
This separation does not grant a workspace, relax model admission, or make the
public shell an execution proxy.

LunaNexa ships two Rabbita browser sites from shared public contracts:

- the management console presents cluster health, users, access grants,
  capacity leases, models, deployments, policy and audit evidence;
- the enterprise site presents onboarding, agreement signing requests, lease
  requests/status, tenant cost/model views, self-service organization creation,
  prepaid machine ordering and a local-browser WebIDE with generic model
  invocation and approved editor handoffs.

An approved desktop handoff crosses the browser boundary with only a
short-lived, single-use code in a URL fragment. The local client removes that
fragment, redeems through an administrator-pinned issuer and keeps the resulting
lease-scoped API credential in its local provider gateway. LunaNexa stores only
digests and rechecks active workspace authority on every credential use.
The explicit private-cloud profile replaces the rental-contract prerequisite
with administrator-granted workspace access; commercial order-bound credentials
never acquire that exemption. The default profile retains contract admission.
Product-specific translation stays outside LunaNexa's source boundary.

Published clients may have separate model scopes. A shared media editor can
use qualified trial providers while text applications retain the company's
reserved text model. External media provider configuration is loaded before
the durable media runtime is constructed. Each provider has an approved
artifact, tenant, node and generation, a loopback relay to its fixed upstream,
and a mounted credential reference. Readiness probes the actual model listing;
job ownership, capability budgets and immutable runtime attribution remain in
LunaNexa. These providers do not masquerade as reconciled node assignments.
Reference images cross the contract as bounded embedded data and become
provider multipart files only after the approved profile validates them.

The enterprise portal writes only tenant-scoped intent. It does not accept a
node ID or raw access secret. The operator console selects one eligible node;
the controller then creates a credential reference and reserves the existing
exclusive-node lease authority idempotently. See `docs/ENTERPRISE_PORTAL.md`.

The workbench is not implicitly a remote administration channel. A
`WorkspaceLease` remains a time-bounded entitlement to control-plane admission
and model capacity, not a DGX login. A separate `ExclusiveNodeLease` may name
one DGX and one user. The two contracts cannot be substituted for one another.
VS Code, CodeBuddy, WorkBuddy, Trae, Qoder and future integrations use scoped
northbound contracts in managed-service mode; any user runtime on a DGX exists
only inside an explicit exclusive lease.

### Exclusive access plane

Each node has one effective operating mode: `ManagedService` or
`ExclusiveLease`. Reserving an exclusive lease immediately removes the node
from scheduler eligibility and issues a cordon directive. The lease authority
then reconciles provisioning, activation, expiry, drain, access revocation and
sanitization. Completion is the only normal path back to managed service;
unproven cleanup quarantines the node.

The contract carries a username and credential reference, never a password or
private key. A narrow host provisioner resolves that reference and performs
allowlisted account and access operations. See `docs/EXCLUSIVE_NODE_LEASES.md`.

### Node plane

Each DGX runs one small LunaNexa node agent. It inventories devices, verifies
assignments, materializes pinned artifacts only for assignments naming that
node, supervises runtime containers, performs health checks, enforces local
limits and reports bounded telemetry. In exclusive mode the same protected
daemon also observes the lease generation and local expiry; the leased account
cannot modify or stop it.

Materialization is a node-owned state transition before runtime preparation:

```text
assigned → downloading → digest verified → signature verified
         → atomically cached → read-only mounted → runtime ready
```

Downloads use an assignment-sized, content-addressed cache under the
deployment-owned node state directory. Partial transfers are resumable and
never become visible as complete artifacts. Cache hits are reverified after an
agent restart. A digest or signature mismatch quarantines the local candidate
and prevents runtime launch. When no desired assignment on that node references
a digest, reconciliation removes the local cache entry. The runtime container
sees a fixed local model path and no artifact URI or storage credential.

The node agent does not implement application workflows or accept arbitrary
remote shell commands. Debug access is a separately authorized operator action,
not part of routine reconciliation.

### Data plane

Event trials reuse account authority and workspace enforcement. A durable event
policy binds each trial tenant to one approved text model and four existing
trial-pool nodes. Readiness uses the same approved assignments, fresh heartbeat,
strict endpoint map and reservation boundaries as normal placement. A bounded
least-in-flight reservation chooses the event replica after scheduler admission;
completion releases it, and the stream remains pinned. Event admission does not
deploy a gateway, allocate nodes or bypass application readiness. See
`docs/EVENT_TRIAL.md`.

Inference traffic is sent only to a ready runtime selected by the scheduler.
The platform supports streaming, bounded queues, cancellation, backpressure,
deadline propagation and idempotent retry where the model operation permits it.
Admission capacity bounds queued plus running work. A separately configured
runtime-concurrency limit controls active adapter calls only when explicitly
positive and below total admission; zero adds no execution semaphore. Accepted overflow waits
under its request deadline, remains cancellable, and reports queue time apart
from accelerator time. Durable active workload IDs reject reconstruction-time
relaunch, while the scoped idempotency key is also propagated to the serving
adapter as defense in depth.
The serving adapter resolves that selected node either through a strict
deployment-owned node-to-HTTPS-endpoint map or through one trusted gateway that
enforces the authenticated node routing hint. In strict mode an absent mapping
fails closed; the generic endpoint is never used as an implicit substitute for
a selected node. Strict-mode placement also requires a non-expired signed
assignment whose deployment ID appears in the node agent's ready-runtime
heartbeat; static inventory or license labels alone cannot make a runtime
schedulable.

Runtime implementations are adapters behind a common lifecycle interface:
inspect, prepare, start, ready, invoke, drain, stop and collect metrics. LunaNexa
does not reimplement CUDA kernels or model servers.

### State and artifact plane

Use durable standard infrastructure through narrow ports:

- transactional metadata store for desired state, generations, leases and
  audit events;
- OCI registry for runtime images;
- an S3-compatible object store reached through the reviewed Moongate endpoint,
  with node-local scoped SigV4 credentials and assignment-bound direct pull;
- Prometheus-compatible metrics and an established log backend;
- deployment-owned secret storage.

Development adapters may be local, but production state must survive controller
restart and must not live only on a DGX node.

Model catalog discovery and artifact ingestion are handled by a separately
deployable, least-privilege model-source adapter. The controller proxies only a
bounded authenticated contract and remains the registry/approval authority; it
does not gain general Internet egress or write access to the model store. The
first source profile is ModelScope and is specified in
[`MODELSCOPE_MODEL_ONBOARDING.md`](MODELSCOPE_MODEL_ONBOARDING.md).

PostgreSQL schema v3 is implemented for enterprise memberships, agreements,
tenant lease requests, workspace users, grants, leases and admission
reservations. Each mutation commits a canonical typed snapshot and normalized
indexed projections together. File persistence for these domains is now an
explicit development fallback. Production controller, registry, enrollment,
scheduler, telemetry, deployment, commercial and technical-policy authority
also uses PostgreSQL snapshots. Exactly one controller holds the session
leadership lock; standby processes restore these stores after election under a
new fencing token. See `docs/DATABASE.md` for the complete domain inventory and
migration procedure. This implementation does not prove external database HA,
backup recovery or interruption-free failover.

The artifact store is authoritative; node-local materializations are disposable
assignment-scoped cache entries. This keeps model transfer out of the management API
process while allowing a selected DGX to start without the serving container
holding object-store credentials.

## Initial four-node acceptance profile

The first acceptance campaign names four DGX Sparks; that is an explicit test
inventory, not a platform-wide node-count invariant. Treat those machines as
independent schedulable nodes, not as one assumed shared-memory machine. Phase
one proves single-node serving. Multi-node sharding or
paired high-speed links are enabled only after the actual network, runtime and
model combination passes a topology-specific benchmark.

The local four-node functional simulator mirrors the four independent node
identities and runtime endpoints with native processes. It validates protocol,
placement and recovery behavior but is not an accelerator or performance
emulator; see `docs/SIMULATION.md`.

Controller placement is a deployment-profile decision. Separation is preferred
when the profile needs compute-failure isolation; constrained labs may
explicitly co-locate management and compute. In either case, loss of any node
covered by the profile's failure claim must not destroy desired state or the
registry. The single-active, standby-controller design retains the node
protocol; the database and deployed failure domains still require separate
availability acceptance.

## Model lifecycle

```text
candidate artifact
→ license and provenance recorded
→ digest verified
→ operator approval
→ canary deployment
→ readiness gate; optional evaluation and benchmark evidence
→ controlled promotion
→ observation
→ rollback or stable release
```

Promotion is never automatic merely because a newer artifact exists. A model
alias points to an approved version, and changes to that pointer create an
auditable policy decision.

## Data minimization

The request payload may contain domain content because inference cannot occur
without it. No other domain context crosses the boundary. The caller should
redact unnecessary identifiers before sending, and LunaNexa should enforce:

- data-class labels and allowed-runtime policy;
- encryption in transit and controlled temporary storage;
- no raw-payload logging by default;
- per-request retention and cache policy;
- explicit controls for evaluation capture or training reuse;
- deletion receipts when retained payloads expire.

Training reuse is opt-in and versioned. An inference request never silently
becomes training data.

## Repository shape to implement

```text
lunanexa/
  cmd/
    control/             # API/controller executable
    node/                # managed-node executable
    cli/                 # operator CLI
  contracts/             # public typed v1 envelopes and receipts
  api/                   # auth, validation, admission and streaming
  controller/            # desired-state reconciliation
  deployment/            # public catalog, intent, plan and operation types
  deployment/store/      # native durable management-plane state and signing
  scheduler/             # filtering, scoring, queues and leases
  registry/              # models, artifacts, runtimes and licenses
  node/                   # node inventory and supervision
  runtimes/               # public adapter interface
  internal/               # private parsers and platform helpers only
  store/                  # durable state ports and adapters
  telemetry/              # metrics, events and bounded logs
  policy/                 # quotas, data classes and placement policy
  workspace/              # provider-neutral workspace, lease and integration contracts
  portal/                 # enterprise membership, agreement and lease-request contracts
  portal/store/           # durable centralized enterprise workflow state
  ui/                     # Rabbita management console generated from typed contracts
  ui/enterprise/          # Rabbita enterprise portal
  ui/workbench/           # Rabbita individual developer workbench
  tests/fixtures/         # non-secret deterministic fixtures
  deploy/                 # manifests and documented deployment overlays
  docs/
```

Public concrete types live in their owning public packages. `internal/*` must
not own types exposed by `contracts`, `scheduler`, `registry` or `runtimes`.

### Adopting an existing model replica pool

The operator may adopt an explicitly configured set of existing Kubernetes
model Deployments. The controller can get and patch only those named resources;
it does not gain workload creation, exec, Secret access, or cluster-wide rights.
Adoption saves each original spec for rollback. Model bytes use the existing
node materializer and artifact gateway, not a shell-copy deployment shortcut.
A signed assignment using the reserved `lunanexa-artifact-preparation` adapter
warms the cache without starting a GPU runtime. It is sent only to agents
advertising `artifact-preparation-v1`. Once caches are ready,
the operator can switch the adopted replicas and inspect their actual health.
This path adds no model execution concurrency limit or additional approval tier.

The adopted Qwen3.6 A3B NVFP4 profile exposes MTP speculative decoding in the
same operator panel. Zero disables it; 1–5 selects draft-token depth, not request
concurrency. The artifact's BF16 MTP experts use Triton independently of the
target's Marlin backend. Desired depth is journaled before applying the four
existing Deployments. Exact arguments, pinned image and observed Deployment
generation/replica readiness must match before UI readiness or benchmark
acceptance. Disabling restores ordinary decoding of the selected model, not the
pre-adoption model. This changes no RBAC scope or admission concurrency setting.
Benchmarks retain a completed disabled baseline and stamp the model digest,
runtime image, decoding depth, generation and fixed measurement profile.

The optional fixed-quality profile fingerprints 64 credential-free request
fixtures and expected answers. Six synchronized 32-user rounds repeat each
case three times before the unchanged warmup and speed phases. Reports retain
192 sanitized quality samples and receipt-derived node counts, never answer
text. UI comparison rejects incomplete/duplicated cases, transport failures,
different fingerprints or tuning, and missing participating-node coverage.

## Observability and benchmarks

Per model/version/runtime/hardware profile, record:

- time to first token or first output;
- inter-token latency and generated tokens per second where applicable;
- end-to-end p50, p95 and p99 latency;
- queue time, admission backpressure and throughput;
- model load time, warm-up time and time to readiness;
- memory pressure, accelerator utilization and rejected admissions;
- cancellation, runtime failure and retry rates;
- drain, failover and controller-recovery time.

Benchmarks are versioned evidence, not marketing claims. A deployment is
promoted only against a named workload profile and declared service objective.

Hosted client publication can be restricted by the deployment-owned
`ClientLaunchConfig.allowed_organization_ids`. Catalog projection, one-time
handoff issuance and redemption share the same exact-ID predicate. Application
services retain their own business logic and per-subject document storage; they
consume LunaNexa through its public handoff and model contracts. Neither an
application route nor an organization label is identity authority.
