#!/bin/sh
set -eu
umask 077

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
destination=$repository_root/_artifacts/zig-linux-amd64
if [ -x "$destination/zig" ]; then
  printf '%s\n' 'official Zig 0.16.0 linux-amd64 compiler already staged'
  exit 0
fi

command -v curl >/dev/null
command -v shasum >/dev/null
command -v tar >/dev/null
archive_sha256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
work_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-zig-amd64.XXXXXX")
cleanup() { rm -rf "$work_directory"; }
trap cleanup EXIT HUP INT TERM

archive=$work_directory/zig.tar.xz
curl --fail --location --show-error --output "$archive" \
  https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz
printf '%s  %s\n' "$archive_sha256" "$archive" | shasum -a 256 -c -
staged=$work_directory/zig-linux-amd64
mkdir -p "$staged"
tar xf "$archive" -C "$staged" --strip-components=1
chmod +x "$staged/zig"
mkdir -p "$repository_root/_artifacts"
mv "$staged" "$destination"
printf '%s\n' 'staged checksum-pinned official Zig 0.16.0 linux-amd64 compiler'
