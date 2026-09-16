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
