#!/bin/bash
# Acceptance-environment plumbing, not platform code: ComfyUI lives in the
# aigc-acceptance namespace and is not supervised by LunaNexa.
#
# Stop the video node from aborting clips it has already generated.
#
# The node's control-plane client is built with a 60 s whole-request budget
# (nodes.py:217 -> api_client.py:73 -> aiohttp.ClientTimeout(total=60)). The
# MiniMax-H3 service encodes the MP4 inside the final GET /videos/<id>/content
# request instead of ahead of it, and that encode takes 102.7 s for a 20 s clip
# (serving_video.py:347 logs the duration). So the download always lost a race
# it had already won, and the finally-block DELETE then destroyed the finished
# video: 404 on every retry.
#
# patches/comfyui-vllm-omni/video_transport.py separates the download timeout
# from the control-plane timeout and leaves a completed-but-undelivered job in
# place. The node directory is baked into the image behind a read-only root
# filesystem, so the patch is mounted over the single file with hostPath +
# subPath; no image rebuild, no other byte of the node changes.
set -euo pipefail
SUDO_PASS="${1:?usage: patch-comfyui-video-transport.sh <sudo-password> [--no-restart]}"
RESTART=1
[ "${2:-}" = "--no-restart" ] && RESTART=0
s() { printf '%s\n' "$SUDO_PASS" | sudo -S -k "$@"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/patches/comfyui-vllm-omni/video_transport.py"
HOST_DIR=/data/comfyui-patches/omni-video-transport
VOLUME=omni-video-transport-patch
NS=aigc-acceptance-20260915
DEPLOY=comfyui-acceptance
TARGET=/opt/ComfyUI/custom_nodes/ComfyUI-vLLM-Omni/comfyui_vllm_omni/utils/video_transport.py

expect_md5="$(md5 -q "$SRC" 2>/dev/null || md5sum "$SRC" | cut -d' ' -f1)"

echo "=== staging the patch file"
s mkdir -p "$HOST_DIR"
s install -m 0644 "$SRC" "$HOST_DIR/video_transport.py"
host_md5="$(s md5sum "$HOST_DIR/video_transport.py" | cut -d' ' -f1)"
[ "$host_md5" = "$expect_md5" ] || { echo "patch file md5 $host_md5 != $expect_md5" >&2; exit 1; }
echo "host md5 ok: $host_md5"

echo "=== mounting it over the node's file"
if s kubectl -n "$NS" get deploy "$DEPLOY" \
     -o jsonpath="{.spec.template.spec.volumes[?(@.name=='$VOLUME')].name}" | grep -q .; then
  echo "mount already present; a restart is still needed for a changed file"
else
  s kubectl -n "$NS" patch deploy "$DEPLOY" --type=strategic -p "$(cat <<JSON
{"spec":{"template":{"spec":{
  "volumes":[{"name":"$VOLUME","hostPath":{"path":"$HOST_DIR","type":"Directory"}}],
  "containers":[{"name":"comfyui","volumeMounts":[{"name":"$VOLUME","mountPath":"$TARGET","subPath":"video_transport.py","readOnly":true}]}]}}}}
JSON
)"
fi

# This pod renders video for other people. Recreating it drops whatever the
# node is waiting on, so an occupied queue is a hard stop, not a warning.
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
  s kubectl -n "$NS" rollout status deploy "$DEPLOY" --timeout=180s
fi

POD="$(s kubectl -n "$NS" get pods -l app="$DEPLOY" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
live_md5="$(s kubectl -n "$NS" exec "$POD" -c comfyui -- md5sum "$TARGET" | cut -d' ' -f1)"
echo "pod $POD md5: $live_md5"
[ "$live_md5" = "$expect_md5" ] || { echo "mounted file does not match the patch" >&2; exit 1; }
echo "video transport patch is live"
