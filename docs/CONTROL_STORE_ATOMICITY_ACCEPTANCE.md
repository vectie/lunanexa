# Control-store failure atomicity — 2026-09-15

## Defects corrected

The previous control store mutated its live in-memory indexes before saving
the snapshot. A failed save could therefore expose an unsaved directive,
workload receipt, idempotency result or audit record to subsequent callers.
Its manual catch/release paths also relied on cancellation being captured by
ordinary exception handlers.

File-backed fencing had a second defect: rejecting a stale write refreshed the
local epoch from disk, which could allow the same old instance's next write to
pass the epoch comparison. Refreshing a snapshot is not acquiring leadership.

All control-store write paths now stage independent indexes and the audit
buffer, persist the candidate, and only then publish it. The process mutex is
released by `defer`, including cancellation. A definitively superseded
controller instance remains rejected after its snapshot refreshes; a new
legitimate store/leadership acquisition is required. This does not turn an
unconfirmed transient database error into a fabricated revocation.

The candidate copies mutable maps and the audit array without an extra JSON
encode/decode cycle. Store mutations replace records, rather than mutate their
nested contents. Public method signatures and persisted snapshot format remain
unchanged.

## Verification

The native store suite passes locally and on the actual Linux management host
with `--deny-warn`. The Linux run used a freshly created database named
`store_atomicity_20260915` inside the isolated acceptance PostgreSQL instance;
the PostgreSQL test was enabled, not skipped. It passed **8/8**.
The Linux API integration suite also passed **127/127** against the updated
store implementation (with existing unrelated warning exclusions).

The suite covers:

- snapshot reconstruction and monotonic restart fencing;
- repeated rejection of the same superseded file-backed controller;
- failed directive/audit publication with a deliberately unwritable snapshot
  destination, unchanged in-memory and reopened durable views, then recovery;
- failed epoch persistence followed by a successful retry;
- failed workload receipt publication leaving both workload-ID and idempotency
  indexes empty, followed by durable successful retry;
- cancellation after candidate mutation, proving unchanged state and usable
  mutex through a subsequent bounded operation;
- actual PostgreSQL leadership handoff, repeated former-leader write failures
  without memory publication, and a successful successor write/reopen.

The local run's PostgreSQL test returns early when its database environment is
absent; local runner totals alone must not be cited as PostgreSQL evidence.
The Linux run explicitly supplied the disposable database URL. Missing Linux
thread-library linkage was fixed in the store package's native build settings.

After testing, the disposable database was dropped. It contained only generated
test state and is reproducible from the tests. No platform account, workspace,
model, existing acceptance database, or production data was removed.

## Scope limits

These results do not claim disk-controller crash durability, PostgreSQL server
failover, or production-controller rollout. The full repository release remains
blocked by other packages' compiler compatibility/cleanup issues. This work
fixes a real control-state correctness defect encountered while removing those
blockers; it does not replace the remaining platform-wide acceptance campaign.
