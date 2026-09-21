#!/bin/bash
# Stop the MiniMax-H3 service from failing its own health check while it encodes
# a video.
#
# serving_video.py calls the CPU-bound MP4 encoder directly on the event loop:
#
#     async def generate_video_bytes(...):
#         ...
#         video_bytes = _encode_video_bytes(artifacts.videos[0], ...)
#     async def generate_videos(...):        # base64 path, same shape
#         video_data = [VideoData(b64_json=encode_video_base64(...)) for ...]
#
# A 481-frame clip takes 102.7 s to encode, and for those 102 s the API server
# answers nothing -- not even /health. The readiness probe then fails, the pod
# leaves its Service endpoints, and every other caller gets 502. Measured on the
# live cluster:
#
#     pod conditions   Ready=False   lastTransition 2026-09-21T11:49:25Z
#     event            Readiness probe failed: ... context deadline exceeded
#     kubectl get endpoints minimaxh3-fl2va   ->  empty
#     curl .../h3/health                      ->  502
#
# patches/vllm-omni-h3/serving_video.py moves both encodes to a worker thread via
# asyncio.to_thread, so the loop keeps serving during the encode. The image layer
# is read-only, so the file is injected through a configmap mounted at
# /serving-video-patch and copied over the installed path by the container's own
# command prefix -- the same channel already used for progress_bar.py.
set -euo pipefail
SUDO_PASS="${1:?usage: patch-vllm-omni-h3-encode.sh <sudo-password> [deployment ...]}"
shift || true
DEPLOYS=("$@")
[ ${#DEPLOYS[@]} -eq 0 ] && DEPLOYS=(minimaxh3-fl2va)
s() { printf '%s\n' "$SUDO_PASS" | sudo -S -k "$@"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/patches/vllm-omni-h3/serving_video.py"
NS=lunanexa
CM=minimaxh3-serving-video-patch
VOL=serving-video-patch
MOUNT=/serving-video-patch
TARGET=/usr/local/lib/python3.12/dist-packages/vllm_omni/entrypoints/openai/serving_video.py
READY_TIMEOUT=1200

expect_md5="$(md5 -q "$SRC" 2>/dev/null || md5sum "$SRC" | cut -d' ' -f1)"

echo "=== publishing the patch as configmap/$CM"
# `sudo -S` reads the password from stdin, so the generated manifest goes to a
# file rather than through a pipe into `kubectl apply -f -`.
CM_YAML="$(mktemp)"
s kubectl -n "$NS" create configmap "$CM" --from-file=serving_video.py="$SRC" \
  --dry-run=client -o yaml > "$CM_YAML"
s kubectl apply -f "$CM_YAML"
rm -f "$CM_YAML"
s kubectl -n "$NS" get cm "$CM" -o jsonpath='{.data.serving_video\.py}' | wc -c

for D in "${DEPLOYS[@]}"; do
  echo "=== $D"

  # An encode is holding the GPU and the job would be lost with the pod. The
  # service is single-slot, so a non-empty queue is a hard stop. Each deployment
  # is fronted by its own proxy location, so the queue to check depends on it.
  case "$D" in
    *ref2va*) PREFIX=/h3r ;;   # reference-to-video
    *)        PREFIX=/h3 ;;    # first/last-frame to video
  esac
  BUSY="$(curl -s -m 10 "http://192.168.2.175:4174$PREFIX/v1/videos" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("unknown"); raise SystemExit
print(sum(1 for v in d.get("data",[]) if v.get("status") in {"queued","in_progress"}))' 2>/dev/null || echo unknown)"
  if [ "$BUSY" != "0" ]; then
    echo "$D has $BUSY queued/in-progress video job(s) on $PREFIX; not restarting." >&2
    exit 2
  fi

  if s kubectl -n "$NS" get deploy "$D" \
       -o jsonpath="{.spec.template.spec.containers[0].volumeMounts[?(@.name=='$VOL')].name}" | grep -q .; then
    echo "mount already present"
  else
    ARGS0="$(s kubectl -n "$NS" get deploy "$D" -o jsonpath='{.spec.template.spec.containers[0].args[0]}')"
    NEW="cp $MOUNT/serving_video.py $TARGET && $ARGS0"
    PATCH="$(python3 - "$VOL" "$CM" "$MOUNT" "$NEW" <<'PY'
import json, sys
vol, cm, mount, newargs = sys.argv[1:5]
print(json.dumps([
    {"op": "add", "path": "/spec/template/spec/volumes/-",
     "value": {"name": vol, "configMap": {"name": cm, "defaultMode": 420}}},
    {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-",
     "value": {"name": vol, "mountPath": mount, "readOnly": True}},
    {"op": "replace", "path": "/spec/template/spec/containers/0/args/0", "value": newargs},
]))
PY
)"
    s kubectl -n "$NS" patch deploy "$D" --type=json -p "$PATCH"
  fi

  echo "=== recreating the pod (startup takes ~8 min on this node)"
  s kubectl -n "$NS" rollout restart deploy "$D"
  s kubectl -n "$NS" rollout status deploy "$D" --timeout="${READY_TIMEOUT}s"

  POD="$(s kubectl -n "$NS" get pods -l app="$D" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
  live_md5="$(s kubectl -n "$NS" exec "$POD" -- md5sum "$TARGET" | cut -d' ' -f1)"
  echo "$D pod $POD md5: $live_md5"
  [ "$live_md5" = "$expect_md5" ] || { echo "installed file does not match the patch" >&2; exit 1; }
  echo "$D patched"
done
