# Non-model source gate — 2026-09-16

This is local repository evidence, not a live-cluster acceptance certificate.
The complete campaign remains tracked in `NON_MODEL_ACCEPTANCE_TODO.md`.
No actual model was deployed and no Spark inventory was fabricated.

## Confirmed checks

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
whole native and JS `moon check --warn-list +73 --deny-warn` passed. This
document does not yet claim that complete release gate has passed.

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

## Separate unfinished acceptance

Undertaking rendering and actual storage delivery, rendered public identity
and email recovery, current deployed-version reconciliation, and the final
integrated private-workspace journey remain open. See the main checklist,
`UNDERTAKING_RENTAL.md`, `UNDERTAKING_UI_ACCEPTANCE.md`, and
`CONTRACT_ARTIFACT_ARCHIVE.md` for their precise scope.
