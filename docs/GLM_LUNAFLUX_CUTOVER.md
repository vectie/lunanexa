# GLM LunaFlux route cutover

The existing company route `glm-5.3.flash` passed authenticated public acceptance
on the LunaFlux NVFP4 pair on 19 October 2026. The old EXL3/vLLM
pair remains stopped. This is an explicit
externally operated text binding, not a fabricated single-node managed
deployment. LunaNexa owns tenant admission, the public alias, metadata and
the lifecycle adapter; LunaFlux owns inference and the two-rank protocol.

## Current capacity upgrade — 19 October 2026, in progress

The public endpoint is currently offline while the paired Sparks are reserved
for the 8K-context/concurrency upgrade and matched vLLM comparison. At the first
inspection the prior native peer had already exited with SIGABRT at 02:04 CST;
the manager stopped its coordinator. This is not an established OOM cause or
a demonstrated fix in the new capacity implementation.

The prepared LunaFlux 5f864415 candidate has 8,192 logical context tokens,
eight resident sequences, sixteen waiting slots, sixteen preparation lanes,
eighteen HTTP connection slots, and 513 shared 16-token history pages (one
reserved). Preparation lanes are not the total owned-request ceiling. Excess
HTTP clients can backpressure before admission. It does **not** promise eight
full 8K histories.
The installer now preserves the accepted opaque runtime's capacity fields
instead of reinstating the initial 2K/four-slot defaults. The candidate is not
installed or publicly qualified yet. Existing route allocation metadata must
change only after its physical campaign passes under 100 GiB/rank and 16 GiB host
reserve. Historical acceptance below does not establish current availability.

The native 47a1f351 context sweep completed 64 exact-label answers, including
7,973 actual input tokens and C16 queued bursts, within the resource limits.
Broader Chinese output exposed a separate token-budget UTF-8 finalization
failure. The 5f864415 build distinguishes a budget cutoff from complete-text
EOS, retaining the valid text prefix without weakening malformed-byte checks.
Its ARM build and 5,297 local native tests pass; real-service retesting and
public acceptance remain required. No GPU arithmetic or checkpoint changed.

## Deployment contract

- Preserve the public alias and company scope. Publish NVFP4 as a distinct
  checkpoint version, never relabel the old EXL3 artifact as NVFP4.
- Resolve the backend credential from deployment-owned secret configuration;
  pass it to readiness and inference, never to public responses.
- Select the text Chat Completions upstream protocol explicitly. The deployed
  LunaFlux Responses parser accepts string input, not structured conversations
  or metadata. Preserve roles and generation limits through its Chat endpoint;
  normalize JSON/SSE and usage in the platform adapter. Never flatten multi-turn
  messages or silently discard tools to make the request succeed.
- Use persistent paired native units with coordinator-first graceful stop,
  `KillMode=mixed`, bounded termination and no acceptance-run time limit.
- Start the peer before the coordinator, only with both GPUs idle and at least
  16 GiB host memory available. Keep each rank at 100 GiB, no unit swap.
- Observe both units and memory while running. A peer exit or resource-limit
  violation stops the owned pair, not unrelated workloads. Do not independently
  restart one TP rank into a surviving peer.
- The tested initial allocation is four resident sequences, 64 prefill rows
  and 2048 context tokens per sequence. This is an allocation, not the model's
  architectural context limit or a claim of all vLLM features.
- Reuse the source-pinned executable and AOT files validated on both Sparks;
  do not compute payload hashes or scan checkpoint integrity during cutover.
  Existing declared artifact identifiers remain metadata, not new verification.

## Rollout and acceptance

Keep the public route unavailable until private loading, real gateway JSON/SSE
generation, model identity, concurrency, cancellation/reuse and memory checks
pass. Preserve the previous route configuration and stopped containers for
rollback; rollback must not silently restore the old engine without operator
intent. Test lifecycle stop/start through LunaNexa before enabling public
traffic. Record actual results here; the plan itself is not evidence of an
online service.

## Observed acceptance — 18 October 2026

This section preserves the pre-cutover observations and blockers. The completed
public cutover is recorded below; its former pending states are not current.

The native pair is installed at persistent user-owned paths on both Sparks,
using the previously validated LunaFlux revision
`7106127262375b5dab6b98a23c2d1d07412ce45e`. Model files are hard-linked from
the existing NVFP4 checkpoint; no payload copies or digest scans were needed.
The existing approved NVFP4 registry record remains a distinct model version.

The manager lifecycle adapter was installed from LunaNexa `cef2eb7`. Its paired
start, coordinator-first stop, GPU release and restart passed. The loaded pair
uses about 95.4 GiB GPU memory per Spark, with measured host availability above
16 GiB and zero unit swap. Private JSON generation correctly answered 17 × 19;
a Chinese streaming response completed with token usage and request retirement,
with no worker failures. These are private checks, not public-route acceptance.

The Responses wire mismatch was reproduced against the real backend. The text
Chat adapter regression suite now passes 50 runtime tests, two lifecycle tests
and five external-route tests, including structured messages and output budget
through the API service. The broader local warning-denied phase gate remains
blocked by existing deprecated-method warnings; no warning suppression or
unrelated migration is part of this change.

Public acceptance is pending a usable existing company GLM API key or signed-in
portal session. The operator's attempt to issue a temporary test key returned
`409 EffectiveMasterLeaseRequired`; it created no credential. No lease policy,
customer identity, or existing key was changed. Until public validation passes,
the public alias must not be advertised as online or as an NVFP4 cutover success.

The opt-in live adapter gate then caught a second wire incompatibility: the
MoonBit HTTP client defaults to chunked request bodies, which this LunaFlux
HTTP parser rejects. The Chat adapter now serializes the request once and uses
its exact UTF-8 byte length for both JSON and SSE response modes. A regression
includes non-ASCII text and asserts no request transfer encoding. Error and
cancellation cleanup close the owned upstream client deterministically.

The real two-GPU adapter gate passed JSON, SSE, disconnect and request reuse:
four admissions, three completions, one cancellation, zero worker failures,
zero active requests and all 512 KV pages free afterward. All 51 runtime tests
passed with this live gate enabled. The two observed rejected chunked requests
are retained in the negative evidence; they were not model execution failures.
The superseded v3 controller build was stopped before deployment after this
finding. Its unit/route tests passed, but its executable is not a release candidate.

Revision `626bd29` repeats the live adapter gate successfully after deterministic
error cleanup was finalized. A separate probe inside the existing controller
pod's network namespace also reached the new `glm53-lunaflux` Kubernetes Service
and obtained the correct answer and usage from TP2. This verifies the actual
cluster network policy and Service path, but not customer authorization.

The staged `lunanexa-glm-native-route` ConfigMap names the existing approved
`libertaidai-glm-5.3-flash-nvfp4@modelscope-master` record and the native source
revision, with honest TP2/100 GiB/16 GiB/2048-token allocation metadata. It is
not yet selected by the production controller. The existing public alias still
targets the old EXL3 record and remains offline. The pending controller patch
and alias promotion are saved separately; neither has been applied.

Additional gates: the contract fixture test passes. The repository isolation
heuristic reports the pre-existing `example.test/moondesk/connect` URI in
`api/shared_trial_offerings_wbtest.mbt`; that unchanged test is not an import.
No exclusions or warning waivers were added. The corrected Linux controller
build is owned by `lunanexa-glm-cutover-build-20261018-v4.service`; until its
completion marker and authenticated public tests are observed, do not mark
this cutover complete.

## Public validation — 19 October 2026

The corrected controller and NVFP4 alias generation 3 are now selected. An
existing signed-in company credential passed public HTTPS JSON, multi-turn,
Chinese SSE completion and two concurrent answers. No key or lease was created.
The controller's initial non-root launch failed because its new release
directory was mode 0750; setting that executable directory to 0755 restored
the controller without restarting either GPU rank.

Public disconnect validation found a separate gateway defect: `proxy_request`
reads the complete upstream body before forwarding it, including SSE. The
client receives valid event syntax, but only after generation finishes; the
native cancellation counter therefore does not increase. Do not count this
as live-stream/cancellation acceptance. Fix SSE forwarding at the HTTP boundary,
preserving ordinary response behavior, credentials and deterministic upstream
close. Prove early delivery while the upstream is still blocked, then retest
the real public path and native cancellation/retirement counters.

The incremental-forwarding candidate delivered a public first content token in
1608 ms and propagated cancellation to the native worker. Its public disconnect
test also exposed a process-level error path: the outer gateway handler tried
to send a fresh 503 after streaming headers had already been sent. One gateway
replica exited; the GPU pair stayed healthy. Reproducing the actual wrapper in
the regression test triggered a panic in `Sender::send_response`. Interrupted
stream handling must close the downstream and its owned upstream without
attempting a second response; acceptance requires repeating disconnect/reuse
with unchanged gateway restart counts. The first candidate is not final proof.

### Completed cutover

Gateway revision `476c2dae384b3707350d879c647436a825a9a2d4` handles an
interrupted SSE response by closing the connection, without re-entering the
generic fresh-response error handler. It was built and deployed to both public
gateway replicas. All 38 affected gateway tests and the warning-denied native
check pass locally and on the manager. The Linux release build passed. The
tests exercise the real outer error handler as well as early delivery,
downstream disconnect, upstream close and unchanged ordinary JSON framing.
Neither final gateway replica restarted during public acceptance.

The existing signed-in company key authorized the actual public path:

- `GET /user/v1/models` lists `glm-5.3.flash`.
- JSON arithmetic returned `323`; multi-turn conversation returned `42`.
- Chinese SSE returned a complete coherent moon-visibility explanation, a
  `stop` finish, final token usage and `[DONE]` within its requested budget.
- Three lifecycle rounds each completed two concurrent answers (`144`, `81`),
  disconnected after a real streaming token, and completed a subsequent answer
  (`323`). First content arrived in 1425, 1421 and 1387 ms respectively. These
  are smoke-test observations, not a comparative throughput benchmark.
- Across this final gateway campaign, native counters changed from
  23 admissions / 20 completions / 3 cancellations to 38 / 32 / 6: twelve
  completed requests and three actual native cancellations. Afterward there
  were zero active/queued requests, all 512 KV pages free, and zero worker
  failures, restarts or deadlines. The two historical chunked-request
  rejections remained unchanged. Both public gateway replicas stayed Ready
  with restart count zero, including after all three disconnects.

The final resource snapshot is below. GPU process memory is reported by
`nvidia-smi --query-compute-apps`; generic GPU-total queries on this unified
memory hardware return `N/A` and are not used as evidence. Host `MemAvailable`
is measured separately. Both owned units retain `MemoryMax=100 GiB`, zero unit
swap and zero restarts; pre-existing host swap is not claimed to be zero.

| Spark | GPU process memory | Host available |
| --- | ---: | ---: |
| `.178` | 97,654 MiB (95.37 GiB) | 18,242,876 KiB (17.40 GiB) |
| `.179` | 97,669 MiB (95.38 GiB) | 19,573,920 KiB (18.67 GiB) |

Selected deployment components:

- LunaFlux native/AOT source: `7106127262375b5dab6b98a23c2d1d07412ce45e`.
- Controller: `626bd29dff082b223fd655cef37bf263aa450ad0`.
- Public gateway: `476c2dae384b3707350d879c647436a825a9a2d4`.
- Alias generation 3: approved
  `libertaidai-glm-5.3-flash-nvfp4@modelscope-master`; the old EXL3 model was
  not renamed or modified.
- Public base: `https://suanli.kechuangfuwu.com:8443/user/v1`.
- Public model: `glm-5.3.flash`. Portal refresh shows running on two Sparks
  with the actual 2K context allocation. Four resident sequences and 64 prefill
  rows remain selected. This is not a claim of unrestricted context or full
  vLLM feature parity; unsupported tool calls are explicitly rejected.

Deployment and route ConfigMap annotations now say `validated-online`. No
customer key, lease policy or GPU executable changed during these gateway
fixes. No payload hashes or checkpoint-integrity scans were computed. The
temporary local copy of the existing customer key is removed after validation;
the original key remains active and unchanged.

Evidence is preserved without overwrite:

- Desktop `/tmp/lunanexa-glm-public-stream-v6-20261019/`: public response
  bodies, acceptance markers and `FINAL_PUBLIC_ACCEPTANCE.json` with selected
  alias/model metadata, counters, per-replica status and memory snapshots.
- Desktop `/tmp/lunanexa-glm-public-stream-v6-repeat1-20261019/` and
  `...-repeat2-20261019/`: the two additional disconnect/reuse rounds.
- Desktop `/tmp/lunanexa-glm-public-stream-v5-20261019/`: the superseded
  candidate's results; its gateway failure is not discarded or called a pass.
- Manager `/home/HwHiAiUser/lunaflux-glm-cutover-20261018-v1/`: build logs,
  `GATEWAY_V6_COMPLETE`, prior deployment snapshots and scoped rollout patches.

The earlier full-repository warning/isolation blockers remain recorded above;
this acceptance does not claim a clean aggregate LunaNexa release campaign.
