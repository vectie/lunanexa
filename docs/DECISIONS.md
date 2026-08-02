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

