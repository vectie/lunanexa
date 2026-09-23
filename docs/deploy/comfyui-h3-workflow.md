# ComfyUI H3 workspace workflow

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
