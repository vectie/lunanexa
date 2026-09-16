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
