# Platform acceptance follow-up

Source baseline: main `732f50e`. These are repository tests, not real browser,
identity-provider, payment, or Spark hardware acceptance.

## Additional customer-surface checks

- JavaScript `ui/enterprise`: 28/28, `--deny-warn`.
- JavaScript `ui/workbench`: 7/7, `--deny-warn`.
- JavaScript `cmd/enterprise`: 20/20, `--deny-warn`.
- JavaScript `cmd/workbench`: 11/11, `--deny-warn`.
- JavaScript `workspace`: 9/9, `--deny-warn`.
- VS Code client-core: 8/8.
- Coursebook and guide diagnostics: 29/30. Source-digest verification fails.

## Documentation evidence is stale

A read-only audit found six mismatched entries among 24 published source
digests: README.mbt.md, docs/PRODUCT_CONTRACT.md, docs/ARCHITECTURE.md,
docs/DEPLOYMENT.md, docs/PLATFORM_IDENTITY.md, and api/server.mbt.
The evidence ledger still records an August inspection. Do not merely refresh
hashes: review affected claims and bilingual user instructions against these
sources, then update provenance and validate both rendered languages.

The static isolation scan also remains failing on internal Kubernetes
container identity declarations, as recorded in MACHINE_LEASE_TIME_ALIGNMENT.md.
Neither failed gate is waived by the passing customer-surface tests.

## Still outside this evidence

The complete objective still requires the remaining real browser/provider,
network-partition, recovery, cleanup and deployment checks. Actual model
deployment and Spark hardware-specific compatibility/performance are explicitly
deferred, not simulated as successful.

## Live identity discovery check

Cluster inspection confirms the platform IdP StatefulSet is 2/2 ready, its
PostgreSQL is 1/1, and the public identity edge is 1/1. The configured issuer is
https://106.39.18.146:5006 with populated service endpoints. This is deployed
infrastructure, not merely a manifest.

OIDC discovery from the operator workstation failed during TLS negotiation
(curl exit 35); the same URL from the management host reached TLS but failed
default certificate trust (exit 60, self-signed certificate). These are distinct
observations; neither proves the login application is broken. Validate using the
deployment's approved public trust certificate, then test browser reachability
and real registration. No domain, certificate, or trust-store changes were made.
Signed-test registration evidence does not substitute for this real IdP path.

Follow-up verified discovery from the management host using only the public
certificate referenced by the deployed edge Secret (no private-key read, no
system trust changes, no insecure TLS bypass). The issuer and authorization,
token and JWKS origins match the configured public identity authority.
The certificate fingerprint is
07:0A:A2:38:5E:B0:B8:68:66:57:F0:14:FE:3A:58:AA:20:AE:97:56:DD:92:32:3C:85:70:89:C5:60:C1:D0:F4.
It expires 2026-09-18 10:04:34 UTC. Renewal/trust distribution requires attention
before launch; no certificate change was performed. Workstation reachability,
browser registration, email verification and actual password login are still
unproven by this discovery check.

The actual in-app browser could not open the account page and reported
ERR_TUNNEL_CONNECTION_FAILED before rendering a login form. A workstation curl
probe with the deployed public certificate and proxy bypass also timed out in
TLS (exit 28), while management-host verified discovery still passed. This
narrows the remaining issue to workstation-to-public-entry reachability or its
transport path, rather than establishing a Keycloak application failure.
No account was created and no password entered during these probes. Native
computer control also reported the Mac locked; browser transport failure is a
separate observation and must not be conflated with the lock state.

## Renewed live TEST ONLY video path

The previous bounded test runtime had expired and its namespace had no Pods.
Created `managed-test-video-20260915-r11` from the existing signed Kubernetes
fixture template with a one-hour assignment. It reached Ready on the actual
`lunanexa-gpu-180` compute node, without hardware identity changes.

Direct runtime acceptance passed: unauthorized 401, queued/in-progress/completed,
premature content 404, exact marked-video SHA-256, delete followed by job/content
404, unchanged Pod UID and zero restarts. Its temporary download was removed.

Private scoped handoff through MoonGate then completed job
`video-995fd67e8588dfb1f2efaa4ad634d4c4e3653c05b3c7fb2536d593286db299ba`;
controller retry returned the same job and downloaded fixture hash matched.
The script removed its download, deleted the test job and revoked its handoff.
The bounded runtime remains for subsequent fault tests. This run tests the API
path, not a new browser ComfyUI run or actual model inference.

## Current recovery campaign needs investigation

For job `video-d6fc7297fcf92ceaeffd978833b58193d6e8d784ca9fceed3baa83e2fee6999d`,
the controller was stopped for 45 seconds. Provider and workspace Pod/container
identities stayed unchanged; the workspace remained ready and non-terminating.
The controller subsequently recovered health, but the script exited with
VideoUnavailable during recovery/cleanup. This run is not a recovery pass.
The test has fallible deferred cleanup, so the surfaced error may mask the
original failure; improve diagnostic preservation before repeating mutations.
Read-only PostgreSQL inspection afterward found the original job Cancelled,
execution_terminal=true and a retained usage receipt. The provider Pod remains
Ready with zero restarts. No replacement job was submitted to hide the failure.

The harness now preserves the primary failure separately from deferred cleanup
and fails successful-body runs if cleanup fails. A non-mutating injected-error
self-test passed. A distinct diagnostic campaign on job
`video-a344db78ac630e7a7da4ee1d0fcfb0eb18ae3349a62771f983e5da2c3fb3f024`
again preserved runtime/workspace identities through 45 seconds of controller
outage. Its primary failure is now confirmed: the same-key request after restart
returned MediaProfileUnavailable (503, retryable=false), saying no exactly-one
authorized active media profile exists. This is the next diagnosis target; do
not relax profile authorization or describe the recovery campaign as passing.

Source inspection found POST retries re-run ready-profile selection before
durable submission. Zero candidates and multiple candidates shared the same
non-retryable error. A local correction returns retryable VideoUnavailable for
zero authorized ready candidates while retaining rejection and the original
request key; multiple candidates still fail as non-retryable configuration
ambiguity. Added route regression requires 503/retryable and zero provider
submissions. Integration testing is underway; this correction is not deployed.

Both no-ready and ambiguous-profile regressions now pass in the four-test
machine-commerce API integration fixture, including private-workspace and paid
media paths. Ambiguity remains 503/non-retryable and neither rejected case
submits to the provider. A fresh Linux candidate is building from the corrected
source; full native regression is running. Live restart acceptance remains open.

Full native regression completed 786/786 with warning classes 92 and 20
excluded. A separate strict media/jobs run exposed four deprecated implicit
ToJson calls in existing test code; these were converted to explicit trait calls
without altering production serialization. Strict native media/jobs rerun passed
18/18 with `--deny-warn`.

## Recovery correction deployed and verified

The Linux candidate completed and was installed only in the isolated acceptance
controller, preserving its PostgreSQL and configuration. Binary SHA-256:
`a1073f201c74943c26f168261f7e996e532a5ff7410cf0cce8d1ccd1623758d2`.
The previous binary remains backed up. A status probe initially queried the
system systemd manager instead of the user manager and incorrectly suggested
inactivity; the actual user service was active and health returned 200.

The r11 fixture had expired normally before this rerun. A new one-hour
`managed-test-video-20260916-r12` fixture reached Ready on the unchanged physical
compute node. The stopped local MoonGate acceptance process was also restarted
using its existing isolated state directory. The expired-fixture and unavailable
gateway preflight failures are not counted as recovery passes.

Live campaign `video-1e7050303ac939b9a7f95bd72229182015304163c07d3e89d500a76239ed4192`
then passed with the corrected controller:

- A queued job traversed MoonGate to LunaNexa.
- Controller stop lasted 45 seconds; provider and workspace Pod/container
  identities remained unchanged, with the workspace ready and non-terminating.
- After restart, the first same-key retry received transient VideoUnavailable;
  the next successful retry returned the original job, not a replacement.
- The original job progressed to completed. Download SHA-256 matched the marked
  TEST ONLY fixture, and its commercial ledger contained exactly one quantity-1
  private-workspace-video-job observation.
- A separate explicit cancel returned deleted. All deferred job, handoff,
  session and temporary-download cleanup completed without errors; harness exit 0.

This proves controller restart recovery through the API path, not a real network
partition, provider-process recovery, a new browser run, or actual GPU inference.
