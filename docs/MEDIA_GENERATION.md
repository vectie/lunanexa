# Managed media generation

## Scope and authority

This extension adds bounded, asynchronous single-request video generation, not
a general workflow engine or batch scheduler. ComfyUI remains a client outside
managed GPU nodes. Clients reach the public contract through MoonGate; LunaNexa
has no MoonGate dependency. Model weights remain registered data artifacts,
never runtime image layers.

The first qualification target is MiniMax-H3 Base FL2VA text-to-audio/video on
one DGX Spark using a pinned vLLM-Omni runtime. SGLang, reference uploads,
ControlNet, LoRA selection and distributed two-Spark execution require separate
adapter/profile qualification. Two independent workers are not tensor parallel
execution. No local 2K or Context-IR support is implied.

Users select a sellable dedicated-endpoint offering, review its quote and terms,
and pay through existing machine commerce. Creation of a video requires the
same authenticated purchaser, organization, active order and ready deployment.
The controller selects infrastructure; browsers cannot supply nodes, runtime
URLs, filesystem paths or runtime arguments. Registration/trial alone does not
authorize machine use. Prepaid capacity usage must not be charged a second time
as shared token inference.

## Job contract and recovery

Public job records contain opaque identifiers, typed lifecycle state, bounded
generation settings, timestamps and an authenticated result reference. Prompts,
runtime credentials, upstream job identifiers and internal endpoint addresses
must not appear in public job history or audit logs. Generated output retention
is explicit, bounded and independent of training consent (always off).

Persist submission intent before sending to the provider. The upstream currently
does not implement idempotent video creation. Therefore an interrupted/ambiguous
submission MUST NOT be automatically resubmitted: it requires reconciliation,
not an optimistic retry that can duplicate GPU work. Once an upstream identifier
is durably attached, status and deletion are safely retryable. Terminal states
cannot regress. Cancellation is not complete until the provider acknowledges
deletion; expired results stop being accessible immediately even when deletion
requires retry. Tenant/order ownership is checked for every operation.

## ComfyUI is a WebIDE

The customer-facing creation surface is ComfyUI itself, listed beside other
WebIDEs in the enterprise workspace selector. Do not build a parallel LunaNexa
prompt editor, workflow canvas or result gallery. LunaNexa owns provisioning,
access, readiness, quotas and audit; ComfyUI owns creative interaction.

A hosted ComfyUI requires a lease-aware authenticated launch bridge, a distinct
process/container and storage boundary per workspace, authenticated HTTP and
WebSocket proxying, and server-side scoped MoonGate credentials. Its public URL
is the bridge, never the unprotected upstream ComfyUI port. ComfyUI multi-user
preferences alone are not tenant isolation. Custom-node installation is an
operator-controlled image change, not an arbitrary tenant host execution path.
Workflow inputs, outputs and history must remain workspace-scoped. Closing a
lease revokes both browser and model access.

Existing single-use client handoff is reused for the launch bridge. Registering
a launch URL only configures discovery; it does not implement that bridge or
prove a running ComfyUI instance. Keep unqualified clients out of live catalog
configuration until their bridge, storage isolation and backend pass acceptance.

## User experience

Keep the primary path to three tasks: select and purchase a qualified plan,
deploy and inspect readiness, then open ComfyUI with an approved starter workflow.
Generation settings and preview/download live in ComfyUI. Technical deployment
evidence belongs in disclosures in LunaNexa.
Do not fabricate progress percentages: display queued, generating, cancelling
and terminal states from the provider. Hardware/artifact/approval blockers must
be visible before offering generation. Browser polling stops on terminal state,
navigation or logout; credentials never appear in result URLs.

## Verification and rollout

Repository tests must cover strict input bounds, prompt-safe transport,
provider response normalization, ownership, conflicting idempotency keys,
ambiguous submissions, monotonic state transitions, persistence failure,
restart recovery, cancellation and retention. Native loopback tests are not GPU
evidence. Physical rollout remains blocked until the exact ARM64 image, artifact
bundle, memory profile, audio/video codec output, throughput, cancellation,
MoonGate ingress, billing evidence and browser download have passed on Spark.

Implementation is incremental. This document defines required behavior; only
tested and integrated slices may be described as delivered.

### 2026-09-14 implementation checkpoint

- Added deployment-owned multi-WebIDE catalog, per-client handoff configuration,
  and enterprise selector (desktop editor and ComfyUI demo states).
- Native client configuration tests: 3 passed. Enterprise UI/browser-state
  tests on JS: 47 passed. Browser interaction checked at desktop and 390px width;
  selecting an unavailable ComfyUI keeps launch disabled with a visible reason.
- Native API regression: 124/124 passed on an isolated Linux checkout using the
  repository's bundled MoonBit 0.10.10 toolchain and extracted PostgreSQL client
  libraries. This covers multiple clients, wrong-client redemption, provider
  binding, account suspension and lease revocation. The test command disables
  warning 92; it is not the full warning-clean production release gate.
- Upgraded `moonbitlang/x` to 0.4.50 for StringView compatibility. The default
  local 0.10.12 compiler still cannot compile `vectie/moonleaf@0.1.14`'s removed
  `strconv.from_str` calls. That dependency remains a full-build blocker.
- Implemented a native hosted WebIDE bridge, per-workspace Kubernetes desired
  state and a pod-loopback model credential proxy. Thirteen native tests cover
  HTTP/WebSocket authentication, origin and route policy, identity separation,
  revocation, partial provisioning retry, secret rotation, initialization and
  approved-model restrictions. Tests use local fixtures, not production GPUs.
- Real ComfyUI `e80c1570b6b44a2557d5d8e341e05782d18c9bbb`, frontend 1.51.9,
  and the vLLM-Omni custom nodes were exercised behind the native bridge on CPU.
  Browser launch, template opening, editing and saving succeeded. Testing found
  and fixed CSP nonce interpolation, encoded workflow paths, the node replacement
  endpoint and incorrect writable custom-node directory configuration.
- Workspace initialization creates an editable video workflow without model
  credentials; subsequent starts preserve edits. Only data directories are
  writable. Plugin code remains image-owned, with other custom nodes disabled.
- Added paid-order-bound WebIDE selection and live credential revocation. The
  portal pins the selected project/model; stale orders never fall back to shared
  inference. JS UI/application tests now pass 48 cases.
- Added native video request validation, vLLM-Omni status/content/delete adapter,
  durable job state machine and controller `/v1/videos` routes. The controller
  binds an approved template/node profile automatically to subsequent purchases;
  a new customer order does not require a per-order configuration edit.
- Persisted video intents use `lunanexa.media-jobs.v2`. Completion timestamps stay
  stable through cleanup and billing retries. Workspace-wide concurrency/hourly
  admission cannot be bypassed by choosing another project or paid order.
  Ambiguous submissions retain their slot and are never automatically reposted.
- Native API regression passes 125 cases on the isolated Linux toolchain,
  including paid video lifecycle, response redaction, idempotent submission,
  cancellation, account suspension and one prepaid job observation without a
  second charge. This still is not the warning-clean full release gate.
- The real HTTP listener also verifies authenticated streamed download, MP4
  content type, no-store headers, anonymous rejection and account revocation.
  Its payload is explicitly fixture bytes, not evidence of playable GPU output.
- The media and hosted-workspace component suite passes 29 native tests with
  `--deny-warn`. Reconciliation uses at most eight concurrent workers and serves
  earlier deadlines first; an unavailable authority does not serialize all jobs.
- The 13 hosted-workspace tests also pass with AddressSanitizer applied to the
  entry packages and first-party C random-source stub in a disposable macOS
  toolchain (plus two instrumentation markers). Apple Clang leak detection is
  unavailable; this is not an all-dependency LeakSanitizer qualification.
- Real disposable PostgreSQL tests pass: 4 database transaction/leadership tests
  and 2 media persistence tests, including ambiguous-submission restart recovery.
  They do not connect to the production database. Additional native unit/loopback
  tests cover video policy, provider transport and runtime fault handling.
- NOT delivered/qualified yet: production images and WebIDE rollout, complete
  cross-process/browser media acceptance, real GPU generation and Spark evidence.
  MoonGate forwarding and the third-party ComfyUI adapter have their own test
  checkpoints; component tests must not be presented as full-pipeline success.

Hosted workspaces belong in a dedicated namespace. `HostConfig` requires both
`controller_namespace` and `model_gateway_namespace`; the generated egress rules
match namespace and pod labels together. Grant the WebIDE provisioner Secret
access only in the workspace namespace, never the controller's production
namespace. Existing configurations must add these fields before upgrading.

### Deployment-owned media profiles

Set `LUNANEXA_MEDIA_BINDINGS_FILE` to a protected JSON file containing an array
of template/node profiles. PostgreSQL is mandatory when this feature is enabled.
Each entry has `template_id`, `template_version`, `node_id`, `origin`, optional
`bearer`, and `profile`. The profile contains a public `model` alias, the exact
upstream `provider_model`, allowed `widths`/`heights`, `maximum_frames`,
`maximum_fps`, `maximum_steps`, and `sound_supported`. These limits must come
from qualification evidence, not illustrative defaults.

The template must declare `VideoGenerate`; its current deployment must be ready,
single-replica and on the configured node. The account, Developer membership,
MasterLease, workspace video capability and paid order must remain active.
Changing endpoint, profile, placement or deployment generation creates a new
immutable binding identity. Retain historical template/node profiles until their
old jobs have been cleaned up; a missing historical binding fails closed.

`POST /v1/videos` requires a stable `Idempotency-Key` and accepts bounded JSON or
URL-encoded text-to-video fields. File references, arbitrary URLs, LoRA paths and
unqualified `extra_params` are rejected. `GET /v1/videos/{id}`, authenticated
`GET /v1/videos/{id}/content`, and `DELETE /v1/videos/{id}` recheck authority.
Results expire after 24 hours in the provider; separately saved workspace files
remain workspace data. Deletion returns 409 while cancellation is unconfirmed.

Operator-only `/v1/media/operator/jobs` reports pending reconciliation without
prompts or credentials. `POST /v1/media/operator/jobs/{id}:reconcile` requires
the exact `expected_request_digest`, an `evidence_ref` and an attested
`provider_job_id`; it polls the original binding and records the operator audit.
It never creates a job or claims that a missing provider record proves GPU abort.
