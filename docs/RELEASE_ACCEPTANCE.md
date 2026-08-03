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

Measured objectives are evidence for the exact model, runtime, driver, network,
and hardware profile. They are not promises for a changed profile.

Use `lunanexa-evidence recommend` to bind a named run to its capacity and
service-objective recommendation, then `lunanexa-evidence bundle` to export the
reviewed evidence bundle. Example typed manifests live under `tests/fixtures`;
production report references and the acceptor name belong in the private
acceptance channel, not the repository.
