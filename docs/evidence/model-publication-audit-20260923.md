# Model publication audit — 2026-09-23

The live controller at the public Operator front door reported 22 model
records: 17 `Approved`, three `Verified`, and two `Candidate`. This is **not**
22 running model APIs. `/v1/catalog/templates` contained three templates, and
`/v1/service-deployments` contained no running service.

An actual one-click attempt with the existing
`zlab-dflash2-text@v1` template created operation
`operation:zlab-dflash2-live-20260923:1`, state `Blocked`. Preflight returned
`EvaluationNotPassed` and `NoCompatibleNode`. The underlying
`z-lab/Qwen3.8-27B-DFlash2` README says it is a speculative *draft* model,
not a standalone text model; the current template must not be advertised as a
usable standalone service. The live registry has only two passed evaluations,
for `tiny-bf16` and the historical `qwen3-0.6b`. Its other approved models used
the explicitly shelved-evaluation registry policy; deployment preflight still
requires a real passed evaluation.

The node placement blocker was real and independently fixed. The cluster
manifest requested `moon/lunaflux:sha256-bec873…`, but that tag resolved to a
Sigstore-bundle OCI index, not the runnable image. The exact image manifest
`moon/lunaflux@sha256:bec873…` exists in the internal registry. The manifest
now requests that digest, and `registry,config,apply,verify` converged all
four Sparks. All four now report the matching LunaFlux runtime name in their
signed heartbeat. This repairs image availability/placement; it does **not**
create an evaluation or prove LunaFlux can serve every imported architecture.

Publication classes requiring distinct work:

- `Qwen3.8-27B-DFlash2` and the similar GLM DFlash2 are draft accelerators
  that require their target model and a compatible speculative runtime.
- Dense/FP8/NVFP4 Qwen models require a runtime that supports their exact
  architecture and quantization, plus on-Spark inference measurements.
- GLM, DeepSeek, and Step MoE models require compatible MoE/quantization
  runtimes and may require a measured two-node profile. A large downloaded
  artifact or a one-GPU template is not evidence it fits.
- Qwen-VL needs a multimodal runtime; MiniMax-H3 needs the video runtime,
  FL2VA-specific approval/evaluation/template, and applicable license scope.
- A genuine live launch additionally needs a successful request through the
  public user-facing API, not only an Operator state transition.

Until those runtime and measured-evaluation gates are complete, the correct
published-running count remains zero. Do not mark the catalog or UI as live.
