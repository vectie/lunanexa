#!/bin/bash
# Acceptance-environment plumbing, not platform code: ComfyUI lives in the
# aigc-acceptance namespace and is not supervised by LunaNexa.
#
# Publish the LunaNexa H3 workflow templates from the repository to the hostPath
# ComfyUI mounts them from.
#
# The templates used to exist only on the data node, which is how the
# reference-to-video template shipped pointing at the Ref2VA endpoint with no
# image node in it: there was no versioned copy for anyone to notice the hole in.
# comfyui-templates/ beside this script is now the source of truth.
#
# No sudo, unlike its siblings: the destination directory is owned by the
# runtime uid already, and the only network call is ComfyUI on loopback. Using
# `sudo -S` here would also fight a heredoc for stdin.
#
# Sync is one-way and destructive on purpose: a stale file left behind shows up
# in ComfyUI's template browser as a second, older copy of the same preset, so
# anything in the destination that is not in the repository is removed. A
# timestamped archive is taken first.
#
# Templates are read per request, so no ComfyUI restart is needed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/comfyui-templates/lunanexa-h3"
DEST=/data/models/comfyui-templates/lunanexa-h3
CONSOLE=http://127.0.0.1:5005

[ -d "$SRC/example_workflows" ] || { echo "no templates at $SRC/example_workflows" >&2; exit 1; }
# Not `ls | xargs -n1 basename`: xargs splits on whitespace, and these names
# contain spaces and parentheses, so it would hand the loop fragments like
# "16:9）.json". The shell glob already yields one correct word per file.
want=$(for f in "$SRC/example_workflows"/*.json; do basename "$f"; done | sort)

echo "=== backup"
if [ -d "$DEST/example_workflows" ]; then
  BACKUP="/tmp/comfyui-templates-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar czf "$BACKUP" -C "$(dirname "$DEST")" "$(basename "$DEST")"
  echo "  $BACKUP ($(wc -c < "$BACKUP") bytes)"
else
  echo "  nothing to back up yet"
fi

echo "=== publishing"
mkdir -p "$DEST/example_workflows"
install -m 0644 "$SRC/__init__.py" "$DEST/__init__.py"

# Prune before copying, so a renamed template cannot survive under its old name.
for existing in "$DEST/example_workflows"/*.json; do
  [ -e "$existing" ] || continue
  name=$(basename "$existing")
  if ! printf '%s\n' "$want" | grep -qxF "$name"; then
    echo "  prune $name"
    rm -f "$existing"
  fi
done
# Read line by line, not `for name in $want`: these names contain spaces and
# parentheses, so word splitting would break them apart.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  install -m 0644 "$SRC/example_workflows/$name" "$DEST/example_workflows/$name"
done <<< "$want"
ls "$DEST/example_workflows" | sed 's/^/  /'

echo "=== parsing what was published, and checking the image paths"
python3 - "$DEST" <<'PY'
import json, os, sys
root = sys.argv[1]
for name in sorted(os.listdir(os.path.join(root, "example_workflows"))):
    doc = json.load(open(os.path.join(root, "example_workflows", name)))
    gen = next(n for n in doc["nodes"] if n["type"] == "VLLMOmniGenerateVideo")
    img = next(i for i in gen["inputs"] if i["name"] == "image")
    loader = [n for n in doc["nodes"] if n["type"] == "LoadImage"]
    if "图生视频" in name:
        assert loader and img["link"] is not None, name
        link = next(l for l in doc["links"] if l[0] == img["link"])
        assert next(n for n in doc["nodes"] if n["id"] == link[1])["type"] == "LoadImage"
        state = f"图接自「{loader[0]['title']}」"
    else:
        assert not loader, name
        state = "纯文本"
    print(f"  {name[:-5]:<34} ok ({state})")
PY

echo "=== verifying against the running ComfyUI"
got=$(curl -s -m 15 "$CONSOLE/api/workflow_templates" |
  python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin).get("lunanexa-h3", []))))' |
  sed 's/\.json$//' | sort)
expected=$(printf '%s\n' "$want" | sed 's/\.json$//' | sort)
if [ "$got" != "$expected" ]; then
  echo "ComfyUI serves a different set than the repository:" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$got") >&2 || true
  exit 1
fi
printf '%s\n' "$got" | sed 's/^/  /'

echo "templates are live"
