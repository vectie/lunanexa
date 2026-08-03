#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

moon info
moon fmt
moon check --target native --deny-warn
moon test --target native --deny-warn
sh scripts/check-release.sh
