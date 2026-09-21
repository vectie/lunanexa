#!/bin/bash
# Acceptance-environment plumbing, not platform code: ComfyUI lives in the
# aigc-acceptance namespace and is not supervised by LunaNexa.
#
# Install LunaNexa's patches over the two modules of the ComfyUI-vLLM-Omni node
# that this cluster's MiniMax-H3 service actually breaks. Both are baked into the
# image behind a read-only root filesystem, so each file is mounted over its
# installed path with hostPath + subPath; no image rebuild, and no other byte of
# the node changes.
#
# utils/video_transport.py
#   * The completed-video download inherited the 60 s control-plane budget. The
#     service encodes the MP4 inside the GET (102.7 s for a 20 s clip), so a job
#     that had already finished was aborted, and the cleanup DELETE then destroyed
#     the only copy: 404 on every retry.
#   * A job that reached `completed` but whose bytes never arrived is no longer
#     deleted, for the same reason.
#   * The download is retried once: something on this path drops a silent
#     connection about 70 s in (see docs/CLUSTER_REMEDIATION_20260919.md 15.2).
#   * A failed job's own error text is passed back to the caller. Upstream drops
#     it, which is how "MiniMax H3 output fps is fixed at 24" reached an operator
#     as "Video generation failed or its access ended".
#
# nodes.py
#   * VLLMOmniGenerateVideo defaulted fps to 16. MiniMax-H3 rejects anything but
#     24 outright (pipeline_minimax_h3._resolve_shape), so a fresh canvas failed
#     before it could work. Default is now 24.
set -euo pipefail
SUDO_PASS="${1:?usage: patch-comfyui-vllm-omni-node.sh <sudo-password> [--no-restart]}"
RESTART=1
[ "${2:-}" = "--no-restart" ] && RESTART=0
s() { printf '%s\n' "$SUDO_PASS" | sudo -S -k "$@"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/patches/comfyui-vllm-omni"
HOST_DIR=/data/comfyui-patches/omni-video-transport
VOLUME=omni-video-transport-patch
NS=aigc-acceptance-20260915
DEPLOY=comfyui-acceptance
NODE_ROOT=/opt/ComfyUI/custom_nodes/ComfyUI-vLLM-Omni/comfyui_vllm_omni

# module name -> path under NODE_ROOT
MODULES="video_transport.py=utils/video_transport.py
api_client.py=utils/api_client.py
nodes.py=nodes.py"

echo "=== staging the patch files"
s mkdir -p "$HOST_DIR"
while IFS='=' read -r name rel; do
  [ -n "$name" ] || continue
  want="$(md5 -q "$SRC/$name" 2>/dev/null || md5sum "$SRC/$name" | cut -d' ' -f1)"
  s install -m 0644 "$SRC/$name" "$HOST_DIR/$name"
  got="$(s md5sum "$HOST_DIR/$name" | cut -d' ' -f1)"
  [ "$got" = "$want" ] || { echo "$name: staged md5 $got != $want" >&2; exit 1; }
  echo "  $name $got"
done <<< "$MODULES"

echo "=== mounting them over the installed modules"
# The volume is added at most once: `add /-` appends, so adding it per module
# would put two entries with the same name in spec.volumes and the API server
# rejects that. A cluster patched before this script grew a second module already
# carries both the volume and the video_transport.py mount, so each piece is
# checked before it is added.
ensure_volume() {
  if s kubectl -n "$NS" get deploy "$DEPLOY" \
       -o jsonpath="{.spec.template.spec.volumes[?(@.name=='$VOLUME')].name}" | grep -q .; then
    echo "  volume $VOLUME already present"
  else
    s kubectl -n "$NS" patch deploy "$DEPLOY" --type=json -p "$(python3 - "$VOLUME" "$HOST_DIR" <<'PY'
import json, sys
volume, host_dir = sys.argv[1:3]
print(json.dumps([{"op": "add", "path": "/spec/template/spec/volumes/-",
                   "value": {"name": volume, "hostPath": {"path": host_dir, "type": "Directory"}}}]))
PY
)" >/dev/null
    echo "  added volume $VOLUME"
  fi
}

ensure_volume
# Derived from MODULES, not a second hard-coded list: the first draft listed the
# paths again here, so a module added to MODULES was staged and verified but
# never mounted.
while IFS='=' read -r modname rel; do
  [ -n "$rel" ] || continue
  if s kubectl -n "$NS" get deploy "$DEPLOY" \
       -o jsonpath="{.spec.template.spec.containers[0].volumeMounts[?(@.mountPath=='$NODE_ROOT/$rel')].mountPath}" | grep -q .; then
    echo "  $rel already mounted"
  else
    ONE="$(python3 - "$VOLUME" "$NODE_ROOT" "$rel" <<'PY'
import json, sys
volume, node_root, rel = sys.argv[1:4]
name = rel.rsplit("/", 1)[-1]
print(json.dumps([{"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-",
                   "value": {"name": volume, "mountPath": f"{node_root}/{rel}",
                             "subPath": name, "readOnly": True}}]))
PY
)"
    s kubectl -n "$NS" patch deploy "$DEPLOY" --type=json -p "$ONE" >/dev/null
    echo "  mounted $rel"
  fi
done <<< "$MODULES"

# This pod renders video for other people. Recreating it drops whatever the node
# is waiting on, so an occupied queue is a hard stop, not a warning.
QUEUE="$(curl -s -m 10 http://127.0.0.1:5005/queue 2>/dev/null || true)"
BUSY="$(printf '%s' "$QUEUE" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("unknown"); raise SystemExit
print(len(d.get("queue_running",[]))+len(d.get("queue_pending",[])))' 2>/dev/null || echo unknown)"
if [ "$BUSY" != "0" ]; then
  echo "ComfyUI queue is not empty ($BUSY entries); not restarting. Re-run when idle." >&2
  exit 2
fi

if [ "$RESTART" = "1" ]; then
  echo "=== recreating the pod"
  s kubectl -n "$NS" rollout restart deploy "$DEPLOY"
  s kubectl -n "$NS" rollout status deploy "$DEPLOY" --timeout=300s
fi

POD="$(s kubectl -n "$NS" get pods -l app="$DEPLOY" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
echo "=== verifying inside $POD"
while IFS='=' read -r name rel; do
  [ -n "$name" ] || continue
  want="$(md5 -q "$SRC/$name" 2>/dev/null || md5sum "$SRC/$name" | cut -d' ' -f1)"
  live="$(s kubectl -n "$NS" exec "$POD" -c comfyui -- md5sum "$NODE_ROOT/$rel" | cut -d' ' -f1)"
  echo "  $rel live=$live"
  [ "$live" = "$want" ] || { echo "$rel does not match the patch" >&2; exit 1; }
done <<< "$MODULES"
echo "ComfyUI-vLLM-Omni node patches are live"
