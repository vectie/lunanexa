# Platform acceptance follow-up

## Completed-job exit evidence correction — local and original live task passed

The completed-job cleanup defect identified below is corrected in source.
Verified original-instance termination can now attach after execution completed,
preserving its original terminal timestamp, outcome and usage receipt. An
already requested cancellation/expiry finishes without calling the dead or
replacement provider. Completed artifacts whose runtime has verifiably exited
are no longer advertised as downloadable. Tenant authorization, original
instance/context matching and durable evidence checks are unchanged.

Native media jobs/runtime strict tests passed 30/30, including completed,
pending-cancel and expiry cases, persistence failure, replacement rejection,
snapshot restoration, duplicate cleanup and no provider calls or duplicate
settlement. Full native functional tests passed 822/822 with warnings 92/20
disabled. This is not a strict whole-repository release claim.

Compatibility caveat: older readers reject a Completed job carrying termination
evidence. Do not downgrade only the controller binary after such records have
been persisted; use a compatible reader or reviewed state recovery. Before the
isolated acceptance rollout, a PostgreSQL custom-format backup was written to
`/tmp/completed-exit-before-20260916.dump` inside the acceptance database Pod,
restricted to mode 0600, and its table of contents was readable with pg_restore.
This is not a restore drill. The previous controller binary will also be retained.
The Linux candidate completed and was installed only in the isolated acceptance
controller, retaining its PostgreSQL and configuration. Binary SHA256:
`7535110acdcc56f54405ad416d459e37e25da929f27f6da15c2f048c4e7b23dc`.
Its user service was active with zero restarts and health passed. Production
controller, node image, identity/TLS configuration and model runtimes were not
updated by this rollout.

The original failed job
`video-b29fdd1909749060ab24d4cb3775d36036aed69d5f351f67857e314e17899433`
then passed two authenticated owner DELETE calls and retained exactly one usage
observation. No replacement task was submitted. Independent read-only SQL
verified Cancelling → Cancelled and termination-reference absent → present,
while terminal_unix_ms remained `1789533646461` and the existing usage receipt
digest remained `c93e41299726dcdfbe0ace2ab16c473a`. The normal reconciler bound
the already authenticated original-instance evidence; no manual database
transition or fabricated receipt was used. New test handoff/session cleanup
completed and the verifier exited zero.

The full native strict gate was repeated and still reports 63 pre-existing
diagnostics. The older r12 missing-evidence case is not resolved by this change;
an absent original report cannot be reconstructed from Pod disappearance.

## Natural runtime expiry during packet loss — passed; completed-job cleanup gap found

The first 90-second lease attempt did not exercise in-flight expiry: background
polling completed job
`video-b29fdd1909749060ab24d4cb3775d36036aed69d5f351f67857e314e17899433`
before the runtime disappeared. The expected per-job termination evidence never
appeared, and deferred customer DELETE exhausted bounded retries. This is not
a passing cleanup result. Read-only database inspection found Cancelling with
execution_terminal=true, an existing usage receipt and no termination reference.
The deployment was stopped and no runtime Pod remained; the historical job was
not edited to conceal the failure.

Source diagnosis: `VideoRuntime::refresh_internal` only attaches verified
instance termination to nonterminal jobs; `acknowledge_instance_termination`
also rejects already-terminal jobs. A later cancellation of a completed job can
therefore still depend on a provider that naturally expired. This completed-job
cleanup lifecycle requires a correction and regression/live revalidation; do
not loosen original-instance evidence or fabricate a deletion acknowledgement.

The second campaign held the new provider's TCP path unreachable while its
90-second assignment expired naturally. Job
`video-efe7af3fe09d33eca6aa14a960f33a7a0dbd4a30a6914fddbe8cecf68443bd7c`
remained nonterminal during the proved packet outage, then received persisted
original-instance termination evidence and exactly one quantity-one usage
observation. The authenticated owner deleted it twice idempotently after
execution authority ended. The managed-runtime namespace was empty before the
runner's final explicit deployment cleanup, proving that manual stop did not
cause the observed expiry. Harness exit was zero; its exact DROP rule was
removed with absence verification and had a 180-second UTC safety cutoff.
Scoped sessions/handoffs were revoked. No model inference or hardware identity
change occurred. This passes **in-flight lease expiry during provider outage**,
not the separate completed-job cleanup failure above.

## Cancellation during provider packet loss — passed 2026-09-16

The `--partition-cancel` follow-up used a new bounded TEST ONLY deployment and
job `video-9affdf6a15da171ddb86b4db92dc55a874aba2a4b0bbde6f30fd2eeb425d295e`.
The exact provider-IP TCP DROP had a 180-second UTC cutoff and deferred removal.
Positive DROP counters and MoonGate unavailability established real packet loss.
While disconnected, DELETE did not report successful deletion: PostgreSQL
showed Cancelling/execution_terminal=false with no usage receipt, and another
request by the same one-job owner returned VideoCapacityBusy.

After rule removal and verified absence, cancelling the original job twice
succeeded idempotently. The commercial snapshot had exactly one quantity-one
private-workspace-video-job observation. A distinct new task could then be
created using the released capacity and was also cancelled during cleanup.
The original Pod UID `b95d931e-f2a1-4ba9-8312-4f6006e3cab9`, container ID
`301d68f21ba805d739c60a321e0c883eb1411a8c36ef9c1f7a93af7ed33d1ee1`
and zero restarts were unchanged. Harness exit was zero, scoped credentials were
revoked, the deployment stopped, and its runtime namespace contained no Pods.

Two earlier attempts are not passes: the first harness incorrectly required
a 409/cancelling body, whereas a timed-out provider operation may return
retryable VideoUnavailable; the second harness's 25-second curl deadline ended
before the provider's default 30-second timeout. Both attempts removed their
rules and stopped their deployments. The successful correction uses a 60-second
client deadline and verifies durable cancellation/capacity independently of
the error-envelope variant. No product authorization or cancellation guarantee
was weakened to obtain the passing result.

Operator-local harness SHA256: runner
`d6c426141a0a7a6a74b88e1e4099a7fe60b19e8f6daf5581ee97e558841ae225`, verifier
`0be328e593111bbec97e74ce79044da8cfe3f6cce45cdc6aa438f83279ba243b`.
This is isolated live protocol/capacity/billing evidence, not model inference,
production identity registration or resolution of older missing exit evidence.

## Provider packet-partition recovery — passed 2026-09-16

The previously open provider-link partition check now has direct live evidence.
The operator-local MoonBit harness ran `run-client-disconnect.mbtx
--provider-partition`, creating one ten-minute TEST ONLY deployment on the real
compute node. No GPU identity or Kubernetes-owned NetworkPolicy was changed.
A host FORWARD DROP rule matched only the disposable provider Pod's TCP traffic;
its UTC match deadline was 90 seconds, and exact-rule deletion was deferred.

Job `video-1b57a5b08fb12101f6e11f57c342c43d18d906d3d647a659cae54132673cdc1b`
was accepted through MoonGate and returned the same ID on controller retry.
During injection, the rule's packet counter was positive, the MoonGate poll
returned bounded `ManagedVideoUnavailable` with same-key recovery guidance,
and PostgreSQL retained exactly one nonterminal job with neither termination
evidence nor a usage receipt. The original provider identity was unchanged.

The exact rule was removed and its absence checked. The original job then
progressed through in_progress to completed; its downloaded marked test MP4
matched SHA256 `100f5f75c28643c855e503d16b0a1b6941fbfceb2d0b0881f16d7a420df54f91`.
Pod UID `adec189e-9dd9-4bde-b2bc-e510dcd1706b`, container ID
`0569b344d342391de451f9b73a9f46c7754b366b931ae96eccb587f90f212178`
and zero restarts were unchanged across the complete campaign. The harness
exited zero after removing temporary downloads, deleting the job, revoking its
handoff/session and stopping the bounded deployment; the managed runtime
namespace was empty. Independent host rule listing also showed no test DROP.

Harnesses reside in `/Users/kq/Workspace/aigc-spark-preflight`, not product
code. SHA256: runner `4b2b471fa12df962e3b32e2857123994c31847629a6f4019f8f678e70f4183fb`,
verifier `13a7d37d6a69afe20bcce823e6d36c9b8294f485fb73120030f06e5be274e4fb`.
Both passed `moon check` before execution. This closes that isolated provider
packet-partition scenario, not real IdP/browser registration, production node
image readiness, historical missing r12 termination evidence, or Spark hardware
and model inference qualification.

## Live revalidation — 2026-09-16 04:25 UTC

Read-only checks after the beginner UX delivery confirmed management SSH access,
both Kubernetes nodes Ready, and the isolated acceptance controller user service
running. The acceptance PostgreSQL, workspace gateway, ComfyUI fixture and both
CPU TEST ONLY providers were Running. The isolated managed-node Pod was 1/1.
The two hosted tenant workspace deployments were scaled to zero; this inventory
does not prove that launching a new session currently succeeds.

Fresh unauthenticated requests to the acceptance gateway root, `/userdata`,
`/history`, `/queue`, `/object_info` and WebSocket upgrade `/ws` all returned 401.
These are live negative-access checks, not signed-in browser acceptance.

The identity StatefulSets remained 2/2 (IdP) and 1/1 (PostgreSQL), and the public
identity edge was 1/1. Direct workstation discovery with proxy bypass still
failed during TLS negotiation (curl 28, HTTP 000). No TLS, trust, issuer or
public exposure setting was changed while the requested TLS scope awaited
clarification.

An independent deployment defect remains: production `lunanexa-node-agent`
has desired=1/available=0. Current Pod `lunanexa-node-agent-596c7548cd-m57qc`
is scheduled but both containers report `ErrImageNeverPull` for pinned image
digest `b77f0c0f7e758fbe32aa262c347952422481ac3a435492bbefd7967f3fcd51a7`.
Older Pods were disk-pressure evictions, but current node DiskPressure=False;
the current blocker is a missing cached image with pull policy Never. This is
separate from the healthy isolated acceptance node agent. Do not blindly start
the older production agent until resource ownership and compatibility with the
isolated campaign have been checked. No image, replica, node identity, model or
saved workspace data was changed by this revalidation.

Initial source baseline: main `732f50e`; subsequent dated sections record later
source and live acceptance checks. Repository tests and live checks are
distinguished below; neither establishes Spark hardware qualification.

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

The earlier static isolation failure on internal Kubernetes container identity
declarations was subsequently corrected with scope-aware scanning (see below).
At main `3fa0fc2`, a fresh repository scan and all 25 scanner process fixtures
passed. This does not waive the stale documentation evidence gate or replace
runtime customer-response checks.

## Current strict source gate — 2026-09-16

A fresh `moon check --target native --deny-warn` at main `3fa0fc2` exited 255
with 110 errors (warnings promoted to errors), including deprecated implicit
ToJson method promotion and fragile asynchronous catch-based cleanup. In
particular, commercial/offline/store, scheduler/file and telemetry/file still
contain cleanup paths flagged by the compiler. This is not evidence that each
path has failed at runtime, but it prevents declaring the strict source gate
complete. Functional test runs that disable warnings 92 and 20 are not an
equivalent substitute. Cancellation-safe persistence and lock release need
review and regression testing before those warnings can be removed honestly.

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

### Real client-response loss and remaining provider-partition boundary

A capability preflight attempted a short-lived, pinned cached
network utility Pod in the acceptance namespace. Admission rejected it under
`restricted:v1.34` because host networking, NET_ADMIN and root execution are not
permitted. No utility Pod or firewall rule was created, and no namespace policy
was relaxed. The proposed host OUTPUT fault is therefore **not** an accepted
provider-link partition result. The previous owned-NetworkPolicy mutation also
remains invalid for that purpose because it replaced the runtime.

An unprivileged loopback HTTP fault shim then exercised actual **client TCP
response loss**. It forwarded the test request through MoonGate, waited for the
real upstream acceptance, and closed the client socket without returning any
response bytes. Curl reported exit 52 with empty stdout. Retrying the same
request key against the controller recovered original task
`video-b42ea2783cc962cd0708ff552bb74111b383dd3544b43bb609e76080d1703306`.
MoonGate polling observed progress/completion; the downloaded marked fixture
matched SHA-256
`100f5f75c28643c855e503d16b0a1b6941fbfceb2d0b0881f16d7a420df54f91`.
The private usage ledger contained exactly one quantity-one job observation.

Runtime Pod UID `6039e738-2ab0-4463-8f44-f640bbb418b3` and container
`495c0f63fab74386e0ea59ac37015f8bd5db27f586d589d5b7e6bc43745397fb`
were unchanged, with zero restarts. Job, download, handoff and session cleanup
completed, followed by stopping the bounded deployment. Read-only PostgreSQL
inspection confirmed Cancelled/execution-terminal with its retained usage
receipt; final Kubernetes inspection found no runtime Pods/claims/templates
and only the default-deny policy. This proves lost-client-response recovery,
not a provider-link partition or actual model inference.

The expanded cancellation-response-loss campaign initially stopped at an
incorrect harness expectation: cancelled content returned 409, not the expected
404. Inspection of `VideoRuntime::content`, `media_failure`, and MoonGate's
bounded error mapping confirmed that this is the existing contract
(`VideoContentUnavailable` -> `VideoConflict`). The harness now requires both
409 and the exact bounded error code; no production behavior was changed to
make the test pass. That failed run cleaned its test deployment. A complete
rerun is required before claiming cancellation/next-capacity coverage.

The first corrected rerun exposed a second acceptance-environment issue: its
running MoonGate executable predated committed error-classification fix
`8fa1b768d007fecd43c248392d94f1fa1ea0ceea`. Current source was not evidence of
current process behavior. A separate build from that exact committed tree
passed the media-gateway suite 4/4 with `--deny-warn`; the full release build
completed with 28 existing warnings. Candidate SHA-256
`210da1ce5e045473616321b49b0012c499488774645e56f72af67b9b790660bb`
replaced only the local acceptance listener on 127.0.0.1:5883, with its original
working directory and deployment-owned controller origin. The two unrelated
MoonGate working-tree edits were not included or changed; the previous binary
remains available for rollback. No production service was updated.

The full rerun then passed, including both actual lost TCP responses:

- Create-response-loss task
  `video-c2d4ab9547f07b4c887e09aa390c4635fabc9fe97f31fe37f47793bd522610a5`
  recovered under the same key, completed and downloaded the same marked fixture,
  with exactly one private job usage observation.
- Cancellation-response-loss task
  `video-41f7acc7b1f0586555e5efe5f4d8c0049fd68a893053dc629c4c615ccc5ecfe2`
  returned identical successful deletion on retry, exposed no downloadable
  artifact (409 `VideoConflict`), and retained exactly one usage observation.
- New queued task
  `video-6c09a002bbdb9256f080b2509ef9cfdb5f337e2dd6db110d315b7c6b513bb017`
  proved that the same owner's one-concurrent-job capacity was released after
  cancellation. It was cancelled during cleanup.

The runtime kept Pod UID `75494d7a-f84c-413f-8829-4c0333ba020b`, container
`306463d78fe528766c4536b3287e02555823e02b16c0049ce96a67e45c8c212d`, and
zero restarts throughout the successful campaign. All temporary downloads,
jobs, handoffs and sessions were cleaned, then the bounded deployment stopped;
the final runtime Pod inventory was empty. This closes client create/cancel
response-loss recovery, not the separately unverified provider-link partition.

Reproduction harnesses remain in the operator's local
`/Users/kq/Workspace/aigc-spark-preflight` directory, separate from product code
and deployment credentials. The successful runner is
`run-client-disconnect.mbtx` (SHA-256
`b7b74dcf78045120e621691bd5caaa83168c01ec5a9f28727f344c54998f44ec`),
with `verify-private-video-discovery.mbtx` (SHA-256
`982e0d7e250d173be6085d87c0d005c5e6c28cef8bba8db4cbc88976bbd1f96c`).
Read-only PostgreSQL checks after cleanup confirmed all three successful-run
tasks as Cancelled/execution-terminal with retained usage receipts.

### PostgreSQL recovery matrix and durable billing replay (2026-09-16)

Re-ran all 19 fixture files in `run-postgres-acceptance-matrix.mbtx` against
the real acceptance PostgreSQL service. Each fixture used a newly created
database through a loopback-only SSH tunnel; the active controller database
was not used as a test fixture. All 19 passed. A separate `pg_database` query
after completion found zero databases matching the harness's
`lnx_acceptance_` prefix.

Coverage includes native SQL binding checks, snapshot allowlists and atomic
rollback, exclusive leadership transfer, account registration restoration,
portal/workspace authority, onboarding journal recovery, machine lease and
credential stores, offline commerce, registry, scheduler, deployments,
enrollment, telemetry, notifications, observability, media submission ambiguity,
control snapshots and inference billing. This is real database integration
evidence, not hardware inference, browser identity or external payment evidence.

The billing fixture previously checked replay only against its original
in-memory commercial store. It now closes the original database connection,
loads the commercial and integration snapshots through a new connection,
constructs a fresh API service, and replays the same durable receipt. It also
rejects a replay with a changed accelerator quantity and then accepts an
unchanged replay, proving the conflict does not leave the billing lock held.
There remains exactly one quantity-two usage observation and one 50-minor-unit
charge. The persisted commercial snapshot is byte-identical to the snapshot
before recovery, not merely equal in an in-memory row count.

`moon info --target native` completed with 174 existing warnings and zero
errors; no generated public interfaces changed. The fixture matrix suppresses
existing warnings 92 and 20, so these passing integration tests are not a
strict whole-repository warning-free release gate.

### PostgreSQL media capacity recovery follow-up (2026-09-16)

Extended the real PostgreSQL media-store fixture beyond ambiguous-submission
restoration. A fresh database connection restores the job and rejects a second
reservation under its one-active-job budget. An exit record for a replacement
instance is rejected without marking execution terminal. An original-instance
termination record is then persisted; another new database connection restores
that exact terminal record, accepts its identical replay, and allows a new
reservation under the same one-job limit. The media-store fixture passed 2/2
with the real database configured. Media job/runtime strict tests passed 28/28;
targeted interface generation completed without public interface changes.
The complete PostgreSQL matrix was repeated after this addition: 19/19 fixture
files passed. An independent catalog query again found zero temporary harness
databases, and the loopback SSH tunnel was closed.

These are test-constructed records exercising the internal persistence
primitive. They do not constitute authenticated live node termination evidence
and do not close the provider-network-partition acceptance gap. No real job,
node inventory or historical missing evidence was altered.

### Provider-pause preflight did not reach fault injection (2026-09-16)

Attempted a fresh bounded TEST ONLY deployment
`managed-test-video-disconnect-1789523474870` before a planned original-process
pause/resume scenario. The deployment operation rolled back with
`assignments removed after readiness timeout`; no ready runtime was observed,
so the pause helper was never invoked and no process received a signal.
The runner deleted the bounded deployment on failure; the operation ended
Deleted and the runtime namespace contained no Pods or warning events.

The acceptance node-agent Pod remained Running/Ready with two historical
restarts, while its heartbeat remained present. This does not establish the
readiness-timeout cause. Its image does not contain `cat`, so an attempted
read-only journal inspection via Kubernetes exec could not run; no files or
permissions were changed. Diagnose the failed assignment/materialization path
before reattempting the fault. The local runner now reports operation state
transitions and recognizes RolledBack/Deleted/Cancelled as terminal instead of
waiting to exhaust its polling budget. That harness change awaits a live rerun.

The proposed pause scenario tests provider unresponsiveness, not packet-level
network partition. Neither is claimed complete by this failed preflight.

Follow-up bounded deployments did reach Ready with unchanged real compute
inventory, so the original timeout is intermittent and its cause remains
unproven. The first follow-up stopped on a local harness parse error before
invoking any signal; that error was corrected and `moon check` passed. Two
subsequent attempts created private jobs, but capability preflight failed before
STOP: the pinned minimal TEST ONLY runtime image has no `/bin/kill` executable.
The final diagnostic explicitly reported `stat /bin/kill: no such file or
directory`. No signal was sent and no container privilege was expanded.
The harness cleanup deleted the created jobs, revoked handoffs/sessions and
stopped each bounded deployment. A suitable unprivileged fault-injection helper
is still needed; process-pause recovery is not yet verified.

Restricted ephemeral-container preflight was subsequently admitted without
additional capabilities, host namespaces, mounted credentials or privilege
escalation. Historical Pod image IDs proved insufficient cache evidence: the
klipper-lb and CUDA helper attempts failed `ErrImageNeverPull`. Direct compute
containerd inventory identified the current NVIDIA DRA image
`sha256:83730194d4e76c0f6b645e3eca732b09770916f6401f7c6927a299f6aea2b65d`.
Its tools are under `/busybox`, not `/bin`; using the observed paths allowed
the helper to start as the runtime's own non-root UID. PID 1's executable was
observed as `/bin/test-video-provider` before any signal attempt.

The same-user STOP/CONT commands returned success, but a subsequent job poll
still returned `in_progress` rather than unavailability, including after moving
helper preparation before job creation. Command success is not proof that PID 1
stopped. These runs therefore do **not** establish an outage or successful
outage recovery. The harness now requires `/proc/1/status` to report stopped
before checking outage behavior; this new assertion compiles but awaits a live
run. Every attempted bounded deployment and helper was cleaned; no namespace
security policy was relaxed. The fault mechanism still needs verification.

### Provider process unresponsiveness and recovery — verified 2026-09-16

The signal approach above was superseded: `/proc/1/status` remained sleeping,
so successful `kill` exit codes were not treated as outage evidence. An
operator-level containerd task pause then confirmed the exact TEST ONLY task
as `PAUSED`, without changing workload capabilities or namespace policy.
Initial assertions incorrectly expected LunaNexa's `retryable` field on a
MoonGate response; source inspection established that MoonGate intentionally
returns only a bounded error code and message. The harness now requires
`ManagedVideoUnavailable` and same-request-key recovery guidance, rather than
assuming that absent field. No MoonGate product change was required.

The completed live campaign used job
`video-7da543772a18a6a37e2b8615c0a8adc350136b479857f933c0dde0632c73f131`:

- Exact containerd task was confirmed paused; the MoonGate poll failed with
  bounded `ManagedVideoUnavailable`.
- PostgreSQL contained exactly one matching job, still nonterminal, with no
  invented termination evidence or usage receipt during the outage.
- The original task was resumed; the same job completed through MoonGate and
  its explicitly marked test MP4 passed the expected hash check.
- Pod UID, container identity and restart count were unchanged throughout.
- Temporary download, job and handoff cleanup completed; the bounded deployment
  was stopped and its runtime namespace contained no Pods.

This establishes process-unresponsiveness recovery with a CPU test provider,
not packet-level network partition, GPU inference, or Spark qualification.

### Live workspace authority outage and same-cookie recovery — 2026-09-16

The workstation's missing 5875 SSH forward initially prevented this campaign
from reaching fault injection. The management-side kubectl listener was still
healthy (connect page 200); restoring only the local SSH forward recovered it.
No public domain, certificate or trust setting changed.

A first outage attempt returned workspace HTTP 503 and retained the Pod UID,
but its recovery command failed because stopping a transient systemd unit
removed that unit. The acceptance controller was restored using its original
systemd-run command, protected EnvironmentFile, working directory and namespace
launcher; its health endpoint returned ok. A new handoff then reopened both
existing outputs and verified the retained video hash. This first attempt was
not counted as an automatic-recovery pass.

After correcting that environment-specific recovery command, a complete rerun
passed: connect 204/root 200; stop isolated acceptance authority; same cookie
receives 503 while workspace Pod UID remains unchanged; recreate the original
authority and wait for health; same cookie again receives 200 with the same
Pod UID. Both saved outputs were listed and the second downloaded video retained
SHA256 `8b4bc945cb35c2dff26e566c525a30fa91649f473aef41a657c9e96bdacb7148`.
No managed-runtime Pods existed before injection. The controller is restored;
the local workspace forward and bounded successful handoff remain for continued
acceptance. This is live HTTP/session/persistence recovery, not a WebSocket
outage test or production identity-provider acceptance.

The subsequent WebSocket campaign also passed. An established authenticated
socket closed with policy code 1008 during the same bounded authority outage;
a new upgrade request with the same cookie returned 503. After the authority
was recreated and healthy, that cookie established a new WebSocket and received
a nonempty message. HTTP returned 200, the workspace Pod UID remained unchanged,
both saved videos remained listed, and the retained download hash matched.
The controller is healthy again. This supersedes only the WebSocket gap in the
preceding paragraph, not the real identity-provider/browser UI or Spark gates.

### Post-restart commercial tenant isolation and capacity

Fresh signed TEST ONLY sessions queried the customer machine-order and offering
endpoints after the authority recovery campaign. The original organization saw
its five historical orders, all Failed or Terminated with capacity_reserved=false.
The independent second organization saw zero orders. Both saw the intentionally
shared test catalog: no-capacity offering available=0, simulated-machine
offering available=1, both reserved=0. Sessions were logged out afterwards.
No new order, payment callback, refund or real payment was issued. This verifies
list isolation and retained terminal capacity state, not checkout UI or every
individual-order authorization route.

### Terminal-order access and key-issuance denial

The follow-up live probes used fresh TEST ONLY sessions for the original and
independent second organization. The original owner received HTTP 409
`MachineOrderNotActive` for the terminal order's access route and HTTP 409
`DedicatedEndpointUnavailable` when requesting an access key. The second
organization received HTTP 404 `NotFound` for that same access route and HTTP
400 `InvalidRequest` for key issuance, matching its nonexistent-order probes.
The original organization's nonexistent-order probes returned the same 404/400
pair. Error bodies did not disclose target lease, payment or organization
fields. No key was issued and both sessions were logged out.

The original five orders remained terminal with no capacity reservation; the
second organization still saw zero orders. This closes these specific negative
authorization checks, not successful paid provisioning, real checkout UI or
all machine-commerce routes.

### Documentation/UI and regression checkpoint (2026-09-16)

The bilingual access guide now separates three short journeys: private-cloud
administrator approval, bounded public trial, and commercial rental. IaaS,
PaaS (WebIDE/ComfyUI), and MaaS delivery remain distinct. The storage guide and
architecture no longer describe the six migrated control-plane snapshot domains
as production file/PVC authority. The source ledger's six stale digests were
refreshed; this targeted review does not certify every historical guide claim.

The compact guide trigger retains its visible question mark at 390px width;
search and guide accessible names follow the selected language. Live browser
inspection verified English/Chinese labels, menu open/close, Chinese guide
open/close and search dismissal. The viewport width and document scroll width
both measured 390px, and search/guide controls measured 44x44px. A rendered
Chinese first viewport was inspected and the temporary viewport was reset.
These checks concern the documentation site, not identity/payment browser E2E.

- Documentation and administrator-diagnostics Node tests: 32/32 passed.
- Native functional regression with `--warn-list -92-20`: 797/797 passed.
  Conditional PostgreSQL cases in this command do not replace the separately
  recorded live database matrix.
- Native strict check with `--deny-warn`: failed with 80 errors, including
  fragile cleanup handlers; the strict release gate is still open work.

No serving deployment, domain, certificate, trust setting or actual model
inference was changed by this checkpoint.

### Live revoked-content denial and second-organization rebuild

Fresh private, no-rental-contract hosted handoffs were exercised for both test
organizations against the existing acceptance deployment. Each connected with
204, opened the workspace with 200 and upgraded WebSocket with 101. Revocation
closed the established socket with policy code 1008 (4437 ms for the second
organization, 5001 ms for the original). New HTTP and WebSocket requests returned
401. Cross-origin upgrades returned 403 and tampered cookies returned 401.

The expanded negative checks also require 401 after revocation for `/userdata`,
the exact saved-video `/view` path, `/history`, `/queue` and `/object_info`.
Both organizations passed all five checks. These are HTTP/client protocol
checks, not a new visual-browser acceptance claim.

The second organization's workspace Pod was recreated during subsequent launch
(`...m498t` to `...xmzdj`, then `...kk2p2`); this is not an unchanged-Pod test.
After the new launch returned 204/200, read-only verification recovered the
previously saved workflow byte-for-byte and the uploaded TEST ONLY input video
with SHA256 `8b4bc945cb35c2dff26e566c525a30fa91649f473aef41a657c9e96bdacb7148`.
Its asset list excluded the original organization's outputs and the original
organization's exact video path returned 404. No replacement workflow/input
was written to make these checks pass. The readback handoff was then revoked;
all new campaign sessions were logged out and temporary downloads removed.

The managed-runtime acceptance namespace was empty during this campaign.
Existing separate test-provider Pods remain; no model was deployed, hardware
identity changed, or old unresolved r12 execution evidence reconstructed.
