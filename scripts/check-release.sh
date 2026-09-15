#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

moon run scripts/check-isolation-test.mbtx
sh scripts/check-isolation.sh
sh scripts/validate-lunaflux-promotion-boundary.sh
sh scripts/deploy/oidc-browser-ingress-manifest-test.sh
sh scripts/deploy/platform-identity-manifest-test.sh
sh scripts/deploy/generate-platform-identity-secrets-test.sh

if rg -n 'image:[[:space:]]+[^@[:space:]]+:(latest|main|master)' deploy >/dev/null; then
  printf '%s\n' 'image scan failed: mutable runtime image tag found' >&2
  exit 1
fi

moon run scripts/check-deployment-secrets-test.mbtx
moon run scripts/check-deployment-secrets.mbtx

printf '%s\n' 'dependency, image, contract, secret, and response scans passed'
