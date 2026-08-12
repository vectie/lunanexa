#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

moon info
moon fmt
moon check --target native --warn-list +73 --deny-warn
moon test --target native --warn-list +73 --deny-warn
sh scripts/check-release.sh
