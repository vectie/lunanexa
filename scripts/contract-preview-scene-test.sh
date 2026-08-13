#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

expected="assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json"
source_docx="assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx"
generated=$(mktemp /tmp/lunanexa-contract-preview.XXXXXX)
trap 'rm -f "$generated"' EXIT HUP INT TERM

moon run cmd/contract-preview-scene --target native -- "$source_docx" "$generated"
cmp "$generated" "$expected"

jq -e '
  . as $root |
  .scene.engine == "moonleaf" and
  (.scene.pages | length) == 18 and
  ([14, 15, 16, 17, 18] | all(. as $page |
    ($page - 1) as $index |
    ([$root.scene.pages[$index][] | .runs[]?.text] | join("")) |
    startswith("文件\($page - 12)：")
  )) and
  ([.scene.pages[15][] | select(.kind == "table") | .rows[].cells[]] |
    any(.grid_span > 1)) and
  ([.scene.pages[17][] | select(.kind == "table") | .rows[].cells[]] |
    any(.vertical_merge == "restart"))
' "$expected" >/dev/null

printf '%s\n' 'MoonLeaf browser scene matches the authoritative 18-page fillable DOCX'
