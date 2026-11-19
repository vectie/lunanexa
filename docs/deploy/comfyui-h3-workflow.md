# ComfyUI H3 workspace workflow

## Durable video recovery (2026-10-28)

The reviewed ComfyUI-vLLM-Omni adapter journals video task identifiers, phases,
progress and output references in the workspace PVC. It does not journal model
credentials or prompts. The same pinned adapter image serves personal workspaces
and the independently stored public demo. Its Video tasks panel reloads these
records after navigation; browser connectivity does not own a generation job.

Accepted provider jobs are polled by their existing identifier, never resubmitted
on reconnect or restart. A submission with no acknowledged identifier is marked
uncertain and requires reconciliation. Completed MP4s are atomically archived in
the workspace output directory before provider cleanup or downstream SaveVideo.
Transport failure must not delete an accepted job or completed output. A failed
or restarted model cannot resume diffusion from an intermediate step: report that
failure honestly rather than starting a second generation automatically.

Acceptance requires both public entries, a UI-started long video, navigation
during generation, restored progress, playable retained output, and isolated
restart/recovery and interrupted-download regression tests. Small-clip success
alone does not establish long-video acceptance.

The personal gateway must allow `GET /lunanexa/video-tasks` and
`POST /lunanexa/video-tasks/<32-lowercase-hex-id>/recover`, including ComfyUI's
`/api` prefix, under the existing workspace authorization. These are not model
submission routes. HTTP 400/401/403/404/413/415/422 on submission is a definitive
rejection shown as failed; a lost acknowledgement remains uncertain and must
not be silently resubmitted.

The adapter accepts both scalar progress from vLLM and the legacy `[n]` optional
integer encoding returned by the personal controller. Unknown progress remains
unknown; it must not replace a saved higher value with zero.

Focused checks: 13 adapter transport regression tests and 62 workspace gateway
tests passed. `moon info` and `moon fmt` completed. The full `--deny-warn` check
and native phase gate currently fail on pre-existing deprecated `to_json()`
calls outside this change; do not describe the full repository gate as green.

The restored personal shared-video profile and three pre-existing shared-video
leases previously capped output at 121 frames. The active 176 FL2VA profile now
includes 608×352 / 481 frames; the existing leases' frame budget is 481. Identity,
grants, expiry, input budget, request counts and concurrency were not changed.
The one-time `scripts/sync-existing-video-frames.mbtx` migration pauses only the
controller's in-memory directory owner, privately backs up its exact snapshot
and lease projections, validates the old scope, changes both representations in
one transaction, and restores the controller replica count even on failure.
It must not be rerun against already-migrated budgets. Model pods are untouched.

The personal 20-second browser job `e59c379b13c44889a0bdc8ff0816d1d7`
was accepted at 20:53:58 Beijing time on 2026-10-28. Closing/reopening the page
and a controlled ComfyUI-only restart retained its identity. After another
adapter rollout, the UI's "connect original task" retrieved its existing result
at 21:06:22; no second generation was submitted. The intervening rollout and
manual recovery make this wall time unsuitable as a generation-speed benchmark.
The final adapter also retries transient status-read 5xx responses and reconnects
known interrupted jobs on startup within their existing observation deadline.

An actual personal video preview exposed a second failure: after the browser
interrupted a ranged media read, the gateway's error handler attempted to send
HTTP headers a second time. This panicked the native HTTP sender and restarted
the gateway (exit 139 in the runtime container). The new 5-MiB range/reader-close
regression reproduced the sender panic before the fix and passed afterward.
Both the browser gateway and the workspace model proxy now track whether a
stream response has started and close an interrupted stream without a second
error response. Listener address reuse prevents TIME_WAIT from delaying a
subsequent restart. Fixed startup stages / OS error numbers are logged without
printing exception context, credentials or prompts.

Final browser acceptance after that release loaded the personal retained MP4 at
608×352 / 20.082 seconds, played it to its end, and sought within it without a
gateway restart. A fresh five-second UI regression then showed 14% progress;
closing the tab and reopening restored the same task `161eaea012` at 43%, rather
than submitting again. It completed automatically with a saved 608×352 /
5.207-second MP4; the normal ComfyUI graph finished in 208.16 seconds and its
queue returned to zero. The final gateway and both personal workspace
containers remained ready with zero restarts throughout this browser retest.
Use the **视频任务** panel for durable status; ComfyUI's
native transient queue display is not the persisted task ledger.

The deployed digest pins for this recovery are:

- Both workspace images: `acceptance/comfyui-workspace@sha256:10f0aa837e2a1c1dec7e9f0be083a84d65bde17ddbf745cbf94d434598810856`.
- Personal browser gateway: `acceptance/webide-runtime@sha256:aab82ddc60eb15b46bcf60002a537f2db1a118bdf0210506e056bd972a36dd30`.
- Personal model proxy: `moon/hosted-apps@sha256:3586f62048aa7d229e65fab361f37625c9e5765a77c676207193f73a2e07f819`.

These use the existing internal registry. Future personal workspace launches
are configured with the same workspace and model-proxy pins. Other consumers
of the hosted-apps image are unchanged. Acceptance screenshots are retained in
`output/comfyui-recovery-20261028/` (`personal-20s-recovered.png`,
`personal-progress-after-reopen.png`, and `public-20s-recovered.png`).

The delivery-bound ComfyUI workspace initializes its editable starter at
`/workspace/user/default/workflows/LunaNexa Video - <model alias>.json`. The initializer takes
the single model selector from the redeemed delivery grant. The video node calls
`http://127.0.0.1:8189/v1`, which is the model proxy in the same pod. That proxy
checks the live delivery authority and allowed model on every request, injects
the workspace credential, and forwards only to the configured model gateway.
The workflow and its input/output files are on the retained workspace PVC, not
the image or the model cache. Initialization leaves existing files unchanged;
when a later delivery selects a different model, it adds a clearly named starter
while preserving the previous model's edited workflow.

Personal shared ComfyUI and delivery-bound ComfyUI can use the same `comfyui`
client ID in one Kubernetes namespace. Their gateways must reconcile only
their own profile: grants without `delivery_id` belong to the personal shared
gateway; delivery-bound grants belong to the exclusive gateway. An expired or
revoked grant is still stopped by its owning gateway. A different profile's
authorization policy must not stop an otherwise valid workspace.

The starter is a text-to-video FL2VA-shaped graph: one 8-step diffusion sampler,
one `VLLMOmniGenerateVideo` node, and one `SaveVideo` node. It specifies 512×512,
25 frames, 24 fps, no sound, and a 900-second wait. The runtime image must carry
the reviewed `ComfyUI-vLLM-Omni` custom node and the ComfyUI `SaveVideo` node.
Its video transport sends a stable `Idempotency-Key` per enqueue attempt.

The acceptance template package is historical example material. Its four
remaining text workflows now point at the pod-local proxy and require the user
to substitute the exact model alias selected by the delivery. These examples
are not prebound; the persisted `LunaNexa Video - <model alias>` workflow is the ready-to-edit
entry. Image and reference-image examples have been removed from the served
package because the present model proxy accepts only bounded text-only video
forms. Do not advertise Ref2VA or image-to-video through this profile until
the upload, model authorization, and runtime profile are qualified together.

This source change does not prove that FL2VA is admitted, deployed, or able to
generate a video on Spark. The current registry's whole-H3 alias is not proof
of a qualified FL2VA component. Before public acceptance, the controller's
delivery template, active model API binding, and grant selector must all refer
to the exact approved FL2VA component. Complete a browser generate/download,
save/reopen, and expiry check through the public UI.
