#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-management-secret-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

manifest=$test_directory/management.yaml
"$repo_root/scripts/deploy/generate-management-secrets.sh" "$manifest" >/dev/null
test -f "$manifest"
test "$(stat -f '%Lp' "$manifest" 2>/dev/null || stat -c '%a' "$manifest")" = 600
test "$(rg -c '^kind: Secret$' "$manifest")" -eq 5
for name in lunanexa-control-credentials lunanexa-database lunanexa-cosign-trust lunanexa-offline-commerce-readiness lunanexa-model-source-credentials; do
  rg -q "^  name: $name$" "$manifest"
done
for key in runtime-token operator-token inference-token audit-token monitoring-token assignment-signing-secret catalog-signing-secret exclusive-lease-signing-secret credential-handoff-issuer-secret credential-issuer-adapter-token client-handoff-issuer-secret lease-helper-receipt-secret guide-diagnostics-token api-key-issuer-secret account-session-issuer-secret provider-callback-secret commercial-provider-adapter-token artifact-worker-callback-token artifact-scanner-callback-token entitlement-authority-callback-token guide-admin-auth-key guide-observation-secret; do
  rg -q "^  $key: " "$manifest"
done
if rg -q 'postgresql://|BEGIN (EC )?PRIVATE KEY|BEGIN PUBLIC KEY' "$manifest"; then
  printf '%s\n' 'secret manifest exposed plaintext material' >&2
  exit 1
fi
control_value_count=$(awk '
  /^---$/ { exit }
  /^data:$/ { in_data = 1; next }
  /^(kind|metadata):$/ { in_data = 0 }
  in_data && /^  [A-Za-z0-9._-]+: / { print $2 }
' "$manifest" | wc -l | tr -d ' ')
control_unique_count=$(awk '
  /^---$/ { exit }
  /^data:$/ { in_data = 1; next }
  /^(kind|metadata):$/ { in_data = 0 }
  in_data && /^  [A-Za-z0-9._-]+: / { print $2 }
' "$manifest" | sort -u | wc -l | tr -d ' ')
test "$control_value_count" -eq 22
test "$control_unique_count" -eq "$control_value_count"
awk '
  /^---$/ { exit }
  /^data:$/ { in_data = 1; next }
  /^(kind|metadata):$/ { in_data = 0 }
  in_data && /^  [A-Za-z0-9._-]+: / { print $2 }
' "$manifest" | while IFS= read -r encoded; do
  test "$(printf '%s' "$encoded" | openssl base64 -d -A | wc -c | tr -d ' ')" -eq 64
done
database_password=$(awk '$1 == "password:" { print $2; exit }' "$manifest")
test "$(printf '%s' "$database_password" | openssl base64 -d -A | wc -c | tr -d ' ')" -eq 64
model_source_token=$(awk '$1 == "token:" { print $2; exit }' "$manifest")
test "$(printf '%s' "$model_source_token" | openssl base64 -d -A | wc -c | tr -d ' ')" -eq 64

set +e
"$repo_root/scripts/deploy/generate-management-secrets.sh" "$manifest" >/dev/null 2>&1
overwrite_status=$?
"$repo_root/scripts/deploy/generate-management-secrets.sh" relative.yaml >/dev/null 2>&1
relative_status=$?
set -e
test "$overwrite_status" -ne 0
test "$relative_status" -ne 0

printf '%s\n' 'management secret generator tests passed'
