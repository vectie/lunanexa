#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root=${1:-"$repo_root/_build/browser-dist"}

cd "$repo_root"
moon build cmd/console cmd/workbench --target js --release

mkdir -p "$output_root/console" "$output_root/workbench"
cp cmd/console/index.html "$output_root/console/index.html"
cp _build/js/release/build/cmd/console/console.js "$output_root/console/console.js"
cp cmd/workbench/index.html "$output_root/workbench/index.html"
cp _build/js/release/build/cmd/workbench/workbench.js "$output_root/workbench/workbench.js"

test -s "$output_root/console/index.html"
test -s "$output_root/console/console.js"
test -s "$output_root/workbench/index.html"
test -s "$output_root/workbench/workbench.js"

printf '%s\n' "browser bundles ready at $output_root"
