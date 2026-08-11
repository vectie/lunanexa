# Architecture decisions

## ADR-001: LunaNexa is one product

**Decision:** Build a single LunaNexa product with multiple binaries and
services. Do not create a family of Luna products for registry, scheduling,
monitoring or node management.

**Reason:** These capabilities share one operator, security boundary, release
lifecycle and acceptance outcome. Premature product separation would create
more contracts and failure modes than customer value.

**Future split rule:** A capability becomes another product only when it has an
independent buyer, independent security boundary and independent release
lifecycle. Large-scale distributed training is the most plausible future
candidate, but it remains a LunaNexa workload until those conditions exist.

## ADR-002: LunaNexa is below MoonGate

**Decision:** MoonGate owns application-facing compatibility, authority and
provider choice. LunaNexa owns cluster-facing model lifecycle and execution.

**Reason:** MoonGate can route between hosted providers and owned capacity while
LunaNexa remains usable by clients that know nothing about MoonSuite.

## ADR-003: Dependency direction is one way

**Decision:** LunaNexa publishes its generic contract. A MoonGate adapter may
consume it. LunaNexa never imports a MoonSuite repository or contract.

**Reason:** The hardware platform must remain structurally independent from its
first consumer.

## ADR-004: No first-party Python control plane

**Decision:** First-party LunaNexa components are MoonBit native applications,
with Rabbita for the operator UI. Approved third-party runtime containers are
opaque adapters and may use their upstream technology stacks.

**Reason:** This preserves one owned implementation standard without requiring
LunaNexa to fork or reimplement mature inference engines.

## ADR-005: Reconcile desired state

**Decision:** Deployment and node management use a durable desired-state model
with generations, leases and reconciliation.

**Reason:** Imperative remote command chains are difficult to recover after
controller or node restarts and provide weak auditability.

## ADR-006: Four nodes are initially independent

**Decision:** Schedule across four DGX Spark nodes, beginning with single-node
model instances. Multi-node inference is an explicit runtime/topology feature,
not a default assumption.

**Reason:** Placement and failover can be delivered before depending on model-
specific sharding or unverified interconnect behavior.

## ADR-007: Structural isolation and payload privacy differ

**Decision:** Product code, control metadata and credentials never cross into
the cluster. Minimal request content may cross because the model must process
it, under typed data and retention policy.

**Reason:** Claiming that hardware sees no semantic payload would be false for
ordinary inference. The enforceable promise is minimization, encryption,
bounded retention and no implicit training reuse.

## ADR-008: Two Rabbita surfaces, one contract boundary

**Decision:** Ship a management console for administrators and a separately
deployable developer workbench for individual users. Both consume shared typed
LunaNexa contracts. Editor extensions and third-party developer-tool
integrations are northbound clients, not managed-node components.

**Reason:** Cluster operations and day-to-day development have different
authority, density and failure-recovery needs. Keeping their shells separate
prevents administrator controls from leaking into user sessions while shared
lease, capability and receipt types prevent policy vocabulary from drifting.
A workspace lease grants bounded model capacity; it never grants a DGX login,
filesystem or arbitrary shell.

## ADR-009: One-click means one governed intent

**Decision:** Add a management intent layer inside LunaNexa. One-click model
deployment submits one idempotent intent from a controller-signed template; it
does not bypass lifecycle or security gates.

**Reason:** The existing low-level assignment contract is appropriate for the
controller and node agent but too detailed for product users. A durable intent
and plan layer improves usability while preserving deterministic scheduling,
reconciliation, audit, and node isolation.

**Boundary:** Platform installation remains a signed Kubernetes or GitOps
operation. LunaNexa does not become a general container orchestrator and does
not give its controller or GPU nodes broad Kubernetes administration authority.

## ADR-010: Managed service and exclusive node access are explicit modes

**Decision:** A GPU node runs either governed model services or one exclusive,
time-bounded user lease. A workspace capacity lease never implies machine
access. Reserving an exclusive node removes it from managed scheduling before
account provisioning begins, and it returns only after access revocation and
sanitization succeed.

**Reason:** Interactive development and multi-tenant model serving have
different trust, cleanup and availability requirements. Making the mode switch
explicit prevents a user shell from coexisting accidentally with managed model
credentials or another tenant's runtime.

**Credential boundary:** Public and durable contracts contain a validated
username and a deployment-owned credential reference. Raw passwords, private
keys and SSH certificates are never LunaNexa state. The preferred production
access mechanism is a short-lived SSH certificate bounded by lease expiry.
