#!/bin/sh
set -eu
umask 077

output= provider_ref= issuer_url= operator_host= enterprise_host= gateway_image=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output=$2; shift 2 ;;
    --provider-ref) provider_ref=$2; shift 2 ;;
    --issuer-url) issuer_url=$2; shift 2 ;;
    --operator-host) operator_host=$2; shift 2 ;;
    --enterprise-host) enterprise_host=$2; shift 2 ;;
    --gateway-image) gateway_image=$2; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

safe_identifier() { case "$1" in ''|*[!A-Za-z0-9._:-]*) return 1 ;; esac; }
safe_host() {
  case "$1" in ''|*[!A-Za-z0-9.-]*|.*|*.) return 1 ;; esac
  case "$1" in *..*) return 1 ;; esac
}
safe_https_url() {
  case "$1" in https://*) ;; *) return 1 ;; esac
  case "${1#https://}" in ''|/*) return 1 ;; esac
  case "$1" in *[!A-Za-z0-9._~:/%+-]*) return 1 ;; esac
}
safe_digest_image() {
  case "$1" in *@sha256:*) ;; *) return 1 ;; esac
  image_name=${1%@sha256:*}
  image_digest=${1##*@sha256:}
  case "$image_name" in ''|*[!A-Za-z0-9._/@:+-]*) return 1 ;; esac
  case "$image_digest" in *[!0-9a-f]*) return 1 ;; esac
  test "${#image_digest}" -eq 64
}

case "$output" in /*) ;; *) exit 64 ;; esac
case "$output" in *'|'*|*'&'*|*'\'*|*'$'*|*'{'*|*'}'*) exit 64 ;; esac
safe_identifier "$provider_ref"
safe_https_url "$issuer_url"
safe_host "$operator_host"
safe_host "$enterprise_host"
test "$operator_host" != "$enterprise_host"
safe_digest_image "$gateway_image"
command -v kubectl >/dev/null

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-oidc-render.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

rendered=$test_directory/oidc-browser-ingress.yaml
sed \
  -e "s|\${LUNANEXA_OIDC_PROVIDER_REF}|$provider_ref|g" \
  -e "s|\${LUNANEXA_OIDC_ISSUER_URL}|$issuer_url|g" \
  -e "s|\${LUNANEXA_OPERATOR_HOST}|$operator_host|g" \
  -e "s|\${LUNANEXA_ENTERPRISE_HOST}|$enterprise_host|g" \
  -e "s|\${OIDC_IDENTITY_GATEWAY_IMAGE}|$gateway_image|g" \
  "$repo_root/deploy/oidc-browser-ingress.yaml" > "$rendered"
if rg -q '\$\{[A-Z0-9_]+\}' "$rendered"; then
  printf '%s\n' 'OIDC ingress render retained a deployment placeholder' >&2
  exit 1
fi

printf '%s\n' \
  'apiVersion: kustomize.config.k8s.io/v1beta1' \
  'kind: Kustomization' \
  'resources:' \
  '  - oidc-browser-ingress.yaml' > "$test_directory/kustomization.yaml"
kubectl kustomize "$test_directory" >/dev/null

output_next=$output.next
cp "$rendered" "$output_next"
chmod 0600 "$output_next"
mv "$output_next" "$output"
printf 'rendered OIDC browser ingress: %s\n' "$output"
