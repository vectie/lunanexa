#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
output_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-node-linux-amd64.XXXXXX")
final_binary=$repository_root/_artifacts/lunanexa-node-linux-amd64
docker_context=${LUNANEXA_AMD64_DOCKER_CONTEXT:-}
artifact_image=lunanexa/node-artifact:local
artifact_container=
docker_for_build() {
  if [ -n "$docker_context" ]; then
    docker --context "$docker_context" "$@"
  else
    docker "$@"
  fi
}
cleanup() {
  if [ -n "$artifact_container" ]; then
    docker_for_build rm -f "$artifact_container" >/dev/null 2>&1 || true
  fi
  rm -rf "$output_directory"
}
trap cleanup EXIT HUP INT TERM

case "$(docker_for_build info --format '{{.Architecture}}')" in
  x86_64|amd64) ;;
  *)
    printf '%s\n' '[blocked] node artifact build requires a native x86_64 Docker builder; select it with LUNANEXA_AMD64_DOCKER_CONTEXT' >&2
    exit 1
    ;;
esac

sh "$repository_root/scripts/deploy/stage-moonbit-linux-amd64.sh"
sh "$repository_root/scripts/deploy/stage-zig-linux-amd64.sh"
docker_for_build build --network host --target artifact --tag "$artifact_image" \
  --file "$repository_root/images/Containerfile.node-artifact" "$repository_root"
artifact_container=$(docker_for_build create "$artifact_image")
docker_for_build cp "$artifact_container:/lunanexa-node" "$output_directory/lunanexa-node"
test -f "$output_directory/lunanexa-node"
install -m 0755 "$output_directory/lunanexa-node" "$final_binary"
file "$final_binary" | grep -q 'ELF 64-bit.*x86-64'
shasum -a 256 "$final_binary"
