#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manifest=$repo_root/deploy/platform-identity.yaml
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-platform-identity-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

test -f "$manifest"
if rg -q '^kind: Secret$' "$manifest" || awk '
  /^[[:space:]]+(password|secret): / && $0 !~ /\$\{/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$manifest"; then
  printf '%s\n' 'platform identity source manifest contains credential material' >&2
  exit 1
fi
for required in \
  'apiVersion: k8s.keycloak.org/v2beta1' \
  'kind: Keycloak' \
  'kind: KeycloakRealmImport' \
  'instances: 2' \
  'startOptimized: false' \
  'tlsSecret: lunanexa-platform-idp-tls' \
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
  'adminEventsEnabled: true' \
  'name: lunanexa-platform-idp-public' \
  'path: /.well-known' \
  'path: /realms' \
  'path: /resources'; do
  rg -q "$required" "$manifest"
done
test "$(rg -c 'pkce.code.challenge.method: S256' "$manifest")" -eq 2
test "$(rg -c 'directAccessGrantsEnabled: false' "$manifest")" -eq 2
test "$(rg -c 'serviceAccountsEnabled: false' "$manifest")" -eq 2
if rg -q 'https://[^ ]*\*|path: /admin' "$manifest"; then
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
  --identity-host id.lunanexa.example \
  --operator-host operator.lunanexa.example \
  --enterprise-host app.lunanexa.example \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --identity-egress-cidr 203.0.113.40/32 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --keycloak-image quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
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
  'https://id.lunanexa.example/realms/lunanexa' \
  'https://operator.lunanexa.example/auth/oidc/callback' \
  'https://app.lunanexa.example/auth/oidc/callback' \
  'namespace: "lunanexa-identity"' \
  'namespace: "lunanexa"' \
  'host: "postgres-ha.lunanexa-identity.svc.cluster.local"' \
  'database: "keycloak"' \
  'cidr: "203.0.113.40/32"' \
  'quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'; do
  rg -q "$expected" "$rendered"
done

set +e
"$repo_root/scripts/deploy/render-platform-identity.sh" \
  --output "$test_directory/mutable.yaml" \
  --management-manifest "$management" \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host id.lunanexa.example \
  --operator-host operator.lunanexa.example \
  --enterprise-host app.lunanexa.example \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --identity-egress-cidr 203.0.113.40/32 \
  --gateway-image registry.example.test/lunanexa/identity-gateway:latest \
  --keycloak-image quay.io/keycloak/keycloak:26.7.3 >/dev/null 2>&1
mutable_status=$?
"$repo_root/scripts/deploy/render-platform-identity.sh" \
  --output "$test_directory/broad-egress.yaml" \
  --management-manifest "$management" \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host id.lunanexa.example \
  --operator-host operator.lunanexa.example \
  --enterprise-host app.lunanexa.example \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --identity-egress-cidr 0.0.0.0/0 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --keycloak-image quay.io/keycloak/keycloak@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  >/dev/null 2>&1
broad_egress_status=$?
set -e
test "$mutable_status" -ne 0
test "$broad_egress_status" -ne 0

printf '%s\n' 'platform-operated public identity manifest tests passed'
