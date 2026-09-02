#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-node-material-test.XXXXXX")
stage=$(mktemp -d /tmp/lunanexa-install-compute-01.XXXXXX)
cleanup() { rm -rf "$test_directory" "$stage"; }
trap cleanup EXIT HUP INT TERM

fake_bin=$test_directory/bin
log=$test_directory/install.log
mkdir -p "$fake_bin"

for command_name in id getent stat install rm rmdir systemctl; do
  case "$command_name" in
    id) body='printf "%s\n" 0' ;;
    getent) body='exit 0' ;;
    stat) body='if [ "${2:-}" = "%U" ] || [ "${1:-}" = "%U" ]; then printf "%s\n" "${SUDO_USER:-tester}"; elif [ "${3:-}" = "'"$stage"'" ] || [ "${2:-}" = "'"$stage"'" ]; then printf "%s\n" 700; else printf "%s\n" "${TEST_SOURCE_MODE:-600}"; fi' ;;
    install) body='printf "%s\n" "$*" >> "${TEST_INSTALL_LOG:?}"' ;;
    rm|rmdir|systemctl) body='exit 0' ;;
  esac
  printf '%s\n%s\n' '#!/bin/sh' "$body" > "$fake_bin/$command_name"
  chmod +x "$fake_bin/$command_name"
done

for name in node-token assignment-verification-key cosign.pub inventory.json bootstrap-token-id bootstrap-token; do
  : > "$stage/$name"
done

PATH="$fake_bin:/usr/bin:/bin" TEST_INSTALL_LOG="$log" SUDO_USER=tester \
  sh "$repo_root/scripts/deploy/install-node-material.sh" --check \
  > "$test_directory/check.log"
grep -q '^\[ok\] LunaNexa node-material helper is ready$' "$test_directory/check.log"

PATH="$fake_bin:/usr/bin:/bin" TEST_INSTALL_LOG="$log" SUDO_USER=tester \
  sh "$repo_root/scripts/deploy/install-node-material.sh" "$stage" \
  > "$test_directory/apply.log"

grep -q -- '-d -o root -g lunanexa -m 0750 /etc/lunanexa$' "$log"
grep -q -- '-d -o lunanexa -g lunanexa -m 0750 /var/lib/lunanexa$' "$log"
grep -q -- '-o root -g lunanexa -m 0640 .*/node-token /etc/lunanexa/node-token$' "$log"
grep -q -- '-o root -g lunanexa -m 0644 .*/cosign.pub /etc/lunanexa/cosign.pub$' "$log"

set +e
PATH="$fake_bin:/usr/bin:/bin" TEST_INSTALL_LOG="$log" TEST_SOURCE_MODE=666 SUDO_USER=tester \
  sh "$repo_root/scripts/deploy/install-node-material.sh" "$stage" \
  > "$test_directory/unsafe.log" 2>&1
unsafe_status=$?
set -e
test "$unsafe_status" -ne 0
grep -q '^refusing unsafe source mode for node-token$' "$test_directory/unsafe.log"

printf '%s\n' 'node material privilege and permission tests passed'
