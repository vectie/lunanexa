#!/bin/sh

set -eu

tag=${1:-}
case "$tag" in
  ''|*[!A-Za-z0-9._-]*)
    printf '%s\n' 'usage: build-coursebook-image.sh SAFE_TAG [DOCKER_BUILD_ARGUMENT ...]' >&2
    exit 64
    ;;
esac
shift

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
build_context=$(mktemp -d /tmp/lunanexa-coursebook-context.XXXXXX)
cleanup() {
  rm -rf "$build_context"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$build_context/images" "$build_context/docs-site/images"
cp "$repository_root/images/nginx.docs.conf" "$build_context/images/"
for source in \
  index.html styles.css app.js \
  admin.html admin.js admin.css \
  coursebook.json coursebook.zh-CN.json coursebook-evidence.json; do
  cp "$repository_root/docs-site/$source" "$build_context/docs-site/$source"
done
cp -R "$repository_root/docs-site/images/." "$build_context/docs-site/images/"

docker build --platform linux/amd64 \
  --network host \
  "$@" \
  --file "$repository_root/images/Containerfile.docs-static" \
  --tag "lunanexa/coursebook-static:$tag" \
  "$build_context"

printf 'built coursebook image with tag %s from minimal context\n' "$tag"
