# Non-model source gate — 2026-09-16

This is local repository evidence, not a live-cluster acceptance certificate.
The complete campaign remains tracked in `NON_MODEL_ACCEPTANCE_TODO.md`.
No actual model was deployed and no Spark inventory was fabricated.

## Confirmed checks

- `sh scripts/release-gate.sh`: **passed** on the undertaking/recovery source
  revision `531e76e`. The run completed process kill/restart, lease cleanup,
  local four-node simulation, evidence export, strict JS checks, UI tests,
  extension/docs tests, original 18-page preview fidelity, font wiring,
  installer/preflight fixtures, secret generation and browser release bundles.
  The four nodes are local simulators, not physical DGX devices. The optional
  gate-controlled PostgreSQL script was not enabled; real PostgreSQL adapter
  tests are recorded separately below.
- `moon test --target native --warn-list +73 --deny-warn`: **858/858**
  passed after all fixes below, with no warning exclusions. Conditional
  PostgreSQL tests do not establish a fresh external-database integration run.
- `sh scripts/check-release.sh`: passed dependency isolation, response
  heuristics, pinned runtime boundaries, identity manifests and secret checks.
  Its 25 isolation/response fixtures and 8 secret-scanner process fixtures
  are static/local checks, not proof of every public runtime response.
- `moon check --target js --deny-warn`: passed without warning exclusions.
  The libpq-only package now explicitly supports native, like its consumer.
- `moon test ui cmd/enterprise cmd/console cmd/workbench installer workspace
  --target js --warn-list +73 --deny-warn`: 153/153 passed, without warning exclusions.
- `node --test extensions/vscode/client-core.test.mjs
  docs-site/coursebook.test.mjs docs-site/guide-diagnostics.test.mjs`:
  43/43 passed after refreshing the modified sources' evidence digests.
- `moon info` and `moon fmt`: completed. Formatting-only changes normalize
  the current compiler's record punctuation and package formatting; they do
  not change the represented runtime settings.

## Failures retained rather than hidden

The first whole native strict test run was 856/857. Its only failing case was
the new operator-download fixture using `/transfers`, which the real adapter
configuration correctly rejects. The fixture now uses the existing allowed
`/v1/offline-transfers` path; the unchanged safety check and corrected case
passed a strict targeted rerun. The final 858/858 whole-native rerun also passed.

The complete `release-gate.sh` additionally enables warning 73. It initially
stopped on redundant constructor qualifiers in pre-existing and new code.
Those have been removed with no warning suppression or semantic change;
whole native and JS `moon check --warn-list +73 --deny-warn` passed. The complete
release-gate sequence subsequently passed, including the final browser build.

The local process-recovery script initially failed before node registration.
Inspection found unconditional Linux procfs resource collection before every
heartbeat; on macOS this raises before sending the heartbeat. The fix retains
the control heartbeat but removes reserved CPU/memory labels when measurement
is unavailable. It neither fabricates capacity nor preserves caller-supplied
capacity claims. The strict host-resource regression passed 3/3.

The original `sh scripts/process-recovery-test.sh` then passed (exit 0): node
and controller process kill/restart, persisted recovery plan and stale-epoch
rejection. Temporary test processes and state were cleaned by its exit trap.
This is local process evidence, not Linux capacity or Spark hardware acceptance.

## Real PostgreSQL follow-up

The existing database matrix passed **21/21 fixture files**, each with
`LUNANEXA_TEST_DATABASE_URL` set to a distinct freshly created database and
`--target native --warn-list +73 --deny-warn`. Together with the new contract
fixture below, **22 distinct fixture files** were exercised against real
PostgreSQL, not skipped because the environment variable was absent. Coverage
includes SQL boundaries, database snapshots, accounts, client handoffs,
technical/portal/workspace state, onboarding, leases/credentials, offline
commerce, registry, scheduler, deployment, enrollment, telemetry,
notifications, observability, media jobs, controller state and inference
receipt-to-ledger replay. Some files also contain pure local assertions.
All per-run databases were dropped by the harness; no production account,
workspace or billing database was selected. No inference model was invoked.
A final `pg_database` query found no `lnx_acceptance_%` databases remaining.
The exact task-owned loopback SSH forward was stopped after both runs.

A new `contractdoc/store/postgres_test.mbt` exercises the undertaking template
against a fresh database in the isolated acceptance PostgreSQL instance, over
an SSH-only loopback forward. Its strict `+73 --deny-warn` run passed 1/1:
packet/field/event persistence and reopening; two closed-connection failures
with unchanged in-memory state; exact replay without duplicate events; stale
creation replay rejection; and successful retry/reopen through a fresh handle.
Its disposable database was dropped afterwards. This does not exercise an
ambiguous commit acknowledgement or certify a production PostgreSQL HA setup.

## Separate unfinished acceptance

Undertaking rendering and actual storage delivery, rendered public identity
and email recovery, current deployed-version reconciliation, and the final
integrated private-workspace journey remain open. See the main checklist,
`UNDERTAKING_RENTAL.md`, `UNDERTAKING_UI_ACCEPTANCE.md`, and
`CONTRACT_ARTIFACT_ARCHIVE.md` for their precise scope.
