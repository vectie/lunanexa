#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manifest=$repo_root/deploy/platform-identity.yaml
public_ingress_manifest=$repo_root/deploy/platform-identity-public-ingress.yaml
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-platform-identity-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

test -f "$manifest"
test -f "$public_ingress_manifest"
if rg -q '^kind: Secret$' "$manifest" "$public_ingress_manifest" || awk '
  /^[[:space:]]+(password|secret): / && $0 !~ /\$\{/ { found = 1 }
  END { exit found ? 0 : 1 }
  ' "$manifest" "$public_ingress_manifest"; then
  printf '%s\n' 'platform identity source manifest contains credential material' >&2
  exit 1
fi
for required in \
  'apiVersion: k8s.keycloak.org/v2beta1' \
  'kind: Keycloak' \
  'kind: KeycloakRealmImport' \
  'instances: 2' \
  'startOptimized: false' \
  'tlsSecret: lunanexa-platform-idp-internal-tls' \
  'registrationAllowed: true' \
  'registrationEmailAsUsername: true' \
  'verifyEmail: true' \
  'duplicateEmailsAllowed: false' \
  'bruteForceProtected: true' \
  'defaultAction: true' \
  'providerId: CONFIGURE_TOTP' \
  'clientId: lunanexa-operator' \
  'clientId: lunanexa-enterprise' \
  'pkce.code.challenge.method: S256' \
  'directAccessGrantsEnabled: false' \
  'serviceAccountsEnabled: false' \
  'fullScopeAllowed: false' \
  'protocolMapper: oidc-audience-mapper' \
  'access.token.claim: "true"' \
  'id.token.claim: "false"' \
  'introspection.token.claim: "true"' \
  'lightweight.claim: "false"' \
  'adminEventsEnabled: true' \
  'name: lunanexa-identity-internal-edge-nginx' \
  'name: lunanexa-identity-public-edge-nginx' \
  'name: lunanexa-identity-public-edge' \
  'name: lunanexa-identity-public' \
  'name: lunanexa-identity-internal-edge' \
  'name: lunanexa-identity-internal' \
  'secretName: lunanexa-identity-internal-tls' \
  'secretName: lunanexa-oidc-internal-ca' \
  'proxy_ssl_verify on' \
  'proxy_ssl_server_name on' \
  'proxy_ssl_name lunanexa-platform-idp-service.${LUNANEXA_IDENTITY_NAMESPACE}.svc.cluster.local' \
  'server_name lunanexa-identity-internal.${LUNANEXA_IDENTITY_NAMESPACE}.svc.cluster.local' \
  'port: 8443'; do
  rg -F -q "$required" "$manifest"
done
test "$(rg -c 'protocolMapper: oidc-audience-mapper' "$manifest")" -eq 2
test "$(rg -c 'access.token.claim: "true"' "$manifest")" -eq 2
test "$(rg -c 'id.token.claim: "false"' "$manifest")" -eq 2
test "$(rg -c 'introspection.token.claim: "true"' "$manifest")" -eq 2
test "$(rg -c 'lightweight.claim: "false"' "$manifest")" -eq 2
rg -U -q 'clientId: lunanexa-operator(.|\n)*included.client.audience: lunanexa-operator' "$manifest"
rg -U -q 'clientId: lunanexa-enterprise(.|\n)*included.client.audience: lunanexa-enterprise' "$manifest"
for required in \
  'name: lunanexa-platform-idp-public' \
  'secretName: lunanexa-platform-idp-tls' \
  'nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"' \
  'nginx.ingress.kubernetes.io/proxy-ssl-server-name: "on"' \
  'host: "${LUNANEXA_IDENTITY_INGRESS_HOST}"' \
  'path: /.well-known' \
  'path: /realms' \
  'path: /resources'; do
  rg -F -q "$required" "$public_ingress_manifest"
done
test "$(rg -c 'pkce.code.challenge.method: S256' "$manifest")" -eq 2
test "$(rg -c 'directAccessGrantsEnabled: false' "$manifest")" -eq 2
test "$(rg -c 'serviceAccountsEnabled: false' "$manifest")" -eq 2
test "$(rg -c 'proxy_ssl_verify on' "$manifest")" -eq 3
test "$(rg -c 'proxy_ssl_server_name on' "$manifest")" -eq 3
test "$(rg -c 'secretName: lunanexa-platform-idp-tls' "$manifest")" -eq 1
test "$(rg -c 'secretName: lunanexa-identity-internal-tls' "$manifest")" -eq 1
if rg -U -q 'name: lunanexa-platform-idp-ingress(.|\n)*app.kubernetes.io/name: ingress-nginx' "$manifest"; then
  printf '%s\n' 'platform identity allows ingress-nginx to bypass the strict TLS edges' >&2
  exit 1
fi
if rg -q 'https://[^ ]*\*|path: /admin' "$manifest" "$public_ingress_manifest"; then
  printf '%s\n' 'platform identity exposes a wildcard client or public admin path' >&2
  exit 1
fi

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
  '      containers:' \
  '        - name: control' \
  '          image: registry.example.test/lunanexa/control@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
  '          ports:' \
  '            - name: http' \
  '              containerPort: 8080' > "$management"
rendered=$test_directory/platform.yaml
"$repo_root/scripts/deploy/render-platform-identity.sh" \
  --output "$rendered" \
  --management-manifest "$management" \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host 203.0.113.40:5006 \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --keycloak-image quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  --identity-edge-image registry.example.test/lunanexa/web@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
  >/dev/null
test -f "$rendered"
test "$(stat -f '%Lp' "$rendered" 2>/dev/null || stat -c '%a' "$rendered")" = 600
if rg -o --no-filename '\$\{[A-Z0-9_]+\}' "$rendered" | awk '
  $0 != "${LUNANEXA_OPERATOR_CLIENT_SECRET}" &&
  $0 != "${LUNANEXA_ENTERPRISE_CLIENT_SECRET}" &&
  $0 != "${LUNANEXA_SMTP_HOST}" &&
  $0 != "${LUNANEXA_SMTP_PORT}" &&
  $0 != "${LUNANEXA_SMTP_USERNAME}" &&
  $0 != "${LUNANEXA_SMTP_PASSWORD}" &&
  $0 != "${LUNANEXA_SMTP_FROM}" { unexpected = 1 }
  END { exit unexpected ? 0 : 1 }
'; then
  printf '%s\n' 'rendered platform identity contains a placeholder' >&2
  exit 1
fi
for expected in \
  'https://203.0.113.40:5006/realms/lunanexa' \
  'https://lunanexa-identity-internal.lunanexa-identity.svc.cluster.local:8443' \
  'https://203.0.113.40:5003/auth/oidc/callback' \
  'https://203.0.113.40:5005/auth/oidc/callback' \
  'LUNANEXA_OIDC_ALLOWED_ORIGINS: https://203.0.113.40:5003,https://203.0.113.40:5005' \
  'namespace: "lunanexa-identity"' \
  'namespace: "lunanexa"' \
  'host: "postgres-ha.lunanexa-identity.svc.cluster.local"' \
  'database: "keycloak"' \
  'proxy_set_header Host 203.0.113.40:5006' \
  'proxy_set_header X-Forwarded-Port 5006' \
  'proxy_ssl_name lunanexa-platform-idp-service.lunanexa-identity.svc.cluster.local' \
  'server_name lunanexa-identity-internal.lunanexa-identity.svc.cluster.local' \
  'name: lunanexa-identity-public' \
  'port: 5006' \
  'registry.example.test/lunanexa/web@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' \
  'quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'; do
  rg -F -q "$expected" "$rendered"
done

dns_rendered=$test_directory/platform-dns.yaml
"$repo_root/scripts/deploy/render-platform-identity.sh" \
  --output "$dns_rendered" \
  --management-manifest "$management" \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host id.example.test \
  --identity-ingress-host id.example.test \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --keycloak-image quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  --identity-edge-image registry.example.test/lunanexa/web@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
  >/dev/null
rg -F -q 'name: lunanexa-platform-idp-public' "$dns_rendered"
rg -F -q 'host: "id.example.test"' "$dns_rendered"
rg -F -q 'number: 443' "$dns_rendered"

set +e
"$repo_root/scripts/deploy/render-platform-identity.sh" \
  --output "$test_directory/mutable.yaml" \
  --management-manifest "$management" \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host 203.0.113.40:5006 \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --gateway-image registry.example.test/lunanexa/identity-gateway:latest \
  --keycloak-image quay.io/keycloak/keycloak:26.7.3 \
  --identity-edge-image registry.example.test/lunanexa/web:latest >/dev/null 2>&1
mutable_status=$?
"$repo_root/scripts/deploy/render-platform-identity.sh" \
  --output "$test_directory/unsafe-authority.yaml" \
  --management-manifest "$management" \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host 203.0.113.40:70000 \
  --operator-host operator.lunanexa.example \
  --enterprise-host app.lunanexa.example \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --keycloak-image quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  --identity-edge-image registry.example.test/lunanexa/web@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
  >/dev/null 2>&1
unsafe_authority_status=$?
"$repo_root/scripts/deploy/render-platform-identity.sh" \
  --output "$test_directory/mismatched-ingress.yaml" \
  --management-manifest "$management" \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host id.example.test \
  --identity-ingress-host other.example.test \
  --operator-host operator.lunanexa.example \
  --enterprise-host app.lunanexa.example \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --keycloak-image quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  --identity-edge-image registry.example.test/lunanexa/web@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
  >/dev/null 2>&1
mismatched_ingress_status=$?
set -e
test "$mutable_status" -ne 0
test "$unsafe_authority_status" -ne 0
test "$mismatched_ingress_status" -ne 0

if rg -q 'ipBlock:|LUNANEXA_IDENTITY_EGRESS_CIDR' \
  "$manifest" "$public_ingress_manifest" "$rendered"; then
  printf '%s\n' 'platform identity retained forbidden public-hairpin topology' >&2
  exit 1
fi

printf '%s\n' 'platform-operated public identity manifest tests passed'
