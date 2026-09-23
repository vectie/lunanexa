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
An independent read-only `/v1/deployment-plans` request after convergence
returned a concrete placement on `spark-368c-0f2ee8b2` and only one blocker:
`EvaluationNotPassed`.

The H3 video runtime image at `sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c`
was signed with the existing encrypted Cosign private key after locating its
host-local password file and checking it derives the already trusted public
key. Host Cosign verification succeeds. Controller verification still rejected
the request because its read-only container cannot create Cosign's default
`/.sigstore` cache. A direct container test with the already-mounted
`sigstore-trusted-root.json` succeeds; the controller adapter and deployment
environment have been fixed in source to use that pinned trusted root. Do not
count the H3 image as controller-verified until the new controller is deployed
and the API creates a durable verification receipt.

The new controller was built and pushed at OCI digest
`sha256:7a33d2a35e18e0a45c5eb5255ef575af7da7a539b294fdc0df8f8af2d4e96b06`.
Its rollout failed during PostgreSQL startup with
`DatabaseError.UnsupportedSnapshot`; the existing controller was rolled back
and the public API recovered. Two diagnostic rebuilds reproduced the startup
failure; their images were not left running. The current database snapshot
domains and schema-version columns were read without mutation and appear to
match the source constants, so the exact throw site is not yet established.
Do not promote the source-only Cosign adapter change as deployed. The public
controller still rejects the H3 verification request, and no H3 assignment or
inference call was made.

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
