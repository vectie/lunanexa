#!/bin/sh
set -eu
umask 077

output= management_manifest= management_namespace= identity_namespace=
identity_host= operator_host= enterprise_host= database_host= database_name=
gateway_image= keycloak_image= identity_edge_image= identity_ingress_host=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output=$2; shift 2 ;;
    --management-manifest) management_manifest=$2; shift 2 ;;
    --management-namespace) management_namespace=$2; shift 2 ;;
    --identity-namespace) identity_namespace=$2; shift 2 ;;
    --identity-host) identity_host=$2; shift 2 ;;
    --identity-ingress-host) identity_ingress_host=$2; shift 2 ;;
    --operator-host) operator_host=$2; shift 2 ;;
    --enterprise-host) enterprise_host=$2; shift 2 ;;
    --database-host) database_host=$2; shift 2 ;;
    --database-name) database_name=$2; shift 2 ;;
    --gateway-image) gateway_image=$2; shift 2 ;;
    --keycloak-image) keycloak_image=$2; shift 2 ;;
    --identity-edge-image) identity_edge_image=$2; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

safe_identifier() { case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac; }
safe_host() {
  case "$1" in ''|*[!A-Za-z0-9.-]*|.*|*.) return 1 ;; esac
  case "$1" in *..*) return 1 ;; esac
}
safe_authority() {
  case "$1" in ''|*[!A-Za-z0-9.:-]*) return 1 ;; esac
  authority_host=$1
  case "$1" in
    *:*)
      authority_host=${1%:*}
      authority_port=${1##*:}
      case "$authority_port" in ''|*[!0-9]*) return 1 ;; esac
      test "$authority_port" -gt 0
      test "$authority_port" -le 65535
      case "$authority_host" in *:*) return 1 ;; esac
      ;;
  esac
  safe_host "$authority_host"
}
safe_database_host() {
  case "$1" in ''|*[!A-Za-z0-9._:-]*) return 1 ;; esac
}
safe_digest_image() {
  case "$1" in *@sha256:*) ;; *) return 1 ;; esac
  image_name=${1%@sha256:*}
  image_digest=${1##*@sha256:}
  case "$image_name" in ''|*[!A-Za-z0-9._/@:+-]*) return 1 ;; esac
  case "$image_digest" in *[!0-9a-f]*) return 1 ;; esac
  test "${#image_digest}" -eq 64
}
safe_path() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "/$1/" in */../*) return 1 ;; esac
  case "$1" in *'|'*|*'&'*|*'\'*|*'$'*|*'{'*|*'}'*) return 1 ;; esac
}

safe_path "$output"
safe_path "$management_manifest"
test -f "$management_manifest"
safe_identifier "$management_namespace"
safe_identifier "$identity_namespace"
test "$management_namespace" != "$identity_namespace"
safe_authority "$identity_host"
if [ -n "$identity_ingress_host" ]; then
  safe_host "$identity_ingress_host"
  test "$identity_host" = "$identity_ingress_host"
fi
safe_authority "$operator_host"
safe_authority "$enterprise_host"
test "$identity_host" != "$operator_host"
test "$identity_host" != "$enterprise_host"
test "$operator_host" != "$enterprise_host"
safe_database_host "$database_host"
safe_identifier "$database_name"
safe_digest_image "$gateway_image"
safe_digest_image "$keycloak_image"
safe_digest_image "$identity_edge_image"
command -v kubectl >/dev/null
command -v rg >/dev/null

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-platform-identity.XXXXXX")
cleanup() { rm -rf "$work_directory"; }
trap cleanup EXIT HUP INT TERM

gateway_manifest=$work_directory/management-with-oidc.yaml
identity_transport_origin="https://lunanexa-identity-internal.$identity_namespace.svc.cluster.local:8443"
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$gateway_manifest" \
  --management-manifest "$management_manifest" \
  --provider-ref lunanexa-platform-oidc \
  --issuer-url "https://$identity_host/realms/lunanexa" \
  --transport-origin "$identity_transport_origin" \
  --operator-host "$operator_host" \
  --enterprise-host "$enterprise_host" \
  --gateway-image "$gateway_image" \
  --identity-edge-image "$identity_edge_image" >/dev/null

identity_manifest=$work_directory/platform-identity.yaml
identity_port=443
case "$identity_host" in *:*) identity_port=${identity_host##*:} ;; esac
sed \
  -e "s|\${LUNANEXA_MANAGEMENT_NAMESPACE}|$management_namespace|g" \
  -e "s|\${LUNANEXA_IDENTITY_NAMESPACE}|$identity_namespace|g" \
  -e "s|\${LUNANEXA_IDENTITY_HOST}|$identity_host|g" \
  -e "s|\${LUNANEXA_IDENTITY_PORT}|$identity_port|g" \
  -e "s|\${LUNANEXA_OPERATOR_HOST}|$operator_host|g" \
  -e "s|\${LUNANEXA_ENTERPRISE_HOST}|$enterprise_host|g" \
  -e "s|\${LUNANEXA_IDENTITY_DATABASE_HOST}|$database_host|g" \
  -e "s|\${LUNANEXA_IDENTITY_DATABASE_NAME}|$database_name|g" \
  -e "s|\${KEYCLOAK_IMAGE}|$keycloak_image|g" \
  -e "s|\${IDENTITY_EDGE_IMAGE}|$identity_edge_image|g" \
  "$repo_root/deploy/platform-identity.yaml" > "$identity_manifest"

identity_ingress_manifest=
if [ -n "$identity_ingress_host" ]; then
  identity_ingress_manifest=$work_directory/platform-identity-public-ingress.yaml
  sed \
    -e "s|\${LUNANEXA_IDENTITY_NAMESPACE}|$identity_namespace|g" \
    -e "s|\${LUNANEXA_IDENTITY_INGRESS_HOST}|$identity_ingress_host|g" \
    -e "s|\${LUNANEXA_IDENTITY_PUBLIC_EDGE_PORT}|$identity_port|g" \
    "$repo_root/deploy/platform-identity-public-ingress.yaml" \
    > "$identity_ingress_manifest"
fi

if rg -q 'registry\.invalid|lunanexa\.invalid' \
  "$gateway_manifest" "$identity_manifest" || \
  rg -o --no-filename '\$\{[A-Z0-9_]+\}' "$gateway_manifest" "$identity_manifest" | awk '
    $0 != "${LUNANEXA_OPERATOR_CLIENT_SECRET}" &&
    $0 != "${LUNANEXA_ENTERPRISE_CLIENT_SECRET}" &&
    $0 != "${LUNANEXA_SMTP_HOST}" &&
    $0 != "${LUNANEXA_SMTP_PORT}" &&
    $0 != "${LUNANEXA_SMTP_USERNAME}" &&
    $0 != "${LUNANEXA_SMTP_PASSWORD}" &&
    $0 != "${LUNANEXA_SMTP_FROM}" { unexpected = 1 }
    END { exit unexpected ? 0 : 1 }
  '; then
  printf '%s\n' 'platform identity render retained a deployment placeholder' >&2
  exit 1
fi
if [ -n "$identity_ingress_manifest" ] && \
  rg -q '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' \
    "$identity_ingress_manifest"; then
  printf '%s\n' 'platform identity public Ingress retained a deployment placeholder' >&2
  exit 1
fi

output_next=$output.next
if [ -n "$identity_ingress_manifest" ]; then
  awk 'FNR == 1 && NR != 1 { print "---" } { print }' \
    "$gateway_manifest" "$identity_manifest" "$identity_ingress_manifest" \
    > "$output_next"
else
  awk 'FNR == 1 && NR != 1 { print "---" } { print }' \
    "$gateway_manifest" "$identity_manifest" > "$output_next"
fi
chmod 0600 "$output_next"
mv "$output_next" "$output"
printf 'rendered LunaNexa platform identity profile: %s\n' "$output"
