#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manifest=$repo_root/deploy/oidc-browser-ingress.yaml
base_policy=$repo_root/deploy/network-policy.yaml
controller_manifest=$repo_root/deploy/controller.yaml
dev_patch=$repo_root/deploy/management-foundation/network-policy-dev-browser-patch.yaml
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-oidc-ingress-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

test -f "$manifest"
if rg -q '^kind: Secret$' "$manifest"; then
  printf '%s\n' 'OIDC ingress manifest must reference deployment-owned secrets' >&2
  exit 1
fi

for required in \
  'name: lunanexa-identity-gateway' \
  'name: LUNANEXA_OIDC_ISSUER_URL' \
  'name: LUNANEXA_OIDC_OPERATOR_CLIENT_ID' \
  'name: LUNANEXA_OIDC_ENTERPRISE_CLIENT_ID' \
  'name: LUNANEXA_OIDC_OPERATOR_COOKIE_SECRET' \
  'name: LUNANEXA_OIDC_ENTERPRISE_COOKIE_SECRET' \
  'name: LUNANEXA_IDENTITY_ASSERTION_SECRET' \
  'key: identity-assertion-secret' \
  'key: operator-cookie-secret' \
  'key: enterprise-cookie-secret' \
  'oidc-pkce-method: "S256"' \
  'oidc-require-state: "1"' \
  'oidc-require-nonce: "1"' \
  'browser-cookie-secure: "1"' \
  'browser-cookie-http-only: "1"' \
  'browser-cookie-same-site: "Lax"' \
  'csrf-header-name: "X-LunaNexa-CSRF"' \
  'identity-exchange-path: "/v1/auth/session:exchange"' \
  'X-LunaNexa-Identity-Signature' \
  'app.kubernetes.io/name: ingress-nginx'; do
  rg -q "$required" "$manifest"
done

# Browser ingress terminates only at the identity gateway. Neither UI gateway
# nor the controller may be a public Ingress backend in this profile.
ingress_document=$test_directory/ingress.yaml
sed -n '/^kind: Ingress$/,$p' "$manifest" > "$ingress_document"
test "$(rg -c 'name: lunanexa-identity-gateway' "$ingress_document")" -eq 2
if rg -q 'name: lunanexa-(control|console|enterprise|workbench)$' "$ingress_document"; then
  printf '%s\n' 'OIDC browser ingress bypasses the identity gateway' >&2
  exit 1
fi

# The production base allows only the identity gateway and a label-locked
# ingress-nginx controller for browser identity. Direct plain-HTTP UI peers are
# reintroduced only by the explicit local/development overlay.
base_controller_policy=$test_directory/base-controller-policy.yaml
sed -n '1,/^---$/p' "$base_policy" > "$base_controller_policy"
rg -q 'app: lunanexa-identity-gateway' "$base_controller_policy"
rg -q 'app.kubernetes.io/name: ingress-nginx' "$base_controller_policy"
if rg -q 'lunanexa-(console|workbench)-public-gateway' "$base_controller_policy"; then
  printf '%s\n' 'production controller policy admits a plain browser gateway' >&2
  exit 1
fi
rg -q 'app: lunanexa-console-public-gateway' "$dev_patch"
rg -q 'app: lunanexa-workbench-public-gateway' "$dev_patch"
rg -q 'name: LUNANEXA_ACCOUNT_SESSION_ISSUER_SECRET' "$controller_manifest"
rg -q 'key: account-session-issuer-secret' "$controller_manifest"
test "$(rg -c 'name: LUNANEXA_IDENTITY_ASSERTION_SECRET' "$controller_manifest")" -eq 1
rg -U -q 'name: LUNANEXA_IDENTITY_ASSERTION_SECRET(.|\n)*optional: true' "$controller_manifest"

# Render and parse the complete multi-document profile offline. Secret values
# remain absent.
rendered=$test_directory/oidc-browser-ingress.yaml
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$rendered" \
  --provider-ref corp-oidc \
  --issuer-url https://id.example.test/realms/corp \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null
if rg -q '\$\{[A-Z0-9_]+\}' "$rendered"; then
  printf '%s\n' 'OIDC ingress render retained a deployment placeholder' >&2
  exit 1
fi
test "$(stat -f '%Lp' "$rendered" 2>/dev/null || stat -c '%a' "$rendered")" = 600

set +e
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/unsafe.yaml" \
  --provider-ref corp-oidc \
  --issuer-url http://id.example.test/realms/corp \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
unsafe_issuer_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/mutable.yaml" \
  --provider-ref corp-oidc \
  --issuer-url https://id.example.test/realms/corp \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway:latest \
  >/dev/null 2>&1
mutable_image_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/injected.yaml" \
  --provider-ref corp-oidc \
  --issuer-url 'https://id.example.test/"malicious' \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
injected_issuer_status=$?
set -e
test "$unsafe_issuer_status" -ne 0
test "$mutable_image_status" -ne 0
test "$injected_issuer_status" -ne 0

printf '%s\n' 'OIDC browser ingress manifest tests passed'
