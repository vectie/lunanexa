# Public H3 ComfyUI demo

## Native H3 public entry — 2026-11-10

The owner confirmed that 5005 must remain usable without login after being told
that the active native H3 workspace, including its workflows and videos, would
be public. `lunanexa/comfyui-public-proxy` now forwards its root UI, APIs and
WebSocket traffic to `comfyui-h3-native.lunanexa.svc.cluster.local:8188` on .176.
It does not require a LunaNexa or Comfy Cloud login. The old stopped vLLM
`/h3/v1/` route is no longer the generation path; refresh previously opened UI
tabs and use the native H3 workflows.

The former public workspace/PVC is retained. `/view` and `/api/view` first use
the native workspace and fall back to the previous public service on a missing
file, preserving older public video downloads. Private account workspaces were
not copied or merged. The owner-approved native workspace is shared publicly.

The MoonMoon user service that occupied 127.0.0.1:5005 was stopped, disabled and
its unit archived; application files were retained. The proxy is 1/1 Ready.
Anonymous browser controls, GPU metadata, queue, native node catalog, WebSocket
101 and retained MP4 range requests (206) pass. ffprobe and a complete ffmpeg
decode through the domain 5005 proxy validated a retained 20.04-second H.264
video at 608x352 without errors. This is
proxy/media acceptance, not a new native-model generation run.

Publish/rollback automation: `scripts/route-public-comfyui-native.mbtx`.
Private snapshots on management: `/home/HwHiAiUser/public-comfyui-native-20261110`.
Verification: `scripts/verify-public-native-video.mbtx`; local evidence is under
`output/public-comfyui-native-20261110/`.

## Recovery on 2026-10-28

Port 5005 is restored by the dedicated `lunanexa/comfyui-public-proxy`
Deployment, forwarding to the existing `comfyui-public` Service and its
independent `comfyui-public-demo` PVC. It does not mount personal workspace
files or revive the legacy operator proxy's other ports. The old proxy could
not start because its historical local image was unavailable.

The same proxy's `/h3/v1/` route forwards only to `minimaxh3-fl2va` on node 176.
Its runtime credential comes from the existing `minimaxh3-runtime-credentials`
Secret and is substituted server-side; no key is added to public workflows.
Five FL2VA templates and four saved public workflows now use the restored
5005 H3 route, with their original files backed up before the address-only
migration. Existing browser-cached graphs may still need their URL updated or
the saved workflow reopened.
The public workspace's existing egress policy also permits TCP 5005 to the
management node only; unrelated network rules remain unchanged.

Node 177 remains the Qwen text service. Ref2VA templates are retained, but
Ref2VA is not running and is not part of this recovery. Nodes 178/179 are
unchanged. This anonymous workspace shares input/output files among visitors;
private work should use the authenticated `/user/` → ComfyUI entry.

The durable-video release now puts the reviewed adapter modules and video-task
panel in the pinned workspace image. The old `comfyui-vllm-omni-patches` subPath
overrides are removed during rollout so they cannot mask this version. Personal
and public workspaces use the same implementation, **not the same PVC or task
list**. The personal gateway admits only task listing and original-task recovery
through the existing authenticated workspace session.

The 176 shared FL2VA profile also includes the verified 608×352, 481-frame,
24-fps, 8-step silent preset. Its former 121-frame cap and dimension list did
not match the public 20-second template. Other providers, model weights, sampler
steps, GPU deployment and concurrency settings are unchanged.

On 2026-10-28 the public UI submitted a 20-second preset and was closed and
reopened during generation. The task identifier and 80% finishing phase were
restored. The MP4 was archived 421.31 seconds after submission; browser metadata
reported 20.082 seconds at 608×352. A subsequent ComfyUI-only restart retained
both its task record and output. This is UI/transport recovery, not intermediate
diffusion checkpointing after a GPU/model crash.
The final pinned release was also verified by playing this retained video to
its 20.082-second end in the 5005 browser, without errors or a workspace restart.

## Historical deployment reference

`deploy/acceptance/comfyui-public-demo-pvc.yaml` exposes the CPU-only ComfyUI
frontend at `http://203.0.113.10:5005/` without an application login. The
management-node proxy forwards port 5005 to the internal `comfyui-public`
ClusterIP Service on port 8188. The former public port 5000 redirects to 5005;
it is not the ComfyUI entry point. FL2VA inference runs on
Spark 25e2 (`192.0.2.176`), and Ref2VA runs on Spark 3782
(`192.0.2.177`). ComfyUI does not mount model weights; its LunaNexa H3
templates call the model endpoints through the management-node proxy.

The public demo uses the dedicated `comfyui-public-demo` PVC. Do not attach
the older `comfyui-acceptance` PVC to the public service: it contains previous
workspace data. Anonymous visitors share the demo input/output workspace, so
this route is for public test material only, not private tenant work.

The workflow browser exposes six LunaNexa H3 presets under **模板 → 扩展 →
lunanexa-h3**. The self-check preset uses FL2VA and needs only a text prompt.
The reference-image preset uses Ref2VA; the ComfyUI adapter supplies the
required, same-duration silent audio condition when an image is submitted.
The first-frame preset uses FL2VA instead. Template files are versioned under
`deploy/acceptance/comfyui-templates/lunanexa-h3/` and installed on the
management node at `/data/models/comfyui-templates/lunanexa-h3/`.

The historical Deployment mounted three patched ComfyUI-vLLM-Omni modules from the
`comfyui-vllm-omni-patches` ConfigMap, generated from the versioned files in
`deploy/acceptance/patches/comfyui-vllm-omni/`. Update that ConfigMap before
rolling the Deployment; a ConfigMap change alone does not refresh subPath
mounts. The model-serving Deployment and Service pair remain separate from
the public ComfyUI Deployment. If a model Service is deleted and recreated,
reload `operator-4173-proxy` nginx so its static upstream DNS resolves the new
ClusterIP.
