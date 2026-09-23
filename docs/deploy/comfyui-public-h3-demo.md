# Public H3 ComfyUI demo

`deploy/acceptance/comfyui-public-demo-pvc.yaml` exposes the CPU-only ComfyUI
frontend on port 5000 without an application login. FL2VA inference runs on
Spark 25e2 (`192.168.2.176`), and Ref2VA runs on Spark 3782
(`192.168.2.177`). ComfyUI does not mount model weights; its LunaNexa H3
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

The Deployment mounts three patched ComfyUI-vLLM-Omni modules from the
`comfyui-vllm-omni-patches` ConfigMap, generated from the versioned files in
`deploy/acceptance/patches/comfyui-vllm-omni/`. Update that ConfigMap before
rolling the Deployment; a ConfigMap change alone does not refresh subPath
mounts. The model-serving Deployment and Service pair remain separate from
the public ComfyUI Deployment. If a model Service is deleted and recreated,
reload `operator-4173-proxy` nginx so its static upstream DNS resolves the new
ClusterIP.
