#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-management-render-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

render() {
  "$repo_root/scripts/deploy/render-management-foundation.sh" \
    --output "$test_directory/rendered" \
    --management-node ubuntu \
    --control-image docker.io/lunanexa/control:test-1 \
    --web-image docker.io/lunanexa/web:test-2 \
    --model-source-image docker.io/lunanexa/model-source:test-4 \
    --workbench-public-image docker.io/lunanexa/workbench-web:test-5 \
    --coursebook-public-image docker.io/lunanexa/coursebook-static:test-6 \
    --postgres-image docker.io/lunanexa/postgres:test-3 \
    --model-store-root /data/models \
    --control-uid 1000 \
    --control-gid 1000 \
    --runtime-endpoint http://127.0.0.1:19090/v1/responses \
    --public-api-base-url http://127.0.0.1:4174 \
    --controller-epoch 7
}

render >/dev/null
manifest=$test_directory/rendered/management.yaml
test -f "$manifest"
test "$(stat -f '%Lp' "$manifest" 2>/dev/null || stat -c '%a' "$manifest")" = 600
if rg -q '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' "$manifest"; then
  printf '%s\n' 'rendered output retained a placeholder' >&2
  exit 1
fi
rg -q 'name: lunanexa-workbench' "$manifest"
rg -q 'name: lunanexa-console-public' "$manifest"
rg -q 'lunanexa.io/exposure: temporary-plain-http' "$manifest"
rg -q 'port: 4174' "$manifest"
rg -q 'name: lunanexa-console-public-gateway' "$manifest"
rg -q 'app: lunanexa-console-public-gateway' "$manifest"
rg -q 'image: docker.io/lunanexa/control:test-1' "$manifest"
rg -q 'image: docker.io/lunanexa/web:test-2' "$manifest"
rg -q 'image: docker.io/lunanexa/model-source:test-4' "$manifest"
rg -q 'image: docker.io/lunanexa/workbench-web:test-5' "$manifest"
rg -q 'image: docker.io/lunanexa/coursebook-static:test-6' "$manifest"
rg -q 'image: docker.io/lunanexa/postgres:test-3' "$manifest"
rg -q 'runAsUser: 1000' "$manifest"
rg -q 'kubernetes.io/hostname: ubuntu' "$manifest"
test "$(rg -c 'imagePullPolicy: Never' "$manifest")" -eq 9
rg -q 'name: lunanexa-model-source' "$manifest"
rg -q 'name: lunanexa-model-source-credentials' "$manifest"
rg -q 'port: 3000' "$manifest"
rg -q 'port: 4173' "$manifest"
test "$(rg -c 'mountPath: /tmp' "$manifest")" -eq 6
test "$(rg -c 'name: nginx-tmp' "$manifest")" -eq 12
test "$(rg -c 'emptyDir: \{\}' "$manifest")" -ge 6
rg -q '"generation":"1"' "$manifest"
rg -q '"heartbeat_timeout_ms":"15000"' "$manifest"
rg -q 'lunanexa.io/management-config-digest: [0-9a-f]{64}' "$manifest"
if rg -q 'LUNANEXA_OFFLINE_COMMERCE_READINESS_(PATH|SECRET)|LUNANEXA_RUNTIME_ENDPOINTS_PATH' "$manifest"; then
  printf '%s\n' 'pending-only runtime variables were not removed' >&2
  exit 1
fi

set +e
"$repo_root/scripts/deploy/render-management-foundation.sh" \
  --output "$test_directory/unsafe-image" --management-node ubuntu \
  --control-image 'bad;image' --web-image docker.io/lunanexa/web:test \
  --model-source-image docker.io/lunanexa/model-source:test \
  --workbench-public-image docker.io/lunanexa/workbench-web:test \
  --coursebook-public-image docker.io/lunanexa/coursebook-static:test \
  --postgres-image docker.io/lunanexa/postgres:test --model-store-root /data/models \
  --control-uid 1000 --control-gid 1000 \
  --runtime-endpoint http://127.0.0.1:19090/v1/responses \
  --public-api-base-url http://127.0.0.1:4174 \
  --controller-epoch 1 >/dev/null 2>&1
unsafe_image_status=$?
"$repo_root/scripts/deploy/render-management-foundation.sh" \
  --output "$test_directory/unsafe-endpoint" --management-node ubuntu \
  --control-image docker.io/lunanexa/control:test --web-image docker.io/lunanexa/web:test \
  --model-source-image docker.io/lunanexa/model-source:test \
  --workbench-public-image docker.io/lunanexa/workbench-web:test \
  --coursebook-public-image docker.io/lunanexa/coursebook-static:test \
  --postgres-image docker.io/lunanexa/postgres:test --model-store-root /data/models \
  --control-uid 1000 --control-gid 1000 \
  --runtime-endpoint https://runtime.example/v1/responses \
  --public-api-base-url http://127.0.0.1:4174 \
  --controller-epoch 1 >/dev/null 2>&1
unsafe_endpoint_status=$?
set -e
test "$unsafe_image_status" -ne 0
test "$unsafe_endpoint_status" -ne 0

printf '%s\n' 'management manifest renderer tests passed'
