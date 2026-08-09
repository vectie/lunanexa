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
