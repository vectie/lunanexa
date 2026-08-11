#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

moon build cmd/control cmd/node --target native
control_binary="$repo_root/_build/native/debug/build/cmd/control/control.exe"
node_binary="$repo_root/_build/native/debug/build/cmd/node/node.exe"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-process-recovery.XXXXXX")
port=$((20000 + ($$ % 20000)))
address="127.0.0.1:$port"
base_url="http://$address"
control_pid=""
node_pid=""

cleanup() {
  if [ -n "$node_pid" ] && kill -0 "$node_pid" 2>/dev/null; then
    kill "$node_pid" 2>/dev/null || true
    wait "$node_pid" 2>/dev/null || true
  fi
  if [ -n "$control_pid" ] && kill -0 "$control_pid" 2>/dev/null; then
    kill "$control_pid" 2>/dev/null || true
    wait "$control_pid" 2>/dev/null || true
  fi
  rm -rf "$test_directory"
}

start_node() {
  log_path=$1
  env \
    LUNANEXA_ENDPOINT="$base_url" \
    LUNANEXA_NODE_ID="node-process-test" \
    LUNANEXA_NODE_TOKEN="process-test-node-authority" \
    LUNANEXA_NODE_PUBLIC_KEY_REF="host-ref:process-test-key" \
    LUNANEXA_BOOTSTRAP_TOKEN_ID="process-test-bootstrap" \
    LUNANEXA_BOOTSTRAP_TOKEN="process-test-bootstrap-authority" \
    LUNANEXA_NODE_INVENTORY_PATH="$repo_root/tests/fixtures/node-process-inventory.json" \
    LUNANEXA_NODE_STATE_PATH="$test_directory/node-state.json" \
    LUNANEXA_NODE_CERTIFICATE_PATH="$test_directory/node-certificate.json" \
    LUNANEXA_MODEL_CACHE_PATH="$test_directory/models" \
    LUNANEXA_ARTIFACT_ENDPOINT="$base_url/artifacts" \
    LUNANEXA_ARTIFACT_CREDENTIAL="process-test-artifact-authority" \
    LUNANEXA_ALLOW_HTTP_LOOPBACK=1 \
    LUNANEXA_COSIGN_BINARY="/usr/bin/cosign" \
    LUNANEXA_COSIGN_PUBLIC_KEY_PATH="$test_directory/cosign.pub" \
    LUNANEXA_ASSIGNMENT_SIGNING_SECRET="process-test-assignment-authority" \
    LUNANEXA_CONTAINER_ENGINE="/usr/bin/podman" \
    LUNANEXA_RUNTIME_NETWORK="lunanexa-process-test" \
    LUNANEXA_CONTAINER_ENGINE_ENDPOINT="unix:///run/podman/process-test.sock" \
    "$node_binary" >"$log_path" 2>&1 &
  node_pid=$!
}
trap cleanup EXIT INT TERM

start_controller() {
  epoch=$1
  reconciliation_only=$2
  log_path=$3
  env \
    LUNANEXA_LISTEN_ADDRESS="$address" \
    LUNANEXA_STATE_PATH="$test_directory/control.json" \
    LUNANEXA_REGISTRY_PATH="$test_directory/registry.json" \
    LUNANEXA_ENROLLMENT_PATH="$test_directory/enrollment.json" \
    LUNANEXA_SCHEDULER_PATH="$test_directory/scheduler.json" \
    LUNANEXA_TELEMETRY_PATH="$test_directory/telemetry.json" \
    LUNANEXA_WORKSPACE_PATH="$test_directory/workspace.json" \
    LUNANEXA_DEPLOYMENT_PATH="$test_directory/deployments.json" \
    LUNANEXA_EXCLUSIVE_LEASE_PATH="$test_directory/exclusive-leases.json" \
    LUNANEXA_RUNTIME_ENDPOINT="http://127.0.0.1:1/v1/responses" \
    LUNANEXA_RUNTIME_CREDENTIAL="process-test-runtime-authority" \
    LUNANEXA_RUNTIME_VERSION="process-test-v1" \
    LUNANEXA_RUNTIME_IMAGE_DIGEST="sha256:4444444444444444444444444444444444444444444444444444444444444444" \
    LUNANEXA_MODEL_ARTIFACT_DIGEST="sha256:3333333333333333333333333333333333333333333333333333333333333333" \
    LUNANEXA_ALLOW_HTTP_LOOPBACK=1 \
    LUNANEXA_CONTROLLER_EPOCH="$epoch" \
    LUNANEXA_RECONCILIATION_ONLY="$reconciliation_only" \
    LUNANEXA_OPERATOR_TOKEN="process-test-operator-authority" \
    LUNANEXA_INFERENCE_TOKEN="process-test-inference-authority" \
    LUNANEXA_AUDIT_TOKEN="process-test-audit-authority" \
    LUNANEXA_MONITORING_TOKEN="process-test-monitoring-authority" \
    LUNANEXA_ASSIGNMENT_SIGNING_SECRET="process-test-assignment-authority" \
    LUNANEXA_CATALOG_SIGNING_SECRET="process-test-catalog-authority" \
    LUNANEXA_EXCLUSIVE_LEASE_SIGNING_SECRET="process-test-exclusive-lease-authority" \
    LUNANEXA_COSIGN_BINARY="/usr/bin/cosign" \
    LUNANEXA_COSIGN_PUBLIC_KEY_PATH="$test_directory/cosign.pub" \
    "$control_binary" >"$log_path" 2>&1 &
  control_pid=$!
}

wait_ready() {
  attempts=0
  while [ "$attempts" -lt 100 ]; do
    if curl --fail --silent --max-time 1 "$base_url/health" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$control_pid" 2>/dev/null; then
      return 1
    fi
    attempts=$((attempts + 1))
    sleep 0.05
  done
  return 1
}

start_controller 1 0 "$test_directory/epoch-1.log"
wait_ready

now_seconds=$(date +%s)
bootstrap_expiry=$((now_seconds * 1000 + 600000))
bootstrap_body="{\"token_id\":\"process-test-bootstrap\",\"secret\":\"process-test-bootstrap-authority\",\"expires_unix_ms\":\"$bootstrap_expiry\"}"
status=$(curl --silent --output "$test_directory/bootstrap-response.json" \
  --write-out '%{http_code}' \
  --request POST \
  --header 'Authorization: Bearer process-test-operator-authority' \
  --header 'Content-Type: application/json' \
  --data "$bootstrap_body" \
  "$base_url/v1/enrollment/tokens")
test "$status" = "201"

start_node "$test_directory/node-first.log"
attempts=0
while [ "$attempts" -lt 100 ]; do
  curl --fail --silent --max-time 1 \
    --header 'Authorization: Bearer process-test-operator-authority' \
    "$base_url/v1/nodes" >"$test_directory/nodes-first.json" || true
  if rg -q 'node-process-test' "$test_directory/nodes-first.json"; then
    break
  fi
  if ! kill -0 "$node_pid" 2>/dev/null; then
    exit 1
  fi
  attempts=$((attempts + 1))
  sleep 0.05
done
rg -q 'node-process-test' "$test_directory/nodes-first.json"
test -s "$test_directory/node-state.json"
test -s "$test_directory/node-certificate.json"

kill -9 "$node_pid"
wait "$node_pid" 2>/dev/null || true
node_pid=""
start_node "$test_directory/node-restarted.log"
attempts=0
while [ "$attempts" -lt 100 ]; do
  if kill -0 "$node_pid" 2>/dev/null; then
    curl --fail --silent --max-time 1 \
      --header 'Authorization: Bearer process-test-operator-authority' \
      "$base_url/v1/nodes" >"$test_directory/nodes-restarted.json" || true
    if ! cmp -s "$test_directory/nodes-first.json" "$test_directory/nodes-restarted.json"; then
      break
    fi
  else
    exit 1
  fi
  attempts=$((attempts + 1))
  sleep 0.05
done
rg -q 'node-process-test' "$test_directory/nodes-restarted.json"

directive='{"node_id":"node-a","desired_state":"Cordoned","generation":"1","issued_unix_ms":"1","receipt":"process-restart-receipt"}'
status=$(curl --silent --output "$test_directory/directive-response.json" \
  --write-out '%{http_code}' \
  --request PUT \
  --header 'Authorization: Bearer process-test-operator-authority' \
  --header 'Content-Type: application/json' \
  --data "$directive" \
  "$base_url/v1/nodes/directive")
test "$status" = "202"

kill -9 "$control_pid"
wait "$control_pid" 2>/dev/null || true
control_pid=""

start_controller 2 1 "$test_directory/epoch-2.log"
wait_ready

curl --fail --silent --max-time 2 \
  --header 'Authorization: Bearer process-test-audit-authority' \
  "$base_url/v1/audit" >"$test_directory/audit.json"
rg -q 'process-restart-receipt' "$test_directory/audit.json"

curl --fail --silent --max-time 2 \
  --header 'Authorization: Bearer process-test-operator-authority' \
  "$base_url/v1/recovery/plan" >"$test_directory/recovery-plan.json"
rg -q '"actions"' "$test_directory/recovery-plan.json"

stale_log="$test_directory/stale-epoch.log"
env \
  LUNANEXA_LISTEN_ADDRESS="127.0.0.1:$((port + 1))" \
  LUNANEXA_STATE_PATH="$test_directory/control.json" \
  LUNANEXA_REGISTRY_PATH="$test_directory/registry.json" \
  LUNANEXA_ENROLLMENT_PATH="$test_directory/enrollment.json" \
  LUNANEXA_SCHEDULER_PATH="$test_directory/scheduler.json" \
  LUNANEXA_TELEMETRY_PATH="$test_directory/telemetry.json" \
  LUNANEXA_WORKSPACE_PATH="$test_directory/workspace.json" \
  LUNANEXA_DEPLOYMENT_PATH="$test_directory/deployments.json" \
  LUNANEXA_EXCLUSIVE_LEASE_PATH="$test_directory/exclusive-leases.json" \
  LUNANEXA_RUNTIME_ENDPOINT="http://127.0.0.1:1/v1/responses" \
  LUNANEXA_RUNTIME_CREDENTIAL="process-test-runtime-authority" \
  LUNANEXA_RUNTIME_VERSION="process-test-v1" \
  LUNANEXA_RUNTIME_IMAGE_DIGEST="sha256:4444444444444444444444444444444444444444444444444444444444444444" \
  LUNANEXA_MODEL_ARTIFACT_DIGEST="sha256:3333333333333333333333333333333333333333333333333333333333333333" \
  LUNANEXA_ALLOW_HTTP_LOOPBACK=1 \
  LUNANEXA_CONTROLLER_EPOCH=2 \
  LUNANEXA_RECONCILIATION_ONLY=1 \
  LUNANEXA_OPERATOR_TOKEN="process-test-operator-authority" \
  LUNANEXA_INFERENCE_TOKEN="process-test-inference-authority" \
  LUNANEXA_AUDIT_TOKEN="process-test-audit-authority" \
  LUNANEXA_MONITORING_TOKEN="process-test-monitoring-authority" \
  LUNANEXA_ASSIGNMENT_SIGNING_SECRET="process-test-assignment-authority" \
  LUNANEXA_CATALOG_SIGNING_SECRET="process-test-catalog-authority" \
  LUNANEXA_EXCLUSIVE_LEASE_SIGNING_SECRET="process-test-exclusive-lease-authority" \
  LUNANEXA_COSIGN_BINARY="/usr/bin/cosign" \
  LUNANEXA_COSIGN_PUBLIC_KEY_PATH="$test_directory/cosign.pub" \
  "$control_binary" >"$stale_log" 2>&1 && {
    printf '%s\n' 'stale controller epoch unexpectedly started' >&2
    exit 1
  }
rg -q '"controller_epoch":"2"' "$test_directory/control.json"

printf '%s\n' 'controller and node-agent process kill/restart, recovery-plan, and stale-epoch checks passed'
