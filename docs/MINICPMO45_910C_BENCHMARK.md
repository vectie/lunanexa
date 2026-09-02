# MiniCPM-o 4.5 on Ascend 910C benchmark report

Benchmark ID: `minicpmo45-seedtts-910c-c1-timestep-cache-20260810`

Date: 2026-08-09; optimization update: 2026-08-10

Status: performance measurement complete; competition acceptance incomplete

## Executive result

The optimized LunaNexa vLLM-Omni candidate now beats the competition's
published text time to first token (TTFT) and audio time to first packet
(TTFP). Whole-audio real-time factor (RTF) is 1.51% above the published value,
down from a 17.14% gap before optimization.

| Metric | Published baseline | Optimized, 3-run mean | Sample SD | Change | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| TTFT | 333.27 ms | 315.59 ms | 1.86 ms | -5.31% | faster |
| Audio TTFP | 986.47 ms | 972.93 ms | 8.84 ms | -1.37% | faster |
| Whole-audio RTF | 0.4423 | 0.4490 | 0.0080 | +1.51% | slower |
| Per-chunk audio RTF | not published | 0.4821 | 0.0096 | n/a | measured |
| End-to-end latency | not published | 1,884.27 ms | 31.85 ms | n/a | measured |

Lower is better for every latency and RTF metric. Across three repetitions,
all 96 measured requests succeeded, no request reported a non-empty error, and
streaming continuity was 100%.

Against the prior LunaNexa candidate on the same host and protocol, the
optimized runtime improves audio TTFP by 5.98%, whole-audio RTF by 13.35%,
per-chunk RTF by 13.23%, end-to-end latency by 13.81%, and request throughput
by 15.96%. TTFT changes by only 0.33%.

This is not a competition pass. Seed-TTS quality and the full Daily-Omni and
Video-MME accuracy suites have not passed their required gates.

## Scope

This report covers the official Seed-TTS performance protocol for MiniCPM-o
4.5 on a real Ascend 910C machine. It records:

- three warm-cache repetitions before and after the optimization;
- the competition's published framework numbers as the reference baseline;
- the attempted organizer-branch deployment and why it was excluded;
- hardware topology, runtime settings, reproducibility hashes and limitations;
- the remaining work required before LunaNexa can register this runtime as an
  approved benchmark profile.

The measurement does not cover saturation throughput, multi-tenant load,
failure recovery, cold-start service objectives or the full accuracy suites.

## Hardware and runtime

`npu-smi` exposed one physical Ascend 910 card entry with two logical 64 GiB
chips. The candidate deployment placed:

- stage 0, the fused autoregressive and talker stage, on logical chip 0;
- stage 1 and stage 2, including Code2Wav, on logical chip 1.

Post-benchmark HBM usage was approximately 51.6 GiB on logical chip 0 and 45.4
GiB on logical chip 1. The service remained healthy after all three runs.

This is a one-physical-card result, but not a one-logical-chip result. It must
not be represented as the minimum one-NPU footprint result.

Runtime inputs:

| Component | Revision or artifact |
| --- | --- |
| Model | `OpenBMB/MiniCPM-o-4_5` local checkpoint |
| Candidate vLLM-Omni base | `eae333b46073d250f4ddb8c6bc3a04637e6a2e5e` |
| Optimized change | cached immutable CFM timestep embeddings in `BatchedToken2Wav` |
| Organizer branch reference | `009b80d686febcf683fdbc2bcdf3ad752884641e` |
| API | OpenAI-compatible `/v1/chat/completions` |
| Deploy config | `minicpmo_4_5_2npu_910c.yaml` |

The installed vLLM, vLLM-Omni and vLLM-Ascend revisions report a version
alignment warning. The final competition image must pin a validated compatible
set rather than relying on source overlays.

## Benchmark protocol

The candidate was measured with the competition Seed-TTS performance shape:

| Setting | Value |
| --- | --- |
| Dataset | Seed-TTS English split |
| Available local rows | 1,088 |
| Measured prompts | 32 |
| Warmups before each run | 3 |
| Concurrency | 1 |
| Request rate | unlimited |
| Oversampling | disabled |
| Output modalities | text and audio |
| Thinking | disabled |
| TTS chat template | enabled |
| Benchmark seed | 0 |

The client loaded the tokenizer from the pinned local checkpoint because the
machine could not reach Hugging Face. It retained the served model name
`openbmb/MiniCPM-o-4_5`; the local path changes neither the request payload nor
server execution.

The server used these MiniCPM-o tuning inputs:

```text
VLLM_ASCEND_ENABLE_CUSTOM_OPS=0
VLLM_OMNI_MINICPMO45_NPU_SDPA_BACKEND=auto
VLLM_OMNI_MINICPMO45_INITIAL_CODEC_CHUNK_FRAMES=25
VLLM_OMNI_MINICPMO45_CODEC_CHUNK_FRAMES=25
VLLM_OMNI_MINICPMO45_CODEC_LEFT_CONTEXT_FRAMES=3
VLLM_OMNI_MINICPMO45_TOKEN2WAV_N_TIMESTEPS=10
VLLM_OMNI_MINICPMO45_NPU_CFM_GRAPH=0
VLLM_OMNI_NPU_SYNC_BEFORE_DEVICE_EVENT=0
```

The launch profile requested `VLLM_ASCEND_ENABLE_CUSTOM_OPS=0` and
`fuse_norm_quant=false`, but the installed development vLLM-Ascend build did
not honor those legacy controls. Its engine log reports enabled `norm_quant`
and `act_quant` fusions and `pass_config.fuse_norm_quant=true`. Valid A/B runs
held that observed backend state fixed; results from another build or pass
configuration require a different profile ID.

## Repeated results

| Run | Requests | TTFT | Audio TTFP | Whole-audio RTF | Per-chunk RTF | E2E |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 32/32 | 317.73 ms | 983.06 ms | 0.4581 | 0.4932 | 1,920.95 ms |
| 2 | 32/32 | 314.39 ms | 968.94 ms | 0.4449 | 0.4771 | 1,868.23 ms |
| 3 | 32/32 | 314.65 ms | 966.78 ms | 0.4439 | 0.4761 | 1,863.62 ms |

Each run generated 136.96 seconds of audio. The combined generated-text,
output-length, audio-frame and audio-duration signature is identical across
all three prior and all three optimized repetitions:

```text
806793917d2bf1907f3523d6f3e16b50f527c88a146f746f059f95eb2913b2b3
```

Raw result checksums:

```text
352d6c0f44142bba80d4fca06948ddf6e4c8127a6043c88ef851a5f12f055877  optimized-run1.json
c54af74c5695dcba93fd010b8425db8271ddea8f939db8056c3d315268511988  optimized-run2.json
ffbda40990f738ce7d41f3e1db9e92a6dc1a1cf540162d112c5aee913f065ef2  optimized-run3.json
```

The raw results and server logs remain on the benchmark host at:

```text
/workspace/user_data/lunanexa-stack/experiments/minicpmo45-audio-opt-20260810
```

That host path is evidence storage, not a durable LunaNexa artifact reference.
Before release acceptance, copy the bundle to digest-addressed artifact storage
and register it through LunaNexa's benchmark and evidence contracts.

## Baseline comparability

The organizer branch was preserved as an immutable source snapshot and started
on the same host. It reached a healthy API after small startup shims, but its
first real request encountered successive API removals in the newer installed
vLLM-Ascend stack:

- `AscendConfig.profiling_chunk_config`;
- `NPUGenerationModelRunner.pcp_size` and the old PCP manager API;
- `AscendConfig.enable_async_exponential`;
- older `use_cp` behavior replaced by the current DCP API.

Eager connector imports also caused Code2Wav inspection failures before lazy
imports were applied. Continuing the port would replace substantial NPU runner
behavior with candidate-era code and would no longer constitute an unmodified
framework baseline.

For that reason, this report compares the candidate with the organizer's
published values. It does not claim a controlled same-host speedup over a
runnable organizer binary. Failed and zero-output attempts were quarantined
outside the valid result directory.

## Same-backend allocation-reuse experiment

A later installed vLLM-Ascend development tree required additional compatibility
work before a current same-host A/B could run. The retained fixes cover the
legacy/current context-parallel manager APIs, optional profiling-config
locations, the full-graph update hook's added `positions` argument, and the
scheduler `_free_request` transition from a two-value tuple to a KV-transfer
dict or `None`. The retained remote Code2Wav, NPU, and scheduler tests pass
48/48 after removing the rejected candidate-only test.

The tested speed candidate preallocated all ten CFM step-output buffers as
stacks, removed final `torch.stack` copies, and elided single-request flow/HIFT
cache clones. Its same-backend control kept every compatibility file identical
and restored only `batched_token2wav.py` to commit `b1192725`.

All six 32-request runs completed without failure or continuity loss. Every
run produced the same 4,801 input tokens, 480 output tokens, 3,321,600 audio
frames, and 138.40 seconds of audio.

| Variant | TTFT | Audio TTFP | Whole-audio RTF | Per-chunk RTF | E2E |
| --- | ---: | ---: | ---: | ---: | ---: |
| Same-backend control | 330.97 ± 11.15 ms | 987.16 ± 8.87 ms | 0.4485 ± 0.0020 | 0.4792 ± 0.0021 | 1,890.08 ± 8.59 ms |
| Allocation-reuse candidate | 328.31 ± 3.37 ms | 1,015.15 ± 1.22 ms | 0.4900 ± 0.0011 | 0.5307 ± 0.0025 | 2,062.55 ± 5.72 ms |

The fail-closed median gate rejected the candidate: RTF regressed 9.49%, TTFP
3.06%, and E2E 9.25%; TTFT improved only 0.39%. The allocation/copy patch was
reverted, while the independently required compatibility fixes were retained.
Raw results and `allocation-reuse-performance-gate.json` remain under the
host's `allocation-v2` experiment directory.

## Single-chip Atlas A2 fixed-shape CFM graph experiment

On 2026-08-25, a separate one-chip A2 host was used to validate the replacement
for the previously rejected growing-shape CFM graph. The visible device was one
Ascend 910B4 with 32 GiB HBM. This is a hardware-specific continuation, not a
replacement for the two-chip 910C evidence above.

The accepted candidate changes the execution architecture that caused the old
capture churn:

- prompt and tail shapes remain eager;
- only the repetitive width-50, cache-402 CFM6 path is captured;
- attention state uses fixed 6-step x 16-block BSH K/V slabs;
- two graph-output slots are allocated once, so replay returns pooled outputs
  rather than cloning every graph result;
- explicit graph-visible attention is startup-gated against the fused BSH
  reference. The observed cache-402 drift was 3.05175781e-05 maximum and
  6.89178705e-08 mean.

The benchmark used the same ten Seed-TTS English rows, seed 0, unlimited request
rate, concurrency 1, temperature 0, and text-plus-audio request body for every
comparison. Each measured run followed a separate ten-request warm-up. The
approximately 60-second first-capture cost is therefore excluded from the
steady serving measurements.

| Variant | Runs | Whole-audio RTF | TTFT | Audio TTFP | Steady chunk RTF | E2E |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A2 canonical control | 1 | 0.35642 | 81.84 ms | 752.01 ms | 0.19897 | 1,538.99 ms |
| BSH without full CFM graph | 1 | 0.36783 | 77.60 ms | 762.09 ms | 0.20687 | 1,588.53 ms |
| Fixed-slab CFM graph | 2 | 0.34482 mean | 79.43 ms mean | 766.57 ms mean | 0.17299 mean | 1,489.10 ms mean |

The two fixed-slab CFM graph runs produced RTF 0.34612 and 0.34352. Relative to
the A2 canonical control, their mean improves whole-audio RTF by 3.26%, steady
chunk RTF by 13.06%, all-chunk mean RTF by 2.56%, and E2E latency by 3.24%.
TTFT improves 2.95%, while audio TTFP regresses 1.94%. All measured runs
completed 10/10 requests with 100% streaming continuity and generated the same
43.20 seconds of audio.

An additional direct-slab graph-I/O candidate removed the replay-time K/V input
copy by binding graph execution to a reusable request-slab pool. After fixing a
short-request two-slot state-machine boundary, it completed two 10/10 runs at
RTF 0.34790 and 0.34447. Its mean RTF was 0.40% slower, and its steady chunk RTF
1.38% slower, than the graph-private-buffer version. The likely explanation is
that task-queue scheduling hid the copy while external buffer binding reduced
GE memory-planning freedom. The candidate was removed from both code and the
best profile.

The retained A2 profile is
`vllm_omni/deploy/minicpmo_4_5_1npu_a2_cfm6_bf16_bsh_cfm_graph_experimental.yaml`.
Raw results remain on the host under `/tmp/a2-bench-v12`,
`/tmp/a2-bench-bsh-cfm-measured*`, and
`/tmp/a2-bench-bsh-cfm-direct-v2-measured*`. These temporary paths are not
durable evidence storage.

Decision: retain the fixed-slab steady CFM graph as the best measured A2 speed
candidate. Do not promote it to the competition submission until the official
Seed-TTS WER and speaker-similarity gates pass on this exact profile.

### A2 Stage-2 trace and BF16 graph-attention screen

A fresh Stage-2-only torch/NPU profile was captured after the fixed-slab graph
had warmed. The profiled request generated 3.88 seconds of audio. Its kernels
accounted for 323.553 ms of device compute; the largest operator families were
Transpose (36.350 ms, 11.24%), TransData (31.477 ms, 9.73%), LayerNormV3
(29.808 ms, 9.21%), MatMulV2 (29.574 ms, 9.14%), Mul (24.981 ms, 7.72%), Add
(21.750 ms, 6.72%), Slice (16.064 ms, 4.97%), and FlashAttentionScore
(13.195 ms, 4.08%). Transpose plus TransData therefore consumed 20.96% of
device compute, while attention arithmetic alone was not the dominant family.

Shape attribution corrected an initially misleading DiT hypothesis. The 405
`[512,512,1,3]` NCHW-to-FRACTAL_Z conversions belong to the FP32 HiFT F0
predictor's five fixed Conv1d layers, not the BF16 DiT causal convolutions.
They consumed 10.639 ms in this A2 trace. The accepted A2 profile deliberately
keeps that path eager because the already-tested F0-only and F0-plus-residual
graphs regressed end-to-end performance by 2.2% and 1.7%, respectively. The
steady DiT path did use `MinicpmoCausalConvPack` and preflattened Linear
weights as intended.

The remaining graph-only attention used explicit FP32 BMM/softmax because the
competition CANN 9.0 image cannot capture fused attention's auxiliary stream.
An opt-in candidate retained Q/K/V and score accumulation in BF16, removing
the explicit BF16-to-FP32-to-BF16 round trips. Its loaded-checkpoint startup
gate passed with maximum/mean drift 0.00048828125/0.0000114208 against fused
BSH attention, far inside the existing 0.03125/0.003 bounds. Three focused
CPU tests also passed.

The real A2 speed gate rejected the candidate. Both measurements followed ten
warm requests and completed 10/10 with 100% streaming continuity. The first
run had one extra output chunk and measured RTF 0.37857. The structurally
matched repeat restored the accepted 1,036,800-frame signature but measured
RTF 0.34939 and steady-chunk RTF 0.17784. Relative to the accepted fixed-slab
means of 0.34482 and 0.17299, those are 1.33% and 2.80% regressions. The BF16
BMM/softmax path evidently loses a more favorable A2 operator/format choice
than its removed casts cost. Its code, tests, and deploy overlay were removed,
and the FP32 graph-attention profile was restored.

The next screen targeted host-side stage orchestration. The existing loop
awaits Stage 0, 1, and 2 output queues sequentially with a 1 ms timeout per
queue, then sleeps another 1 ms when idle. A candidate replaced those repeated
timeouts with one persistent queue waiter per LLM stage and woke the loop when
any waiter completed. Its three-waiter lifecycle and cancellation smoke test
passed in the competition environment, but the serving gate rejected it. The
first run produced the non-comparable 48-chunk signature and measured RTF
0.37856; the matched 47-chunk repeat measured RTF 0.34913, TTFP 0.76618 s, and
steady-chunk RTF 0.17764. Against the accepted 0.34482/0.17299 RTF values, the
matched repeat regressed overall and steady performance by 1.25% and 2.69%.
Persistent asyncio task scheduling cost more than the removed polling delay on
this single-request A2 lane, so the implementation and its test were removed.
Raw result JSON remains temporarily under
`/tmp/a2-bench-event-orchestrator-measured{1,2}` on the benchmark host.

Huawei documents `TASK_QUEUE_ENABLE=2` as the higher-throughput binary-mode
queue path for Host-bound A2 workloads, so it was screened next without any
model change. The installed torch-npu/CANN stack rejected it during Stage 0
ACLGraph capture with `ERR00007`: Level 2 is unsupported while capturing an
NPU graph and the runtime requires Level 1 or 0. This was a startup failure,
not an OOM or a measured performance result. The accepted service remains on
Level 1; disabling its valuable Stage 0/1 graphs merely to enable Level 2 is
not a credible trade.

Global static-kernel compilation was then isolated to the batch-one Stage 1
Talker decode graph. The compiler did build and install a real static-kernel
package, and all ten measured requests completed, but the candidate changed
the generated codec sequence materially: 58 chunks and 54.0 seconds of audio
versus the accepted 47 chunks and 43.2 seconds. Serving duration also rose to
17.666 seconds. Its apparent whole-audio RTF of 0.32714 is therefore a larger
denominator artifact, not an accepted speedup; steady-chunk RTF regressed to
0.18471 and TTFP to 0.77045 seconds. Because static compilation changed the
Talker output distribution before any formal quality gate, the candidate was
rejected after one run, its deploy overlay was removed, and the installed
static-kernel package was cleaned up. The raw result remains temporarily at
`/tmp/a2-bench-talker-static-kernel-measured1`.

The next retained candidate enables A2's HF32 Cube execution for FP32 MatMul in
Stage 2 only. It does not change tensor storage, graph-attention softmax,
LayerNorm, Euler integration, or HiFT convolution precision. The switch is
strictly opt-in through `VLLM_OMNI_MINICPMO45_NPU_MATMUL_HF32=1`, is applied
before CFM graph warm-up, and fails at startup when the installed torch-npu
does not expose `torch.npu.matmul.allow_hf32`. The activation message was
observed in the real Stage-2 worker log.

Three structurally matched 10-request runs all completed 10/10, produced the
accepted 47-chunk/1,036,800-frame/43.2-second signature, and maintained 100%
streaming continuity. Their means were:

| A2 single-chip metric | Fixed-slab accepted | HF32 MatMul, 3-run mean | Change |
| --- | ---: | ---: | ---: |
| Whole-audio RTF (lower is better) | 0.34482 | 0.34117 | 1.06% faster |
| Audio TTFP (lower is better) | 0.76657 s | 0.75777 s | 1.15% faster |
| Text TTFT (lower is better) | 79.43 ms | 78.82 ms | 0.77% faster |
| Steady-chunk RTF (lower is better) | 0.17299 | 0.17285 | 0.08% faster |

An earlier HF32 run produced 48 chunks and was excluded from this comparison.
The matched raw results remain temporarily under
`/tmp/a2-bench-hf32-matmul-measured{2,3}` and
`/tmp/a2-hf32-quality10-offline-v2`. The retained experimental overlay is
`vllm_omni/deploy/minicpmo_4_5_1npu_a2_cfm6_bf16_bsh_cfm_graph_hf32_matmul_experimental.yaml`.

The official-export path also exposed a benchmark-infrastructure defect: using
`--seed-tts-official-export-dir` implicitly enabled WER and tried to download
Whisper after serving had finished. Export-only mode now captures PCM and
writes official `{utterance_id}.wav` files without initializing ASR; WER and
SIM still require their explicit flags. The repaired A2 run exported all ten
WAVs with zero failures. Eleven focused export and precision-policy tests
passed. Actual Seed-TTS WER and speaker similarity remain unmeasured because
the required pinned evaluator checkpoints are unavailable on this offline
host. HF32 therefore passes the speed and structural gates but remains an
experimental best candidate, not a competition-ready submission.

A clean post-HF32 Stage-2 trace used explicit idle windows before and after
the captured request. Its 576 `MinicpmoCausalConvPack` calls exactly matched
the pre-HF32 trace; an earlier 768-call capture was discarded as asynchronous
spillover from its warm-up request. On the clean trace, total device kernel
time changed from 323.553 ms to 323.194 ms (-0.11%) and MatMulV2 from
29.574 ms to 29.170 ms (-1.37%). The remaining largest families were
Transpose 37.722 ms (11.67%), TransData 30.843 ms (9.54%), LayerNormV3
30.441 ms (9.42%), MatMulV2 29.170 ms (9.03%), and Mul 25.319 ms (7.83%).
This confirms that future large gains require eliminating layout and
normalization boundaries across their producer-consumer chain; HF32 alone is
a small retained hardware-policy improvement.

The trace also confirmed that A2 BF16 startup had always rejected the
configured final-AdaLN Addcmul lowering at `0.0078125` maximum drift. A
guarded candidate tested a grouping-preserving form,
`addcmul(shift, norm, 1 + scale)`, which reduced synthetic mean drift from
0.001175 to 0.000889 while keeping the maximum to one BF16 quantization step.
It was nevertheless rejected by the real serving gate. Its two structurally
matched runs averaged whole-audio RTF 0.34243, 0.37% slower than the retained
HF32 mean, despite a 0.45% better steady-chunk RTF. Ten exported waveforms had
the same filenames and lengths as the HF32 control but only 0.264 mean direct
sample correlation, demonstrating strong diffusion sensitivity to the
rounding change. Direct waveform correlation is not an official quality
metric, but the candidate had neither an end-to-end speed win nor sufficient
evidence to justify that risk. The tolerance, formula change, tests, and
overlay were removed; the strict `1e-6` fail-closed behavior remains.

The next A2 trace-driven fix removed a layout discontinuity inside the
fixed-shape CFM executable itself. Although the accepted fixed slabs already
stored CNN history as cache-major `[batch, 2, 1024]`, flat NPUGraph capture
hard-coded the older channel-major Conv/MLP partition. The clean graph model
therefore spent 5.784 ms per replay on 384 avoidable cache transposes
(`192 x [2,512,2] -> [2,2,512]` and the reverse), accounting for 8.84% of
that 65.476 ms executable. Flat capture now selects the same cache-major
partition as the separately compiled steady-width path; the post-attention
variant follows the same layout rule.

One 48-chunk run was excluded using the same structural rule as earlier A2
experiments. Three matched 10-request runs completed 10/10 with zero failures,
100% streaming continuity, and the accepted 47-chunk / 1,036,800-frame /
43.2-second signature:

| A2 single-chip metric | HF32 control | Cache-major CFM graph, 3-run mean | Change |
| --- | ---: | ---: | ---: |
| Whole-audio RTF (lower is better) | 0.34117 | 0.33852 | 0.78% faster |
| Audio TTFP (lower is better) | 0.75777 s | 0.75645 s | 0.18% faster |
| Text TTFT (lower is better) | 78.82 ms | 77.70 ms | 1.43% faster |
| Steady-chunk RTF (lower is better) | 0.17285 | 0.16915 | 2.18% faster |

Two ten-file official-format exports produced identical filenames and sample
lengths. Direct PCM correlation is not a usable accuracy proxy here: two
repeated candidate exports correlated only 0.213 on average, comparable to
the 0.167 control-to-candidate value. The real Seed-TTS WER/SIM gate remains
blocked on the offline host's missing pinned evaluator checkpoints, so this
is retained as the new speed candidate but is not yet competition-ready.
Raw speed results remain temporarily under
`/tmp/a2-bench-hf32-cache-major-cfm-measured{2,3,4}` and exports under
`/tmp/a2-hf32-cache-major-cfm-quality10*`.

A follow-up attempted to remove the remaining BHSD attention layout traffic
inside that same fixed CFM executable. It combined the installed
`npu_minicpmo_qkv_pack` operator, planar K/V slabs, and graph-capturable
explicit FP32 attention, rather than benchmarking the QKV pack as an isolated
eager operator. The loaded-checkpoint startup gate passed: native QKV compiled
at width 50, and explicit attention at cache width 402 differed from fused
SDPA by at most 0.000244140625 with 0.000003592 mean absolute drift. Two CFM
output slots captured successfully and replayed without request failures.

The serving gate nevertheless rejected the candidate. One 48-chunk run was
excluded by the established structural rule. Three matched 10-request runs
all completed 10/10 with zero failures, 100% continuity, and the accepted
47-chunk / 1,036,800-frame / 43.2-second signature:

| A2 single-chip metric | Retained cache-major CFM | Full-graph QKV/layout candidate | Change |
| --- | ---: | ---: | ---: |
| Whole-audio RTF (lower is better) | 0.33852 | 0.34531 | 2.01% slower |
| Audio TTFP (lower is better) | 0.75645 s | 0.77998 s | 3.11% slower |
| Text TTFT (lower is better) | 77.70 ms | 79.01 ms | 1.68% slower |
| Mean E2E latency (lower is better) | 1.46186 s | 1.49123 s | 2.01% slower |
| Steady-chunk RTF (lower is better) | 0.16915 | 0.16930 | 0.09% slower |

This confirms that the existing ACLNN custom-op boundary remains too opaque
even when captured by the outer NPUGraph: eliminating visible transpose nodes
does not guarantee a better producer-consumer schedule on A2. The candidate
code and deploy overlay were removed, and the retained cache-major BSH + HF32
profile was restored. Any future QKV/layout fusion must therefore be exposed
to GE as a graph-visible decomposition/converter or fused across the consuming
attention and output projection, not reintroduced as the same standalone
layout boundary. Raw rejected results remain under
`/tmp/a2-bench-hf32-qkv-full-cfm-measured{1,2,3,4}` on the benchmark host.

A trace refresh was first attempted with the existing Stage-2 torch-profiler
overlay. It is not compatible with the retained raw NPUGraph executable on
this CANN 9.0 image: the profiler creates an additional stream before the
first steady graph capture, and `capture_end` failed with runtime error
107025, `capture model contains a stream that was not joined to the original
stream`. The process exited through the intentional fail-closed graph path;
no profile or performance sample from that attempt was accepted.

External dynamic `msprof` subsequently produced a clean post-capture trace.
CANN requires `PROFILING_MODE=dynamic` to be present before the target process
starts; dynamic attach is interactive and cannot be combined with
`--duration`. The accepted service was therefore relaunched with only that
diagnostic environment variable, warmed until both fixed CFM slots replayed,
and then sampled through `start`, one request window, `stop`, and `quit`.
This did not reproduce error 107025. A source-level regression test now also
asserts that raw flat capture dispatches the BSH cache path through explicit
single-stream attention while leaving the ordinary planar path unchanged.

The representative ten-request external trace completed 10/10 requests and
exposed the next architectural opportunity. Each request executed the same
three eager CFM shapes before any variable tail: prompt width 302, width 50
with cache 302, and width 50 with cache 352. The trace counted exactly 960
FlashAttention block calls for each shape, or ten complete six-step by
sixteen-block CFM evaluations. Only eight later cache-402 evaluations used
the fixed outer graph across the ten requests; nine variable-width tails
remained eager. In total, the host submitted 236,082 kernel launches and the
largest device families were TransData 310.47 ms, MatMulV2 264.81 ms,
LayerNormV3 231.97 ms, Transpose 211.70 ms, Mul 199.21 ms, Add 164.69 ms,
Slice 152.83 ms and FlashAttention 129.77 ms. Profiler overhead makes this
run invalid as a serving-speed comparison, but the operator counts and fixed
shape recurrence are valid attribution evidence.

The first trace-driven candidate left prompt and variable tails eager, but
admitted both fixed width-50 cache-fill shapes to the outer raw NPUGraph. It
retained one output set for each one-shot fill shape, two ping-pong sets for
steady cache-402, and a strict three-key graph-cache bound. Capture and replay
succeeded without error 107025 and peak HBM stayed below 29.5 GiB. The result
was a useful but unacceptable trade: the two structurally matched runs cut
mean audio TTFP from 756.45 ms to 667.93 ms (-11.70%), while whole-audio RTF
regressed from 0.33852 to 0.35471 (+4.78%), mean E2E regressed from 1.46186 s
to 1.53184 s (+4.79%), and steady-chunk RTF regressed from 0.16915 to 0.18277
(+8.05%). One 1,048,320-frame run was excluded by the established structural
rule. The two-shape candidate is rejected.

The follow-up candidate captured only the first-packet width-50/cache-302
shape and restored cache-352 to eager fused attention. Logs proved the strict
shape policy: cache-302 captured and replayed in one slot, cache-352 never
entered a graph, and cache-402 replayed through the existing two slots. Peak
HBM remained about 29.1 GiB. One 1,040,640-frame run was excluded by the
established structural rule; four matched runs completed 10/10 with 100%
continuity and the accepted 1,036,800-frame / 43.2-second signature:

| A2 single-chip metric | Retained cache-major CFM | Cache-302-only graph, 4-run mean | Change |
| --- | ---: | ---: | ---: |
| Whole-audio RTF (lower is better) | 0.33852 | 0.33470 | 1.13% faster |
| Audio TTFP (lower is better) | 0.75645 s | 0.67398 s | 10.90% faster |
| Text TTFT (lower is better) | 77.70 ms | 76.72 ms | 1.26% faster |
| Mean E2E latency (lower is better) | 1.46186 s | 1.44539 s | 1.13% faster |
| Steady-chunk RTF (lower is better) | 0.16915 | 0.18452 | 9.09% slower |

The split recovers first-packet latency and produces a small repeatable
whole-audio win, but it changes later-chunk scheduling enough to regress the
steady metric. Positional RTF confirms the effect: mean first-chunk RTF moved
from 0.90053 to 0.80236, while the next full chunk moved from 0.20246 to
0.21710. The graph therefore remains a candidate rather than replacing the
retained profile.

A subsequent revision changed allocation order rather than graph math. It
captured both frequently replayed cache-402 ping-pong slots before admitting
the one-shot cache-302 graph. Logs proved the intended order and both phases
replayed, but two matched 10-request runs measured whole-audio RTF 0.35554 and
0.35736 (0.35645 mean), mean E2E 1.53539 s and 1.54324 s, and steady-chunk RTF
0.18862 and 0.18988. TTFP remained fast at 0.66943 s and 0.67477 s. The
capture-order revision therefore regressed whole-audio RTF by 5.30% versus
the retained 0.33852 profile and was removed. This closes graph-pool ordering
as the cause; future cache-fill work must avoid a second persistent raw-graph
boundary rather than merely move it.

The development-only profiler overlay is
`vllm_omni/deploy/minicpmo_4_5_1npu_a2_cfm6_bf16_bsh_cfm_graph_profile.yaml`.
Remote raw artifacts remain under
`/tmp/vllm-omni-profiles/minicpmo45/a2-fixed-cfm-stage2` and
`/tmp/a2-bench-bsh-cfm-bf16-attn-measured*`; these temporary paths are not
durable evidence storage.

## Competition quality gates

The organizer materials require performance submissions to validate accuracy
on Daily-Omni, Seed-TTS and Video-MME, with no more than a two-percentage-point
drop from the corresponding framework baseline. The working reference gates
are:

| Suite | Published baseline | Working minimum or maximum | Current status |
| --- | ---: | ---: | --- |
| Daily-Omni accuracy | 79.5% | at least 77.5% | not run at full scale |
| Video-MME accuracy | 69.0% | at least 67.0% | not run at full scale |
| Seed-TTS speaker similarity | 0.709 | at least 0.689 | not evaluated |
| Seed-TTS WER | 1.414 | at most 1.56 | not evaluated |

Local dataset readiness also blocks a compliance claim:

- the local Daily-Omni annotation path currently resolves 1,196 questions,
  while the organizer protocol specifies 1,197;
- only ten Video-MME videos are extracted locally, while the official run
  covers 2,700 questions;
- the ASR and speaker-similarity evaluator dependencies and checkpoints are
  not yet installed and pinned.

No candidate should be promoted from this performance report alone.

## Interpretation

The implemented change caches MiniCPM-o's immutable CosyVoice CFM timestep
embeddings by estimator, device, dtype, CFG batch size and timestep count. The
old path rebuilt sinusoidal frequencies on CPU, copied them to NPU and reran
the timestep MLP for every diffusion step of every streamed chunk. Cache fill
keeps the original per-step MLP batch shape and Euler order. Flow-matching
steps, chunk geometry and sampling parameters remain unchanged.

The original targeted Code2Wav gate passes, and the expanded current-backend
Code2Wav/NPU/scheduler set passes 48/48 on the benchmark host. Structural output
parity does not replace official WER and speaker-similarity evaluation.

The result changes the urgent performance picture:

- TTFT is 5.31% better than the published reference, so text-prefill
  changes are not the primary target;
- TTFP is now 1.37% better than the published reference;
- whole-audio RTF is only 1.51% above the published reference;
- the controlled prior-to-optimized improvement is much larger than the
  three-run sample variation.

NPU CFM graph replay was investigated and rejected. Removing the timestep
host transfer exposed an unsupported internal-format Conv2D. Disabling NPU
internal formats made capture succeed, but a smoke run regressed mean audio
RTF to 1.43, per-chunk RTF to 1.60 and added about 6.1 GiB HBM. Growing
attention-cache shapes make graph capture churn a likely cause. The
internal-format experiment was reverted and graph mode is explicitly off.

The next optimization sweep should hold the same 32-request manifest fixed and
change one factor at a time:

1. profile-guided per-step Code2Wav workspace reuse; do not retry whole-stack
   output preallocation unchanged;
2. custom-op-capable vLLM-Ascend image;
3. initial and steady codec chunk geometry, behind quality validation;
4. flow-matching timestep count, behind quality validation;
5. NPU SDPA backend selection.

Every speed candidate must export audio for WER and speaker-similarity scoring.
Promote a setting to the full suites only after it improves TTFP or RTF and
passes the Seed-TTS quality budget.

## Acceptance decision

Decision: **retain as an experimental benchmark profile; do not approve for
competition submission or production promotion.**

Reasons:

- TTFT, TTFP, RTF and end-to-end improvements are real and repeatable;
- TTFP now beats the published reference and RTF is within 1.51%;
- the organizer baseline could not be reproduced as an unmodified same-host
  runtime;
- all three required quality suites remain incomplete;
- the runtime dependency set is not yet version-aligned;
- the result bundle has not yet been moved into durable digest-addressed
  evidence storage.

## References

- [Competition guidance](https://modelbest.feishu.cn/docx/U41vdXMmQo7tv3xW2p9c9uEanKe)
- [Competition benchmark details](https://qcn9xlavkz5b.feishu.cn/wiki/UzxWwSnofifkxCkFNcAcTIaNnFe)
- [LunaNexa phased plan](PLAN.md)
- [LunaNexa architecture](ARCHITECTURE.md)

## A2 full-block graph follow-up

The full BSH DiT block was also compiled as one canonical-Conv TorchAir/GE
partition on the available single-chip 910B4 host. With real MiniCPM-o 4.5
weights, isolated block latency fell from 1,096.45 us to 402.44 us (2.72x).
That isolated gain did not translate uniformly to serving: a matched
cache-302 run improved audio TTFP from 0.75645 s to 0.67801 s and whole-audio
RTF from 0.33852 to 0.33707, but regressed steady-chunk RTF from 0.16915 to
0.18721. The candidate is retained only as an explicit low-TTFP experiment.

Extending the block graph into the cache-402 steady NPUGraph was unsafe on the
installed stack. GE execution inside the outer capture failed with
`Unsupport run graph with different stream`. ACLGraph replay was 45.5% slower
than its eager control, and its static-shape TBE compilation failed before
producing a binary; the host image also lacks the separate NPUGraphEx package.
The accepted balanced A2 profile is therefore unchanged. Full-block GE is
disabled whenever the outer flat-capture path is active, pending a compatible
CANN/TorchAir/NPUGraphEx runtime and a new matched quality/performance gate.
