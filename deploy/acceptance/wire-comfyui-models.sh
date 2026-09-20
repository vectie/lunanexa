#!/bin/bash
# Acceptance-environment plumbing, not platform code: ComfyUI lives in the
# aigc-acceptance namespace and is not supervised by LunaNexa.
#
# Give ComfyUI a model tree it can actually see.
#
# As deployed, the pod mounts /data/models at /workspace/models, which ComfyUI
# never scans: its own tree is /opt/ComfyUI/models on the read-only image layer,
# so every loader in the Z-Image workflow reports a missing file no matter what
# the model store holds. This builds the category layout ComfyUI expects inside
# the store, links the downloaded split files into it, and mounts that directory
# over /opt/ComfyUI/models.
set -euo pipefail
SUDO_PASS="${1:?usage: wire-comfyui-models.sh <sudo-password>}"
s() { printf '%s\n' "$SUDO_PASS" | sudo -S -k "$@"; }
STORE=/data/models
TREE="$STORE/comfyui"
IMPORT=ms-ce32a7f5bad27910e098526e
# The adapter downloads into .imports/<id>.partial and moves it into place when
# the revision verifies, so both locations have to be looked at.
SOURCE="$STORE/.imports/$IMPORT.partial"

echo "=== where the download is landing"
s ls -la "$STORE/modelscope" 2>/dev/null | tail -5 || true
find "$STORE" -maxdepth 4 -name 'split_files' -type d 2>/dev/null | head -3

echo "=== ComfyUI-shaped tree in the store"
# /data/models is root-owned; the tree belongs to the runtime uid.
s mkdir -p "$TREE"/{diffusion_models,text_encoders,vae,checkpoints,unet,clip,loras}
s chown 1000:1000 "$TREE" "$TREE"/*

link() { # link <source> <category> <name>
  local source="$1" category="$2" name="$3"
  if [ -f "$source" ]; then
    s ln -sfn "$source" "$TREE/$category/$name"
    echo "  linked $category/$name -> $source"
  else
    echo "  (not yet) $category/$name"
  fi
}

# The split-file layout ComfyUI's own Z-Image template expects.
SPLIT=$(find "$SOURCE" -maxdepth 2 -name 'split_files' -type d 2>/dev/null | head -1)
if [ -n "$SPLIT" ]; then
  link "$SPLIT/diffusion_models/z_image_turbo_bf16.safetensors" diffusion_models z_image_turbo_bf16.safetensors
  link "$SPLIT/text_encoders/qwen_3_4b.safetensors" text_encoders qwen_3_4b.safetensors
  link "$SPLIT/vae/ae.safetensors" vae ae.safetensors
else
  # Fall back to whatever the adapter has so far: it downloads file by file.
  for candidate in $(find "$SOURCE" -name 'z_image_turbo_bf16.safetensors' -o -name 'qwen_3_4b.safetensors' -o -name 'ae.safetensors' 2>/dev/null); do
    case "$(basename "$candidate")" in
      z_image_turbo_bf16.safetensors) link "$candidate" diffusion_models z_image_turbo_bf16.safetensors ;;
      qwen_3_4b.safetensors) link "$candidate" text_encoders qwen_3_4b.safetensors ;;
      ae.safetensors) link "$candidate" vae ae.safetensors ;;
    esac
  done
fi

echo "=== the pod must read the tree"
s chmod -R a+rX "$TREE" 2>/dev/null || true

echo "=== mount it where ComfyUI looks"
s kubectl -n aigc-acceptance-20260915 get deploy comfyui-acceptance -o json > /tmp/comfyui.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/comfyui.json'))
spec = d['spec']['template']['spec']
spec.setdefault('volumes', [])
if not any(v.get('name') == 'comfyui-models' for v in spec['volumes']):
    spec['volumes'].append({
        'name': 'comfyui-models',
        'hostPath': {'path': '/data/models/comfyui', 'type': 'Directory'},
    })
for container in spec['containers']:
    if container['name'] != 'comfyui':
        continue
    mounts = container.setdefault('volumeMounts', [])
    if not any(m.get('mountPath') == '/opt/ComfyUI/models' for m in mounts):
        mounts.append({
            'name': 'comfyui-models',
            'mountPath': '/opt/ComfyUI/models',
        })
d.pop('status', None)
json.dump(d, open('/tmp/comfyui-patched.json', 'w'))
print('patched manifest written')
PY
s kubectl apply -f /tmp/comfyui-patched.json
s kubectl -n aigc-acceptance-20260915 get pod -l app=comfyui-acceptance \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
