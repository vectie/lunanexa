# Event trial mode

## Ongoing seven-day public trial (2026-10-24)

The same operator UI also supports ongoing admission: leave the end date blank
(`expires_unix_ms: 0`). Registration can remain open indefinitely, but each
account receives exactly seven days from its original activation. Login,
redeeming again, controller restart and closing admission never renew that grant.
Positive end dates keep the legacy fixed-event behavior. `maximum_users: 0`
means no enrollment cap; `maximum_requests: 0` means no total or hourly request
count cap for that trial, while admission counts and runtime usage remain recorded.
Existing limited grants and historical benchmarks are not migrated or widened.
The public deployment uses only the selected 176/177 replicas; no new concurrency
cap, machine access, company membership or administrator permission is implied.
The operator's trial summary includes each ongoing-trial participant's original
dates, admitted calls, metered calls, model-reported input/output units and runtime
milliseconds. Metered totals use durable deduplicated workload receipts and
commercial attribution; missing receipts are not invented or converted from text.
These trial observations do not create paid charges. Public registration QR codes
contain only the registration URL; personal connection QR codes contain a private
API credential and are never public promotional material.

The operator panel's **Users & access → Event trial mode** owns a fixed-window
event or ongoing seven-day admission. It is separate from ordinary registration trials, one-hour
guest Wi-Fi trials, company access packages and Energy Valley shared offerings.

## Operator journey

1. Choose the event name, start/end in Beijing time, participant cap, per-person
   request budget, one approved text-model alias and one to four trial-pool machines.
2. Save a draft. This does not allocate machines, move workloads, change node
   pools, install applications or configure an upstream gateway.
3. Review the observed ready replica count and blockers. Open registration only
   after all selected machines serve the exact approved model/runtime artifact,
   report fresh heartbeats, have strict node endpoint mappings,
   and are not held by another reservation or exclusive lease. Membership and
   workspace-lease enforcement must also be enabled.
4. Share `/user/?trial=event`. A new verified registration during the window
   receives a bounded shared workspace. A previously registered account without
   a trial can explicitly join the current event. Company memberships and
   existing trials are not replaced. No admin role, machine lease or SSH access
   is issued.
5. Close registration when required. This stops new participants, not existing
   valid grants. Fixed-window grants expire at the original event end; ongoing
   grants expire seven days after their original activation. After the first
   participant, the registration switch and single-request input/output ceilings remain
   mutable; dates, request counts, model and node scope stay fixed.

The supported profile serves one text-model alias on one to four selected machines.
Its form defaults are 30 participants, 200 requests/person, no event-specific
per-replica concurrency cap, and one active generation/person across their trial tenant. Input
defaults to 8,192 canonical UTF-8 payload bytes and is configurable up to 65,536.
Output is configurable in the
operator form (new drafts default to 8,192 tokens; legacy policies retain 1,024
until explicitly changed). The platform ceiling and actual model context still
apply. Saving updates existing active trial workspace leases without changing
their expiry, usage, request count or concurrency. Request-time reconciliation
repairs interrupted synchronization. The customer example, connection QR,
workbench and omitted API `max_tokens` default follow the same policy. **Input
units are not a promise of an 8K tokenizer context window.** Actual model limits
remain independently enforced. Launching an application still requires that
application's deployed runtime and workspace checks. This mode does not silently
enable unrestricted media generation or claim every application is ready.

## Gateway and routing boundary

### Harness follow-up: a resource refusal disguised as an invalid key

On October 25, actual DeepSeek Harness 0.2.1-rc.3 UI verification confirmed its
existing provider used the correct public base URL, Chat Completions protocol
and model ID. Listing models succeeded. The current chat failure was **403**,
not the earlier 401; Harness classifies both as `AUTH`. A gateway trace of the
actual request identified `WorkspaceLimitExceeded`. The live policy still had
8,192 input bytes and 1,024 output tokens; Harness's compression request asked
for 4,096 output tokens. The successful portal probe used only 512.

Resource budget refusals now use 400, with a stable error code and an actionable
message, rather than 403. MoonGate preserves the distinction for known budget
errors (including legacy controller responses), without forwarding arbitrary
upstream details. Diagnostics contain route categories, HTTP status and bounded
error codes, never credentials or request/response content. Container logging
uses unbuffered async stderr so short-lived request failures are observable.

Operator changes to input **and** output budgets synchronize existing active
trial leases under the same policy receipt; trial dates, keys, usage, models,
machines, grant state and concurrency are preserved. Revoked/expired and foreign
leases are not widened. Runtime context capacity still applies. Production
success and final configured limits are recorded below only after UI acceptance.

### Harness and configurable-limit acceptance — 2026-10-25

At 03:08 Beijing time the existing `kcfw` provider in the installed DeepSeek
Harness returned the requested connection-test answer. No client provider,
model, API key or credentials were replaced. The `/mana/` operator form saved
**65,536 canonical input bytes / 16,384 output tokens** and confirmed sync to
existing active trials. Read-only durable verification found the matching event
and existing trial lease at those values, one active trial / one bound key /
zero missing bindings, unchanged original expiry, open registration, unlimited
participant/request counts and per-replica concurrency zero on 176/177 only.
The existing per-trial workspace concurrency value was preserved, not changed.

Actual Harness UI requests then completed:

| Request | Input tokens | Output tokens | Completion evidence |
| --- | ---: | ---: | --- |
| Connection answer | 10,673 | 5 | Requested answer visible |
| Python cache class and 20 tests | 10,785 | 2,594 | Code block and explicit ending marker |
| Eight-section fictional workshop handbook | 13,560 | 3,599 | Eight sections and explicit ending marker |

The client's persisted completion metadata reported `stop`, not `length`, for
all three. These tests establish connectivity and non-truncated outputs beyond
1,024 tokens, not semantic correctness of the generated examples or a concurrent
throughput benchmark. No tool/file operations were requested from Harness.
Screenshots are under `tmp/model-trial-ui-20261022/`:
`harness-api-success-20261025.png`, `harness-long-code-success-20261025.png`,
and `harness-long-text-success-20261025.png`.

The gateway HTTP envelope now matches the controller's 1 MiB transport ceiling;
the canonical per-account input limit remains independently enforced. This
removes a hidden 64 KiB transport rejection for JSON-escaped requests without
truncating input. Oversized bodies get `413 RequestBodyTooLarge`, not an auth
error. Gateway SHA-256:
`5b8ed61506c2f1eed833bb7c5c2c2b9f532eac2269ee02b3067d3052a45cf724`.
Controller budget-sync SHA-256:
`52e4ef1475a61e0dd3c79d008f774c0216ab3d8349b7e8def183dee11c4513aa`.
Operator console image:
`sha256:c1cfe20a35e30d3c5ff6efae0248b6904f098b5e4422e1183634d95402a7f7fc`.

Validation: 259 targeted backend/account/workspace tests and all 1,211 MoonGate
native tests passed. The strict whole-LunaNexa native gate is not green: it stops
on existing deprecated `to_json` warnings outside this change, and the isolation
heuristic reports `api/shared_trial_offerings_wbtest.mbt`. Those unrelated files
were not changed to manufacture a clean gate. Optional-value projection coverage
explicitly tests both deployed plain-object and legacy `[object]` encodings so
the user portal can receive the saved budget instead of falling back to 1,024.

Final projection controller SHA-256:
`1a99734b524def3c8ccdd76aa68cf63fddf96c936341c853926e1f5ed01d7b01`.
Portal decoding now accepts both optional envelope shapes and removes explicit
nulls only for the four optional trial fields before derived decoding. Required
fields and invalid values still fail validation. All **152 enterprise UI/client
JS tests passed**, including the new actual-wire budget fixture. Published portal
image `sha256:a18c66fb28764d7ee44f34c8ca9cbcf0d25f7d3f5377590a27abc08dbeb63e49`,
public JS SHA-256 `0539423282ef5773da8c5e591a59c12d6acb724a639d1c942fb4e78c688c3380`.
After both final controller and gateway releases, a new Harness UI conversation
at 03:23 returned `OK` using the unchanged saved provider/key. After the user
signed back in as `ceshi`, the portal's expanded streaming API example visibly
showed **16,384 tokens**, including `max_tokens: 16384`. The existing bound key
remained active with its original 2026-10-31 23:47:15 Beijing expiry; the historical
revoked key remained revoked. The UI's **Test API connection** completed model
listing, ordinary chat and streaming chat successfully in 3,357 ms, reporting
42 input / 70 output tokens. Screenshots: `portal-16384-verified-20261025.png`
and `portal-api-verified-20261025.png` in the same evidence directory. No login
credential was requested or changed.
The refreshed trial card increased from 22 to 24 requests after the two chat
probes, retaining unlimited request count and the original expiry. Final portal
evidence: `portal-16384-and-usage-verified-20261025.png`.
Durable post-restart checks retained the original expiry and bound key, with
trial/key call counts 19/12 after the three initial successful requests.

### Owner-authorized public test-key homepage — 2026-10-25

The owner explicitly requested publishing the already-tested `ceshi` API key,
its base URL/model and original connection QR on the public homepage. They
rejected a new key and a browser chat form, and explicitly chose manual removal
instead of an expiry change or automatic shutdown. No key, grant, concurrency,
model or GPU-node setting was changed. Public calls share the original test
account's usage attribution; removing the homepage block does not revoke the key.

Published homepage ConfigMap: `nexai-public-landing-open-api-20261025`; previous
rollback ConfigMap: `nexai-public-landing-model-live-20261025`. Only the existing
`nexai-public-landing` Deployment's site volume changed; rollout reached 1/1 ready.
Source contains deployment placeholders rather than the credential. The release
script injects the owner-approved key and UI-exported QR at publication time.

Live UI verified the same key, exact original SVG and the copy-success feedback.
The IAB clipboard-read bridge returned an empty string, so clipboard contents
were not independently asserted. A local barcode decoder read the QR from the
actual homepage screenshot and matched the key, `/trial/v1` URL, Qwen alias and
16,384 output budget. A 375px viewport had no horizontal page overflow. There is
no inference form and no automatic expiry/removal logic on this page.

Evidence in `tmp/model-trial-ui-20261022/`: `home-public-api-20261025.png`,
`home-public-api-section-20261025.png`, `home-public-api-mobile-20261025.png`.
The QR decoder reported PASS without printing the key. Both JavaScript syntax
checks and `git diff --check` passed. No new model inference test was launched
for this static publication; the existing key's real-client acceptance is above.

#### Default HTTPS address correction — 2026-10-25

At the owner's request, removed `:8443` from the homepage Base URL and regenerated
the connection QR using `https://suanli.kechuangfuwu.com/trial/v1`. Clipboard
configuration reads the same updated field. Key, model, output budget, expiry and
permissions remain unchanged. Published ConfigMap:
`nexai-public-landing-open-api-noport-20261025`; rollback remains
`nexai-public-landing-open-api-20261025`. Rollout completed successfully.

From the management server, standard HTTPS returned homepage 200 and unauthenticated
`/trial/v1/models` 401 (the expected authentication boundary, not an inference test).
A content comparison confirmed the default-port homepage serves the approved key,
new address and regenerated QR, without any `:8443` literal. The local browser's
default-port proxy connection failed, so visual QA used the still-accessible 8443
entry serving the same deployment. The published QR was decoded from that live
screenshot and matched the no-port address, original key, model and 16,384 budget.
Evidence: `tmp/model-trial-ui-20261022/home-public-api-noport-20261025.png`.
No DNS, networking, model or gateway configuration was modified.

### Production authentication repair acceptance — 2026-10-25

Published controller SHA-256 `0a2ea70550452dd97ebdc44b879b366073592cc4997fb90cb714f5cc35db79af`,
gateway SHA-256 `0beb824b0d813753775354364a1b8dd369aaf7698fd40578a8a833cc172337b8`,
and enterprise image `sha256:742dde0ac6223fc94bc131924c73e08ac16225bc712bbc62a6d5fe7b480efedd`.
Public enterprise JS matched local SHA-256
`fe2c7bfaf4aed3b0e39d5f77c3f52eb2c056ac6fcb8f6c65b7169cbdb0e1dc13`.
Startup reconciliation reported **bound=1, expiry-capped=1, ambiguous=0**.
Read-only durable verification found one active trial, one binding and zero
missing bindings. Its original trial expiry and seven admitted calls survived;
the existing key was not reissued. The revoked historical key stayed revoked.

From the production `/user/` saved-key UI, the existing personal key completed
public `/trial/v1/models`, ordinary chat and SSE chat including `[DONE]`.
The UI reported **2,586 ms total**, **42 input / 80 output tokens** across the
two short answers. Durable trial calls advanced **7 → 9**, key calls **0 → 2**.
This is a connectivity test, not a throughput benchmark. No concurrency or
model configuration was changed. DeepSeek Harness itself was not accessed;
the acceptance covers its OpenAI-compatible public API path, not unseen client
configuration. Screenshot: `tmp/model-trial-ui-20261022/trial-api-auth-success-20261025.png`.

Relevant regressions passed: 258 backend tests (API/access/account/workspace),
151 enterprise UI/client tests, six contract tests and two gateway tests.
Whole-repository strict gates remain blocked by pre-existing compiler
deprecation warnings; the isolation runner also flags the existing
`api/shared_trial_offerings_wbtest.mbt` fixture. Neither was reported as a pass.
Output-budget backend changes previously prepared were included in the
controller build; this acceptance did **not** change the live trial output
policy or publish the pending console/workbench bundles.

Personal trial workspace grants are not company/private-cloud authority. Key
issuance must bind the key to the existing trial and cap its expiry to that
trial's original end. At controller startup, legacy unbound keys are reconciled
only when exactly one live same-subject/tenant/org/project, trial-model-scoped
candidate exists. Ambiguous cases are counted for operator review; revoked or
expired keys are never revived. Repair preserves secret, usage and trial dates,
and is idempotent across restart. The customer's saved-key **Test API connection**
action checks the public model list and makes ordinary and streaming metered chat requests without
displaying the secret. Authentication, authorization and transport errors are
reported separately. The gateway accepts the explicitly configured first-party
browser origin; it still requires Bearer authority and never forwards cookies.

One MoonGate instance can use LunaNexa's existing OpenAI-compatible entry with
user-scoped credentials; LunaNexa dispatches to the selected nodes. No MoonGate
source, admin credential, or MoonSuite runtime is imported into LunaNexa or
installed on a GPU node. Creating an event does **not** deploy or configure
MoonGate. Gateway availability must be tested separately before the meeting.

The optional `deploy/event-trial-model-entry.yaml` exposes the supported
`GET /models` and `POST /chat/completions` routes under `/trial/v1` through the existing TLS
edge. Render its example hostname to the approved deployment hostname.
The entry requires the caller's own scoped API key; it does not expose gateway
configuration, accept unconfigured browser origins, create an account, or open
registration. Existing `/user/` browser authentication and `/mana/` remain
unchanged. SDK users select this event base URL explicitly; existing connection
dialogs and desktop handoffs are not automatically rewritten to this URL.
The same TLS edge serves LAN port 443 and externally forwarded port 8443.
Use the public hostname for certificate validation on both; LAN clients must
resolve that hostname to the LAN ingress address rather than rely on public-IP
hairpin routing to port 443.
The controller does not currently expose a public Responses API. Its internal
runtime's `/v1/responses` adapter must not be advertised as a public route.

The event router selects the least in-flight eligible replica, rotating ties,
and pins the request/stream to that replica. `per_node_concurrency: 0` adds no
event-specific concurrency ceiling; infrastructure admission and the serving
runtime still enforce their independently configured resource budgets. Only an
explicit positive operator value limits per-replica calls; exceeding it returns
a retryable `429 EventCapacityBusy`, without another queue. A benchmark user
count is a test workload, not an inferred service cap. Nodes missing ready heartbeats, serving evidence, routing maps, or
reservation clearance are excluded. An already-open event may continue on a
smaller healthy pool; new registration requires all policy nodes ready. The existing
pre-output retry budget applies to the selected replica; the event mode does
not switch an emitted stream to a different backend. Independently operated
replicas do not retry implicitly. No implicit fallback to
another model or tenant's dedicated endpoint is allowed.

The global `scheduler.runtime_concurrency` also defaults to zero (no additional
execution semaphore). Explicit positive legacy settings still take effect until
an operator changes them. Total admitted requests, authorization, deadlines and
the model server's memory protection remain independent of both optional caps.

The process-local router tracks current calls only; durable scheduler admission
continues to prevent replay of active workloads across restart. Persistent
event policy, participation and consumption live in the existing account
snapshot (file or PostgreSQL). Old snapshots without event fields restore as
ordinary trials. Participant-cap checks and trial creation share one store lock.
Workspace grants, leases and scheduler quotas are idempotently resumed after a
partial provisioning failure.

### Independently operated model replicas

An existing vLLM deployment is not a signed managed deployment. The optional
deployment-owned `LUNANEXA_EVENT_TEXT_POOL_JSON` registers exactly four distinct
node IDs and controller-loopback origins, together with one approved model
alias, served model name, artifact digest, runtime version and image digest.
`LUNANEXA_EVENT_TEXT_CREDENTIAL` is supplied by a Secret, never in the policy
or browser. Each proxy must address a single node-pinned service. Operators
must verify the image digest and model materialization during deployment;
the model-list API by itself does not attest weight or image hashes.

Readiness concurrently verifies fresh active trial-node heartbeats, reservation
and exclusive-lease clearance, model approval/artifact binding, architecture,
data policy, `/health` and the exact `/v1/models` served ID. Every inference
retains durable scheduler admission, user budgets and the same least-in-flight
router. Health is rechecked before dispatch. No fake managed assignment or
runtime inventory is created for externally operated replicas.
The freshness check shares the authenticated heartbeat intake's existing future
clock-skew window (`heartbeat_replay_window_ms`); the stale-heartbeat timeout is
unchanged. Operator blockers identify the failing replica and eligibility check.

For an explicitly authorized reassignment of idle reserved machines, operator
`POST /v1/resource-reservations/{id}:drain` accepts the current `generation`
and `readiness_confirmation: release-idle-nodes:{id}`. It refuses tracked
services, assignments or missing fresh empty heartbeats. It only starts
draining: the existing reconciler must independently observe stopped workloads
before releasing the host fence. Account access, leases and user data are not
revoked. Save the original reservation before reassignment.

## API

- Operator `GET /v1/accounts/event-trials`: policies, registration counts,
  observed ready nodes and named readiness blockers.
- Operator `POST /v1/accounts/event-trials`: save a draft or toggle registration.
  Configuration needs the existing authenticated operator authority and is
  audited. No browser-supplied readiness assertion can open registration.
- Operator `POST /v1/accounts/event-trials/{event_id}/participants`, body
  `{"account_id":"existing-account-id"}`: explicitly invite an existing
  EnterpriseUser during the configured window, including a private rehearsal
  while registration stays closed. This uses the same all-selected-ready gate, cap,
  fixed expiry, workspace and per-account API-key authority. Company/operator
  access and active grants cannot be replaced. After an earlier grant has
  expired or been revoked, an explicit operator invitation may create a new,
  separately scoped event grant while preserving the earlier history. This
  does not renew self-service trials or reactivate revoked accounts. The
  invitation is audited; a customer credential cannot call this endpoint.
- Signed-in `POST /v1/auth/event-trial:redeem`: join the active event, without
  accepting model IDs, topology, expiry or privileges from the client.
- Existing `/v1/auth/register`, `/v1/auth/trial`, shared trial workloads,
  workspace and scoped API-key paths enforce the resulting authority.

Opening registration selects event-managed admission for new registrations;
outside its window the account is created without an automatic legacy trial.
Saving a closed draft alone leaves the existing registration mode unchanged.
Wi-Fi redemption remains a separate gateway-attested operation. Expired,
revoked or different trial authority is never renewed by event redemption.

## UI-managed model scope, model change and measurement

The deployment page supports the reviewed Qwen3.6 A3B NVFP4 runtime profile.
`LUNANEXA_MODEL_POOL_JSON` names exactly four existing model deployments and
their node cache roots. The scoped Role permits get/patch of those four only.
The operator adopts their original specifications once, prepares verified
weights through signed node assignments, switches the participating replicas,
then activates routing only after the new served model is observed on each.
Original specifications remain available for rollback. Weight preparation
does not allocate a GPU or launch a second serving runtime. Activation does
not open event registration or alter participant grants.

The UI can select a nonempty subset and give the nodes human display names.
Applying scope persists routing exclusions first. If an excluded replica has
in-flight requests, the UI reports that it is draining and requires a retry
after completion; it does not interrupt an answer. Otherwise only the excluded
adopted model Deployment is scaled to zero. UID/resourceVersion checks prevent
mutating a replacement resource. Nodes, unrelated workloads and weights remain.
Later preparation, model changes, MTP/tuning updates, rollback and benchmark
warm-up operate on the participating subset. To re-enable a stopped service,
select it, then use the model-switch action and wait for observed readiness.
Benchmark reports record the node IDs; changed or unknown node sets cannot be
presented as like-for-like throughput improvements.

`LUNANEXA_MODEL_BENCHMARK_JSON` optionally sets a HTTPS portal origin and a
durable result path. The same panel then offers **单人 + 32 人测速**. The
operator action creates a closed one-hour test event for the selected model,
using 32 dedicated non-admin identities registered through the normal portal.
It uses their browser login sessions to issue their own scoped API keys, and
sends model requests through the public `/trial/v1/chat/completions` entry.
No identity-admin credential is mounted into the controller for this feature.
The test identities are suspended and their keys, grants, leases and trial
memberships revoked afterwards; a subsequent explicit test can reuse these
identities with a fresh event grant. Previous permanently revoked test
identities are not reactivated. Public event registration must remain closed.
While the benchmark is running, its exact 32 identities skip automatic legacy
trial provisioning during normal registration; they receive only the explicit
one-hour benchmark grant. Other registrations retain their existing behavior.
The controller must be able to reach the configured portal HTTPS origin.
`deploy/model-benchmark-network-policy.yaml` supplies the narrowly scoped
443/8443 gateway egress for this installation. Network and enrollment failures
are surfaced with the current stage, without exposing credentials or responses.

Each run first sends 32 short warm-up requests through the same user-facing
entry and verifies receipts from all participating replicas. Their first-use cost is
reported separately, never counted as target-passing measurement. Operators
should run this before opening the event after restarting or changing models;
health/model-list readiness alone is not a first-inference warm-up guarantee.
Each measured run makes three single-user requests and three rounds of 32 simultaneous
requests, with a 512-token output ceiling and distinct synthetic prompts.
Evidence stores usage token counts, first-token and completion timing,
per-request rates, receipts and execution-node counts, never generated text,
passwords, sessions or API-key secrets. Output decode rate is
`(completion_tokens - 1) / (last_content_time - first_content_time)`; total
throughput includes first-token wait and round completion time. Streams with
missing usage/receipt, fewer than 256 tokens or incomplete termination are not
counted as valid throughput measurements. These test parameters are not
concurrency limits on the model service. Interrupted runs are marked as such
and reclaim test access rather than automatically restarting load.

The panel distinguishes end-to-end rate from decode rate. End-to-end includes
connection, first-token wait, output generation, durable receipt/metering and
stream termination. The latency disclosure separates client connect/close and
controller authorization, admission, runtime first output, receipt commit,
execution release and billing. Old reports remain readable with missing
timings explicitly unavailable, not manufactured as zero.

PostgreSQL workload completion appends its new receipt and audit to the
`control_workload_commits` journal. The control-store mutex and leadership/epoch
checks remain, and the in-memory state changes only after the atomic durable
write. Recovery overlays the journal on the control checkpoint in one database
statement. A subsequent ordinary control-state write checkpoints and clears
the journal in one transaction. This removes historical-snapshot rewriting
from each completion; it does not acknowledge early or skip usage persistence.
Snapshots use LZ4 compression. Before rolling back to a pre-v7 controller,
quiesce writes and checkpoint the journal using the v7 reader; do not start an
old reader while journal rows remain. Retain both the snapshot and journal in
database backups.

## Release acceptance

Unit tests cover fixed-window boundaries, policy validation, participant caps,
durable restoration, idempotence, quota consumption and least-in-flight slots.
The HTTP integration test uses four local model protocol adapters and exercises
operator authorization, fail-closed opening, redemption, model invocations,
balanced dispatch, node cordon, model scope and resource ceilings. These are
not hardware throughput measurements.

Before production activation: deploy controller and both portal bundles,
reserve/prepare the four authorized machines through normal operations,
configure the MoonGate entry, complete verified registration and a model call
through `/user/`, then test actual four-machine concurrency, expiry, restart and
the applications intended for the event. Do not advertise event capacity from
unit-test results or repurpose machines reserved by another operator.

See [the October 22 rehearsal record](EVENT_TRIAL_REHEARSAL_20261022.md) for
the deployed topology, verified scope, remaining acceptance work and rollback
constraints. This record is not approval to open registration.
