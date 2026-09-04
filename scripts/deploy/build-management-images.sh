#!/bin/sh
set -eu

tag=${1:-}
case "$tag" in
  ''|*[!A-Za-z0-9._-]*)
    printf '%s\n' 'usage: build-management-images.sh SAFE_TAG' >&2
    exit 64
    ;;
esac

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repository_root"

sh scripts/build-browser-bundles.sh
sh scripts/deploy/stage-moonbit-linux-amd64.sh
sh scripts/deploy/stage-zig-linux-amd64.sh
if [ -n "${LUNANEXA_BUILD_HTTPS_PROXY:-}" ]; then
  set -- \
    --build-arg "HTTPS_PROXY=$LUNANEXA_BUILD_HTTPS_PROXY" \
    --build-arg "https_proxy=$LUNANEXA_BUILD_HTTPS_PROXY" \
    --build-arg "HTTP_PROXY=$LUNANEXA_BUILD_HTTPS_PROXY" \
    --build-arg "http_proxy=$LUNANEXA_BUILD_HTTPS_PROXY"
else
  set --
fi
docker build --platform linux/amd64 \
  --network host \
  "$@" \
  --file images/Containerfile.control \
  --tag "lunanexa/control:$tag" .
docker build --platform linux/amd64 \
  --network host \
  "$@" \
  --file images/Containerfile.identity-gateway \
  --tag "lunanexa/identity-gateway:$tag" .
docker build --platform linux/amd64 \
  --network host \
  "$@" \
  --file images/Containerfile.web \
  --tag "lunanexa/web:$tag" .
docker build --platform linux/amd64 \
  --network host \
  "$@" \
  --file images/Containerfile.model-source \
  --tag "lunanexa/model-source:$tag" .
docker build --platform linux/amd64 \
  --network host \
  "$@" \
  --file images/Containerfile.workbench-web \
  --tag "lunanexa/workbench-web:$tag" .
sh scripts/deploy/build-coursebook-image.sh "$tag" "$@"

printf 'built management images with tag %s\n' "$tag"
