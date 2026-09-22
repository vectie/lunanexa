# Offline artifact worker image

`Containerfile.offline-artifact-worker` packages the real native
`cmd/offline-artifact-worker` executable separately from the controller. Build
with the same reviewed MoonLeaf source revision as the renderer (the revision
must include `xlsx.recalculate`) and stage the Linux native executable at
`_artifacts/lunanexa-offline-artifact-worker`. A macOS binary is not a substitute.
Pin both the runtime base and published worker image by digest in the deployment
profile. The image intentionally contains no credential, tenant document,
template, font or private key.

The dispatcher mounts a per-job writable staging volume at `/work`, supplies
`LUNANEXA_OFFLINE_ARTIFACT_STAGING_ROOT=/work`,
`LUNANEXA_OFFLINE_ARTIFACT_JOB_FILENAME`, and selects
`LUNANEXA_OFFLINE_ARTIFACT_MODE=prepare` or `finalize`. Only finalization receives
the deployment-owned `LUNANEXA_RENDER_EVIDENCE_SECRET`. Run as UID/GID 65532 with
read-only root filesystem, dropped capabilities, no service-account token and
no network access. The volume must already be writable by that UID/GID.

Preparation performs exact DOCX replacement or XLSX replacement followed by
real recalculation and writes deterministic prepared bytes. The independent
renderer must inspect those bytes and return the existing signed v3 evidence
manifest with actual visual artifacts. Finalization recomputes the same source,
verifies its digest, checks the renderer evidence and emits the typed result.
Neither stage invents a renderer receipt or skips visual verification.

## Spreadsheet profile

The quote-template engine supports arithmetic `+ - * /`, parentheses,
percentages, same-sheet A1/absolute references, `SUM`, `MIN`, `MAX` over numeric
arguments/rectangular ranges, and `ROUND` with integer precision -9 through 9.
It recomputes dependencies and replaces every formula cache. Division by zero,
circular references, non-finite values, error cells, unsupported functions,
cross-sheet/external references and shared/array/data-table formulas fail closed.
Work is limited to 10,000 cells, 2,048 characters per formula, 64 nesting or
dependency levels and 200,000 cell evaluations. It is a deterministic IEEE-754
template profile, not an Excel compatibility engine and not the authoritative
integer-money ledger. Templates requiring more functionality must be explicitly
extended and tested; do not claim readiness for those templates.

Repository tests validate stale-cache replacement, changed input propagation,
unsupported syntax, errors, cycles and repeated deterministic customization.
Production readiness additionally requires the actual approved templates and
font profiles to pass prepare → render → finalize in the built Linux image.
