#!/bin/sh
set -eu
umask 077

output=${1:-}
input_directory=${2:-}
management_namespace=${3:-}
identity_namespace=${4:-}
case "$output" in /*) ;; *) printf '%s\n' 'usage: generate-platform-identity-secrets.sh /ABSOLUTE/NEW/FILE.yaml /ABSOLUTE/INPUT_DIR MANAGEMENT_NAMESPACE IDENTITY_NAMESPACE' >&2; exit 64 ;; esac
case "$input_directory" in /*) ;; *) exit 64 ;; esac
case "/$output/" in */../*) exit 64 ;; esac
case "/$input_directory/" in */../*) exit 64 ;; esac
case "$management_namespace" in ''|*[!A-Za-z0-9._-]*) exit 64 ;; esac
case "$identity_namespace" in ''|*[!A-Za-z0-9._-]*) exit 64 ;; esac
test "$management_namespace" != "$identity_namespace"
test ! -e "$output"
test ! -L "$output"
test -d "$input_directory"
command -v kubectl >/dev/null
command -v openssl >/dev/null

for name in database-username database-password smtp-host smtp-port smtp-username smtp-password smtp-from; do
  test -f "$input_directory/$name"
  test ! -L "$input_directory/$name"
  test -s "$input_directory/$name"
done
smtp_port=$(tr -d '\r\n' < "$input_directory/smtp-port")
case "$smtp_port" in ''|*[!0-9]*) exit 64 ;; esac
test "$smtp_port" -gt 0
test "$smtp_port" -le 65535

work_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-platform-identity-secrets.XXXXXX")
cleanup() { rm -rf "$work_directory"; }
trap cleanup EXIT HUP INT TERM
gateway_directory=$work_directory/gateway
realm_directory=$work_directory/realm
mkdir -m 0700 "$gateway_directory" "$realm_directory"

printf '%s' lunanexa-operator > "$gateway_directory/operator-client-id"
printf '%s' lunanexa-enterprise > "$gateway_directory/enterprise-client-id"
for name in operator-client-secret enterprise-client-secret operator-cookie-secret enterprise-cookie-secret identity-assertion-secret; do
  openssl rand -hex 32 | tr -d '\n' > "$gateway_directory/$name"
done
cp "$gateway_directory/operator-client-secret" "$realm_directory/operator-client-secret"
cp "$gateway_directory/enterprise-client-secret" "$realm_directory/enterprise-client-secret"
for name in smtp-host smtp-port smtp-username smtp-password smtp-from; do
  tr -d '\r\n' < "$input_directory/$name" > "$realm_directory/$name"
done

set --
for secret_file in "$gateway_directory"/*; do
  secret_name=${secret_file##*/}
  set -- "$@" "--from-file=$secret_name=$secret_file"
done
kubectl create secret generic lunanexa-identity-ingress-credentials "$@" \
  --namespace "$management_namespace" --dry-run=client -o yaml \
  > "$work_directory/gateway.yaml"
kubectl create secret generic lunanexa-platform-idp-database \
  --from-file=username="$input_directory/database-username" \
  --from-file=password="$input_directory/database-password" \
  --namespace "$identity_namespace" --dry-run=client -o yaml \
  > "$work_directory/database.yaml"
set --
for secret_file in "$realm_directory"/*; do
  secret_name=${secret_file##*/}
  set -- "$@" "--from-file=$secret_name=$secret_file"
done
kubectl create secret generic lunanexa-platform-idp-realm-secrets "$@" \
  --namespace "$identity_namespace" --dry-run=client -o yaml \
  > "$work_directory/realm.yaml"

output_next=$output.next
awk 'FNR == 1 && NR != 1 { print "---" } { print }' \
  "$work_directory/gateway.yaml" "$work_directory/database.yaml" \
  "$work_directory/realm.yaml" > "$output_next"
chmod 0600 "$output_next"
mv "$output_next" "$output"
printf 'generated protected platform identity secret manifest: %s\n' "$output"
