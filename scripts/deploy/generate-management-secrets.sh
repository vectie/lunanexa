#!/bin/sh
set -eu
umask 077

output=${1:-}
case "$output" in /*) ;; *) printf '%s\n' 'usage: generate-management-secrets.sh /ABSOLUTE/NEW/FILE.yaml' >&2; exit 64 ;; esac
case "/$output/" in */../*) exit 64 ;; esac
test ! -e "$output"
test ! -L "$output"
command -v kubectl >/dev/null
command -v openssl >/dev/null

work_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-management-secrets.XXXXXX")
cleanup() { rm -rf "$work_directory"; }
trap cleanup EXIT HUP INT TERM

credentials_directory=$work_directory/control
database_directory=$work_directory/database
trust_directory=$work_directory/trust
model_source_directory=$work_directory/model-source
mkdir -m 0700 "$credentials_directory" "$database_directory" "$trust_directory" \
  "$model_source_directory"

for name in \
  runtime-token operator-token inference-token audit-token monitoring-token \
  assignment-signing-secret catalog-signing-secret exclusive-lease-signing-secret \
  credential-handoff-issuer-secret client-handoff-issuer-secret lease-helper-receipt-secret \
  guide-diagnostics-token api-key-issuer-secret account-session-issuer-secret \
  provider-callback-secret \
  artifact-worker-callback-token artifact-scanner-callback-token \
  entitlement-authority-callback-token guide-admin-auth-key guide-observation-secret; do
  openssl rand -hex 32 | tr -d '\n' > "$credentials_directory/$name"
done
openssl rand -hex 32 | tr -d '\n' > "$model_source_directory/token"

printf '%s' lunanexa > "$database_directory/database"
printf '%s' lunanexa > "$database_directory/username"
openssl rand -hex 32 | tr -d '\n' > "$database_directory/password"
database_password=$(tr -d '\n' < "$database_directory/password")
printf 'postgresql://lunanexa:%s@lunanexa-postgres:5432/lunanexa?sslmode=disable' \
  "$database_password" > "$database_directory/url"

openssl ecparam -name prime256v1 -genkey -noout -out "$trust_directory/cosign.key"
openssl ec -in "$trust_directory/cosign.key" -pubout -out "$trust_directory/cosign.pub" >/dev/null 2>&1
printf '%s' pending > "$work_directory/offline-readiness-pending"

set --
for secret_file in "$credentials_directory"/*; do
  secret_name=${secret_file##*/}
  set -- "$@" "--from-file=$secret_name=$secret_file"
done
kubectl create secret generic lunanexa-control-credentials "$@" \
  --dry-run=client -o yaml > "$work_directory/control.yaml"
kubectl create secret generic lunanexa-database \
  --from-file=database="$database_directory/database" \
  --from-file=username="$database_directory/username" \
  --from-file=password="$database_directory/password" \
  --from-file=url="$database_directory/url" \
  --dry-run=client -o yaml > "$work_directory/database.yaml"
kubectl create secret generic lunanexa-cosign-trust \
  --from-file=cosign.pub="$trust_directory/cosign.pub" \
  --dry-run=client -o yaml > "$work_directory/cosign.yaml"
kubectl create secret generic lunanexa-offline-commerce-readiness \
  --from-file=pending="$work_directory/offline-readiness-pending" \
  --dry-run=client -o yaml > "$work_directory/offline.yaml"
kubectl create secret generic lunanexa-model-source-credentials \
  --from-file=token="$model_source_directory/token" \
  --dry-run=client -o yaml > "$work_directory/model-source.yaml"

output_next=$output.next
awk 'FNR == 1 && NR != 1 { print "---" } { print }' \
  "$work_directory/control.yaml" "$work_directory/database.yaml" \
  "$work_directory/cosign.yaml" "$work_directory/offline.yaml" \
  "$work_directory/model-source.yaml" > "$output_next"
chmod 0600 "$output_next"
mv "$output_next" "$output"
printf 'generated protected management secret manifest: %s\n' "$output"
