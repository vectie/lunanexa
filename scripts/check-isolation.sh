#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

source_files=$(find . -type f \( -name '*.mbt' -o -name 'moon.pkg' -o -name 'moon.mod' \) \
  ! -path './_build/*' ! -path './target/*')

if printf '%s\n' "$source_files" | xargs rg -n -i \
  '(^|["/])(moongate|moonsuite|moonclaw|moondesk|moontown)(["/]|$)' >/dev/null; then
  printf '%s\n' 'isolation check failed: product-specific dependency found' >&2
  exit 1
fi

if printf '%s\n' "$source_files" | xargs rg -n \
  '(container_id|stack_trace|node_address|filesystem_path|provider_credential)' >/dev/null; then
  printf '%s\n' 'response leak check failed: forbidden internal field found' >&2
  exit 1
fi

printf '%s\n' 'isolation and public-response scans passed'

