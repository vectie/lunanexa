#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-platform-identity-secret-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM
input_directory=$test_directory/input
mkdir -m 0700 "$input_directory"
printf '%s' keycloak > "$input_directory/database-username"
printf '%s' 'database-password-from-secret-manager' > "$input_directory/database-password"
printf '%s' smtp.example.test > "$input_directory/smtp-host"
printf '%s' 587 > "$input_directory/smtp-port"
printf '%s' smtp-user > "$input_directory/smtp-username"
printf '%s' 'smtp-password-from-secret-manager' > "$input_directory/smtp-password"
printf '%s' no-reply@example.test > "$input_directory/smtp-from"

manifest=$test_directory/platform-secrets.yaml
"$repo_root/scripts/deploy/generate-platform-identity-secrets.sh" \
  "$manifest" "$input_directory" lunanexa lunanexa-identity >/dev/null
test -f "$manifest"
test "$(stat -f '%Lp' "$manifest" 2>/dev/null || stat -c '%a' "$manifest")" = 600
test "$(rg -c '^kind: Secret$' "$manifest")" -eq 3
for expected in \
  'namespace: lunanexa' \
  'namespace: lunanexa-identity' \
  'name: lunanexa-identity-ingress-credentials' \
  'name: lunanexa-platform-idp-database' \
  'name: lunanexa-platform-idp-realm-secrets' \
  'identity-assertion-secret:' \
  'operator-cookie-secret:' \
  'enterprise-cookie-secret:' \
  'smtp-password:'; do
  rg -q "$expected" "$manifest"
done
if rg -q 'database-password-from-secret-manager|smtp-password-from-secret-manager|BEGIN .*PRIVATE KEY' "$manifest"; then
  printf '%s\n' 'platform identity secret manifest exposed plaintext material' >&2
  exit 1
fi
operator_count=$(awk '$1 == "operator-client-secret:" { print $2 }' "$manifest" | wc -l | tr -d ' ')
operator_unique=$(awk '$1 == "operator-client-secret:" { print $2 }' "$manifest" | sort -u | wc -l | tr -d ' ')
enterprise_count=$(awk '$1 == "enterprise-client-secret:" { print $2 }' "$manifest" | wc -l | tr -d ' ')
enterprise_unique=$(awk '$1 == "enterprise-client-secret:" { print $2 }' "$manifest" | sort -u | wc -l | tr -d ' ')
test "$operator_count" -eq 2
test "$operator_unique" -eq 1
test "$enterprise_count" -eq 2
test "$enterprise_unique" -eq 1

set +e
"$repo_root/scripts/deploy/generate-platform-identity-secrets.sh" \
  "$manifest" "$input_directory" lunanexa lunanexa-identity >/dev/null 2>&1
overwrite_status=$?
"$repo_root/scripts/deploy/generate-platform-identity-secrets.sh" \
  "$test_directory/invalid.yaml" relative lunanexa lunanexa-identity >/dev/null 2>&1
relative_status=$?
set -e
test "$overwrite_status" -ne 0
test "$relative_status" -ne 0

printf '%s\n' 'platform identity secret generator tests passed'
