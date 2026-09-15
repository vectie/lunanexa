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

Other packages still contain deprecated or fragile async cleanup patterns.
Running functional tests with warning exclusions does not satisfy the strict
repository release gate. Environment-conditional PostgreSQL tests are not live
database evidence unless their required environment is explicitly supplied.

The release script now gets past dependency compilation: isolation, promotion
boundary, OIDC browser ingress, platform identity manifests and identity-secret
generator tests pass. It then fails the existing possible-literal-secret scan.
That finding still requires review; this checkpoint neither waives it nor
asserts that it represents a real leaked credential.

The two-hour managed TEST ONLY provider instance is no longer present in its
acceptance namespace. The persistent user workspace and outputs remain; no
claim is made that this expired test deployment is a currently available model
endpoint. Real Spark/model and remaining platform-wide acceptance are pending.
