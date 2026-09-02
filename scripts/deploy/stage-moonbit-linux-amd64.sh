#!/bin/sh
set -eu
umask 077

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
destination=$repository_root/_artifacts/moon-linux-amd64
if [ -x "$destination/bin/moon" ] && \
  [ -f "$destination/lib/core/moon.mod" ] && \
  [ -d "$destination/registry/index" ] && \
  [ -d "$destination/registry/cache" ]; then
  printf '%s\n' 'official MoonBit linux-amd64 toolchain already staged'
  exit 0
fi

command -v curl >/dev/null
command -v shasum >/dev/null
command -v tar >/dev/null
registry_source=${MOON_HOME:-$HOME/.moon}/registry
test -d "$registry_source/index"
test -d "$registry_source/cache"

toolchain_sha256=b8f9273653f9af49c447775a7ecc7d20a2784849a15fe489a03afd6718c75d0d
core_sha256=5e5a3bdb0679250979808c4f0fc5b373261ab55632f1890660bfc914543f3276
work_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-moonbit-amd64.XXXXXX")
cleanup() { rm -rf "$work_directory"; }
trap cleanup EXIT HUP INT TERM

curl --fail --location --show-error \
  --output "$work_directory/toolchain.tar.gz" \
  https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz
curl --fail --location --show-error \
  --output "$work_directory/core.tar.gz" \
  https://cli.moonbitlang.com/cores/core-latest.tar.gz
printf '%s  %s\n' "$toolchain_sha256" "$work_directory/toolchain.tar.gz" \
  | shasum -a 256 -c -
printf '%s  %s\n' "$core_sha256" "$work_directory/core.tar.gz" \
  | shasum -a 256 -c -

staged=$work_directory/moon-linux-amd64
mkdir -p "$staged/lib"
tar xf "$work_directory/toolchain.tar.gz" -C "$staged"
tar xf "$work_directory/core.tar.gz" -C "$staged/lib"
cp -R "$registry_source" "$staged/registry"
find "$staged" -type f -name '._*' -delete
chmod +x "$staged"/bin/* "$staged/bin/internal/tcc"
mkdir -p "$repository_root/_artifacts"
mv "$staged" "$destination"
printf '%s\n' 'staged checksum-pinned official MoonBit linux-amd64 toolchain; run finalize-moonbit-linux-amd64.sh on Linux before a bare-host build'
