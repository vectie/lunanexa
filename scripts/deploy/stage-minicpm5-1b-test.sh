#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script=$repo_root/scripts/deploy/stage-minicpm5-1b.sh
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-minicpm-stage-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

sh -n "$script"
sh "$script" --plan > "$test_directory/plan"
grep -q '^revision=fc2e73f63bbf2cce5739929c2bebbb046fbfae8d$' "$test_directory/plan"
grep -q '^approval_state=StagingOnly$' "$test_directory/plan"
grep -q '^\.gitattributes|1591|4a924f9f3caa6ec3c6076c1052483e7e3275490e92c0bf6a8defd23fbf4281e1$' "$test_directory/plan"
grep -q '^README.md|23472|b032e36400dc26ba8d78aa5ad63e4cf8bd17f70bf8551e500335185d8e7d061a$' "$test_directory/plan"
grep -q '^model-00000-of-00001.safetensors|2161290912|7ab8fd86563125929be78aeec8cb3969c7ed2ead3be1ab9d3ec0a9fa69c8660d$' "$test_directory/plan"
grep -q '^tokenizer.json|9894271|3e065a558a034185fe299917b398685c1facd0169a9eea1e629eb30c171fed81$' "$test_directory/plan"

if sh "$script" --download --destination relative/path > "$test_directory/relative" 2>&1; then
  printf '%s\n' 'relative destination was accepted' >&2
  exit 1
fi
grep -q 'destination must be an absolute path' "$test_directory/relative"

fake_bin=$test_directory/bin
mkdir -p "$fake_bin" "$test_directory/download"
printf '%s\n' '#!/bin/sh' 'exit 22' > "$fake_bin/curl"
chmod +x "$fake_bin/curl"
if PATH="$fake_bin:/usr/bin:/bin" sh "$script" --download \
  --destination "$test_directory/download" > "$test_directory/failure" 2>&1; then
  printf '%s\n' 'failed download was accepted' >&2
  exit 1
fi
test ! -e "$test_directory/download/staging-evidence.json"
grep -q '^\[download\] .gitattributes$' "$test_directory/failure"

printf '%s\n' 'MiniCPM pinned staging recipe tests passed'
