# Release acceptance evidence

Repository tests provide deterministic evidence for contracts, policy,
reconciliation, scheduling, UI state, recovery, and leak checks. They do not
stand in for the real-cluster gate.

Before `EvidenceBundle.release_ready()` may be accepted, attach:

- results from a clean controller and four enrolled DGX Spark nodes;
- immutable model/runtime digests and license evidence;
- concurrency, saturation, cold-start, long-stream, and mixed-workload runs;
- controller, agent, and runtime restart observations;
- drain, saturation, bounded queueing, and failover evidence;
- scans of API responses, assignments, runtime environments, and images;
- security, operations, and license report references;
- the name of the human accepting the evidence.

The typed gate is fail-closed. In addition to the repository scenario and
isolation flags, it requires explicit passing evidence for the physical GPU
cluster, PostgreSQL failover, direct object-store transfer and resume,
inference-to-ledger charging, configured payment/signature providers, and real
browser acceptance. Separate HA, object-store, provider, sanitization and
browser report references are mandatory. A local simulation cannot populate
these fields truthfully.

For the contract-governance slice, attach evidence for each dependency stage:

- two distinct mapped operator identities, including an audit receipt and an
  expiry-closure run with the configured grace period;
- a high-value execute/close request rejected for self-approval and approved
  by a second operator;
- Effective MasterLease admission gating before issuing a new API key;
- a settlement draft bound to an immutable ledger-summary digest and a
  violation notification that creates a closure proposal without implicit
  closure;
- an approved amendment materialized into a successor packet with the correct
  `preceding_packet_ref` chain;
- payment and acceptance obligations, including an overdue reconciliation;
- tenant-scoped contract-number allocation with idempotent retry evidence and
  the operator governance dashboard projection.

These checks prove the local durable workflow. They do not replace approved
IdP/RBAC, legal/finance, ledger, invoice, notification or signature-provider
acceptance for a real deployment.

Measured objectives are evidence for the exact model, runtime, driver, network,
and hardware profile. They are not promises for a changed profile.

Use `lunanexa-evidence recommend` to bind a named run to its capacity and
service-objective recommendation, then `lunanexa-evidence bundle` to export the
reviewed evidence bundle. Example typed manifests live under `tests/fixtures`;
production report references and the acceptor name belong in the private
acceptance channel, not the repository.
