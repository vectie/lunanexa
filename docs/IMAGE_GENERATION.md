# Qualified single-model image runtime

Implemented 2026-11-07. The provider and HTTP adapter are native MoonBit.
ComfyUI is a pinned third-party model runtime. GPU nodes contain no application
checkout, application credentials, domain schema or agent runtime.

`media/image/provider` admits a bounded prompt and seed into one fixed
Z-Image-Turbo graph: 1024×1024, batch 1, eight steps. It observes only its own
SaveImage output and reconciles an uncertain submission through history/queue
reads. It never automatically submits a second graph after a lost response.

`cmd/image-adapter CONFIG_FILE PRIVATE_BIND` serves authenticated
`POST /v1/images/generations` and `GET /v1/images/generations/ID`.
Only `model`, `prompt`, `n=1`, `size=1024x1024` and `response_format=b64_json`
are accepted. POST requires a 64-character hexadecimal Idempotency-Key;
conflicting reuse is rejected. The journal is written before dispatch and
binds origin, node, model, artifact, profile and workflow. One unfinished job
is admitted at a time, with a durable total request cap.

Startup requires a private qualification file with a matching SHA256,
`approved=true`, node, artifact, origin and `workflow=z-image-turbo-v1`.
This records operator qualification after actual measurements; it must never
be fabricated to bypass validation. Consumers own identity, consent, public
moderation and their event budget. The adapter owns no event schema.

## Deployment measured on node 177

- ComfyUI v0.33.2, commit `7cee3ceb1a35503172e0dfb8dbdbdedee2aba8aa`.
- Model repository `Comfy-Org/Z-Image-Turbo`, revision
  `6fc90a3b1b653e935a0d175e260736de25b84df5`.
- Diffusion SHA256 `2407613050b809ffdff18a4ac99af83ea6b95443ecebdf80e064a79c825574a6`.
- Encoder SHA256 `6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a`.
- VAE SHA256 `afc8e28272cd15db3919bacdb6918ce9c1ed22e96cb12c4d5ed0fba823529e38`.
- Runtime image `moon/comfyui-runtime@sha256:d215c569d3bcade249a4e28a8dd56bc45c355a0616d45b6ab5e99984e3702e65`.
- Bundle digest `sha256:78cad5efa344027953a476f3e38eb92a152bda9a314813cb7500cf16f471b357`.

Qwen's reservation was lowered from 0.80 to 0.55 with explicit user authorization;
loading and warming took about five minutes. Only node 177 changed to a dedicated
NVIDIA time-slicing profile with two logical slots. This is one physical GPU,
with neither memory isolation nor separate failure domains. The other nodes'
device-plugin configuration was preserved. ComfyUI requests one logical slot,
24Gi memory, with a 40Gi limit and one image job at a time.

First model execution and image retrieval: 18.169s. Fresh-seed warm execution:
8.095s. Warm execution overlapping Qwen: 8.086s. A same-seed 2s cache hit was
excluded. Short Qwen requests after warmup took 0.342–0.344s before image work
and 0.667–0.698s during warm image work; the first text warmup request was
16.48s. These include HTTP/kubectl overhead and are small synthetic samples,
not sustained load or long-context throughput measurements. Sampled system
MemAvailable fell from about 44GiB to about 11.1GiB; no continuous peak claim.

The adapter and its private credential remain on management node 175.
ComfyUI uses ClusterIP only, an ingress policy restricted to the adapter, no
external network egress, a read-only model mount and a private output PVC.
No application client can provide graphs, filenames, model paths or callbacks.

## Operations and pitfalls

All first-party operational helpers are `.mbtx`. Run preparation, dependency
build and model verification before resizing or publishing. The resize helper
checks for zero running/waiting text requests and a real authenticated response,
then uses a resourceVersion-guarded patch. The existing vLLM key stays inside its
container and reaches curl through stdin configuration, never command arguments.

The private release directory retains rollback arguments, node label, dependency
versions, model manifest, qualification images and checksums. Service credentials
are file/Secret references, never repository, book or GPU payloads. A registry
cross-repository blob mount reuses existing immutable runtime layers.

ComfyUI requires existing user/input/output directories, a writable explicit
SQLite path, and USER/cache settings when running as UID 1000 without a passwd
entry. The local-path helper's public BusyBox pull was unavailable; only this
volume's helper was switched to an already pinned cached image with the required
shell/mkdir tools. Do not change the global provisioner to work around one pull.

Native gateway images are intentionally minimal and lack `/bin/cp`; they cannot
replace a static-assets init container's base. Use its existing web image.
Linux source archives from macOS must exclude AppleDouble `._*.mbt` resource forks.

Validation: isolated provider/service tests cover fixed graph admission,
lost-response reconciliation with one POST, restart, quota and qualification
binding. Scoped native `--deny-warn` passes. The real consumer UI test uses
isolated identities and actual images; it creates no public event participants.
The rest of the actively modified LunaNexa workspace is outside this change.
