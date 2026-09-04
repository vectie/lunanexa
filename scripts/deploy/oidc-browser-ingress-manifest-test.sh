#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manifest=$repo_root/deploy/oidc-browser-ingress.yaml
public_ingress_manifest=$repo_root/deploy/oidc-browser-public-ingress.yaml
controller_patch=$repo_root/deploy/oidc-browser-ingress-controller-patch.yaml
base_policy=$repo_root/deploy/network-policy.yaml
controller_manifest=$repo_root/deploy/controller.yaml
dev_patch=$repo_root/deploy/management-foundation/network-policy-dev-browser-patch.yaml
enterprise_source=$repo_root/cmd/enterprise/main.mbt
direct_management_fixture=$repo_root/scripts/deploy/testdata/oidc-direct-ip-management.yaml
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-oidc-ingress-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

test -f "$manifest"
test -f "$public_ingress_manifest"
if rg -q '^kind: Secret$' "$manifest" "$public_ingress_manifest"; then
  printf '%s\n' 'OIDC ingress manifest must reference deployment-owned secrets' >&2
  exit 1
fi

for required in \
  'name: lunanexa-identity-gateway' \
  'app: lunanexa-control' \
  'lunanexa.io/browser-identity-sidecar: enabled' \
  'LUNANEXA_OIDC_ISSUER_URL:' \
  'LUNANEXA_OIDC_TRANSPORT_ORIGIN:' \
  'LUNANEXA_OIDC_PKCE_METHOD: "S256"' \
  'LUNANEXA_OIDC_REQUIRE_STATE: "1"' \
  'LUNANEXA_OIDC_REQUIRE_NONCE: "1"' \
  'LUNANEXA_BROWSER_COOKIE_SECURE: "1"' \
  'LUNANEXA_BROWSER_COOKIE_HTTP_ONLY: "1"' \
  'LUNANEXA_BROWSER_COOKIE_SAME_SITE: "Lax"' \
  'LUNANEXA_CSRF_HEADER_NAME: "X-LunaNexa-CSRF"' \
  'LUNANEXA_IDENTITY_RELAY_ENDPOINT: "http://lunanexa-identity-relay:8081"' \
  'LUNANEXA_CONTROL_BEARER_ENDPOINT: "http://lunanexa-control:8080"' \
  'LUNANEXA_CONTROL_BEARER_PATH_PREFIX: "/v1/"' \
  'LUNANEXA_IDENTITY_EXCHANGE_PATH: "/v1/auth/session:exchange"' \
  'LUNANEXA_IDENTITY_REGISTRATION_PATH: "/v1/auth/register"' \
  'LUNANEXA_IDENTITY_REGISTRATION_ASSERTION_VERSION: "lunanexa.identity.registration.v1"' \
  'LUNANEXA_OPEN_REGISTRATION_ENABLED: "1"' \
  'LUNANEXA_BROWSER_OIDC_START_PATH: "/auth/oidc/start"' \
  'LUNANEXA_BROWSER_SESSION_PATH: "/auth/session"' \
  'LUNANEXA_BROWSER_LOGOUT_PATH: "/auth/logout"' \
  'LUNANEXA_BROWSER_AUDIENCES: "operator,enterprise"' \
  'LUNANEXA_BROWSER_SESSION_RESPONSE_FIELDS: "session_token,csrf_token,expires_unix_ms"' \
  'LUNANEXA_REUSE_COOKIE_BOUND_SESSION: "1"' \
  'LUNANEXA_REQUIRE_SESSION_COOKIE_BEARER_BINDING: "1"' \
  'LUNANEXA_REVOKE_SESSION_ON_LOGOUT: "1"' \
  'LUNANEXA_REJECT_NONCANONICAL_API_PATHS: "1"' \
  'LUNANEXA_OPERATOR_API_PATH_PREFIXES: "/v1/"' \
  'LUNANEXA_ENTERPRISE_API_PATH_PREFIXES: "/v1/auth/,/v1/portal/self,/v1/portal/signature-requests,/v1/portal/lease-requests,' \
  'LUNANEXA_ALLOWED_BROWSER_BEARER_PREFIXES: "lnxs_"' \
  'X-LunaNexa-Identity-Signature' \
  'X-LunaNexa-Identity-Email' \
  'X-LunaNexa-Identity-Display-Name' \
  'app.kubernetes.io/name: ingress-nginx'; do
  rg -q "$required" "$manifest"
done
rg -U -q 'lunanexa.io/service: oidc-provider(.|\n)*port: 8443' "$manifest"
if rg -q 'LUNANEXA_ENTERPRISE_API_PATH_PREFIXES:.*\/v1\/portal\/,' "$manifest"; then
  printf '%s\n' 'enterprise browser policy includes operator portal routes' >&2
  exit 1
fi
logout_source=$test_directory/enterprise-gateway-logout.mbt
sed -n '/extern "js" fn gateway_logout_promise/,/^\/\/\/|/p' \
  "$enterprise_source" > "$logout_source"
if rg -q 'body:|Content-Type' "$logout_source"; then
  printf '%s\n' 'enterprise gateway logout violates the empty-body contract' >&2
  exit 1
fi
for destination in console enterprise workbench; do
  rg -q "name: lunanexa-identity-gateway-to-$destination" "$manifest"
done
for required in \
  'name: lunanexa-control' \
  'name: identity-relay' \
  'name: identity-http' \
  'containerPort: 8081' \
  'name: LUNANEXA_IDENTITY_GATEWAY_MODE' \
  'value: relay' \
  'name: LUNANEXA_CONTROL_ENDPOINT' \
  'value: http://127.0.0.1:8082' \
  'name: LUNANEXA_IDENTITY_EXCHANGE_PATH' \
  'value: /v1/auth/session:exchange' \
  'name: LUNANEXA_IDENTITY_REGISTRATION_PATH' \
  'value: /v1/auth/register' \
  'name: LUNANEXA_RELAY_ALLOWED_METHOD' \
  'value: POST' \
  'name: LUNANEXA_RELAY_MAXIMUM_BODY_BYTES' \
  'value: "256"' \
  'name: LUNANEXA_RELAY_REQUIRED_CONTENT_TYPE' \
  'value: application/json'; do
  rg -q "$required" "$controller_patch"
done
rg -U -q 'kind: Deployment\nmetadata:\n  name: lunanexa-identity-gateway' "$manifest"
if rg -q 'LUNANEXA_(OIDC_.*CLIENT|OIDC_.*COOKIE|IDENTITY_ASSERTION_SECRET)' "$controller_patch"; then
  printf '%s\n' 'minimal identity relay must not mount OIDC or assertion secrets' >&2
  exit 1
fi

# Browser ingress terminates only at the identity gateway. Neither UI gateway
# nor the controller may be a public Ingress backend in this profile.
ingress_document=$public_ingress_manifest
test "$(rg -c 'name: lunanexa-identity-gateway' "$ingress_document")" -eq 2
test "$(rg -c 'number: 8081' "$ingress_document")" -eq 2
if rg -q 'name: lunanexa-(control|console|enterprise|workbench)$' "$ingress_document"; then
  printf '%s\n' 'OIDC browser ingress bypasses the identity gateway' >&2
  exit 1
fi

# The production controller port is not reachable from ingress or a separate
# identity pod. The OIDC overlay admits the gateway only to relay port 8081.
base_controller_policy=$test_directory/base-controller-policy.yaml
sed -n '1,/^---$/p' "$base_policy" > "$base_controller_policy"
if rg -q 'app: lunanexa-identity-gateway|app.kubernetes.io/name: ingress-nginx' \
  "$base_controller_policy"; then
  printf '%s\n' 'base controller policy exposes the native listener to browser ingress' >&2
  exit 1
fi
rg -U -q 'name: lunanexa-identity-relay(.|\n)*egress: \[\]' "$manifest"
rg -U -q 'app: lunanexa-identity-gateway(.|\n)*port: 8081' "$manifest"
rg -U -q 'app: lunanexa-identity-gateway(.|\n)*port: 8080' "$manifest"
relay_policy=$test_directory/identity-relay-policy.yaml
sed -n '/^  name: lunanexa-identity-relay$/,/^---$/p' "$manifest" > "$relay_policy"
if rg -q 'port: 443' "$relay_policy"; then
  printf '%s\n' 'controller relay policy grants external egress' >&2
  exit 1
fi
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

# Render the sidecar overlay on top of a previously rendered management
# manifest. This minimal fixture exercises the same named Deployment merge.
management=$test_directory/management.yaml
printf '%s\n' \
  'apiVersion: apps/v1' \
  'kind: Deployment' \
  'metadata:' \
  '  name: lunanexa-control' \
  'spec:' \
  '  selector:' \
  '    matchLabels:' \
  '      app: lunanexa-control' \
  '  template:' \
  '    metadata:' \
  '      labels:' \
  '        app: lunanexa-control' \
  '    spec:' \
  '      serviceAccountName: lunanexa-control' \
  '      containers:' \
  '        - name: control' \
  '          image: registry.example.test/lunanexa/control@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  '          ports:' \
  '            - name: http' \
  '              containerPort: 8080' > "$management"
rendered=$test_directory/oidc-browser-ingress.yaml
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$rendered" \
  --management-manifest "$management" \
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
rg -U -q 'name: lunanexa-control(.|\n)*name: control(.|\n)*name: identity-relay' "$rendered"
rg -q 'http://127.0.0.1:8082' "$rendered"
rg -q 'containerPort: 8081' "$rendered"
rg -U -q 'kind: Deployment\nmetadata:\n  name: lunanexa-identity-gateway' "$rendered"
rg -q 'http://lunanexa-identity-relay:8081' "$rendered"
rg -q 'http://lunanexa-control:8080' "$rendered"
rg -q 'LUNANEXA_OIDC_TRANSPORT_ORIGIN: ""' "$rendered"
rg -U -q 'kind: Ingress(.|\n)*name: lunanexa-oidc-browser' "$rendered"
test "$(stat -f '%Lp' "$rendered" 2>/dev/null || stat -c '%a' "$rendered")" = 600

private_transport_rendered=$test_directory/oidc-browser-private-transport.yaml
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$private_transport_rendered" \
  --management-manifest "$management" \
  --provider-ref platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --transport-origin https://lunanexa-identity-internal.lunanexa-identity.svc.cluster.local:8443 \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null
rg -F -q 'https://203.0.113.40:5006/realms/lunanexa' \
  "$private_transport_rendered"
rg -F -q 'https://lunanexa-identity-internal.lunanexa-identity.svc.cluster.local:8443' \
  "$private_transport_rendered"

no_domain_rendered=$test_directory/oidc-browser-no-domain.yaml
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$no_domain_rendered" \
  --management-manifest "$direct_management_fixture" \
  --provider-ref platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --transport-origin https://lunanexa-identity-internal.lunanexa-identity.svc.cluster.local:8443 \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --identity-edge-image registry.example.test/lunanexa/web@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
  >/dev/null
rg -F -q 'https://203.0.113.40:5003/auth/oidc/callback' "$no_domain_rendered"
rg -F -q 'https://203.0.113.40:5005/auth/oidc/callback' "$no_domain_rendered"
rg -F -q 'https://203.0.113.40:5003,https://203.0.113.40:5005' "$no_domain_rendered"
if rg -q '^kind: Ingress$' "$no_domain_rendered"; then
  printf '%s\n' 'no-domain browser render emitted an invalid IP:port Ingress' >&2
  exit 1
fi
rg -U -q 'kind: Deployment(.|\n)*name: lunanexa-identity-edge(.|\n)*replicas: 2' \
  "$no_domain_rendered"
rg -U -q 'name: lunanexa-console-public(.|\n)*app: lunanexa-identity-edge' \
  "$no_domain_rendered"

set +e
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/unsafe.yaml" \
  --management-manifest "$management" \
  --provider-ref corp-oidc \
  --issuer-url http://id.example.test/realms/corp \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
unsafe_issuer_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/mutable.yaml" \
  --management-manifest "$management" \
  --provider-ref corp-oidc \
  --issuer-url https://id.example.test/realms/corp \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway:latest \
  >/dev/null 2>&1
mutable_image_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/injected.yaml" \
  --management-manifest "$management" \
  --provider-ref corp-oidc \
  --issuer-url 'https://id.example.test/"malicious' \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
injected_issuer_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/unsafe-transport.yaml" \
  --management-manifest "$management" \
  --provider-ref platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --transport-origin https://lunanexa-identity-internal.lunanexa-identity.svc.cluster.local:8443/realms \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
unsafe_transport_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/invalid-port.yaml" \
  --management-manifest "$management" \
  --provider-ref platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --operator-host 203.0.113.40:70000 \
  --enterprise-host 203.0.113.40:5005 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
invalid_port_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/injected-authority.yaml" \
  --management-manifest "$management" \
  --provider-ref platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --operator-host '203.0.113.40:5003;return-200' \
  --enterprise-host 203.0.113.40:5005 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
injected_authority_status=$?
set -e
test "$unsafe_issuer_status" -ne 0
test "$mutable_image_status" -ne 0
test "$injected_issuer_status" -ne 0
test "$unsafe_transport_status" -ne 0
test "$invalid_port_status" -ne 0
test "$injected_authority_status" -ne 0

printf '%s\n' 'OIDC browser ingress manifest tests passed'
