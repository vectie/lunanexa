#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

moon info
moon fmt
moon check --target native --warn-list +73 --deny-warn
moon run scripts/test-native.mbtx
sh scripts/check-release.sh
