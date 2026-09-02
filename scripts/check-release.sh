#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

sh scripts/check-isolation.sh
sh scripts/validate-lunaflux-promotion-boundary.sh
sh scripts/deploy/oidc-browser-ingress-manifest-test.sh

if rg -n 'image:[[:space:]]+[^@[:space:]]+:(latest|main|master)' deploy >/dev/null; then
  printf '%s\n' 'image scan failed: mutable runtime image tag found' >&2
  exit 1
fi

if rg -n -i '(password|token|secret)[[:space:]]*[:=][[:space:]]*[^$<{[:space:]][^[:space:]]+' \
  deploy tests/fixtures | \
  rg -v 'automountServiceAccountToken:[[:space:]]*false|nginx.ingress.kubernetes.io/auth-tls-secret:' >/dev/null; then
  printf '%s\n' 'secret scan failed: possible literal secret found' >&2
  exit 1
fi

printf '%s\n' 'dependency, image, contract, secret, and response scans passed'
