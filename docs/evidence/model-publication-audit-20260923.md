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

At the time of the initial audit, the published-running count was zero. The
follow-up below removes evaluation as a publication prerequisite, but does not
turn a deployment plan into a running or measured model API.

## Follow-up: controller recovery and optional evaluation (2026-09-23)

The earlier `UnsupportedSnapshot` rollout failure was caused by a stale
controller executable in `deploy/cluster/one-click.sh`: `moon build` in this
workspace writes under `_build/native/release/build/vectie/lunanexa/`, while
the image step had read `_build/native/release/build/cmd/`. The stale executable
did not contain the `exclusive_deliveries` snapshot domain, although the
current source allowlist did. The failed image reproduced the error against an
isolated PostgreSQL clone; the freshly built executable passed that startup
point against the same clone. The builder now requires the workspace-aware
binary path and refuses to package a missing fresh executable.

The first isolated startup then identified one additional live-manifest drift:
the mounted `lunanexa-cosign-trust` Secret already contained
`sigstore-trusted-root.json`, but the Deployment lacked
`LUNANEXA_COSIGN_TRUSTED_ROOT_PATH`. After adding that path, the isolated
controller returned HTTP 200 from `/health`. Production was updated in one
Deployment patch to include the environment variable and the immutable image
`moon/lunanexa-control@sha256:08ab022ade2686c0361a44c424300e9beb3387399cb6b1347e6e05dcd34df741`.
The production Pod became 4/4 ready with zero restarts, acquired PostgreSQL
leadership, and returned HTTP 200 from `/health`; the public Operator page on
port 4174 also loaded.

The Operator browser is a separate image. Only its `console/index.html` and
`console/console.js` were replaced in
`moon/lunanexa-web@sha256:b7c2a84226ada0e177ef3c68de5476ea5f809718933713bb34cb6401ebf005f2`;
enterprise, workbench, private contract fonts and other assets were preserved.
The public `:4174/console/console.js` SHA-256 matched the built bundle
(`574fc6973b0675c61cb787145745b912c39eeb891987909d905eca0cc819c64b`).
Both public and private HTTP origins and the Operator auto-login meta remained
in the served index. Public `:4174/v1/catalog/templates` returned HTTP 200
without a browser-supplied credential, confirming the same-origin Operator
proxy still attaches its scoped authority.

Model evaluation is now optional evidence, not an intermediate approval or
deployment gate. License acceptance, artifact verification, explicit operator
approval, runtime image verification and capacity checks remain in force.
Absence of evaluation does not create a fake passing result: promotion receipts
leave `evaluation_id` empty unless a real passed record exists. A read-only
production plan for `glm53-exl3-text@v2` returned `executable: true`, no
preflight findings and placement on `spark-25e2-3d35c8fd` without creating a
deployment. This proves the former `EvaluationNotPassed` blocker is removed;
it does **not** prove GLM inference succeeds or establish benchmark performance.
The separate runtime and physical acceptance work remains open.

Verification: 1214/1214 native MoonBit tests, 176/176 API tests, and the
disposable PostgreSQL integration suites (7/7 database contract and 359/359
service tests). The previous production image digest
`sha256:a783785c5f84a3a4eee7bb43d8f0939df47bc60924b8242058c30a8a8f142cf7`
remains the documented rollback point.
