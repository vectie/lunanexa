# Inference billing failure acceptance — 2026-09-16

The inference-charge path now uses `errdefer` for commercial-memory rollback
and `defer` for mutex release. Cleanup no longer depends on a catch handler
receiving asynchronous cancellation. The read-only project check likewise
releases its mutex with `defer`. This does not resolve ambiguous database
commit acknowledgements or claim cancellation-during-commit testing.

The existing PostgreSQL regression now closes its database handle and attempts
two new charge writes. Each must fail, preserve the exact pre-failure commercial
snapshot, and leave the mutex usable for the next call. A separate connection
then reconstructs durable state, retries the original receipt, rejects a changed
replay, and confirms exactly one observation and one ledger entry with unchanged
persisted bytes.

The actual test ran against a freshly created database in the isolated
`aigc-acceptance-20260915/acceptance-postgres` instance through an SSH-only
loopback forward. The environment-gated database test was enabled and passed
1/1. The harness dropped that disposable database afterwards; it contained only
generated test state, not platform accounts, workspaces or production billing.

The command used the existing unrelated warning exclusions `-92-20`. A separate
whole-repository strict check before this correction still failed with 54
diagnostics. Neither this narrow test nor a default run with no database URL
establishes the full release gate, provider-payment acceptance, or deployment
of the change to any running controller. No actual inference was executed.

Follow-up API regression passed 129/129 with the same warning exclusions.
`moon info api` completed without public-interface changes; the touched files
were formatted and `git diff --check` passed. The temporary loopback SSH
database forward was stopped after the real database test completed.

## Strict current-source revalidation

After the cancellation/compatibility gate cleanup, the same real PostgreSQL
fixture passed 1/1 again with `--warn-list +73 --deny-warn`, without warning
exclusions, as part of the 2026-09-16 isolated database matrix. Its temporary
database was dropped. The complete repository release gate also passed; see
`NON_MODEL_SOURCE_GATE_20260916.md`. This still does not mean these changes have
been deployed to a running controller or that a real provider was billed.
