# Event trial rehearsal — 2026-10-22

## Public homepage model-trial launch — 2026-10-25

Published the homepage's live-service edition after the browser model path
was verified. The primary action is now “免费试用通用模型”, linked to
`/user/?trial=event`; an explicit existing-user link opens
`/user/workbench/?trial=1`. Removed the coming-soon/date/敬请期待 copy,
replaced the launch-date card with seven-day model trial information, and
retained the company branding, mascot, FDE section and existing service layout.
The UI/UX guidance informed the distinction between the primary onboarding
action and subordinate existing-user shortcut; no visual redesign was made.

Only the homepage Deployment's site ConfigMap changed to
`nexai-public-landing-model-live-20261025`; rollout succeeded. The preceding
`nexai-public-landing-trial-fde-20261024` ConfigMap remains available for rollback.
Anonymous HTTPS responses match local files exactly:

- HTML SHA-256: `f24cf33d1e3d99b08d7b7d49e4ab26eac28de4600852539fddd702dd2e30229c`.
- CSS SHA-256: `45b15a3324a3fbb8e6542e12e61d457c4d63a1cdfe6f76686f44d0c3baf87126`.

Browser verification confirms the live copy and the primary CTA's navigation
to the existing ceshi account's ready trial card, without resetting its expiry.
The existing-user shortcut also reaches the workbench; clicking Connect
successfully loads the trial lease and authorized Qwen NVFP4 model.
Homepage screenshot: `tmp/model-trial-ui-20261022/home-model-live-20261025.png`.
This release does not alter model execution, account entitlements, concurrency,
or personal API-key behavior; the outstanding API acceptance remains separate.

## Model connectivity recheck through the customer UI — 2026-10-25

The user prioritized model availability before API-key and phone-QR acceptance.
Using the existing ceshi browser session, opened `/user/workbench/?trial=1`,
connected successfully and submitted two consecutive actual requests to
`nv-community-qwen3.6-35b-a3b-nvfp4` through the UI:

- Code explanation and arithmetic: correctly returned the example's output
  and `17 × 23 = 391`; **76 input / 19 output tokens, 322 ms execution**.
  Receipt: `workload:workload-8267807e-c3c0-434b-a9dc-f74ad344c0e6:cf3e9625708ad7cd367fd3a141d1d460080f036b5315a8a899b4625afbdabcd2`.
- Synthetic community AI-workshop plan: returned three phases totaling
  **90 minutes and 150 yuan**, within the requested 500-yuan budget;
  **101 input / 96 output tokens, 1355 ms execution**.
  Receipt: `workload:workload-db99007c-a18b-4ccf-8600-9f3788417da7:e4fcdbc4d70855f3f636e0964d34a46cd5c1b373d21ae4e2d6774936fccae0c8`.

The page shows two completed requests, 177 input / 115 output tokens and
1677 ms aggregate execution. These are execution timings, not measured E2E
latencies or concurrent throughput. Screenshots:
`tmp/model-trial-ui-20261022/model-connectivity-arithmetic-20261025.png` and
`tmp/model-trial-ui-20261022/model-connectivity-business-20261025.png`.
No model or concurrency setting was changed. This proves the browser trial
inference path, not external personal-key API or phone-camera QR acceptance.

API-key follow-up remains separate: the approved key was issued with an
incorrect later expiry, then revoked through the UI after explicit user
approval, before any inference use. The key was not exposed in chat. A focused
fix in `api/workspace_admission.mbt` separates personal-trial workspace grants
from private-company authority; its build was started, but no release or new
key issuance is claimed here. The user has authorized replacement within the
original Qwen-only scope ending 2026-10-31 23:47:15 Beijing. Resume that work
only after checking the interrupted build/test state; do not treat the earlier
"creation not submitted" note below as current status.

## Fresh-account acceptance and workbench bootstrap fix — 2026-10-25

The user completed a fresh registration themselves. The `ceshi` account's
portal showed a seven-day entitlement expiring **2026-10-31 23:47:15 Beijing**,
`0/不限` requests, the Qwen NVFP4 model and public `/trial/v1` API address.
Reopening the portal preserved that exact expiry; no machine approval was
required. No password, session token or API secret was copied into this record.

The first browser workbench attempt failed. The new route/status diagnostic
established that `/v1/workspace/self` succeeded but
`GET /v1/settings/effective` returned `401 Unauthenticated`. The controller's
public-settings route accepted inference/operator credentials but omitted the
already-supported enterprise browser session. This is not an expired browser
login or a model failure. The fix accepts the existing enterprise session on
that read-only public projection; admin settings remain operator-only.
Event API regression tests pass 4/4, now exercising workspace bootstrap,
public settings, denied admin settings and anonymous rejection together.

Published browser diagnostics and corrected the obsolete “event-wide expiry”
banner. Workbench asset SHA-256:
`4afdcd23aae3845d26cfbd2b084a4a3e2c2796dbb6b64f994978071ea23f0d8a`.
The enterprise portal also gains a user-triggered personal-trial API test:
one same-origin `/trial/v1/chat/completions` call, showing real answer, elapsed
time and reported token usage, without printing the key or raw upstream errors.
JS enterprise/UI regression tests pass 151/151; workbench/enterprise tests
previously passed 78/78. Existing deprecation warnings are not claimed fixed.
The API-test frontend is deployed as
`sha256:2ee48e9bf52391dac829b70e4c1806f32c145299fae494e36d4f0cbe15c7377e`;
served enterprise JS SHA-256
`1daef825a2ba8c12182d3402e6004a183f3678dc0ad9ccab7f578db98b9ae069`
matches the built artifact. The API test is not invoked automatically by
registration or key issuance. The management UI was refreshed and shows
`1/不限名额`, `2/2` ready replicas, and the new person's zero-usage row.

Controller `control-trial-settings-20261025` rolled out 1/1; binary SHA-256
`7a27fee0b971aaa810f388d93c130a69b63cf244aedf664d70ac7f6a7776cf1d`.
Compared with the preceding remote controller source, the backend change is
exactly one additional enterprise-session authorization condition. Workbench
bootstrap now visibly succeeds for the new account.

The first actual workload exposed another pre-existing client assumption:
workbench requests hard-coded an 8192 MiB memory ceiling and the selected
model therefore failed event admission (`EventCapacityNotReady`). The browser
now obtains the selected model's minimum memory from its existing authenticated
portal catalog, preserves the lease's output budget, and allows 120 seconds
for a trial response rather than the old fixed 30 seconds. No model, precision,
KV-cache or concurrency setting was changed. Unlimited session usage now shows
`0 / 不限`, not `0/0`. Workbench/UI tests pass 48/48. Live workbench image
`sha256:ec946a794f6ed5bd4995d34bc560b42920f2a914062064e037eb3fcbbf57dcdf`
serves the verified asset
`7472fc88f05c29810e581058a690326a2391cf0fb7ae50c76be7b5d337e1c6ee`.

The next attempt revealed the second admission mismatch: the trial-node
inventory advertises only `Confidential`, while the legacy workbench envelope
used `Internal`. Trial browser envelopes now use `Confidential`, consistently
with the existing personal OpenAI API route, while preserving ephemeral
retention, no-cache and no-training-reuse. Node policies were not broadened.
Final workbench image:
`sha256:a747d12a0c37b57783490083246b15871076613e7750c0608462aee9e9786903`;
served and built JS match
`0f574a15a2548d78432d8aad10ffe3c533079901ba6e9901e3ce1437c1b0dcd3`.

Once admitted, the legacy editor payload (`instruction` and `file` only) was
rejected by the runtime adapter, which requires canonical `input` or `messages`.
The workbench now wraps the existing instruction/draft as canonical text input.
The first real successful business question was submitted through the UI:
plan a 90-minute, ten-person AI workshop within 500 yuan. It returned three
Chinese suggestions and receipt
`workload:workload-7344e320-83ae-4455-819d-4da81817ba24:9810603ef9e31038d2147a414ef433e519962fd2992c8d50b1b62b7d773727aa`.
Reported usage: **84 input, 53 output tokens; 752 ms execution**. This is not
an E2E or 32-user throughput benchmark. A fresh management-UI load attributed
the same 84/53 units to ceshi: **4 calls, 2 metered receipts, 779 ms total**.
Those totals include the earlier failed runtime invocation (27 ms, zero tokens)
and two admission rejections; they do not mean four successful answers.

The final presentation fix extracts the assistant's Responses `output_text`
blocks instead of displaying raw JSON, with structured fallback preserved.
Current workbench image:
`sha256:5230ea301be9087c9332ef135a1a269211c119a045a27ef34beca56ea07556b0`;
asset SHA-256 `e6da6a8dd080f0016feb2c185c30320f2ddeccdb13171101c06a11819dfa38c8`.
Workbench/UI regression tests pass **49/49**.

The final readable-output build was rechecked via a second actual UI request.
It returned three plain-text suggestions (no raw JSON), **84 input / 60 output
tokens, 865 ms execution**, receipt
`workload:workload-b08eb2b9-76e5-4a4b-9612-0df22cd5f52d:62d441b5901bfc2750be19cb68bcd912666203cfb24ace877554f7bda3ed065e`.
Screenshot: `tmp/model-trial-ui-20261022/ceshi-workbench-success-20261025.png`.
Both successful calls used the registered user's normal browser trial session,
not an operator token or a command-line inference request.
Final refreshed operator ledger: **5 calls, 3 metered receipts, 168 input,
113 output units, 1644 ms execution**. This equals the two successful answers
(752 + 865 ms) plus one 27 ms failed runtime receipt; the two earlier admission
failures have no token usage. Proof:
`tmp/model-trial-ui-20261022/ceshi-usage-verified-20261025.png`.

The new API button's live acceptance remains pending. API key
creation was presented for action-time approval and **has not been submitted**.
Phone-camera QR acceptance remains pending. Model deployments, precision,
concurrency settings, and nodes 178/179 were not changed.

## Public admission opened and homepage published — 2026-10-24

After the user's explicit “现在开放” confirmation, opened registration using
the management UI. The saved card now shows **活动时间内允许注册**, unlimited
participants/calls, seven days per activation, and **2/2 ready replicas**.
The public registration URL is `https://suanli.kechuangfuwu.com:8443/user/?trial=event`.
No GPU configuration, node scope or machine-access permission was changed.
Proof: `tmp/model-trial-ui-20261022/ongoing-trial-open-20261024.png`.

Published the homepage's compute entry and FDE section with the retained
rollback ConfigMap. The deployed new ConfigMap is
`nexai-public-landing-trial-fde-20261024`. Live HTML SHA-256
`2088e23f97d93a9aa7dd16ef60c64cdd060ab0c46c88bad15b0c7542f746475f`
and CSS SHA-256 `520d590c63a054743ccc9c1946b35d1b8e15a04f62d1d7721a006fd4e8875015`
match local source. Verified the FDE anchor and compute CTA on the real public
site. Desktop layout and visible content checked; phone-camera acceptance is
still pending, not inferred from QR generation. Homepage proof:
`tmp/model-trial-ui-20261022/home-trial-fde-live-20261024.png` and
`tmp/model-trial-ui-20261022/home-fde-section-live-20261024.png`.

Asked the user to complete a fresh test registration themselves, including
password entry and submission. Full new-user inference, personal-key API and
per-person usage acceptance remain pending that handoff. Public enrollment
being open is not evidence that those remaining checks have passed.

## Ongoing seven-day trial preparation — 2026-10-24 23:26 Beijing

Latest operator policy replaces the old 30-person / 200-call / October 25
deadline: ongoing registration, unlimited participants and calls, seven days
from each account's original activation, with per-person usage records. Only
176/177 are selected. 178/179, model settings and concurrency settings were not
changed in this release. Fixed positive-expiry policies retain their behavior.

Controller release `control-ongoing-trial-20261024` rolled out successfully;
binary SHA-256 is `b9dff402c4f585c59904906b37d8703520bfecdaea1222677ea80af7fd2e4d2c`.
Console and enterprise images are respectively
`sha256:f2cd3d07ea14f18bd6e10b8f38e115a3cf7ad8b87ba0cefd1d7ca6c6bc368ef5`
and `sha256:a895b7a79ed15bdc3e21911ae320e8db1c6d0dc501fe3b1b363ba8f9ce9cb4c2`.
Public `/mana/console.js` and `/user/enterprise.js` hashes match the local
release bundles. Before-deployment manifests and the old executable remain on
the management host under `lunanexa-model-ui-20261022.fJCMrU` for rollback.

Saved the policy through the authenticated management UI. It shows unlimited
participants/calls, seven days per activation and **2/2 ready replicas**.
Registration remains **closed**, pending the action-time public-access
confirmation. Screenshot: `tmp/model-trial-ui-20261022/ongoing-trial-ready-20261024.png`.
Homepage compute/FDE entry source is prepared from the existing FDE poster;
publication and fresh-user acceptance remain pending. No claim of live
registration, personal API or phone-camera QR acceptance is made here.

Regression evidence: native event API 4/4, including unlimited-key issuance,
chat admission and operator-only participant summary; ongoing account test
checks 32 participants, 201 requests, staggered seven-day expiry, no login
renewal and persisted consumption after reload. Account/directory 27/27 and
JS UI/console/enterprise 355/355 passed. Isolation-runner fixtures 30/30 passed.
`moon info`, `moon fmt` and scoped diff whitespace checks passed. Existing
strict deny-warning/native-runner/isolation scan failures remain; the
PostgreSQL-specific billing test was not exercised without its test database.

## Fixed-quality campaign preparation and management outage — 2026-10-23

The operator requested repeated fixed-input ordinary/MTP1 comparisons on only
176/177, APC off, basic KV caching retained, no new concurrency cap, and MTP1
selection only after no measured quality regression. Code build/release through
the existing release flow was explicitly approved; all model changes and live
benchmarks must still be UI operations.

Local implementation adds `trial-32x3-512-short-quality64x3-fixed-v1`: 64
synthetic cases repeated three times at concurrency 32, without the old
per-run nonce in quality prompts. Temperature is zero and top-p is one. No
seed guarantee is claimed: the current public chat adapter does not forward a
seed, so this suite does not send one or pretend it is effective. A request /
expected-answer fingerprint and receipt-derived quality node counts are
exported. The UI compares per-case failure frequency, rejects partial,
duplicate, failed-transport or mismatched-configuration evidence, and keeps
legacy results visibly distinct from fixed-input tests. The 99 speed requests
and their E2E/TTFT/tail definitions are unchanged. No automatic promotion.

Local checks: benchmark 6/6; API 219/219 including 5 benchmark-specific tests;
UI 113/113 including 5 decoding/quality tests; console 91/91. Native API and JS
console checks and JS release build succeed with existing deprecation warnings.
`moon info`, `moon fmt`, and `git diff --check` succeed. Global deny-warn and the
native-runner gate still fail on pre-existing deprecated APIs; they are not
reported as passing. Generated interfaces add only the fixture builder and
optional report fields within this change's scope.

Before any new production write, read-only checks found management node
`ubuntu` under `DiskPressure=True` since 2026-10-23 14:47:18 UTC (22:47 Beijing).
It has a disk-pressure NoSchedule taint; the controller, console, PostgreSQL,
identity services and MoonGate have pending replacements. The scheduling event
reports the taint plus node-selector mismatch, not model concurrency. 176/177
model Deployments remain 1/1; 178/179 model replicas remain zero. No model
configuration, platform release, permissions, or filesystem cleanup was applied
in this campaign preparation. Refreshing `/mana/` now shows a controller
connection error; previously loaded benchmark results were stale UI state, not
a new run or proof of a healthy controller. Do not ask the user to re-login as
the remedy for this infrastructure outage.

At 15:25 UTC kubelet reports 76,218,494,976 available bytes of 489,861,931,008,
ample free inodes, hard free-space thresholds 5%, minimum reclaim 10%, pressure
transition period 5 minutes, and image GC high/low 85/80%. Available space had
risen from about 68 GiB to 71 GiB during read-only inspection, without our
deleting anything. The taint was still present at the latest check. Neither
the disk-growth cause nor a stable recovery is established. Do not force-clear
the taint, lower thresholds, restart the whole cluster, or delete data without
appropriate scope. The prepared release helper refuses publication while
disk pressure or platform unavailability remains.

Evidence: `tmp/model-trial-ui-20261022/ui-management-disk-block-20261023.png`.
Read-only diagnostic helper: `inspect-management-disk.mbtx`; release helper:
`release-fixed-quality.mbtx` in the same directory (subsequently executed after
recovery, as recorded below).
Fixed live tests, conditional MTP1 selection, and further TTFT/tail optimization
are **not complete**. The retained desired configuration is still ordinary
decode, APC off, 176/177 only. No new throughput result is claimed.

Recovery update: at 15:27:36 UTC the disk-pressure condition cleared and the
NoSchedule taint was removed automatically, without our changing thresholds,
deleting files or forcing scheduling. PostgreSQL and the private registry
subsequently returned to Running; other platform pods were retrying image
pulls after the registry outage. Approved code staging/build started only after
the pressure cleared. No new Deployment revision had yet been applied at that
point.
At approximately 15:32 UTC the existing controller recovered 10/10, console
1/1 and MoonGate 1/1. The browser had returned to its login screen during the
outage, so operator re-login was requested only after service recovery.

Subsequent publication completed: controller binary SHA-256
`3ea078daffc201d49de04076f3f778b812e7b9f3a59b5eff33cc4783c0a4b731`,
console image `sha256:58c59f7b62b79cdac6e210acc1fdb2c5a5647572c14e5efd2b9a0d997e990442`.
Public `/mana/console.js` SHA-256 was independently verified as
`43ba2e48e097fa35532b2049a3fe9355f1ac392e00383ad3e6ad0d76d826c4cd`.
The console also now preserves the current authenticated page on temporary
network/5xx refresh failures; 401/403 still reject authentication, and anonymous
clients are not promoted. Existing server checks remain unchanged.

The user then reported `身份提供商当前不可用`. This was not evidence of an
incorrect password or expired session: the identity PostgreSQL image used a
local-only alias with pull policy Never, and two identity proxies retained a
broken containerd alias after image GC. The database PVC remained Bound. The
database was pointed to its original immutable PostgreSQL 16.15 image index
`sha256:bb3e1a57e5407e0a5280b4211980a5e537f4abd234a87014ac979849a78dd825`
with IfNotPresent; one already-failed database pod was recreated without
deleting its StatefulSet or PVC. The mirror's manifest confirms the original
amd64 child `sha256:1938c16e9d2f10a6a3623b344b64ae8d45f407f2c5f34f0979468bb689b9227a`.
No mutable tag or different database version was substituted.

Pulling the original proxy digest still failed at container creation because
containerd selected a missing alias for its image config ID. The scoped
recovery image `sha256:76c5d4f44b79cb8f5330ddfd367d9b0e9e6012a60b983664cac5bae461c37a25`
changes only an OCI metadata label: every original filesystem layer, command,
entrypoint and environment is preserved, as are the live proxy/auth/TLS
settings. The existing public proxy recovered 1/1 and internal proxy 2/2.
Management-host mirror download was measured at about 40 KB/s versus about
2 MB/s locally. The original image was therefore downloaded locally, with the
original amd64 manifest and every blob SHA-256 verified, and mirrored into the
existing private registry. Its metadata-only recovery digest is
`moon/identity-postgres@sha256:4fae780d898166b2e44bac091a11111120efad8fb47cfeaf838b94670182199a`;
publish-time checks prove identical executable config (except the recovery
label) and every original filesystem layer. This is still PostgreSQL 16.15,
not the changed mutable `16-bookworm` tag.

The previous pod's normal deletion remained stuck in its external image pull.
Its UID `89389459-85c5-45c2-a8c8-4f865c0254c2` had no image ID or container ID,
zero restarts, started=false and PodReadyToStartContainers=false. Only this
already-terminating, never-started pod record was force-removed. The same
original PVC remained Bound. At 16:07 UTC the replacement database pod became
Running/Ready. Original private source YAML for PostgreSQL and the public
proxy now records the recovered immutable image references and IfNotPresent;
private original backups were retained. The recovered internal proxy manifest
was also saved privately. Failed Keycloak pods were recreated only after the
database became ready. End-to-end browser login subsequently succeeded and
loaded the authenticated deployment console, showing only 176/177 participating
with ordinary decode and APC off. Reloading to load the newly published console
cleared the in-memory login credentials; the user was asked to sign in again,
explicitly distinguishing this from the repaired provider outage. The clean
login view is captured in
`tmp/model-trial-ui-20261022/ui-login-recovered-20261024.png`.
No passwords, permissions or model settings were changed, and no new live
benchmark result is claimed. Fixed-suite execution awaits the new-bundle
operator login; do not relabel the previous non-fixed evidence as a new run.

## Current two-node ordinary / MTP1 / ordinary result — 2026-10-23

The operator requested a fresh A/B/A comparison on 176 and 177 only, using
the `/mana/` controls and normal-user benchmark path. Prefix caching is off,
basic runtime KV caching is retained, routing is least-load, chunked prefill
and token budget remain automatic. Model, precision, context, sampling and
concurrency settings are unchanged. No production code/build change is mixed
into this campaign. Nodes 178 and 179 remain excluded with model replicas zero.

Each arm uses `trial-32x3-512-short-quality64-v2`: 64 quality checks, 32-way
warmup covering both selected nodes, three single-user requests, and three
rounds of 32 simultaneously launched requests. Preparation, quality checks,
warmup and single-user measurements are excluded from aggregate concurrent
throughput. Full E2E timings include first-token and stream-completion delays.

| Measurement | A1: ordinary | B: MTP1 | A2: ordinary |
|---|---:|---:|---:|
| Aggregate E2E token/s | 516.16 | 611.89 | 566.48 |
| Per-request E2E mean / minimum token/s | 19.48 / 14.11 | 22.33 / 16.90 | 20.48 / 15.76 |
| Decode-only mean token/s | 27.02 | 30.78 | 26.43 |
| TTFT mean / P95 seconds | 6.553 / 14.703 | 3.966 / 5.287 | 3.506 / 5.154 |
| Tail mean / P95 seconds | 1.876 / 4.827 | 2.929 / 7.886 | 2.508 / 7.048 |
| Concurrent responses >=30 token/s | 2/96 | 3/96 | 0/96 |
| Quality checks passed | 60/64 | 62/64 | 63/64 |
| Single-user E2E mean token/s | 60.79 | 70.43 | 65.34 |

A1 `benchmark-1792764779827`:
`/Users/kq/Downloads/model-pool-evidence-1792765152786.json`.
B `benchmark-1792765656369`:
`/Users/kq/Downloads/model-pool-evidence-1792765937676.json`.
A2 `benchmark-1792766416171`:
`/Users/kq/Downloads/model-pool-evidence-1792766806552.json`.
All three arms completed 99/99 measured requests and reclaimed all 32 temporary
grants each. All 96 concurrent outputs per arm contain 512 tokens, with 48
responses per node and zero cached input tokens. Every arm successfully warmed
both selected nodes before measurement. A1 fails user 1 and user 27 in both
quality rounds (`quality: mismatch total`); B fails user 1 in both rounds; A2
fails only user 1, round 2. No malformed JSON or incomplete measured stream was
observed. B introduces no failed case relative to A1, but user 1 / round 1 fails
in B and passes in A2. The same user/round facts and expected answers are used;
the synthetic dossier includes a per-run nonce, so these are not byte-identical
prompts. Quality requests use temperature zero. No claim of quality equivalence
or full business acceptance is supported by these small, varying results.

MTP1 is the throughput winner in this campaign: aggregate throughput is about
18.5% above A1 and 8.0% above A2; decode-only mean is about 13.9% and 16.5%
higher. It is not a universal latency winner: A2 has lower mean/P95 TTFT and
tail than B. Mean authentication / admission / runtime TTFT times (seconds)
are A1 2.492 / 1.860 / 1.593, B 1.206 / 1.543 / 0.770, and A2
0.964 / 1.462 / 0.521. Mean receipt / billing times are respectively
0.396 / 1.383, 1.189 / 1.583, and 0.298 / 2.106 seconds. These variable
platform phases prevent attributing every E2E difference to speculative
decoding; no new causal database-lock or kernel profile was performed.

**Retained configuration: ordinary decoding, APC off, basic KV caching
retained**, on 176 and 177. This is a conservative quality-first hold, not a
claim that ordinary decoding is faster. The operator required no quality
sacrifice; the faster MTP1 arm has not established quality non-regression
against the final ordinary control. A fixed-prompt, repeated quality comparison
is still needed before selecting MTP1 under that requirement. Neither mode
meets 32/32 users at 30 E2E token/s in each of three rounds. No concurrency cap,
lower precision, shorter response target or weaker correctness check was used.

Final UI verification around 2026-10-23 22:47 Beijing time: actual ordinary
decoding and unchanged execution tuning show 2/2 applied, 178/179 are excluded
and stopped, and the final test has 99/99 completed / 32/32 grants reclaimed.
Read-only Deployment verification confirms desired/ready 1/1 on each selected
service and desired zero on each excluded model service. UI evidence:
`tmp/model-trial-ui-20261022/ui-two-node-aba-results-20261023.png` and
`tmp/model-trial-ui-20261022/ui-two-node-aba-final-20261023.png`.
This campaign changed only UI-controlled decoding settings and this report;
no new production build, MoonGate change or database-path change was deployed.

## Previous two-node scope / MTP-depth outcome — 2026-10-23

The operator selected `192.168.2.176` (`spark-25e2-3d35c8fd`) and
`192.168.2.177` (`spark-3782-feee26eb`), with the latter display name `177`.
The existing four-service adoption authority is unchanged. A new `/mana/`
selection saves routing exclusion before stopping only the two excluded adopted
model Deployments; weights, node agents, and unrelated workloads are retained.
Subsequent tuning, rollout, rollback, and 32-user benchmarks use selected nodes.
Reports retain exact node IDs so different fleet sizes cannot appear as paired
configuration comparisons. No admission or runtime concurrency cap was added.

Feature checks: model pool 8/8, event trial 7/7, API 218/218, UI 111/111.
`moon info`, `moon fmt`, and `git diff --check` completed. Global deny-warn and
native-runner gates remain blocked by pre-existing deprecated API warnings;
dependency-isolation also reports the existing shared-trial fixture dependency.
Controller SHA-256: `b6d554f9b31bcdeb634f766245aa2ddd37dd5648584c6271475f915de4aaec54`.
Console image: `sha256:0315da39d7f4cd8d3cec8df5aede8d7a19ed3a32a0eedd6b76f25e3e4f40421f`.

The controller restart exposed an unrelated expired offline-commerce readiness
attestation (issued 2026-09-22 11:28:07 UTC; expired 2026-10-23 11:28:07 UTC).
Startup incorrectly made the whole controller unavailable. Recovery uses the
documented intentionally-pending mode by removing both optional readiness env
references, preserving the original deployment in the private release directory.
No expired evidence was accepted or re-signed, and offline commerce remains gated.
The controller rolled out healthy; the existing browser session recovered without
asking the user to log in again. Model scope and benchmark acceptance are recorded
below only after their UI operations finish.

UI scope application is now verified: 176 and 177 are selected and healthy,
MTP1 and existing execution settings show 2/2 applied, and 178/179 both show
`已退出路由 · 模型已停止`. A read-only Deployment check confirms replicas
`event-qwen-176=1`, `qwen3-llm=1`, `event-qwen-178=0`, `event-qwen-179=0`.
No Kubernetes object was renamed; `177` is the operator-facing display name.
UI proof: `tmp/model-trial-ui-20261022/ui-two-node-scope-20261023.png`.
First two-node UI run `benchmark-1792760791044` completed and reclaimed all 32
temporary grants. Export: `/Users/kq/Downloads/model-pool-evidence-1792761064731.json`.
All 96 concurrent responses contained 512 output tokens; each selected node
served 48. MTP1, APC off, least-load, automatic prefill/budget:

| Measurement | Two-node baseline |
|---|---:|
| Single-user end-to-end | 81.45–83.18 token/s |
| 32-user end-to-end mean / minimum | 23.42 / 20.21 token/s |
| Requests reaching 30 token/s | 4/96 (rounds 0/32, 1/32, 3/32) |
| Aggregate end-to-end throughput | 675.09 token/s |
| Decode-only mean / minimum | 30.83 / 29.75 token/s |
| TTFT mean / P95 | 3.754 / 4.892 s |
| Tail mean / P95 | 1.709 / 3.254 s |
| Quality checks | 62/64 |

Both quality failures are the known user-1 `total` mismatches, rounds 1 and 2,
with HTTP 200 and complete streams. No cached tokens were used. Authentication,
admission, runtime TTFT, receipt, and billing means are respectively
0.810 / 1.507 / 1.125 / 0.417 / 1.176 s. These are observed phase timings, not
a completed database-lock profile. The two-node 32-user target is **not met**.
MTP2 was next applied through the UI to the two selected nodes only for a
same-scope comparison. No precision, sampler, context or concurrency change.

MTP2 UI run `benchmark-1792761615942` also completed 99/99 requests and reclaimed
32/32 temporary grants. Export: `/Users/kq/Downloads/model-pool-evidence-1792761973444.json`.
The exact same two nodes each served 48 concurrent requests; all 96 outputs
contained 512 tokens. Quality was 62/64 with the same two user-1 `total`
mismatches and no additional failed case in this bounded suite.

| Two-node comparison | MTP1 | MTP2 |
|---|---:|---:|
| Mean / minimum end-to-end token/s | 23.42 / 20.21 | 22.04 / 18.37 |
| Aggregate end-to-end token/s | 675.09 | 618.65 |
| Requests reaching 30 token/s | 4/96 | 6/96 |
| Decode-only mean token/s | 30.83 | 30.82 |
| TTFT mean / P95 seconds | 3.754 / 4.892 | 5.495 / 7.635 |
| Tail mean / P95 seconds | 1.709 / 3.254 | 1.555 / 3.868 |
| Single-user end-to-end token/s | 81.45–83.18 | 53.53–77.41 |

No useful MTP2 gain was established. Its auth/admission means rose to
1.797 / 1.975 s while runtime TTFT stayed near 1.150 s; this is **not evidence
that MTP2 caused every platform-side increase**. The measured execution speed
did not improve, and neither configuration met the 32-user end-to-end target.
The UI was used to restore MTP1 on the two selected nodes. Final readiness is
verified separately below; no extra concurrency limit or weaker answer format
was introduced. Prefix caching remains off because earlier cache experiments
introduced additional malformed-output cases. Full business-quality acceptance
and platform admission/tail latency fixes remain open.

Final UI verification at approximately 2026-10-23 13:35 UTC: 176 and 177 both
report actual MTP1, with execution settings applied 2/2; 178 and 179 remain
excluded and stopped. The latest test shows 99/99 completed and 32/32 grants
reclaimed. Restoration is verified as a deployment state, not a third timed
benchmark. The two-node scope and names remain persisted. Final proof:
`tmp/model-trial-ui-20261022/ui-two-node-restored-20261023.png`; comparison crop:
`tmp/model-trial-ui-20261022/ui-two-node-mtp-comparison-20261023.png`.
Final `moon info` completed with 310 existing warnings / 0 errors, `moon fmt`
completed, and `git diff --check` is clean. No additional production changes
to MoonGate or the database write path were made in this two-node scope turn.

## Previous four-node outcome: tuning UI complete; end-to-end target not met

As of 2026-10-23 09:48 UTC, all four replicas are healthy on MTP1, APC **off**,
least-load routing, automatic chunked prefill and automatic token budget.
Model/precision/context/sampler are unchanged; no concurrency cap was added.
Tuning and benchmark operations were executed in `/mana/`; code compilation
and release used the repository release scripts. MoonGate cache opt-in
passthrough is deployed, but does not force caching when the runtime is off.

Latest short-input UI run `benchmark-1792748549551`: 96/96 concurrent requests
completed with 512 output tokens, mean/minimum end-to-end **29.00/20.93 token/s**,
only **30/96 >=30**, aggregate **767.07 token/s**. TTFT mean/P95 **5.298/8.848 s**,
tail **1.171/2.602 s**, single-user **78.07–80.91 token/s**. Quality is **63/64**
(user 1, round 2, `total` mismatch), not full acceptance. All 32 test identities'
temporary permissions are reclaimed. Export:
`/Users/kq/Downloads/model-pool-evidence-1792748874936.json`.
UI proof images are retained at
`tmp/model-trial-ui-20261022/ui-tuning-final-20261023.png` (result panel) and
`tmp/model-trial-ui-20261022/ui-tuning-full-20261023.png` (full page).

APC + MTP produced two new malformed-JSON cases on cache hits and was disabled.
4096-token budgeting and MTP2 did not establish a reliable target-reaching gain.
The inference-usage delta was retained after an A/B/A comparison: mean tails
**1.545 / 3.102 / 1.171 s** (delta / old / delta). This supports the narrower
write path, **not** a claim that latency is fixed or throughput is reliably
improved. Latest auth/admission/runtime TTFT means are **0.950/2.398/1.677 s**;
controller waiting remains material. Heartbeat/full-snapshot mutex contention
is a code-supported candidate, not yet kernel- or lock-profiled causal proof.

Retained controller binary SHA-256:
`319a8d8a6d68c50abc843952d75620a96f08ead90f619adfb4276246dfd050e2`.
The inference call site is restored to this delta implementation after the
counterfactual. Durable receipt, billing and `[DONE]` ordering are preserved.
The retained call site again passed API 217/217 tests; final `moon info`,
`moon fmt` and whitespace checks completed. This does not remove the documented
pre-existing global deny-warn failures.
The known quality baseline failures and platform tail/admission work remain
unresolved; no global optimum, 32-user guarantee, or full quality equivalence
is claimed. Detailed chronology and every measured round follow.

## Prefix/prefill/MTP tuning chronology, 2026-10-23

The UI now has typed prefix-caching, soft cache-affinity routing, chunked-prefill
and per-step token-budget controls. Model precision, context length, sampler,
runtime image, and the no-event-concurrency-cap policy stay unchanged. Routing
only changes do not restart replicas. Execution changes require all four exact
deployment configurations to become ready before a benchmark can start.

The public OpenAI bridge continues to treat raw payloads/responses as ephemeral
and does not enable response caching. JSON `runtime_prefix_cache: true` explicitly
opts a request into transient, tenant-salted GPU prefix-state reuse on the
adopted model pool. Unmarked requests use a request-specific salt. The UI's
synthetic benchmark sends this opt-in; application clients must opt in too to
receive prefix reuse benefits. Routing records only bounded prefix digests,
scoped by tenant/model/generation, with a five-minute affinity expiry; this is
a locality prediction, not a KV residency claim or a concurrency cap.

New benchmark profiles distinguish short, unique-long (cold prefix, not cold
process), and repeated-long prefixes. They retain 512-token output ceilings,
three single-user and three 32-user rounds. Before timing, two concurrent
32-user long-context checks exercise updated facts, arithmetic, Chinese labels,
and JSON output. A failed check prevents full quality acceptance. Transport
failures stop the run; semantic failures remain in the evidence while timing
continues for diagnosis. Paired reports explicitly count new and repeated
failures, never treating an imperfect baseline as all-correct. These checks do
not establish complete business-quality equivalence. Actual cached-token counts
come from upstream usage when present; missing metrics are not zero hits.

The controller/UI feature release and MoonGate cache-header passthrough are
deployed. The first UI-started run, `benchmark-1792737877356`, stopped before
performance timing: all 64 quality requests returned HTTP 403 / zero output
tokens. This is not evidence of incorrect model answers. The event path and
workspace lease both hard-coded 8 KiB of canonical JSON input bytes, rejecting
the new synthetic dossiers before runtime invocation. A backward-compatible
`max_input_bytes` event option now keeps old events at 8192, while the closed
benchmark requests 32768. It is exposed in the event UI; no prompt truncation,
output shortening, public registration or concurrency change is involved.
The input-budget follow-up is deployed. No new performance improvement is
claimed yet. Previous measured results below remain historical.

The subsequent UI runs both completed 64 HTTP-200 quality requests with 62/64
strict content checks passing: MTP1 `benchmark-1792739140065`, followed by
ordinary decode `benchmark-1792739985385`. Both failures are user 1, rounds 1
and 2; both returned receipts and complete streams, with zero cached tokens.
Thus these observations do not attribute the discrepancy to MTP or APC.
The evidence exports are `model-pool-evidence-1792739280539.json` and
`model-pool-evidence-1792740123746.json` in `/Users/kq/Downloads/`.
Those runs stopped before performance timing under the original hard gate.
A diagnostic follow-up is deployed: strict JSON/field matching is unchanged,
but known-field mismatch names (never raw answers) are retained and diagnostic
timing is separated from quality acceptance. No concurrency cap is added.
Ordinary-decode diagnosis was followed by a UI restoration of MTP1 on all four
replicas before the new performance baseline. Controller binary SHA-256:
`b45b4ab9a88d0c7eb13523cb8f87e3a29ab63e05baa1fbb8dce8fe40cb31de6d`;
console image SHA-256:
`734ab37c022dbcdd949b403aaeeb8fac860e509ab3be0fa5573211bd8817286f`.
Latest scoped checks pass: API 217, UI 110, benchmark 5, model pool 6,
event-trial 7 and runtimes 52 tests. Global deny-warn gates remain blocked by
pre-existing deprecations documented in the local test logs, not reported as
passing.

Read-only startup logs also confirm the pinned runtime defaults for this model:
prefix caching disabled, chunked prefill enabled, KV dtype `auto`, attention
block size 1056. An ordinary-decode first quality round incurred a Triton
`_compute_slot_mapping_kernel` JIT compilation; its cold latency is not a
warmed performance result. No KV precision reduction or prompt truncation was
used to conceal this cost.

### Fresh tuning baselines (not the historical MTP acceptance below)

The two baseline runs (first two rows) use MTP1, prefix default/off, least-load routing, chunked-prefill
default/on and automatic token budget. All 96 concurrent outputs are 512
tokens; all 32 accounts are reclaimed. Quality is 62/64 in both, but the failed
cases differ: short has user 1 in rounds 1/2; repeated-long has users 1/27 in
round 2. All failures flag `total`, without storing the actual answer. Equal
pass counts do not establish quality equivalence; the baseline itself varies.

| Profile / UI run | End-to-end mean / minimum | >=30 requests | TTFT mean / P95 | Tail mean / P95 | Aggregate |
| --- | --- | --- | --- | --- | --- |
| Short `benchmark-1792741270220` | 30.83 / 26.05 token/s | 51/96 | 2.554 / 5.474 s | 1.531 / 3.958 s | 888.26 token/s |
| Repeated-long `benchmark-1792741552484` | 23.14 / 20.22 token/s | 0/96 | 4.829 / 7.493 s | 1.364 / 3.121 s | 676.48 token/s |
| Repeated-long, APC only `benchmark-1792742498408` | 23.04 / 19.25 token/s | 0/96 | 4.611 / 7.791 s | 0.791 / 1.967 s | 669.99 token/s |
| Repeated-long, APC + routing `benchmark-1792742908604` | 23.21 / 20.19 token/s | 1/96 | 4.801 / 7.694 s | 1.075 / 3.074 s | 658.56 token/s |
| Repeated-long, APC + routing + budget 4096 `benchmark-1792743940104` | 22.44 / 17.66 token/s | 0/96 | 5.919 / 10.219 s | 1.084 / 2.382 s | 620.43 token/s |
| Repeated-long, APC + routing, tail follow-up `benchmark-1792745040113` | 23.35 / 15.87 token/s | 1/96 | 4.651 / 7.763 s | 1.009 / 1.911 s | 594.41 token/s |
| Repeated-long, APC off, MTP1, tail follow-up `benchmark-1792745863494` | 22.18 / 19.17 token/s | 1/96 | 6.184 / 10.550 s | 0.727 / 1.662 s | 654.28 token/s |
| Repeated-long, APC off, MTP2 `benchmark-1792746683780` | 23.42 / 21.07 token/s | 0/96 | 5.040 / 7.756 s | 0.907 / 1.976 s | 684.64 token/s |
| Short, restored MTP1, tail follow-up `benchmark-1792747567923` | 29.67 / 19.35 token/s | 45/96 | 3.331 / 6.039 s | 1.545 / 7.599 s | 775.77 token/s |
| Short, MTP1, old billing counterfactual `benchmark-1792748059749` | 28.77 / 21.74 token/s | 35/96 | 2.982 / 3.720 s | 3.102 / 6.860 s | 738.92 token/s |
| Short, MTP1, delta recheck `benchmark-1792748549551` | 29.00 / 20.93 token/s | 30/96 | 5.298 / 8.848 s | 1.171 / 2.602 s | 767.07 token/s |

UI exports: `/Users/kq/Downloads/model-pool-evidence-1792741509808.json`
and `/Users/kq/Downloads/model-pool-evidence-1792741893052.json`.
Repeated-long input is 3943–3944 tokens and all reported cached counts are
zero, consistent with the disabled runtime prefix cache. Each node handled
24 concurrent measured requests. These fresh observations do **not** reproduce
the earlier all-96 >=30 result, and the older result must not be presented as
the current performance outcome.

The short run's measured controller receipt/billing means are 0.794/0.615 s;
the repeated-long run's are 0.180/1.104 s. A focused follow-up, deployed after
the 4096-budget comparison,
updates only the current inference observation/charge in the existing JSONB
snapshot, avoiding serialization/transmission of full business and unchanged
integration histories. It retains durable completion and the existing schema;
the isolated PostgreSQL replay, conflict, rollback and recovery tests pass.
Its speed contribution has not been measured. The UI APC-only comparison is
kept on the previous controller binary to avoid mixing code and cache changes.

APC-only evidence: `/Users/kq/Downloads/model-pool-evidence-1792742841823.json`.
All 96 requests completed, quality was 62/64 (user 1 in both rounds, `total`
mismatches), and 44/96 performance requests reported 2112 cached tokens each
(92928 total). This establishes actual reuse but **not** an end-to-end speed
improvement. The first measured round was slower than later rounds; retain all
three. A background controller compilation was SIGSTOP-paused before this run
to avoid competing CPU work on the management host; it was resumed after
the APC/routing comparisons. Those comparisons used the previous controller.

APC + routing evidence: `/Users/kq/Downloads/model-pool-evidence-1792743296288.json`.
Cache hits increased to 86/96 (1892 mean cached tokens); quality was 62/64
(users 1/27 in round 2). Mean runtime TTFT fell from 2.855 to 2.107 seconds,
but mean controller admission increased from 0.955 to 1.799 seconds, offsetting
that saving in total TTFT. This pair does not establish an end-to-end gain.
Node counts were 26/23/25/22: affinity is soft, not an equal-partition guarantee.
The background compiler was resumed after all requests had completed, and the
pending tail binary finished as SHA-256
`319a8d8a6d68c50abc843952d75620a96f08ead90f619adfb4276246dfd050e2`.
An independent rebuild check returned `no work to do`. A stale local SSH wait
was closed only after remote compilation completion was verified.

That tail binary was subsequently published as `control-model-tuning-tail-20261023`;
the controller rollout succeeded. The previous quality release and deployment
backup remain available for rollback. Model configuration was not changed by
this code release; its latency effect still requires a same-config UI run.

The explicit chunked-prefill / 4096-token budget run is exported at
`/Users/kq/Downloads/model-pool-evidence-1792744361424.json`. It completed
99/99 timed requests and reclaimed 32/32 accounts; cache hits were 85/96 and
quality 62/64 (user 1, both rounds). It did not improve end-to-end speed, so
automatic budget / automatic chunking were restored through the UI. Runtime
TTFT was 2.259 s while authentication/admission means were 1.639/1.699 s;
platform variability prevents attributing the whole regression to the budget.

The automatic-budget tail follow-up was exported through the UI as
`/Users/kq/Downloads/model-pool-evidence-1792745332336.json`. It completed
99/99 requests and reclaimed 32/32 accounts. Cache hits were 88/96; runtime
TTFT mean was 2.106 s. Mean billing was 0.809 s and its maximum 8.693 s;
stream-tail maximum was 8.978 s. Thus the patch has **not** established a
reliable tail or aggregate-throughput improvement; durable JSONB row updates
still rewrite stored payloads internally and the commercial mutex remains.

More importantly, quality was 59/64: `total` mismatches for user 1 in both
rounds and user 27 in round 2, plus **invalid JSON** for users 2/31 in round 2
(both reported 1056 cached input tokens and reached the 128-token quality
ceiling). No raw answer is retained, so
the precise malformed content is unknown. The operator therefore turned APC
and cache-affinity routing **off through the UI**, retaining MTP1 and automatic
prefill/budget for a controlled repeat. This combination is not quality-approved.
Upstream reports [53912](https://github.com/vllm-project/vllm/issues/53912)
and [47194](https://github.com/vllm-project/vllm/issues/47194) describe hybrid
MTP/cache correctness failures in other configurations; they motivate caution
but do not prove the cause of this installation's failures. No blind runtime
upgrade, KV precision reduction, sampler change or relaxed quality matcher was
used to hide the issue.

The cache-off MTP1 restart logs reported 69.97 GiB available KV cache and
2,998,509-token capacity per replica (theoretical maximum 45.75 full 65,536-token
requests). This benchmark's roughly eight 4K-input streams per replica are not
close to that capacity. No KV quantization was introduced.

The UI now explicitly marks hybrid APC + MTP as experimental and separates
speed from quality approval; it also explains the current model's >1024-token
cache-page alignment when choosing a batch budget. Console image:
`sha256:cb4f10b804ecab115d2463d6c6f1a15722956eea76e4f6bdcb7cd19bddb7f739`,
JS SHA-256 `9621538a51b6221a81ae8958a7d2b92313f865df61c6651a82dae3adfa1e7f99`.
UI tests pass 110/110. `moon info` and `moon fmt` completed; generated interface
changes include the expected inference-usage delta API, with existing feature
interfaces retained. This is not a claim that global deny-warn gates pass.

The cache-off counterfactual, still MTP1 / automatic prefill and budget, is
`/Users/kq/Downloads/model-pool-evidence-1792746192945.json`. All 99 measured
requests completed and 32/32 identities were reclaimed. Quality was 63/64:
only user 1 in round 2 had a `total` mismatch; **no invalid JSON**. Both quality
and performance reported zero cached tokens. This supports leaving the combined
APC/MTP path off, without claiming a fully isolated proof of its defect. Nodes
handled 24 measured concurrent requests each. Single-user end-to-end was
67.14–70.28 token/s; concurrent decode mean 31.62, auth/admission means
1.616/1.458 s, runtime TTFT 2.821 s and billing 0.610 s. The platform's TTFT
variability still prevents a reliable all-user 30-token/s outcome.

Post-run, read-only runtime counters cover exactly 195 requests across four
replicas (64 quality + 32 warm-up + 99 measured). MTP1 draft/accepted-token
counts were 7916/5550, 7998/5522, 7967/5533, 7699/5287; total acceptance was
21892/31580 = 69.32%. These are combined-workload counters, not a performance-only
acceptance metric. The subsequent UI action changes only MTP depth to 2;
APC stays off and the token budget remains automatic.

MTP2 evidence: `/Users/kq/Downloads/model-pool-evidence-1792747049356.json`.
It completed 99/99 requests, reclaimed 32/32 accounts and distributed the
96 concurrent requests evenly (24 per replica). All outputs were 512 tokens;
all cached-token counts were zero. Single-user end-to-end was 67.21–75.21
token/s, concurrent decode mean 32.21 (MTP1: 31.62, +1.89%), runtime TTFT
2.848 s (MTP1: 2.821), auth/admission 0.664/1.270 s (MTP1: 1.616/1.458).
Therefore the 5.59% mean end-to-end increase cannot be credited to MTP depth
alone; the small decoding difference and larger platform-wait variation do
not establish a reliable win. Quality was 62/64, user 1 in both rounds with
`total` mismatch, no malformed JSON. This is a known baseline failure pattern,
not proof of new MTP2 damage, but it is also not full quality acceptance.

Runtime MTP2 counters (quality + warm-up + measured) reported draft batches /
draft tokens / accepted tokens of 6547/13094/6981, 6241/12482/6760,
6497/12994/7037 and 6519/13038/7007. The second draft positions accepted
2552, 2518, 2610 and 2602 tokens respectively; depth 2 was genuinely executing.
Given no reliable all-user or quality-qualified gain, the operator restored
MTP1 through the UI, keeping APC off, least-load routing and automatic budget.
Final short-input verification follows after all four replicas are ready.

Restored-MTP1 short verification is
`/Users/kq/Downloads/model-pool-evidence-1792747894569.json`: 99/99 complete,
32/32 reclaimed, 24 concurrent requests per node, all outputs 512 tokens,
68–69 input tokens and zero cache hits. Quality was 62/64 (user 1, both rounds,
`total` mismatch; no malformed JSON). Single-user end-to-end was 70.94–83.70
token/s (mean 79.30); concurrent decode mean 40.36, with all 96 decode-only
rates above 30. End-to-end was only 45/96 above 30, so decode success does not
constitute acceptance. Billing mean/P95/max was 1.338/7.312/7.931 s, accounting
for most of the 8.040-second maximum tail. Round pass counts were 2/32, 21/32,
22/32; all are retained, including the slow first round.

The inference-usage delta code has not established a reliable latency win.
It was therefore rolled back to the prior `control-model-tuning-quality-20261023`
binary for a same-model-config short counterfactual. Source/tests are retained
as an unaccepted experiment; model settings, UI controls and MoonGate remain
unchanged. The rollback rollout succeeded; the local inference call site was
also restored to full-snapshot persistence, so a later ordinary build does not
silently reactivate the experimental delta method. Do not describe the tail as fixed.

After restoring that call site, API tests again passed 217/217. The isolated
PostgreSQL suite again passed all eight groups (1/1/1/1/1/5/1/1 tests), including
replay, rollback and recovery, and stopped its temporary server. Test data was
retained at `/var/folders/_j/kcn3f7817s71gymnv_nnn1bm0000gn/T/lunanexa-latency-pg-.70839.fa49ec13`.
`moon info`, `moon fmt` and `git diff --check` completed; pre-existing deprecated
API warnings remain and the global deny-warn gates are not claimed to pass.

The old-billing counterfactual is
`/Users/kq/Downloads/model-pool-evidence-1792748411385.json`. It completed 99/99,
reclaimed 32/32 and retained quality 62/64 (user 1, both `total` mismatches).
The 96 concurrent outputs were 512 tokens and node counts 24 each. Mean
receipt/release/billing were 0.532/0.123/2.307 s; tail mean/P95/max were
3.102/6.860/7.486 s. Single-user end-to-end was 45.27–79.75 token/s.
Old persistence therefore does not remove the long tail and its mean is worse
than the delta run. A same-binary delta recheck is being performed to complete
an A/B/A comparison; neither path is claimed to have fixed the problem.

The delta recheck export is
`/Users/kq/Downloads/model-pool-evidence-1792748874936.json`. It completed
99/99 and reclaimed 32/32, with 24 concurrent requests per node and zero cached
tokens. Quality was 63/64 (user 1, round 2, `total` mismatch; no malformed JSON).
Mean receipt/release/billing were 0.190/0.025/0.919 s. Tail maximum was 2.750 s,
but TTFT maximum 8.852 s and admission P95 6.124 s. Concurrent decode mean was
43.38 token/s; all 96 decode-only rates exceeded 30. End-to-end round passes
were only 3/32, 20/32, 7/32. The delta binary is retained based on the repeated
mean-tail improvement, while admission and quality limitations remain explicit.

Read-only database size inspection found control/commercial snapshot text sizes
of 6,699,447 / 2,924,817 bytes. Heartbeat updates still use full control snapshots
and share the store mutex with admission reads and receipt writes; this is a
candidate contributor to spikes, not yet an isolated causal measurement.

The UI adds per-item quality diagnostics (status/output count, never answer
text) and JSON evidence export. The failed run was exported through the UI to
`/Users/kq/Downloads/model-pool-evidence-1792738403595.json`.

MoonGate forwards only `x-lunanexa-prefix-cache: tenant`; caller identity,
cookies and control credentials are still not forwarded. Its native check and
1211 tests pass. Release `gateway-event-tuning-20261023` initially failed because
the host umask masked the new directory's execute permission for the existing
unprivileged container user. Correcting only that release directory to 0755
restored the gateway; the old binary remains available for rollback.

## Historical acceptance: UI-controlled MTP, 2026-10-23

**Passed for this bounded, warmed benchmark: four machines, 32 simultaneous
users, all three rounds at least 30 end-to-end token/s per user.** All **96/96**
concurrent responses were valid and exactly 512 output tokens. Four replicas
remain on **MTP with one draft token**. No execution concurrency cap was added.
This is not a guarantee for arbitrary prompts, long contexts, cold starts,
sustained activity, or client networks.

Both runs were started from the deployed `/mana/` UI, using 32 independently
authenticated test accounts, personal API keys and the public
`:8443/trial/v1` MoonGate path. The off baseline was measured first; the MTP
configuration was then applied to all four existing services **through the
UI**, not a manual model-deployment patch. Each run used the same three
single-user requests, three rounds of 32 concurrent requests, 512-token
ceiling and separately reported 32-request warm-up. Account grants and keys
were reclaimed **32/32** after each run. Public registration stayed closed.

| Measurement | Ordinary decode, off | MTP, one draft token |
| --- | --- | --- |
| Concurrent valid / target-passing responses | 96/96 / **96/96** | 96/96 / **96/96** |
| Concurrent end-to-end range | 30.15–36.61 token/s | **32.20–45.15 token/s** |
| Mean concurrent end-to-end rate | 32.48 token/s | **36.08 token/s (+11.1%)** |
| Mean concurrent decode-only rate | 36.96 token/s | 42.79 token/s (+15.8%) |
| Concurrent mean / maximum first-token wait | 1.444 / 1.862 s | 1.791 / 2.274 s |
| Concurrent mean / maximum stream tail | 0.521 / 1.371 s | 0.497 / 1.526 s |
| Aggregate concurrent end-to-end throughput | 970.37 token/s | **1066.30 token/s** |
| Single-user end-to-end range | 72.22–76.08 token/s | **79.70–86.27 token/s** |
| Separate warm-up maximum TTFT | 1.970 s | 5.241 s |

Each machine handled exactly **24** measured concurrent requests in each
run. MTP per-round minima were **33.59, 34.24 and 32.20 token/s**, with
**32/32** passing in each round. The slowest MTP response has only about
**7.3%** headroom over 30, so this result does not establish a wide service
margin. No longer outputs, fewer users, best-round selection or early `[DONE]`
were used. Warm-up, account preparation and permission cleanup are outside
the inference rates and are reported separately.

The off baseline also passed this time, narrowly. The previous journal run
below failed at 67/96; it is retained, not overwritten. The fresh controller
release, timing/history and normal runtime variability differ across those
runs, and we have not isolated their contribution. Thus MTP should not be
credited with turning a simultaneous failing baseline into a passing one.
The paired test supports a measured speed improvement, not a claim that all
platform latency was solved: first-token wait was **higher**, not lower, with
MTP in this pair.

### Configuration and actual execution evidence

- Same model artifact in both runs:
  `sha256:c1e20ce8b80fbd28d6fe63a6b60ec837da8ff841446cd2884d647878bec4635b`;
  `nv-community/Qwen3.6-35B-A3B-NVFP4`.
- Same vLLM 0.26.0 image:
  `sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c`.
- Only the model serving arguments below were appended; target-model Marlin,
  65,536 context, GPU memory fraction 0.80 and the existing route remained.
  No `max_num_seqs`, platform execution slot or per-node concurrency cap was
  introduced. The test event retains `per_node_concurrency: 0`.

```text
--speculative-config {"method":"qwen3_5_mtp","num_speculative_tokens":1,"moe_backend":"triton"}
```

The existing checkpoint contains the MTP weights; no new model download was
needed. The MTP experts are unquantized, so the draft-only Triton backend is
explicit and the main model remains on Marlin. All four deployments had the
new observed generation, one updated/ready/available replica and matching
arguments. All four runtime logs report real `SpecDecoding metrics`, typically
about **67–71% draft acceptance** in substantial intervals. These are runtime
interval observations, including warm-up/single-user work, not an invented
per-request acceptance metric. Startup also confirms shared target embedding
and output-head weights. MTP is executing, not merely checked in the UI.

The runtime warns that `min_p` and `logit_bias` are unsupported in its
speculative mode; this benchmark uses neither. This task did not validate
answer quality, those sampling controls, MTP depths 2–5, or other models.
The legacy method name is accepted by pinned vLLM 0.26.0 and normalized to
`mtp` with a deprecation warning.

### Delivered UI and release verification

The deployment page now provides off / MTP depth selection, an explicit
four-service restart action, ordinary-decode restoration, desired versus
actually ready per-node configuration, and a retained off/on benchmark
comparison. A healthy old endpoint does not count as the requested new
configuration. Benchmark evidence is stamped with model digest, runtime
image, pool generation, draft depth and test profile; configuration changes
during a run invalidate it. These focused UI state/error distinctions follow
the UI/UX skill; no unrelated hardening or RBAC expansion was added.

- Controller binary SHA-256:
  `8bad22c9c4791d8c45e089ca58d490f3b876e981e87e852cee3d22d378d11412`,
  release `control-model-speculative-20261023`. Existing schema v7 retained.
- Console image:
  `sha256:494c91d8ad772d194972887f3a18405a7430a5504dd07228fd0239bdf1628b31`;
  public JS SHA-256:
  `eeb4e9e61847810f865dc326467c173905e99316d1a7f30354eb001b7932239c`.
- Passed: 5 model-pool tests, 215 API tests, 199 UI/console tests,
  6 contract tests and 2 benchmark tests. Ordinary native check and release
  builds completed without errors; formatting, generated interfaces and
  whitespace checks completed. Existing strict deprecated-warning failures
  and the pre-existing isolation product-string violation remain; this is
  not represented as a clean whole-repository release gate.

Evidence under `tmp/model-trial-ui-20261022/`:

- `benchmark-speculative-off-20261023.json` — SHA-256
  `edb137b2c97756e2fee62c64cdad5eee10e91dfbe5ea6bcfc88b642492b933c5`.
- `benchmark-speculative-mtp1-20261023.json` — SHA-256
  `62d90b58ca546ef15bcf2e08758b88cbc83203094ea8f0b7fd7067a1ae06581b`.
- `runtime-speculative-mtp1-20261023.json` — matching four deployment
  arguments/status and selected runtime execution logs, SHA-256
  `7252597e6bb5c18f20131db0269a14a77bdee0ef3afb76cb32bf515417394b19`.
- `benchmark-speculative-mtp1-20261023.png` — live UI comparison, complete
  results and test-permission cleanup.

## Historical acceptance: journal release, 2026-10-23

**Not passed: 32 users × 30 end-to-end token/s is still not established.**
The final UI run used the released receipt-journal controller and schema v7.
All 99 measured requests completed, but only **67/96** concurrent requests
reached 30 token/s across their entire request lifetimes. No concurrency
limit, output-length increase, reduced user count, or best-round selection was
used to manufacture a passing result.

| Measurement | Single user (3 requests) | 32 concurrent users (3 × 32 requests) |
| --- | --- | --- |
| Valid 512-token responses | 3/3 | 96/96 |
| End-to-end rate, each request | 70.45–72.42 token/s | 28.03–36.86 token/s |
| End-to-end ≥30 | 3/3 | **67/96** |
| Mean end-to-end rate | 71.23 token/s | 31.31 token/s |
| Decode-only rate | 76.30–78.36 token/s | 36.17–39.37 token/s |
| Mean / maximum first-token wait | 0.202 / 0.270 s | 1.851 / 2.459 s |
| Mean / maximum stream tail | 0.366 / 0.399 s | 0.779 / 2.226 s |

Concurrent aggregate throughput was **919.21 token/s**, below the 960 token/s
aggregate implied by 32 × 30. Per-round ≥30 counts were **18/32, 22/32,
27/32**. Each physical node handled **24** measured concurrent requests.
The separate 32-request warm-up succeeded on all nodes, with a maximum TTFT
of 2.969 s. Warm-up is not silently included in target-passing results.
All 32 identities, keys and temporary trial permissions were reclaimed;
public registration stayed closed. The operator UI visibly confirms 99/99
completed and 32/32 reclaimed. The original weekend draft was not opened or
silently migrated to the new alias.

### What was fixed, and what remains

Request-level warm-up now covers all four replicas before measurement, and
the dominant full-history receipt rewrite was replaced with durable journal
appends. Compared with the original 96-request baseline, mean stream tail fell
from an inferred **2.827 s to a directly measured 0.779 s**; the maximum fell
from 7.230 s to 2.226 s. The UI now makes end-to-end rate the primary target
and distinguishes it from decode-only rate, with an expandable latency split.

The remaining waits cannot be attributed solely to model decode speed. Mean /
maximum controller timings for the final concurrent run were:

| Stage | Mean | Maximum |
| --- | --- | --- |
| API credential authorization | 391.61 ms | 846 ms |
| Authorization / routing admission | 724.41 ms | 1046 ms |
| Execution-slot wait | 7.26 ms | 31 ms |
| Runtime invocation to first output | 538.09 ms | 783 ms |
| Receipt / audit persistence, including lock wait | 296.64 ms | 1761 ms |
| Admission release | 47.89 ms | 431 ms |
| Usage / billing persistence, including lock wait | 349.50 ms | 857 ms |
| Client stream close | 7.70 ms | 51 ms |

The next optimization targets are the remaining serialized authorization,
admission, metering writes and interference from full control checkpoints.
These intervals include lock/event-loop delays: they are **not** an exact
database-query or CPU profile. Post-test resource usage was below configured
CPU budgets but does not rule out transient throttling during load. No CPU
budgets were changed on that basis. The final journal run has better receipt
timing but does not have a better target-pass count than the intermediate LZ4
run; both are retained below rather than selecting the more flattering run.
Repeated runs add legitimate durable test history; the database was not reset
or pruned between tests.

This is a bounded, warmed, short-prompt, 512-output-token test, not a cold-start,
long-context, sustained-load or arbitrary-network guarantee. Further work is
still required before claiming the strict 32-person end-to-end target.

Final evidence:

- `tmp/model-trial-ui-20261022/benchmark-latency-journal-20261023.json`
  SHA-256 `5972c76605aa1e9f42b7b3744e1c0028ca50ed364408a73f45e417a1c12eb683`.
- `tmp/model-trial-ui-20261022/benchmark-latency-journal-20261023.png` —
  final UI, including target counts and permission cleanup.
- `tmp/model-trial-ui-20261022/collect-latency-report.mbtx` — read-only
  retrieval and full per-round summaries. Failed/intermediate retests remain
  in their own files; none was overwritten.

## Latency investigation and UI retests (2026-10-23)

The first-use wait and stream-tail wait are different bottlenecks. No execution
concurrency cap was added, no model pod was restarted, and the model, output
ceiling, route, user count and normal authentication path stayed unchanged.
Live inference was initiated only by the operator UI. Source/build/releases,
read-only metrics and database diagnostics used development tools.

### Causes and changes

1. Runtime histograms from the original 99 requests attribute the large first
   waits to the **first inference on each model replica**. Three replicas each
   had one request with 10–20 s runtime TTFT; the replica not visited by the
   three single-user requests had eight such concurrent first-use requests.
   Runtime queue-time sums were below 1 ms per replica. This establishes the
   model first-use cost, not an exact kernel/JIT breakdown. The UI workflow now
   prewarms all four replicas through 32 short, authenticated requests, records
   their costs separately, and verifies four-node receipt coverage. Health and
   model-list readiness alone are not treated as warmed inference. The retests
   below used already-running models; they are **not a fresh cold-restart test**.
2. Old tail latency inferred from client timings averaged **2.827 s**, reaching
   **7.230 s**, for the 96 concurrent requests. New client/controller timing
   fields directly distinguish receipt/audit persistence, admission release,
   metering and stream close. These showed receipt/audit serialization was the
   dominant tail stage, not client close or MoonGate buffering.
3. Replacing full application-side JSON serialization with a small SQL update
   was insufficient: the database still rewrote/recompressed the entire
   approximately 4.3 MB control snapshot. A same-server temporary-copy profile
   measured PGLZ rewrite **158.428 ms**, steady LZ4 rewrite **39.306 ms**, and a
   journal append **1.128 ms**. Temporary-table timings exclude production WAL
   and are diagnostic comparisons, not claimed end-to-end results.
4. Schema v6 selects LZ4 for snapshots. Schema v7 and the controller change
   append each workload receipt/audit atomically to `control_workload_commits`.
   Recovery overlays the journal on the checkpoint; ordinary control writes
   atomically checkpoint and clear it. Durable acknowledgement, audit ordering,
   leadership, authorization and commercial metering remain. No early `[DONE]`
   is sent to hide persistence time. A pre-v7 rollback requires quiescing writes
   and checkpointing with the v7 reader first; backups include both tables.

### Intermediate UI results (not a passing acceptance)

Each run: 32 independently authenticated test identities, four replicas,
three single requests plus three rounds of 32 simultaneous requests, 512
output tokens each, public `:8443/trial/v1`. Warm-up is reported separately.

| Configuration | Concurrent end-to-end range | ≥30 count | Mean TTFT | Mean / maximum tail | Aggregate |
| --- | --- | --- | --- | --- | --- |
| Original UI baseline, no request warm-up | 14.94–34.95 | 36/96 | 2.47 s | 2.827 / 7.230 s (inferred) | 620.32 token/s |
| Warm-up + SQL delta, PGLZ | 24.00–36.35 | 46/96 | 0.964 s | 2.687 / 6.069 s | 771.73 token/s |
| Warm-up + SQL delta, LZ4 | 28.77–36.52 | 79/96 | 1.328 s | 0.908 / 2.394 s | 929.71 token/s |

The LZ4 run's single-user end-to-end rate was 73.03–75.56 token/s, with mean
TTFT 0.189 s. Its concurrent decode rate remained 36.00–38.38 token/s; the
mean end-to-end rate of 31.94 is **not** proof that every user reached 30.
All 99 measured requests in both retests completed, each node handled 24
concurrent-round requests, and all 32 test identities were reclaimed.

Evidence: `tmp/model-trial-ui-20261022/benchmark-latency-20261023.json`,
`benchmark-latency-lz4-20261023.json`, `compression-journal-profile-20261023.txt`,
and `compression-migration-20261023.txt` in the same directory. Reports contain
usage/timings/receipts, not prompts, generated answers or credential secrets.
The journal controller's final UI acceptance is recorded above.

### Release and regression evidence

- Controller journal binary SHA-256:
  `44df3a85f8d3e9aa104675b40cdfac7c922923a8c8bdd5f1b55da93870d74617`;
  release directory
  `/home/HwHiAiUser/lunanexa-model-ui-20261022.fJCMrU/control-model-journal-20261023`.
- UI image:
  `sha256:7171f51c30661b0c595fac207bcd3afda709185a4cf9ab82b058f360ce4f7e73`;
  public console JS SHA-256:
  `e458148e1bd35c48975b48f76eff78e6c64db98757bd9d340a41dcaede321feb`.
- Live database reports schema version **7**. No model-serving image, serving
  argument, route or execution concurrency configuration was changed.
- Passed: 215 API tests; 107 UI and 90 console tests; 2 stream benchmark
  tests; 10 isolated PostgreSQL/storage tests; 6 contract tests. The isolated
  tests cover epoch rejection, failed-write non-publication, unchanged large
  checkpoint payload, journal overlay/reopen, duplicate-workload replacement,
  atomic checkpoint rollback and subsequent checkpoint restoration.
- `moon info` and `moon fmt` completed; changed-file whitespace checks passed.
  Native release build completed without errors. The repository is **not a
  clean full release gate**: regular check reports 437 warnings and the strict
  warning gate remains non-green. The isolation script also flags the
  pre-existing product-string rule in `api/shared_trial_offerings_wbtest.mbt`.
  Those unrelated files were not changed to manufacture a clean gate.

## Historical: UI benchmark completed (2026-10-23 00:00 CST)

The approved UI benchmark completed all **99/99** requests through the public
HTTPS `:8443/trial/v1` MoonGate entry, using 32 independently registered,
normally authenticated accounts and their own model-scoped API keys. Three
single-user requests and three rounds of 32 concurrent requests each produced
512 output tokens with valid usage and workload receipts. No command-line
inference or manual account provisioning was used for this benchmark.

| Measurement | Single user, 3 requests | 32 users, 3 rounds / 96 requests |
| --- | --- | --- |
| Valid requests | 3/3 | 96/96 |
| Per-user decode rate | 75.32–77.67 token/s | 36.12–39.00 token/s |
| Mean per-user decode rate | 76.87 token/s | 36.88 token/s |
| Decode rate at least 30 token/s | 3/3 | 96/96 |
| Mean first-token wait | 16.84 s | 2.47 s |
| End-to-end rate at least 30 token/s | 0/3 | 36/96 |

**The output/decode-rate target passes this bounded test. The stronger claim
of 32 × 30 token/s measured across complete request lifetimes does not pass.**
The three concurrent rounds generated 49,152 tokens over 79.236 seconds,
yielding **620.32 token/s overall**, including first-token wait and stream
completion. These are finite 512-token bursts, not a sustained-load or
long-context capacity certification.

Round-level timings explain why decode rate must not be confused with total
throughput:

| 32-user round | First-token median / maximum | Slowest complete request | Approx. round throughput |
| --- | --- | --- | --- |
| 1 | 1.178 / 18.008 s | 34.281 s | 477.93 token/s |
| 2 | 1.117 / 2.344 s | 22.539 s | 726.92 token/s |
| 3 | 0.970 / 1.187 s | 22.334 s | 733.59 token/s |

The single requests each waited 16.501–17.292 seconds for first content.
Subsequent concurrent rounds show much shorter first-token waits, but still
have completion overhead beyond the content-generation interval. This run
does not establish the exact cause of initial or trailing latency; no kernel
profiling or latency optimization is claimed.

Each node handled **24 concurrent-round requests**. Runtime log snapshots
showed **8 running / 0 waiting** on each of the four nodes during the test.
The UI and durable report confirm **32/32 test accounts cleaned up**, with
keys, trial grants, leases and trial memberships revoked and accounts
suspended. Public activity registration stayed closed. No per-node or shared
execution concurrency cap was introduced.
The original weekend-event draft still references the previous model; it was
not silently migrated or opened by this test. Before public registration,
select the new alias in that draft through the operator UI. Its current 0/4
policy-match display is distinct from the new model pool's 4/4 readiness.

Evidence:

- `tmp/model-trial-ui-20261022/benchmark-complete-20261023.json` — sanitized
  durable report with 99 per-request measurements; no credentials or text.
  SHA-256: `d68428c36763c203d2649a41f8816677e85e1d223e65655ad5453dcb79c55b94`.
- `tmp/model-trial-ui-20261022/benchmark-complete-20261023.png` — final UI.
- `tmp/model-trial-ui-20261022/collect-benchmark-report.mbtx` — read-only
  retrieval and round summary of the already completed UI run.

## Latest: UI-driven A3B replacement (23:02 CST)

The ModelScope revision `nv-community/Qwen3.6-35B-A3B-NVFP4` is now running
on all four Spark nodes. The operator UI showed **4/4 new-model ready** and
**new model routing enabled**. The alias is
`nv-community-qwen3.6-35b-a3b-nvfp4`; the verified revision digest is
`sha256:c1e20ce8b80fbd28d6fe63a6b60ec837da8ff841446cd2884d647878bec4635b`.
Download, license acceptance, registration, four-node preparation, model
switching, and route activation were performed through the operator UI.
Source fixes and platform software builds/releases used development tools;
model services were not manually switched with command-line patches.

The user confirmed creation of 32 dedicated test identities and one-hour
model-only grants. The first UI attempt stopped before registration because
controller network policy rejected the portal HTTPS connection. Exact gateway
egress was added; the same public-page GET from the controller then returned
HTTP 200. A second UI attempt registered one account but found a legacy-trial
conflict (HTTP 409); its access was reclaimed. The fix makes the active
benchmark's exact identities skip legacy trial provisioning, while preserving
ordinary registrations, and adds stage-specific sanitized errors. The complete
API test suite passed 214/214 tests, including three new regressions. The
account, stream benchmark and model-pool suites passed another 18 tests.
The fixed controller has been published; model-serving pods were not restarted.
Neither preparation failure issued inference requests. The successful retry
and its measured results are recorded above. Dense-model results below remain
historical baseline evidence, not measurements of this replacement.

Two integration issues were corrected and verified: the switch adapter now
includes the materializer's `sha256/` directory in the read-only model mount,
and the console decodes the optional benchmark report without hiding the
four-node panel. The updated UI/console suite passed 197 tests; the pool suite
passed three tests, including the cache-path assertion. Full benchmark sample
wire decoding was separately tested. No per-node execution cap was added.

Runtime observations: vLLM 0.26.0 resolved
`Qwen3_5MoeForConditionalGeneration`, loaded about 20.38 GiB per model, and
selected the Marlin NVFP4 weight-only backend. Initial loading and graph
warmup completed; this does not establish inference speed.

Release evidence:

- Console image: `sha256:4acfbde225a01f092b02327de50feeb14e86e4d736e3d34ec797bdad7c2e7e72`.
- Console JS: `8029effe55008a56721befb4438d7fdbf744b5d12ff0661b2b897561655afeb4`.
- Controller binary: `df3fd843be7c8c81ee029106edb2e09bc118d710baf70675b6400d190f9ac6ce`.
- Controller release directory: `/home/HwHiAiUser/lunanexa-model-ui-20261022.fJCMrU/control-model-benchmark-registration`.
- UI evidence: `tmp/model-trial-ui-20261022/benchmark-ready-confirmation.png`.

The temporary CPU-only ARM build pod was removed after successful agent image
publication; binaries, images, and previous deployment configurations remain
available. Public event registration remains closed.

## Historical dense-model status and claim boundary

Controller and both operator/customer portal bundles are deployed. The event
API observes **four ready replicas and no readiness blockers**. One MoonGate
event process is running, with a dedicated authenticated HTTPS model entry:

`https://suanli.kechuangfuwu.com:8443/trial/v1` (external).

`https://suanli.kechuangfuwu.com/trial/v1` (LAN port 443; requires hostname
resolution to the LAN TLS ingress, `192.168.2.175`). The `/event/v1` entry is superseded, not
retained as an alias.

**Capacity acceptance failed: 32 concurrent users work, but 30 output tokens/s
per user does not.** Both LAN 443 and external 8443 completed 32/32 real-auth
test streams. GPU metrics prove eight running requests on each physical node,
32 total, with zero waiting. Per-user decode rates were only 7.34–7.60 tokens/s.
The public event remains closed. The user explicitly authorized 32 dedicated
test identities; these are not a claim that 32 human attendees participated.

The arbitrary two-per-node and four-global execution caps have been removed.
Total in-flight admission remains 128, with authentication and model resource
protection retained. See the configuration compatibility note below.

## Follow-up diagnosis: why only 7.34–7.60 token/s?

The bottleneck is reproducible at the model runtime without MoonGate or the
LunaNexa router. The strongest explanation is dense-model weight bandwidth on
GB10, plus ordinary model/kernel overhead. This is supported by measured
backend timing and a tensor-inventory bandwidth estimate, **not** a completed
Nsight kernel/DRAM profile. No serving settings, precision, model, concurrency
limits, deployment, or user authority were changed in this diagnostic pass.

### Controlled direct-backend comparison

After confirming .176 had zero running/waiting requests, bounded internal
diagnostics used its existing runtime credential, a loopback Kubernetes port
forward, the same synthetic 76-token prompt family and thinking disabled.
Each request produced 256 output tokens; prior participant acceptance used
512, so these are diagnostic comparisons, not another 32-user acceptance run.
Credentials stayed in memory/stdin. The revoked participant accounts remained
revoked and public registration stayed closed.

| Path and load | Per-request output rate | Evidence |
| --- | --- | --- |
| Direct vLLM Responses, one request | 8.00 token/s | 181 ms TTFT; 31.890 s for 255 decode intervals |
| Direct vLLM Chat Completions, one request | 7.98 token/s | 181 ms TTFT; 31.973 s for 255 decode intervals |
| Direct vLLM Responses, eight requests | 7.52–7.55 token/s | Eight running, zero waiting, zero preemptions |
| Earlier MoonGate, four nodes × eight requests | 7.34–7.60 token/s | 32 real identities, both LAN 443 and external 8443 |

vLLM's own inter-token timing counters agree with the client: the single
Responses request adds 31.89096 s / 255 intervals = 125.06 ms/token; the
eight-request round adds 270.46687 s / 2,040 intervals = 132.58 ms/token.
The client measured essentially the same times. This rules out a large
MoonGate/HTTP/SSE delay as the explanation for the roughly fourfold target gap.
It also shows continuous batching is functioning: eight users share a decode
step, producing roughly 60 total token/s on one node, rather than taking turns
at 8 total token/s.

### Weight inventory and bandwidth estimate

Read-only inspection of all 66 safetensors headers on .177, whose verified
artifact digest matches the other nodes, found the following stored tensors:

| Component | Stored bytes, decimal GB | Ordinary text-decode treatment |
| --- | --- | --- |
| Text layers | 24.37943 | Included in weight-read estimate |
| Output language-model head | 2.54280 | Included; stored in BF16, not FP8 |
| Text scales and final norm | 0.00298 | Included |
| Input embeddings | 2.54280 | Full table excluded: lookup is not a full-table scan |
| Vision tower | 0.92146 | Excluded from this text-only decode estimate |
| MTP tensors | 0.47720 | Excluded; current runtime has no speculative decoding |

The config resolves to `Qwen3_5ForConditionalGeneration`, with a dense
64-layer text model, hidden size 5,120, intermediate size 17,408 and vocabulary
248,320. Its quantization is dynamic block FP8 E4M3, block size 128 × 128;
not every tensor is FP8. This is not a small-active-parameter MoE workload.

The resulting ordinary decode weight-read estimate is **26.9252 GB** per
step. NVIDIA specifies **273 GB/s** unified-memory bandwidth for DGX Spark
([hardware specification](https://docs.nvidia.com/dgx/dgx-spark/hardware.html)).
Assuming one read of those dense weights per ordinary autoregressive decode
step, even ideal peak-bandwidth transfer alone takes:

`26.9252 GB / 273 GB/s = 98.63 ms/step`, or about **10.14 steps/s**.

Observed steps take 125–133 ms in the direct probes. Their scale is consistent
with the weight-bandwidth constraint plus attention, recurrent state,
activation quantization, matrix operations, scheduling and imperfect bandwidth
utilization. **The difference is not a measured attribution to any one kernel.**
Tensor transformations/caching and actual DRAM traffic have not been profiled;
this is a reasoned roofline estimate, not a universal model-speed guarantee.

Thirty output tokens/s requires 33.33 ms per ordinary step. The same inventory
would require about **808 GB/s per replica** for weight reads alone, roughly
three times Spark's specified peak, before other work. Four independent
replicas increase aggregate capacity; they do not pool memory bandwidth for
one request. The deployed topology is replicated models with load balancing,
not four-way tensor parallelism. Removing more admission limits cannot bridge
this model/hardware bandwidth gap.

### Other causes checked

- The diagnostic eight-request sample had only 2.46% KV cache usage, no waiting
  and no preemptions. A 65,536-token configured context is a maximum, not the
  actual 76-token input length in these calls.
- .176 stayed in P0 with 96% sampled GPU activity, 2,535–2,554 MHz SM clocks and
  50–58°C during load. Power/thermal slowdown flags were inactive; their
  cumulative counters did not increase across the run. High GPU activity is
  not evidence that tensor-compute FLOPS are saturated.
- The existing container CPU quota was 16 cores. `nr_throttled` remained 1 and
  `throttled_usec` remained 20,041 throughout: no new CPU throttling occurred.
- Available system memory stayed around 14.4 GiB. There was no swap-out,
  only 61 swap-in pages across the observation, essentially zero memory PSI,
  and no new OOM kills. Historical swap/OOM counters must not be misreported
  as failures during this test. These samples do not support sustained paging
  as the cause of the stable 125–133 ms decode time.
- Startup selected `CutlassFp8BlockScaledMMKernel`, FlashAttention and CUDA
  graphs. vLLM 0.26.0 deliberately disables DeepGEMM for this architecture on
  Blackwell due to E8M0 accuracy degradation; upstream source confirms the
  exclusion ([versioned source](https://github.com/vllm-project/vllm/blob/v0.26.0/vllm/utils/deep_gemm.py)).
  It is not evidence of CPU fallback, and forcing DeepGEMM is not a safe
  performance fix without numerical validation.

### Implication and next experiments, not yet executed

The current four-replica dense FP8 setup cannot be accepted for 32 × 30 token/s
on the existing evidence. Ordinary kernel/config tuning may recover overhead,
but the bandwidth estimate does not support promising a fourfold speedup from
such tuning alone. Candidate experiments are same-model speculative/MTP
decoding, tensor-parallel execution over verified high-speed interconnect, or
an explicitly approved alternative quantization/model. Each changes execution
or quality trade-offs and must be measured for all 32 users; none is assumed to
pass. Even halving weight bytes does not by itself prove 30 token/s.

Sanitized diagnostic artifacts: `tmp/event-trial-20261022/decode-diagnosis.json`
and `decode-weight-metadata.json`. The first retains all ten completed requests,
server counters and before/during/after resource samples. Remote original:
`decode-diagnosis-1792652268463.json`. Scripts: `diagnose-decode.mbtx`,
`inspect-weight-metadata.mbtx`, and `summarize-decode.mbtx`. No model outputs,
user prompts, credentials or new participant permissions were saved in these
evidence files. No Nsight profiling, runtime restart or production code change
was performed in this diagnosis.

## 32-user acceptance result and readiness fix

Each account was created in the production identity provider, enrolled through
the operator's private invitation API, logged in through `/user/auth/password`,
and issued its own project/model-scoped API key through the normal user API.
No administrator credential was used as a model-consumer credential. No public
event registration was opened. Rehearsal ID: `acceptance-four-spark-20261022`.

Each measured round used 32 synchronized requests, 76 input tokens and 512
output tokens per request, with thinking disabled by the existing event runtime
adapter. Output counts come from terminal usage, not characters or SSE chunks.
Decode rate is `(completion_tokens - 1) / (last_text_time - first_text_time)`;
end-to-end aggregate includes first-token latency and completion/audit overhead.
The load generator ran on management: 8443 used the public hostname route; LAN
443 used explicit TLS SNI/address resolution to `192.168.2.175`. This is not a
geographically distributed Internet-client load test. Public
`106.39.18.146:443` NAT forwarding remains a separate unresolved deployment item;
the tested 443 result must not be presented as proof of that public mapping.

| Entry | Success | Per-user decode min / median / max | TTFT p95 | Aggregate end-to-end | Users meeting 30 token/s |
| --- | --- | --- | --- | --- | --- |
| External 8443 | 32/32 | 7.34 / 7.52 / 7.60 token/s | 1.355 s | 218.55 token/s | 0/32 |
| LAN 443 | 32/32 | 7.34 / 7.51 / 7.59 token/s | 1.351 s | 217.85 token/s | 0/32 |

All 32 streams overlapped for more than 66.5 seconds. Launch spread was 0–1 ms.
The aggregate decode-window rates were 232.47 and 232.03 token/s, respectively,
also below the required 960 token/s. A preceding four-user warmup also only
achieved 7.80–8.06 token/s per user. Short prompts are not a long-context or
production workload guarantee.

The 150-second GPU observation collected 283 samples: peak running 32, each
node eight, peak waiting zero. The observed full-concurrency sample had zero
preemptions and approximately 2.46% KV cache usage on each node. Model logs
reported roughly 60–61 generation tokens/s per node at eight running requests.
One live .176 sample showed GB10 GPU utilization 96%, SM clock 2535 MHz and
61°C. This localizes the throughput shortfall to model execution, not the
removed admission gates; it is not a complete kernel-level root-cause profile.
The runtime selected FP8 CUTLASS, CUDA graphs and FlashAttention. It explicitly
disabled DeepGemm because of an architecture accuracy warning; that safeguard
was not overridden. No model, precision, quality target or GPU limits were
silently changed to manufacture a pass.

The earlier 3/4 readiness fluctuation was reproduced in **7 of 90** observations:
.177's authenticated heartbeat was approximately 446–467 ms ahead of controller
time. Heartbeat intake already accepted this within its 60-second skew window,
but event readiness incorrectly rejected any future timestamp. Readiness now
uses the same accepted-skew boundary and samples time after asynchronous state
reads. Stale/excessive-skew heartbeats and wrong models still fail closed.
After deployment, **90/90 observations were 4/4**, including a sample with a
slightly future heartbeat. This is a bounded observation, not an indefinite
availability guarantee.

Live event policy has `per_node_concurrency: 0` (no extra event cap). The new
controller omits its execution semaphore when `runtime_concurrency` is zero or
is redundant with scheduler admission. Legacy node agents reject zero in their
shared settings schema, so immutable settings generation 6 encodes
`runtime_concurrency: 128 == admission_capacity: 128`; the new controller creates
**no separate execution semaphore**. This is not a replacement eight- or
32-request cap. All five processes consume the same settings generation.

Controller binary SHA-256:
`200796a6db5d29a4729e91cac78d09ce8edf2bb38ad701859cfa3b16524351be`.
The deployed console bundle matches SHA-256
`44faaf1ffe0696915357b1f892f7e1f5bf2b39eb15593ad73428e3b509c685ac`;
its event form labels zero as no additional event limit.

Native API tests: **210/210 passed**. Settings/event tests: 13/13; focused UI and
console event tests also passed. `moon info` and targeted formatting completed;
`git diff --check` passed. The repository-wide strict native runner was attempted
but failed during CLI fixture build on 45 existing deprecation warnings promoted
to errors in commercial/planning modules. It is not reported as a full-suite pass.

Sanitized local evidence is under `tmp/event-trial-20261022/`:
`acceptance-measured-8443.json`, `acceptance-measured-443.json`, and
`acceptance-metrics.json`. Remote originals retain timestamped names and all
per-request receipts. Credential files remain restricted on management and must
not be committed or published.

Cleanup completed through the normal operator APIs: all 32 LunaNexa test
accounts were revoked (which also revokes their scoped keys), their 32 workspace
access grants were revoked, and their 32 workspace leases were revoked through
the lease `:end` endpoint. Every old key was subsequently rejected with HTTP 401
on both 8443 and LAN 443: 64 negative authorization checks passed. Both event
policies remain closed. Historical identities, grants and audit evidence were
retained rather than deleted; registered-user counts are historical enrollment,
not proof that the revoked users retain access. Remote evidence:
`acceptance-cleanup.json` (restricted).

The public entry accepts `GET /models` and `POST /chat/completions`
relative to that base URL. The controller has no public Responses handler;
`POST /responses` is not exposed. Requests carry the caller's own
LunaNexa scoped API key. MoonGate retains no shared participant credential.
Existing user/operator routes, browser session authority, and the separate
general MoonGate process on management port 15721 are unchanged. SDK users must
explicitly choose the new event base URL; existing UI connection dialogs and
desktop handoff URLs still use the established model entry.

## Draft policy — operator review required before activation

- ID: `future-community-weekend-20261024`.
- Title: 未来社区 · 周末首场体验.
- Proposed window: October 24, 09:00 through October 25, 22:00, Beijing time.
- 30 participants; 200 requests per participant; no extra event per-replica
  execution cap. Existing personal trial lease authority remains separate.
- Approved alias: `qwen-qwen3.8-27b-fp8`; served model: `qwen3.8-27b`.
- `registration_open: false`; registered participants: zero.

These dates/caps are editable draft defaults, not a user-confirmed meeting
schedule or a measured throughput guarantee.

## Deployed topology

TLS edge → one `moongate-event` → LunaNexa controller event router → four
node-pinned services. Least-in-flight selection rotates equal-load ties;
health, user authority, expiry and quotas remain controller-owned.

| Spark | Node ID | Service | Controller loopback |
| --- | --- | --- | --- |
| .176 | `spark-25e2-3d35c8fd` | `event-qwen-176:8000` | `127.0.0.1:19176` |
| .177 | `spark-3782-feee26eb` | `qwen3-llm:8000` | `127.0.0.1:19092` |
| .178 | `spark-57f5-98a504ed` | `event-qwen-178:8000` | `127.0.0.1:19178` |
| .179 | `spark-368c-0f2ee8b2` | `event-qwen-179:8000` | `127.0.0.1:19179` |

Runtime image digest:
`sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c`.
Model manifest/artifact digest:
`sha256:dd1ee7f73c94e4e66122c56b1eddb9550c066c58939250b8a3bb5d941cacc0b2`.
All **82 manifest-listed model files passed SHA-256 verification on all four
nodes**. The three new deployments use the pinned runtime digest; the existing
.177 replica's observed running digest matches it.

## Evidence

- Native API suite: 207 tests passed, including fixture-backed event enrollment,
  bounded authority, balanced dispatch, cordon and external replica checks.
- MoonGate fixed-origin text gateway: two protocol tests passed.
- Direct live Chat Completions: eight successful requests, two per physical
  replica, with four nodes exercised concurrently. New replicas' first calls
  took about 16–18 seconds to warm; second short calls took about 0.4 seconds.
- Direct live Responses: four successful non-streaming calls and four completed
  SSE streams, one of each per replica. The synthetic prompt returned text and
  completion/usage evidence; these short calls took roughly 0.3–0.4 seconds.
- Deployed private MoonGate: healthy process; missing/invalid keys denied;
  provider-management route unavailable.
- Public trial entry: LAN port 443 (tested from management using TLS SNI and
  `--resolve suanli.kechuangfuwu.com:443:192.168.2.175`) and external port 8443
  (tested from the desktop via public DNS) both reach the same MoonGate.
  Invalid keys receive 401 for models/chat; Origin-bearing requests receive
  403. TLS validation stayed enabled. `/event/v1/models` now returns 404.
- LAN DNS remains a deployment prerequisite: management currently resolves
  this hostname to public `106.39.18.146`. The explicit LAN-address test proves
  the port/route/certificate, not that every LAN client's DNS is configured.
- Follow-up probing found that the controller does not expose `/v1/responses`.
  The earlier direct-backend Responses evidence remains valid, but is not
  public API acceptance. The public route/documentation were narrowed to the
  actually supported models and Chat Completions endpoints.

Those earlier direct backend calls were **not** participant acceptance. The
subsequent 32-user rounds above now verify the real identity → MoonGate → router
→ four-node path, but fail the requested throughput criterion. Full application
availability and hardware failover under active participant load remain unproven.

Rehearsal artifacts and rollback snapshots are on `lunanexa-management`:

`/home/HwHiAiUser/lunanexa-event-trial-20261022.9DbhEI/`

Relevant receipts: `model-verified-{176,177,178,179}.txt`,
`live-rehearsal.json`, `responses-rehearsal.json`, binary `SHA256SUMS`, and
saved before-deployment JSON files. Full deployment snapshots are restricted
files; do not publish them, because environment/configuration may be sensitive.
Local test scripts and downloaded model-call receipts are under
`tmp/event-trial-20261022/`; scripts pass real credentials in memory/stdin, not
command arguments or printed output.

## Resource changes and rollback

- The user explicitly released all four machines for this rehearsal.
- Idle reservation `reservation-vectie-annual-20260928` was drained via the
  operator API and reconciled to `Released`, generation 4. Its account,
  commercial grant, workspace lease and data were not revoked.
- .178/.179 node inventory usage pools are now `trial`. The stale idle .178
  lease-helper deployment is scaled to zero; prior settings are saved.
- **`minimaxh3-fl2va` on .176 is paused (zero replicas)** to free that GPU.
  Its deployment settings and data are preserved. H3/media availability is
  therefore not part of this event's accepted capability.
- Seven task-created inspection/staging pods were removed after verification.
  All model caches remain. Existing weights were not overwritten.

To retire the rehearsal, first close event registration and let admitted calls
finish. Remove the exact `lunanexa-event-model-entry` ingress route (and its
dedicated middleware/network policy when unused) to withdraw the event entry.
Scale the three `event-qwen-*` deployments to zero and wait for GPU release
before restoring H3 or dedicated reservations. Do not start competing GPU
workloads while these replicas remain allocated. Keep .177's original service
untouched. Restore node-pool and helper settings from the saved before-state as
appropriate for the next allocation.

A Released reservation cannot be reactivated by replaying its old idempotency
key. Re-reserve through the normal authorized API with a new reservation ID and
idempotency key, using the preserved original grant/lease and requested limits;
do not edit scheduler state directly. Controller/portal rollback must restore
the saved binary-volume/image settings, not merely change the controller image
(the native executable is mounted separately).

## Remaining acceptance

1. Authenticated `/mana/` inspection is now complete: the activity card displays
   0/30 participants, four of four ready, and registration closed/draft. The
   operator still needs to confirm the proposed schedule/caps before activation.
2. Resolve the measured capacity shortfall and repeat 32-user acceptance. Do not
   lower the 30 token/s criterion or substitute a different model/precision
   without an explicit decision. The real user-auth path and balanced four-node
   concurrent execution are verified; the capacity gate is **failed**.
3. Check each intended trial application separately. Do not advertise all
   platform applications as available from text-model readiness alone.
4. Only then open event registration and distribute `/user/?trial=event`.
