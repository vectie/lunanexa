# GLM LunaFlux route cutover

The existing company route `glm-5.3.flash` is being migrated from the stopped
EXL3/vLLM pair to the validated LunaFlux NVFP4 pair. This is an explicit
externally operated text binding, not a fabricated single-node managed
deployment. LunaNexa owns tenant admission, the public alias, metadata and
the lifecycle adapter; LunaFlux owns inference and the two-rank protocol.

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

## Public validation — 19 October 2026 (in progress)

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
