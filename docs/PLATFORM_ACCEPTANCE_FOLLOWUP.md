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

## Network fault attempt exposed a cleanup evidence gap

Campaign `video-ab17731dfa08c06016251c3ea1dee1b1bdee9fbf61a35c949c04711440b61dfd`
changed only the r12 runtime's ingress policy with a UID precondition. A new
management-host connection timed out, proving the initial transport disruption.
However, the supervisor detected drift of its owned policy and replaced the
runtime resources. The original policy and Pod no longer existed; replacement
Pod address became 10.42.1.40. Therefore this is **not** a passing pure-network
partition test or proof that a running original instance survives a partition.

The restore precondition correctly rejected the replacement policy rather than
overwriting it. Read-back showed the intended original ingress rules on the new
owned policy. The test also wrongly expected the controller's VideoUnavailable
envelope through MoonGate, whose bounded adapter returns ManagedVideoUnavailable.
The invalid injection mode is disabled until transport can be interrupted
outside the supervisor-owned resource specification.

Job deletion could not be confirmed. Its scoped session/handoff were revoked,
but read-only PostgreSQL inspection found Cancelling, execution_terminal=false,
no usage receipt and no termination evidence. This is intentionally not counted
as successful cleanup. Source inspection explains a genuine lifecycle gap:
`RuntimeSupervisor::stop_record` deletes resources and discards the runtime record
after absence, without preserving a new explicit original-container exit report.
The media plane correctly refuses to treat Pod disappearance as process-exit
proof, leaving capacity retained. Fix the node stop/evidence lifecycle before
claiming complete expiry, drift-replacement or cancellation acceptance; do not
forge a terminal receipt or manually mark the job settled.

### Node stop correction under validation

The source correction retains the original controller-signed assignment in the
node journal. Legacy live entries can backfill it only from the same verified
assignment. The stop path now requests an exact-UID Pod deadline of one second,
waits for explicit termination of every previously published container, persists
the existing authenticated report outbox, and only then permits deletion. A
deadline or terminal Pod phase alone is not used to settle any known job.
Disappearance of an unresolved published Pod preserves the journal/cache and
returns Draining. This cannot reconstruct evidence already lost by older code.

Pod PATCH permission is required, but the transport accepts only the bounded
UID-test/deadline operation; policy, image and credential mutation stay excluded.
The adapter uses Kubernetes' documented
[Pod active deadline](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
and still requires its explicit container-exit observation, not API absence.

Local native Kubernetes checks and all 42 tests passed with `--deny-warn`,
including held-running instances across restart, failed report persistence,
exactly-once outbox recovery, legacy backfill, corrupted attribution, missing
Pods, and forbidden PATCH shapes. Whole-repository regression and a fresh Linux
node build are in progress. The correction is not deployed yet; the old failed
campaign is still not settled and not claimed as clean.

The full native regression subsequently passed 792/792 (warning classes 92/20
excluded); Kubernetes strict tests remained 42/42. Candidate node binary
`23ac92c537f41b0d4902728b9b9e9de46db1a923027a38cfe016d83020a9d6ca`
was packaged as an executable-only layer, image digest
`sha256:beba5fcba4bc88e4cc3ef25bd53c9b6585343945a96482ee8c64e6b37740c152`.
A non-root, tokenless inspection Pod succeeded on the actual compute node. The
isolated runtime Role received Pod patch permission and the isolated managed
node switched images while retaining its Pod UID and persisted host state.

Live `managed-test-video-20260916-r13` used a ten-minute assignment. The original
test user's unresolved r12 job still rejected a new request with VideoCapacityBusy
(409), confirming it was not silently released. A separate disposable user was
granted VideoGenerate with one concurrent request and 20/hour, preserving expiry.
Adding an overlapping lease did not override its selected old lease; updating
that immutable lease returned 409. The old text-only lease was explicitly ended
through the operator API so the already-created replacement lease became current.
No original-user quota or historical failed job was altered.

Second-user job
`video-aed3c6c1e5ed629b75ce4e77af5a8f308c0dfb4d49c29725e1c95404f3dd27e3`
was queued through MoonGate. Stopping the deployment through the operator API
produced a Failed/execution-terminal record, persisted original-instance report
`runtime-termination-04f9083711ee6347df2a5b0da9a72e1ff78d348a1901b4457a54b2dc890c85f0`,
and exactly one private-workspace usage receipt. The Pod was removed and the
workspace identity remained unchanged. The test did **not** fully pass: deferred
customer DELETE returned VideoAccessEnded after deployment authority ended.

The API correction under validation permits the current authenticated owner to
clear an already evidenced, settled terminal job without execution authority or
provider traffic. Account/workspace/key/model checks remain required; ordinary
in-flight or artifact-bearing jobs do not take this shortcut. Targeted tests and
a new controller candidate are in progress; do not claim this last cleanup has
passed until the original live job is checked again.

### Complete stop/settlement/customer-cleanup follow-up

The API integration fixture passed 4/4 after adding private-owner terminal
cleanup and revoked-account rejection checks. Final whole-repository native
regression again passed 792/792 with warning classes 92/20 excluded; the strict
Kubernetes package remained 42/42. Interfaces were regenerated with no public
interface changes. Existing repository warnings and unrelated release gates
remain outstanding.

Controller candidate `b3a81450674647e5fe829777b46487d71703df5107153f1408a8e14454fedf4e`
was installed in the isolated user service with the same PostgreSQL/configuration
and a retained rollback binary. Against the **original** r13 task above, the
current second-user session successfully performed DELETE twice; the ledger
remained singular. Read-only PostgreSQL inspection confirmed Cancelled,
execution_terminal=true, and the same exit reference and usage receipt. The
test session/handoff were revoked, and no substitute task was used for this check.

A separate five-minute r14 deployment then verified recovered capacity for the
same one-concurrent-job owner. Job
`video-5151a814627470b6332d9e771e8192af3d7f5a22eb07192981a0496036dda0ea`
passed MoonGate submission, same-job controller retry, in-progress/completed,
and the exact marked-MP4 digest. Its provider job, temporary download and handoff
were cleaned. The r14 deployment was then explicitly stopped. The completed
non-root image-smoke Pod was also deleted; its manifest and pinned image remain
reproducible. Workspace files and audit/billing history were preserved.
Final namespace inspection found no Pods, ResourceClaims or claim templates;
only the intentional default-deny NetworkPolicy remained.

This closes the newly exercised managed-stop and private terminal-cleanup flow.
It does not reconstruct the missing r12 exit evidence, qualify the rejected
network-policy partition test, or complete the remaining browser/identity,
release-gate and real-hardware evidence.

### Identity entry and security-gate recheck (2026-09-16, 3531195)

The management-host discovery check again verified TLS against the deployed
public certificate and matched the issuer and endpoint origins. The workstation
direct TLS probe timed out (curl exit 28); a fresh in-app browser tab for
`https://106.39.18.146:5006/realms/lunanexa/account/` failed with
`ERR_TUNNEL_CONNECTION_FAILED` before displaying a login form. No registration,
password login, email verification or MFA acceptance is established by this
check. Domains, certificates and system trust were not changed. The observed
certificate expires at 2026-09-18 10:04:34 UTC.

The existing platform-identity, direct-IP browser-edge and OIDC browser-ingress
manifest suites all passed. These are local rendering and configuration checks,
not proof that the public browser path works. The deployment literal-secret
heuristic passed; its eight process fixtures passed, including checks that
rejected credential literals are not printed.

The repository isolation gate still fails. Its seven existing fixtures pass,
but the actual repository scan matches `ObservedContainer.container_id` in the
node's durable journal and the `container_id` argument of
`observe_container_termination`. Neither match alone proves a customer-response
leak: the scanner does not distinguish internal persistence/parameters from
response schemas. No fields were renamed, excluded or allowlisted to force a
green result. The scanner needs a scope-aware correction and regression coverage;
public-response tests remain necessary independently of that correction.

### Scope-aware isolation gate correction

The gate now delegates to a MoonBit script that distinguishes declarations from
serialized field spellings. Function parameter names are not response fields;
private record declarations are permitted only in the Kubernetes node adapter.
There is no whole-directory exclusion: public records, object construction and
serialized JSON in that adapter still fail. Private records outside that adapter
also remain checked. Product-specific dependency checks retain their original
boundary, including untracked and hidden source files, while build outputs are
excluded. Findings print file/line locations rather than source values.

All 25 process fixtures passed, including same-file private/public transitions,
object-valued parameter defaults, quoted/embedded/multiline serialized fields,
misleading comments/string contents, paths containing spaces and output
redaction. The actual repository scan passed without renaming any runtime field
or altering the on-disk journal format. Native API regression passed 129/129
with warning classes 92/20 excluded. This remains a source heuristic, not proof
of absence of arbitrary data-flow leaks, and does not replace runtime API tests.

The final whole-repository native run passed 792/792 with the same warning
exclusions. `moon info --target native` completed with 174 existing warnings and
no errors; this is not a strict warning-free release pass. `moon fmt` completed;
its unrelated formatting-only changes in 148 previously clean backend files
were reverted rather than included in this scanner change. `git diff --check`
passed, with no generated public interface changes.
