# Compiler compatibility checkpoint — 2026-09-15

## Reproducible dependency repair

LunaNexa now requests the published `vectie/moonleaf@0.1.15`, replacing 0.1.14.
The upstream source commit is `7f0b108` on MoonLeaf `main`. The package registry
accepted the release, and LunaNexa downloaded the published archive with SHA-256
`13ecdba0d0a3600d0c15e77b7d31b18b367a27739de7426a4c14f0c5a7e5e466`.
This is not a local dependency-cache patch or an unpublished path override.

MoonLeaf replaced three removed `core/strconv.from_str` calls with typed
`core/string` parsing. Regression tests cover invalid/overflowing integer
defaults, positive cached page counts, malformed cached counts and exponent
spreadsheet date values. Its strict all-target check and all-target tests pass:
**111/111 each on native, JavaScript, Wasm and Wasm-GC**. Public interfaces are
unchanged.

In LunaNexa, one old runtime test fixture now explicitly supplies `endpoint:
None`; no model-serving implementation was changed. Three imports used only
by PostgreSQL tests were moved into test-only dependency blocks.

## Full native and real database results

`moon test --target native --warn-list -92-20` passed **755/755** after repairing
two stale image-escaping assertions. The page legitimately contains a static
brand image: the tests now compare image-element counts with an unmodified
baseline, still forbid the raw hostile payload, and require its complete HTML
escaping. No application escaping behavior was weakened or disabled.

The 19 files containing conditional PostgreSQL tests were then run serially
against **19 fresh, separate databases** in the isolated PostgreSQL instance.
Every run explicitly received its database URL; **19/19 files passed**, with
36 runner tests across those files (some files also contain non-database cases).
Coverage includes SQL parameter isolation, atomic snapshot batches, production
account/handoff domains, accounts, portal, workspace directory, onboarding,
exclusive leases and credentials, commercial offline state, registry, scheduler,
deployment state, node enrollment, telemetry, notifications, observability,
media ownership/ambiguous submission recovery, controller fencing, and exactly
once inference billing.

The SQL mutation test now owns a temporary guard table on its connection rather
than assuming that an unrelated earlier test created the platform schema.
It checks parameter round-tripping and that the guard row survives the corpus.

Each generated `lnx_acceptance_*` database was dropped after its run; a final
catalog query returned **0** remaining databases with that prefix. Only generated
test data was removed. The loopback SSH forward created for this matrix was
closed afterward; existing application routes were not removed.

## Control-store deployment follow-up

The store corrections from `bff091a` were built on the Linux host and installed
only into `lunanexa-acceptance-controller-20260915.service`, preserving its
PostgreSQL and protected deployment configuration. The previous executable was
retained for rollback. Deployed controller SHA-256:
`03aae423662c3b13a8a201de7783e71df0824bba8e28846e4fedbab2b9710b82`.

The isolated controller returned healthy after restart. A fresh private handoff
opened the existing ComfyUI workspace without a rental contract, returned
connect 204/root 200, listed both retained videos, and downloaded the second
video with its unchanged SHA-256
`8b4bc945cb35c2dff26e566c525a30fa91649f473aef41a657c9e96bdacb7148`.
The temporary download was removed; a bounded workspace credential was retained.

The Linux controller build still used the earlier staged dependency
compatibility adjustments. It must not be presented as a pristine build using
the newly published dependency. Its purpose here was deploying the already
verified control-store fix. The new published dependency is being validated in
the normal local LunaNexa checkout.

## Remaining boundaries

### In-progress authority recovery batch

After this batch, the complete native functional suite was rerun with
`moon test --target native --warn-list -92-20`: **760/760 passed**. This is not
the full strict gate and does not rerun conditional PostgreSQL cases with live
database configuration. The standalone scanner process fixtures also passed
8/8 again, and the deployment scan passed.

API-key issue, revoke, subject-wide revoke and usage consumption now release
their mutex with `defer` and restore the prior in-memory map on an unsuccessful
operation, including cancellation unwind. Six native access tests pass with
`--deny-warn`. New tests reject temporary-file writes for all four operations,
compare memory and reopened disk state, verify retry after removing the injected
failure, and cancel an authorization waiting behind an owned mutex. The latter
is lock-wait cancellation evidence, not cancellation during a database commit.

Workspace user creation and lifecycle transitions use the same scoped cleanup
principle. A new file-backed test covers failed creation, suspension and
revocation, subsequent successful retry, and rejection of reactivation after
durable revocation. Grant/lease issuance, expiry reconciliation, activation,
revocation and workload reservation/ownership paths now also use scoped cleanup.
Directory tests pass 12/12 with `--deny-warn`, without warning exclusions; package
interface generation also succeeds. The added admission failure fixture verifies
retry after failed reservation, retained ownership after failed release, and
cross-subject rejection. Conditional PostgreSQL cases in this run are not fresh
live PostgreSQL evidence. A partial-success fault test first reproduced a real
divergence: authority expiry persisted, admission write failed, and the old
rollback restored active authority in memory. Authority and admission now track
successful persistence separately, preserving the already durable expiry while
rolling back the failed reservation. The regression passes and retries the same
workload successfully. This does not provide cross-file atomicity or prove
ambiguous database-commit recovery. Cancellation during persistence still needs
dedicated coverage; lock-wait cancellation alone does not prove that case.

The isolated deployed workspace was also reopened again: connect 204, root 200,
both retained video outputs listed, and the second download hash unchanged.
These local source changes have not yet been rolled out to that controller.

Other packages still contain deprecated or fragile async cleanup patterns.
Running functional tests with warning exclusions does not satisfy the strict
repository release gate. Environment-conditional PostgreSQL tests are not live
database evidence unless their required environment is explicitly supplied.

The release script now passes: isolation, promotion boundary, OIDC browser
ingress, platform identity manifests, identity-secret generator tests, image
checks and the deployment literal-secret heuristic all completed successfully.
The previous secret-scan finding was an ingress `proxy-ssl-secret` reference,
not an embedded credential. The replacement validates entire allowed reference
values instead of excluding a whole line by keyword. Its 23 classification
fixtures and 8 full-process fixtures cover references, invalid references,
literal credentials and same-line credential smuggling. Rejected diagnostics
withhold values; full-process fixtures explicitly assert this redaction.
This remains a heuristic, not proof that the repository contains no secrets.

A separate `moon check --target native --deny-warn` still exits 255 and reports
100 errors, including fragile asynchronous cleanup patterns. The release script
passes with compiler warnings and is not a substitute for that strict phase
gate. The current scanner changes remain part of the unfinished acceptance
batch, not a declaration of platform completion.

The two-hour managed TEST ONLY provider instance is no longer present in its
acceptance namespace. The persistent user workspace and outputs remain; no
claim is made that this expired test deployment is a currently available model
endpoint. Real Spark/model and remaining platform-wide acceptance are pending.
