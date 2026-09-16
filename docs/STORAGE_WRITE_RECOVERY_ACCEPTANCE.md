# Scheduler and telemetry write recovery — 2026-09-16

This checkpoint covers local persistence failure and successful retry, not
PostgreSQL ambiguous-commit recovery, cancellation during a database commit,
or a deployed controller upgrade.

Telemetry's new regression first failed against the prior implementation:
after a rejected temporary-file write, memory contained the new sample and had
already discarded the old bounded-history sample. Sample and benchmark writes
now restore their previous arrays on unsuccessful completion, including scoped
unwind, before releasing the mutex. Tests cover history pruning, both write
paths, unchanged disk state, retry, and reopening the final persisted state.
The strict native telemetry suite passes 6/6.

Scheduler mutations now release their mutex through scoped cleanup and restore
the prior snapshot on unsuccessful persistence. Rejected admission no longer
updates the in-memory usage window without persisting it. A regression injects
temporary-file write failure into quota changes, admission, start attribution,
completion, cancellation and placement history. Each failure preserves both the
in-memory snapshot and disk bytes; removing the fault permits retry. Completion
replay records only one completion and 125 accelerator milliseconds. Reopening
the final store matches the in-memory snapshot. The strict native scheduler
suite passes 8/8.

These targeted runs use `--deny-warn` without exclusions. Generated public
interfaces are unchanged. Broader strict-gate failures in other packages remain
separate work, and conditional database cases are not fresh live PostgreSQL
evidence merely because their test runner exits successfully.

The full native functional suite passed 794/794 with
`moon test --target native --warn-list -92-20`. A subsequent strict scheduler
rerun also passed 8/8 after adding an assertion that quota rejection in a new
usage window leaves both memory and disk unchanged. The full run's warning
exclusions are required by other packages and do not satisfy the strict
repository gate. No cluster service was upgraded in this batch.

## Offline commercial store follow-up

The offline commerce store's 23 rollback handlers now use scoped mutex release
and error cleanup instead of catch-and-rethrow cleanup. Existing per-operation
rollback fields, validations and replay decisions are retained. The strict
native store suite passes 14/14 with no warning exclusions; interface generation
reports zero warnings and no public interface change.

File-fault regressions reject temporary writes during template registration,
order creation, quote replacement, upload callback, entitlement activation
callback and entitlement reversal callback. Each compares the full in-memory
snapshot and original disk bytes, removes the injected fault, and completes
the original operation. Existing activation/reversal replay checks and final
reopen-to-Revoked checks also pass. These tests do not inject cancellation at
the commit boundary or prove recovery from an ambiguous PostgreSQL commit.
The remaining callback and worker transitions retain their existing functional
tests, not exhaustive new persistence-fault coverage.

The follow-up `moon test commercial/offline api --target native --warn-list
-92-20` run passed 130/130. This selected-package API/contract regression is
separate from the 14 strict store tests above; it is not a full repository or
live external-provider acceptance run. This batch has not been deployed.

At commit `548e686`, the real PostgreSQL acceptance matrix passed 19/19 fixture
files, each with an explicitly configured connection and a separate fresh
database. An independent catalog query afterwards found zero
`lnx_acceptance_*` databases; the run's loopback-only SSH tunnel was closed.
This exercises the existing database fixtures, not database failover. In
particular, the scheduler fixture currently restores capacity only and the
telemetry fixture restores an empty snapshot. Nonempty state across newly
established database connections remains a coverage gap for those two fixtures.

That narrow nonempty-recovery gap was subsequently covered and the real matrix
rerun passed 19/19. Scheduler coverage now persists quota and a started workload,
closes its connection, restores through a new connection, rejects duplicate
admission, completes the workload twice, then opens a third connection and
verifies exactly one completion/125 accelerator milliseconds and available
capacity for a new workload. Telemetry persists a bounded sample, closes its
connection, and restores the exact snapshot/value through a new connection.
Both packages also pass their 14 local strict tests; those local runs alone
skip environment-conditional database execution. Interface generation passes.
An independent database catalog query again found zero temporary acceptance
databases, and the test tunnel was closed. Database-server failover and ambiguous
commit recovery remain separate unproven scenarios.

## Cancellation boundary

New white-box tests hold the commerce/telemetry mutex in an owner task and
cancel two consecutive waiting writers using an explicitly identified timeout
error. Both waiters must enter and time out; neither can release the owner's
lock, mutate the snapshot or alter disk bytes. After the owner releases its
lock, a bounded new write and reopen succeed. Combined strict package tests
pass 22/22. This is lock-wait cancellation coverage, not cancellation during
persistence.

Source inspection confirms `PostgresDatabase::save_opaque_snapshot` acquires
its async mutex and then performs BEGIN, snapshot write and COMMIT through the
synchronous native `PQexec`/`PQexecParams` adapter. There is no asynchronous
yield between these transaction calls. Consequently an async timeout in that
task is not an adequate commit-interruption test, and synchronous database I/O
may delay other work on the same execution thread. Independent connection or
server fault injection and an explicit ambiguous-outcome recovery design remain
necessary; the passing tests do not establish those properties.

The scheduler and telemetry real-database fixtures subsequently added two
consecutive writes after explicitly closing their original connection. Both
reject with QueryFailed and preserve their entire in-memory snapshot; a fresh
connection restores exactly the pre-failure data. Scheduler completion then
recovers and remains exactly once. The selected real PostgreSQL matrix passes
2/2 fixture files, deletes its two temporary databases, and its SSH tunnel was
closed. This is a known disconnection before a write, not a server kill,
database failover or an ambiguous COMMIT outcome.

The commercial PostgreSQL fixture also rejects two order-creation attempts
after closing its connection, retaining the complete snapshot. A new connection
restores that snapshot, accepts the same order/key, and returns the same order
on replay without a duplicate. Its selected real-database run passes 1/1 and
the strict local commerce store suite passes 15/15. The temporary database was
dropped by the runner and the tunnel was closed. Together these three domain
fixtures cover known-disconnected writes, not interruption during COMMIT.
