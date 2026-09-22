# Offline production rollout — 2026-09-22

This is a progress ledger, not a ten-capability acceptance certificate.

## Applied and observed

- Final LunaNexa native suite including the MoonEdit bridge, technical waiver,
  scope boundaries, invalid-authorization compensation, controller configuration
  and frozen-preview fix: **1140/1140**, with `--deny-warn`.
  Coursebook and diagnostics tests: **35/35**. Enterprise/browser package
  regression: **70/70** (see the separate UI evidence for coverage boundaries).
  `moon info`, `moon fmt`, deployment/isolation/secret release scans and
  `git diff --check` passed. These tests do not replace live acceptance below.
- A PostgreSQL custom-format pre-upgrade dump was retained in the management
  host's private backup directory; `pg_restore --list` parsed it successfully.
  This verifies archive readability, not a completed disaster-recovery rehearsal.
- The controller was rebuilt on the management node from the working tree plus
  the updated MoonLeaf source. It is not described as a clean tagged release.
- Production controller image manifest:
  `sha256:5a7054c8630b66eb6b73fd800ade7c6d7159c92cf49d0fe237a92e14f9f4d13c`.
  Only the control container image was changed; the runtime loopback proxies and
  identity relay images were preserved.
- Production pod `lunanexa-control-98576f548-w2v5n` reached **4/4 Ready**.
  Database health and offline reconciliation reported healthy after startup;
  real node telemetry continued receiving HTTP 202.
- Approved contract assets PVC is mounted read-only at
  `/usr/share/lunanexa/assets/contracts`; the explicit assets root and legacy
  template path are configured. See the OFL evidence package for source hashes.
- The platform owner explicitly removed bilingual legal templates as an
  acceptance requirement in this conversation. This does not remove source
  fidelity, immutable version/hash, approval provenance, fonts or visual checks.

## Still not attested by these observations

Actual isolated production DOCX/PDF and quote Jobs, persistent S3/scanner,
immutable writes, retention and independent-volume restoration are now recorded
in `offline-dispatcher-production-20260922.json`,
`offline-transfer-production-20260922.json`, and `offline-ofl-v2-20260922/`.
These were technical qualifications, not evidence of a signed or paid customer
order. The object-store backup is not independent off-site disaster recovery.

The user-facing MoonEdit generation bridge and real controller-issued downloads
subsequently passed in v3, as recorded below. Technical-waiver dispatcher
activation/reversal remains a separate pending acceptance check. No fixture
callback, historical test token, or liveness check substitutes for those outcomes.

## Controller v2 and transfer deployment follow-up (offline-transfer owner)

At 2026-09-22 18:44 CST, the already-built controller v2 (binary mtime
18:36:06 CST) replaced v1 in one strategic-merge rollout. The exact manifest is
`sha256:2cbe16f912014c9def2f14dd39d6c1aaedbcff5037deef6583c03635170eab0a`.
The pod reached 4/4 Ready. The change loaded the two immutable template approval
scopes, transfer/session Secret references and combined private/registry CA,
while preserving existing sidecars and the original registry CA mount.

The live readiness response evaluated at `1790073873898` reported all ten
capabilities configured and verified. It still reported
`ReadinessArtifactDispatcherSuccessStale` and
`ReadinessEntitlementDispatcherSuccessStale`: these are honest diagnostics, not
completed business acceptance. The compiled `offline_blocker_applies` explicitly
does not use past success as a prerequisite for the first begin/generation;
required heartbeats, scoped approval and actual terminal authority remain gates.

Controller v2, the current web v2 (`sha256:c5755070a5603fd1bd620aa4e1a32defe78724aeb5a7a6c210b4cc942d9bb9db`),
and offline runtime r1/r2 were pushed to the internal registry with certificate
verification. Registry HEAD returned HTTP 200 and the exact control/web digests.
The public identity edge exposes only GET/PUT capability paths under
`/v1/offline-transfers/<safe-id>` to private TLS; internal object APIs are not
publicly proxied. `nginx -t` passed and the existing public health route stayed 200.

Details: `offline-controller-v2-deployment-20260922.json` and
`offline-transfer-production-20260922.json`. The dedicated independent restore
Pod/PVC/network policy and synthetic denial session files were removed; the
private 0600 cold archive and build artifacts needed by other release tasks remain.

The real controller-produced technical quote subsequently passed customer
download through public TCP 5003: HTTP 200, 2,558 bytes, SHA-256
`e83a8d0ca6f92e0668d35433fa09a5b2cce1d8719631d7b26ca65b35f80c8240`.
Reusing the capability returned 409, and the controller persisted
`TransferConsumed` with the matching completion receipt. The same authenticated
customer's existing active Developer membership in a different tenant was used
to request the same artifact: HTTP 403 `OfflineCommerceDenied`, no new grant.
No membership/store rewrite, fake payment, contract signature or fulfillment was
used. See `offline-customer-quote-download-20260922.json`.

## Controller v3 bridge deployment (offline-transfer owner)

The frozen MoonEdit bridge runtime was built with native release optimization
and published as `sha256:ec18ed94a93176b41b8de1e2b0f8920ee4ef98a12434cb9a9d6fb4abf8eb01df`.
The v3 rollout reached 4/4 Ready; registry TLS HEAD verified the same digest.
All ten capability attestations loaded, including the real OIDC entitlement
authority evidence reference. Only `ReadinessEntitlementDispatcherSuccessStale`
remained in the global diagnostics; no business success was fabricated.
The initial controller startup exited once with
`DatabaseError.ConnectionUnavailable`, then automatically restarted successfully;
the existing sidecars did not restart. This is recorded, not described as a
zero-restart rollout. Actual MoonEdit acceptance follows independently.

See `offline-controller-v3-deployment-20260922.json` for immutable binary/source
hashes and the observed startup state. v3 does not contain a technical waiver.

The actual MoonEdit-generated DOCX/PDF pair also passed controller-issued
customer downloads through public TCP 5003. Both returned HTTP 200 with exact
controller SHA-256, then HTTP 409 on capability replay; both sessions were
persisted as `TransferConsumed`. The 10,825,525-byte PDF SHA-256 is
`65e70f452ad7dd7029acaf6edde0fad1b4175741209a82c168d3f45d8cf7b543`.
Requesting that PDF from the same customer's existing active membership in a
different organization returned HTTP 403 `OfflineCommerceDenied`. No new user,
membership or commercial record was created by these download checks. Evidence:
`offline-customer-ofl-docx-download-20260922.json` and
`offline-customer-ofl-pdf-download-20260922.json`. The downloaded PDF was retained
locally for independent visual verification; capability tokens are not evidence.

The corrected workspace browser bundle was deployed as web v4
`sha256:53ceb4bfee88b77b4766ef5959f34c773891c62f8d6e7b203290217df4c435d6`.
All three UI deployments rolled out, and public
`http://106.39.18.146:5003/enterprise/enterprise.js` matched the freshly built
SHA-256 `d0f7e1816925ae8e94b6cc8e43c11fb8e5795729e70f1fdc775c7e70662c7db6`.
During packaging, the UI agent discovered that the previous build script copied
a stale non-workspace cache: deployed web v2 did not contain the intended latest
JavaScript. The intermediate web v3 image shared that fault and was never deployed;
v4 uses the corrected workspace path. Registry TLS HEAD returned 200 with the
exact v4 manifest digest. Browser interaction acceptance is recorded separately,
not inferred from the matching script digest. See
`offline-web-v4-deployment-20260922.json`.

Actual browser testing then exposed another HTTP-specific issue: `crypto.subtle`
is unavailable on the deliberately non-TLS public site. Web v5 replaces that
dependency with the existing MoonBit SHA-256 implementation, retaining mandatory
digest verification. Image `sha256:19926dc6d97c37beabc7a4f36cb16763fb31627a4e2f6441764423e87c0ac859`
was TLS-pushed, all three UIs rolled out, and the public enterprise script matched
`bd680d3a3881f3604c4acbd789d05b0915b7ea593705be9c402e92713b0f8d8d`.
The UI agent then actually clicked both verified PDF and DOCX downloads on the
existing Generated revision-6 packet and observed successful verified downloads.
No signing or payment action was performed. See `offline-web-v5-deployment-20260922.json`.

## Controller v4 and final one-order technical rehearsal

Controller v4 image
`sha256:bd2d47d5b449bf5b356fb8473d2801bc9336c81e655710c723b8cdacd652bcf6`
contains the reviewed per-order technical waiver and Generated-packet read-only
preview correction. Its source was the frozen working tree plus MoonLeaf
`066efc2`, not a claimed clean LunaNexa commit. Initial rollout was 4/4 Ready
with zero restarts. The UI agent verified the existing four-page preview and
successful PDF/DOCX downloads through the actual browser.

The dispatcher completed real activation and reversal for the one explicitly
authorized technical order; dedicated access and identity cleanup followed.
See `offline-technical-waiver-production-20260922.json`. The one-order deployment
authorization was then removed and the controller rolled out again: ordinary
technical waivers are once more disabled by default. The final readiness query
returned an empty blocker list. This scope-closing rollout did reproduce one
`DatabaseError.ConnectionUnavailable` startup exit, followed by an automatic
successful restart; final state was 4/4 Ready, control restart count 1, sidecars
0. The underlying transient connection cause remains unproven, and this is not
described as a zero-restart release. Details and immutable hashes are in
`offline-controller-v4-deployment-20260922.json`.

The coursebook evidence update was separately published as image
`sha256:968a862f893cdd40bb90af3a714a90a30e02e91b95cbdf01473650179ff08d67`;
served evidence SHA-256 matched the reviewed source. See
`offline-coursebook-v3-deployment-20260922.json`.

## Adjacent live service observations

- The owner confirmed external TCP 5007 forwarding. A fresh public MoonTown
  `/health` request returned HTTP 200. Its separate operator authentication
  boundary remains enforced.
- MoonDesk, MoonClaw and MoonTown production user services were active. The
  two temporary root-owned release canary services and their local forwarding
  process were stopped; production services and rollback files were retained.
- MoonTown's actual Guide request reached its private gateway but timed out
  after 55 seconds; the UI showed an error and became retryable. This is **not**
  a successful inference test. A direct request to the GLM runtime also timed
  out, bypassing MoonGate. The runtime uses two-node tensor parallelism; its
  peer placement and relationship to the unavailable fourth Spark are under
  diagnosis. The timeout must not be attributed exclusively to MoonGate.
- Spark `192.168.2.179` stopped application-level responses despite accepting
  TCP connections. Later diagnostics via the fabric interface showed that the
  node recovered and all four Spark nodes became Ready. Its GLM rank-1 had
  exited normally at 17:46; a separate benchmark later suffered an OOM. These
  are distinct observations, not proof that GLM itself was OOM-killed. After
  the user approved restoration and the benchmark task confirmed resource
  release, the original GLM pair was restored without changing its model or
  runtime configuration. A real direct inference returned HTTP 200 with output
  in 0.490 seconds; the MoonGate path returned real output in 1.088 seconds.
  These are small smoke requests, not a performance benchmark or SLA. The
  MoonTown browser Guide subsequently passed a real logged-in browser question
  and Chinese answer; its evidence remains separate from these direct smokes.
