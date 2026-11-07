# Unified model-service deployment

Implemented and adopted on the supported production portals, 2026-11-07.
The migration preserves running services, model files, user volumes, API aliases,
credentials and inference settings. Acceptance evidence and limits are recorded
below and in `HANDOFF.md`.

## One authority

A model service has one durable identity, model/template binding, resource owner,
node allocation, desired state and observed runtime state. Operator and customer
APIs submit the same lifecycle intent. The customer projection is tenant scoped;
operator access does not create a separate deployment or override resource owners.

The deployment store owns the service-instance ledger. Its existing signed
catalog/operation snapshots retain their format and signatures; the service
ledger is an additional versioned snapshot within the same persistence backend.
Legacy signed snapshots must open without rewriting their signature material.
Managed operations and customer deliveries register their existing identities in
this ledger before runtime mutation. Adopted runtimes use the same ownership and
conflict checks; they are not a second allocation authority.

Resource ownership is platform managed, a fixed company allocation, or an explicit
company/tenant reservation. Existing scheduler reservation, node-lease and per-reservation
service-budget checks remain authoritative. A desired start retains its claim
through pending/unknown outcomes. A stop releases a runtime claim only after
termination is observed; it does not delete the company allocation, weights or
personal files. Unrelated active node ownership rejects before any adapter write.
Stopped delivery replicas do not keep an ended reservation's ownership forever;
fixed company allocation remains until an explicitly coordinated reassignment.

## Model-neutral runtime adapters

Runtime bindings describe execution mechanics: signed node assignments,
Kubernetes deployments, or a host-configured process group. They do not branch
on GLM/Qwen/model-family names. Model-specific runtime arguments belong to the
approved deployment template/profile, not controller business logic. Existing
process-group targets, start/stop order and runtime identity are adopted from
host configuration; migration does not replace or restart them.

Private adapter addresses and credentials remain deployment references. Public
service responses never expose them. API key/inference routing continues using
the existing published aliases and tenant scopes, with no additional proxy hop.

## Migration order

1. Capture private inventory and rollback settings; compare runtime identity,
   model identity, node set and company authority. Never guess ownership from a
   model name or from a human-readable deployment name.
2. Persist adoption records for existing instances without executing start,
   stop, switch, scaling or reconfiguration. Repeated adoption must be identical.
3. Route both operator and customer lifecycle intents through the common
   service resource check and adapter dispatcher. Old public paths, if retained
   for client compatibility, delegate to this dispatcher and cannot bypass it.
4. Register ordinary node-assignment and customer-delivery instances through the
   same resource authority. Remove model-specific control configuration and
   frontend branches after the live bindings are adopted.
5. Publish both portal projections from the same service instances; disclose
   runtime details rather than exposing separate model-specific workflows.

## Acceptance

- Adoption of a running service performs no adapter mutation and retains its
  exact alias/model, owner, node set and observed identity.
- Operator and tenant actions share generation/idempotency and resource rules.
  Cross-tenant access, overlapping foreign allocations and unowned nodes reject
  before adapter calls; matching authorized company resources retain their
  existing budget semantics.
- Restart/retry does not create another service, start another runtime or lose
  an unresolved claim. Adapter failures do not report a successful transition.
- Stop/start tests use isolated adapter fixtures. Live migration is observed
  without interrupting existing production inference or issuing extra grants.
- Existing public API URLs, keys, model IDs, files and job/report records remain.
  Verify a small real inference response and both supported portal projections.
- Run native and contract/response/isolation/restart gates. Record pre-existing
  failures separately; no simulated result is a physical-cluster acceptance.

Performance: service ownership checks use the loaded ledger and current
reservation snapshot. No per-token persistence, extra inference hop, idle UI
polling, automatic load test or new concurrency restriction is introduced.
Runtime observations run outside global admission and discard stale generations.
Kubernetes stop waits for matching pods to terminate, rather than treating desired
replica count zero as released GPU capacity.

### Production adoption evidence

Six existing service bindings were adopted without runtime mutations. The five
Kubernetes deployment UIDs and complete runtime specifications match the private
inventory captured before migration. Qwen and MiniMax remain running; the company
GLM service remains stopped, as it was before migration. No GPU start/stop or
inference request was issued to change that state. Ten service deployments, four
assignments, the reservation and company memberships were retained unchanged.

The generic management-host runtime controller replaced the active user-service
adapter; the platform controller and both supported portal bundles were published.
The operator projection was checked in the authenticated live portal. The final
company-member browser check requires a company session; tenant scope, role checks
and response privacy are covered by native API/UI fixtures. This is not a claim
that live GLM inference was tested while the service was stopped.

API native tests pass (228), browser/UI tests pass (389), contract/controller/
scheduler fixtures pass (35), and Linux store/model-pool/runtime-controller tests
pass (23). Isolation and response-leak checks pass. The full strict native gate
was initially blocked by deprecated JSON calls. Follow-up cleanup on the same
date migrated the downstream calls revealed after those first failures, removed
the remaining strict annotation/keyword warnings, and fixed the obsolete empty
deployment assertion. Full native check and all 1,956 native workspace tests now
pass without disabling diagnostics. The existing unreleased MoonLeaf workspace
also needed four annotation removals; the exact companion change is retained in
`development/moonleaf-native-annotations.patch` without committing its unrelated
pending source work.

Live Start-button verification is recorded in [GLM startup](GLM_STARTUP.md).
The action really starts the units, but this run failed after about 41 seconds
because the 1M KV allocation lacked about 0.32 GiB. The operator projection now
requires actual endpoint readiness, rather than equating active processes with
ready inference. No successful startup duration is claimed from that failed run.
