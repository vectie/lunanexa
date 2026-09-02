#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script=$repository_root/scripts/deploy/finalize-moonbit-linux-amd64.sh
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-moonbit-finalize-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_directory/bin" "$test_directory/toolchain/bin" \
  "$test_directory/toolchain/lib/core"
printf '%s\n' 'name = "moonbitlang/core"' > "$test_directory/toolchain/lib/core/moon.mod"

cat > "$test_directory/bin/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
  *) exit 64 ;;
esac
EOF
cat > "$test_directory/toolchain/bin/moon" <<'EOF'
#!/bin/sh
set -eu
test "${1:-}" = -C
core=${2:-}
shift 2
test "$*" = 'bundle --warn-list -a --target native'
mkdir -p "$core/_build/native/release/bundle/prelude"
: > "$core/_build/native/release/bundle/prelude/prelude.mi"
EOF
chmod +x "$test_directory/bin/uname" "$test_directory/toolchain/bin/moon"

PATH="$test_directory/bin:$PATH" sh "$script" "$test_directory/toolchain" \
  | grep -q '^finalized MoonBit native core bundle for linux-amd64$'
PATH="$test_directory/bin:$PATH" sh "$script" "$test_directory/toolchain" \
  | grep -q '^MoonBit native core bundle already finalized$'
test -f "$test_directory/toolchain/lib/core/_build/native/release/bundle/prelude/prelude.mi"
printf '%s\n' 'MoonBit linux-amd64 finalizer tests passed'
