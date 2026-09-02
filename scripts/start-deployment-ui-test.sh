#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-deployment-ui-start.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_directory/bin"
cat > "$test_directory/bin/moon" <<'EOF'
#!/bin/sh
test "$*" = 'run cmd/installer --target native'
test "${LUNANEXA_INSTALLER_LISTEN_ADDRESS:-}" = '127.0.0.1:4198'
test "${LUNANEXA_INSTALLER_TOKEN:-}" = 'test-session-token-value'
EOF
chmod +x "$test_directory/bin/moon"

token_file=$test_directory/session-token
output_file=$test_directory/output
PATH="$test_directory/bin:$PATH" \
  LUNANEXA_INSTALLER_TOKEN=test-session-token-value \
  LUNANEXA_INSTALLER_TOKEN_FILE="$token_file" \
  sh "$repo_root/scripts/start-deployment-ui.sh" > "$output_file"

test "$(cat "$token_file")" = test-session-token-value
token_mode=$(stat -f '%Lp' "$token_file" 2>/dev/null || stat -c '%a' "$token_file")
test "$token_mode" = 600
grep -q 'Session token written to protected file:' "$output_file"
if grep -q 'test-session-token-value' "$output_file"; then
  printf '%s\n' 'protected token leaked into startup output' >&2
  exit 1
fi

set +e
PATH="$test_directory/bin:$PATH" \
  LUNANEXA_INSTALLER_TOKEN=test-session-token-value \
  LUNANEXA_INSTALLER_TOKEN_FILE="$token_file" \
  sh "$repo_root/scripts/start-deployment-ui.sh" > /dev/null 2>&1
overwrite_status=$?
set -e
test "$overwrite_status" -ne 0

printf '%s\n' 'deployment UI protected-token startup tests passed'
