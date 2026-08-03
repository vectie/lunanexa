#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

moon build cmd/evidence --target native
binary="$repo_root/_build/native/debug/build/cmd/evidence/evidence.exe"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-evidence-export.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT INT TERM

"$binary" bundle \
  tests/fixtures/telemetry-evidence.v1.json \
  tests/fixtures/evidence-input.v1.json \
  "$test_directory/evidence.json"
"$binary" recommend \
  tests/fixtures/telemetry-evidence.v1.json \
  tests/fixtures/recommendation-input.v1.json \
  "$test_directory/recommendation.json"

rg -q '"release_version": "0.1.0-test"' "$test_directory/evidence.json"
rg -q '"accepted_by": "test-acceptor"' "$test_directory/evidence.json"
rg -q '"objective_met": true' "$test_directory/recommendation.json"
rg -q '"memory_headroom_mib": 4000' "$test_directory/recommendation.json"

printf '%s\n' 'evidence bundle and recommendation export checks passed'
