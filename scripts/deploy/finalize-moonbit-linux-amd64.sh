#!/bin/sh
set -eu

toolchain=${1:-}
case "$toolchain" in
  /*) ;;
  *) printf '%s\n' 'usage: finalize-moonbit-linux-amd64.sh ABSOLUTE_TOOLCHAIN_ROOT' >&2; exit 64 ;;
esac

test "$(uname -s)" = Linux || {
  printf '%s\n' 'MoonBit linux-amd64 finalization must run on Linux' >&2
  exit 1
}
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) printf '%s\n' 'MoonBit linux-amd64 finalization requires x86_64' >&2; exit 1 ;;
esac

test -x "$toolchain/bin/moon"
test -f "$toolchain/lib/core/moon.mod"
if [ -f "$toolchain/lib/core/_build/native/release/bundle/prelude/prelude.mi" ]; then
  printf '%s\n' 'MoonBit native core bundle already finalized'
  exit 0
fi

MOON_HOME=$toolchain
PATH="$toolchain/bin:$PATH"
export MOON_HOME PATH
"$toolchain/bin/moon" -C "$toolchain/lib/core" bundle \
  --warn-list -a --target native
test -f "$toolchain/lib/core/_build/native/release/bundle/prelude/prelude.mi"
printf '%s\n' 'finalized MoonBit native core bundle for linux-amd64'
