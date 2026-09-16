#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
edge_manifest=$repo_root/deploy/oidc-browser-direct-ip-edge.yaml
console_service_patch=$repo_root/deploy/oidc-browser-direct-ip-console-service-patch.json
workbench_service_patch=$repo_root/deploy/oidc-browser-direct-ip-workbench-service-patch.json
console_gateway_patch=$repo_root/deploy/oidc-browser-disable-console-public-gateway-patch.yaml
workbench_gateway_patch=$repo_root/deploy/oidc-browser-disable-workbench-public-gateway-patch.yaml
management=$repo_root/scripts/deploy/testdata/oidc-direct-ip-management.yaml
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-browser-direct-ip-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

for source in \
  "$edge_manifest" \
  "$console_service_patch" \
  "$workbench_service_patch" \
  "$console_gateway_patch" \
  "$workbench_gateway_patch" \
  "$management"; do
  test -f "$source"
done
if rg -q '^kind: Secret$|data:.*(password|secret)|stringData:' \
  "$edge_manifest" "$console_service_patch" "$workbench_service_patch"; then
  printf '%s\n' 'direct-IP browser edge source contains secret material' >&2
  exit 1
fi
rg -F -q 'listen 8443 ssl;' "$edge_manifest"
rg -F -q 'ssl_protocols TLSv1.2 TLSv1.3;' "$edge_manifest"
rg -F -q 'proxy_pass http://lunanexa-identity-gateway:8081;' "$edge_manifest"
if rg -q 'listen (80|8080)|proxy_pass http://lunanexa-control' "$edge_manifest"; then
  printf '%s\n' 'direct-IP browser edge exposes plaintext or bypasses the identity gateway' >&2
  exit 1
fi

rendered=$test_directory/direct-ip.yaml
edge_image=lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/moon/lunanexa-web@sha256:a6136238fb0d39165fb26296b809786204fc6e74c2fee774e5103f7a4fe17550
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$rendered" \
  --management-manifest "$management" \
  --provider-ref lunanexa-platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --transport-origin https://lunanexa-identity-internal.lunanexa-identity.svc.cluster.local:8443 \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --identity-edge-image "$edge_image" \
  >/dev/null

test "$(stat -f '%Lp' "$rendered" 2>/dev/null || stat -c '%a' "$rendered")" = 600
if rg -q '\$\{[A-Z0-9_]+\}|^kind: Secret$|^kind: Ingress$' "$rendered"; then
  printf '%s\n' 'direct-IP browser edge emitted a placeholder, Secret or Ingress' >&2
  exit 1
fi

extract_named_document() {
  resource_name=$1
  awk -v resource_name="$resource_name" '
    $0 == "---" {
      if (selected) exit
      document = ""
      selected = 0
      next
    }
    {
      document = document $0 "\n"
      if ($0 == "  name: " resource_name) selected = 1
    }
    selected { output = document }
    END { printf "%s", output }
  ' "$rendered"
}

edge_deployment=$test_directory/edge-deployment.yaml
console_service=$test_directory/console-service.yaml
workbench_service=$test_directory/workbench-service.yaml
console_gateway=$test_directory/console-gateway.yaml
workbench_gateway=$test_directory/workbench-gateway.yaml
extract_named_document lunanexa-identity-edge > "$edge_deployment"
extract_named_document lunanexa-console-public > "$console_service"
extract_named_document lunanexa-workbench-public > "$workbench_service"
extract_named_document lunanexa-console-public-gateway > "$console_gateway"
extract_named_document lunanexa-workbench-public-gateway > "$workbench_gateway"

for required in \
  'kind: Deployment' \
  'replicas: 2' \
  "image: $edge_image" \
  'imagePullPolicy: Never' \
  'containerPort: 8443' \
  'secretName: lunanexa-oidc-ingress-tls' \
  'lunanexa.io/role: management'; do
  rg -F -q "$required" "$edge_deployment"
done
test "$(rg -c 'type: LoadBalancer' "$rendered")" -eq 1
for required in \
  'type: LoadBalancer' \
  'app: lunanexa-identity-edge' \
  'port: 5003' \
  'port: 5005' \
  'targetPort: edge-https'; do
  rg -F -q "$required" "$console_service"
done
test "$(rg -c 'targetPort: edge-https' "$console_service")" -eq 2
if rg -q 'port: (4174|3000|5001)' "$rendered"; then
  printf '%s\n' 'direct-IP browser edge retained a legacy public port' >&2
  exit 1
fi
rg -F -q 'type: ClusterIP' "$workbench_service"
rg -F -q 'port: 8080' "$workbench_service"
rg -F -q 'replicas: 0' "$console_gateway"
rg -F -q 'replicas: 0' "$workbench_gateway"
for required in \
  'name: lunanexa-identity-edge-direct-ip' \
  'name: lunanexa-identity-gateway-from-direct-ip-edge' \
  'app: lunanexa-identity-gateway' \
  'port: 8443'; do
  rg -F -q "$required" "$rendered"
done

dns_rendered=$test_directory/dns.yaml
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$dns_rendered" \
  --management-manifest "$management" \
  --provider-ref lunanexa-platform-oidc \
  --issuer-url https://id.example.test/realms/lunanexa \
  --operator-host operator.example.test \
  --enterprise-host enterprise.example.test \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null
rg -U -q 'kind: Ingress(.|\n)*name: lunanexa-oidc-browser' "$dns_rendered"
if rg -q 'name: lunanexa-identity-edge$|port: 5003|port: 5005' "$dns_rendered"; then
  printf '%s\n' 'DNS browser render included direct-IP edge resources' >&2
  exit 1
fi

set +e
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/mutable.yaml" \
  --management-manifest "$management" \
  --provider-ref lunanexa-platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --identity-edge-image registry.example.test/lunanexa/web:latest \
  >/dev/null 2>&1
mutable_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/missing.yaml" \
  --management-manifest "$management" \
  --provider-ref lunanexa-platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  >/dev/null 2>&1
missing_status=$?
"$repo_root/scripts/deploy/render-oidc-browser-ingress.sh" \
  --output "$test_directory/wrong-port.yaml" \
  --management-manifest "$management" \
  --provider-ref lunanexa-platform-oidc \
  --issuer-url https://203.0.113.40:5006/realms/lunanexa \
  --operator-host 203.0.113.40:5004 \
  --enterprise-host 203.0.113.40:5005 \
  --gateway-image registry.example.test/lunanexa/identity-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --identity-edge-image "$edge_image" \
  >/dev/null 2>&1
wrong_port_status=$?
set -e
test "$mutable_status" -ne 0
test "$missing_status" -ne 0
test "$wrong_port_status" -ne 0

printf '%s\n' 'OIDC browser direct-IP edge manifest tests passed'
