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

printf '%s\n' 'MoonLeaf browser scene matches the authoritative fillable DOCX'
