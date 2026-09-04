#!/bin/sh
set -eu
umask 077

output= management_manifest= provider_ref= issuer_url= transport_origin=
operator_host= enterprise_host= gateway_image=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output=$2; shift 2 ;;
    --management-manifest) management_manifest=$2; shift 2 ;;
    --provider-ref) provider_ref=$2; shift 2 ;;
    --issuer-url) issuer_url=$2; shift 2 ;;
    --transport-origin) transport_origin=$2; shift 2 ;;
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
is_dns_ingress_host() {
  case "$1" in *:*) return 1 ;; esac
  case "$1" in *[A-Za-z-]*) ;; *) return 1 ;; esac
  safe_host "$1"
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

safe_path() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "/$1/" in */../*) return 1 ;; esac
  case "$1" in *'|'*|*'&'*|*'\'*|*'$'*|*'{'*|*'}'*) return 1 ;; esac
}
safe_path "$output"
safe_path "$management_manifest"
test -f "$management_manifest"
safe_identifier "$provider_ref"
safe_https_url "$issuer_url"
if [ -n "$transport_origin" ]; then
  safe_https_url "$transport_origin"
  case "${transport_origin#https://}" in */*)
    printf '%s\n' 'OIDC transport origin must not include a path' >&2
    exit 64
  esac
fi
safe_authority "$operator_host"
safe_authority "$enterprise_host"
test "$operator_host" != "$enterprise_host"
safe_digest_image "$gateway_image"
command -v kubectl >/dev/null

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-oidc-render.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

base=$test_directory/management.yaml
profile=$test_directory/oidc-browser-ingress.yaml
patch=$test_directory/oidc-browser-ingress-controller-patch.yaml
rendered=$test_directory/rendered.yaml
browser_ingress=
cp "$management_manifest" "$base"
sed \
  -e "s|\${LUNANEXA_OIDC_PROVIDER_REF}|$provider_ref|g" \
  -e "s|\${LUNANEXA_OIDC_ISSUER_URL}|$issuer_url|g" \
  -e "s|\${LUNANEXA_OIDC_TRANSPORT_ORIGIN}|$transport_origin|g" \
  -e "s|\${LUNANEXA_OPERATOR_HOST}|$operator_host|g" \
  -e "s|\${LUNANEXA_ENTERPRISE_HOST}|$enterprise_host|g" \
  -e "s|\${OIDC_IDENTITY_GATEWAY_IMAGE}|$gateway_image|g" \
  "$repo_root/deploy/oidc-browser-ingress.yaml" > "$profile"
if is_dns_ingress_host "$operator_host" && \
  is_dns_ingress_host "$enterprise_host"; then
  browser_ingress=$test_directory/oidc-browser-public-ingress.yaml
  sed \
    -e "s|\${LUNANEXA_OPERATOR_HOST}|$operator_host|g" \
    -e "s|\${LUNANEXA_ENTERPRISE_HOST}|$enterprise_host|g" \
    "$repo_root/deploy/oidc-browser-public-ingress.yaml" > "$browser_ingress"
fi
sed \
  -e "s|\${OIDC_IDENTITY_GATEWAY_IMAGE}|$gateway_image|g" \
  "$repo_root/deploy/oidc-browser-ingress-controller-patch.yaml" > "$patch"
if rg -q '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' \
  "$base" "$profile" "$patch"; then
  printf '%s\n' 'OIDC ingress render retained a deployment placeholder' >&2
  exit 1
fi
if [ -n "$browser_ingress" ] && \
  rg -q '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' \
    "$browser_ingress"; then
  printf '%s\n' 'OIDC browser Ingress render retained a deployment placeholder' >&2
  exit 1
fi

printf '%s\n' \
  'apiVersion: kustomize.config.k8s.io/v1beta1' \
  'kind: Kustomization' \
  'resources:' \
  '  - management.yaml' \
  '  - oidc-browser-ingress.yaml' > "$test_directory/kustomization.yaml"
if [ -n "$browser_ingress" ]; then
  printf '%s\n' '  - oidc-browser-public-ingress.yaml' \
    >> "$test_directory/kustomization.yaml"
fi
printf '%s\n' \
  'patches:' \
  '  - path: oidc-browser-ingress-controller-patch.yaml' \
  >> "$test_directory/kustomization.yaml"
kubectl kustomize "$test_directory" > "$rendered"

output_next=$output.next
cp "$rendered" "$output_next"
chmod 0600 "$output_next"
mv "$output_next" "$output"
printf 'rendered OIDC browser ingress: %s\n' "$output"
