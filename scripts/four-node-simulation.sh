#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

artifact_digest='sha256:3333333333333333333333333333333333333333333333333333333333333333'
image_digest='sha256:4444444444444444444444444444444444444444444444444444444444444444'
operator_token='simulation-operator-authority'
inference_token='simulation-inference-authority'
audit_token='simulation-audit-authority'
monitoring_token='simulation-monitoring-authority'
runtime_token='simulation-runtime-authority'
assignment_secret='simulation-assignment-authority'
workspace_subject='subject-simulated-user'

keep_artifacts=0
if [ "$#" -eq 0 ]; then
  simulation_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-four-node.XXXXXX")
elif [ "$#" -eq 1 ]; then
  simulation_directory=$1
  if [ -e "$simulation_directory" ]; then
    printf '%s\n' "simulation output already exists: $simulation_directory" >&2
    exit 1
  fi
  mkdir -p "$simulation_directory"
  keep_artifacts=1
else
  printf '%s\n' 'usage: scripts/four-node-simulation.sh [NEW_EVIDENCE_DIRECTORY]' >&2
  exit 1
fi

choose_base_port() {
  candidate=$((24000 + ($$ % 12000)))
  attempts=0
  while [ "$attempts" -lt 200 ]; do
    range_busy=0
    for offset in 0 1 2 3 4; do
      if nc -z 127.0.0.1 "$((candidate + offset))" >/dev/null 2>&1; then
        range_busy=1
        break
      fi
    done
    if [ "$range_busy" -eq 0 ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate=$((candidate + 5))
    if [ "$candidate" -gt 60000 ]; then
      candidate=24000
    fi
    attempts=$((attempts + 1))
  done
  printf '%s\n' 'could not find five free loopback ports for simulation' >&2
  return 1
}

base_port=$(choose_base_port)
control_address="127.0.0.1:$base_port"
base_url="http://$control_address"
control_pid=''
runtime_pids=''
node_pids=''

cleanup() {
  for process_id in $node_pids $runtime_pids $control_pid; do
    if [ -n "$process_id" ] && kill -0 "$process_id" 2>/dev/null; then
      kill "$process_id" 2>/dev/null || true
      wait "$process_id" 2>/dev/null || true
    fi
  done
  if [ "$keep_artifacts" -eq 0 ]; then
    rm -rf "$simulation_directory"
  fi
}
trap cleanup EXIT INT TERM

moon build cmd/control cmd/sim-node cmd/sim-runtime cmd/sim-seed --target native
control_binary="$repo_root/_build/native/debug/build/cmd/control/control.exe"
node_binary="$repo_root/_build/native/debug/build/cmd/sim-node/sim-node.exe"
runtime_binary="$repo_root/_build/native/debug/build/cmd/sim-runtime/sim-runtime.exe"
seed_binary="$repo_root/_build/native/debug/build/cmd/sim-seed/sim-seed.exe"

env \
  LUNANEXA_SIMULATION_ONLY=1 \
  LUNANEXA_REGISTRY_PATH="$simulation_directory/registry.json" \
  LUNANEXA_MODEL_ARTIFACT_DIGEST="$artifact_digest" \
  LUNANEXA_RUNTIME_IMAGE_DIGEST="$image_digest" \
  "$seed_binary" >"$simulation_directory/seed.log" 2>&1

printf '%s\n' '[' >"$simulation_directory/runtime-endpoints.json"
for index in 1 2 3 4; do
  node_id="sim-dgx-$index"
  runtime_port=$((base_port + index))
  separator=','
  if [ "$index" -eq 4 ]; then separator=''; fi
  printf '  {"node_id":"%s","endpoint":"http://127.0.0.1:%s/v1/responses"}%s\n' \
    "$node_id" "$runtime_port" "$separator" >>"$simulation_directory/runtime-endpoints.json"
  printf '%s\n' \
    "{\"node_id\":\"$node_id\",\"agent_version\":\"simulator-v1\",\"os_release\":\"simulated-dgx-spark\",\"runtime_names\":[\"text-runtime\"],\"accelerators\":[{\"device_id\":\"gpu-0\",\"architecture\":\"nvidia-gb10\",\"memory_total_mib\":128000,\"memory_free_mib\":110000,\"healthy\":true}],\"labels\":{\"lunanexa.models\":\"model.text@v1\",\"lunanexa.warm-models\":\"model.text@v1\",\"lunanexa.data-classes\":\"Confidential\",\"lunanexa.reliability-per-mille\":\"1000\",\"lunanexa.accelerator-utilization-per-mille\":\"0\"},\"taints\":[]}" \
    >"$simulation_directory/$node_id-inventory.json"
  printf '%s\n' 'ready' >"$simulation_directory/$node_id-control"
  env \
    LUNANEXA_SIMULATION_ONLY=1 \
    LUNANEXA_SIM_NODE_ID="$node_id" \
    LUNANEXA_SIM_LISTEN_ADDRESS="127.0.0.1:$runtime_port" \
    LUNANEXA_SIM_CONTROL_PATH="$simulation_directory/$node_id-control" \
    LUNANEXA_SIM_INVOCATION_PATH="$simulation_directory/$node_id-invocations.log" \
    LUNANEXA_SIM_RUNTIME_CREDENTIAL="$runtime_token" \
    "$runtime_binary" >"$simulation_directory/$node_id-runtime.log" 2>&1 &
  runtime_pids="$runtime_pids $!"
done
printf '%s\n' ']' >>"$simulation_directory/runtime-endpoints.json"
printf '%s' '' >"$simulation_directory/cosign.pub"

start_controller() {
  epoch=$1
  env \
    LUNANEXA_LISTEN_ADDRESS="$control_address" \
    LUNANEXA_STATE_PATH="$simulation_directory/control.json" \
    LUNANEXA_REGISTRY_PATH="$simulation_directory/registry.json" \
    LUNANEXA_ENROLLMENT_PATH="$simulation_directory/enrollment.json" \
    LUNANEXA_SCHEDULER_PATH="$simulation_directory/scheduler.json" \
    LUNANEXA_TELEMETRY_PATH="$simulation_directory/telemetry.json" \
    LUNANEXA_WORKSPACE_PATH="$simulation_directory/workspace.json" \
    LUNANEXA_DEPLOYMENT_PATH="$simulation_directory/deployments.json" \
    LUNANEXA_EXCLUSIVE_LEASE_PATH="$simulation_directory/exclusive-leases.json" \
    LUNANEXA_REQUIRE_WORKSPACE_LEASE=1 \
    LUNANEXA_RUNTIME_ENDPOINT='http://127.0.0.1:1/v1/responses' \
    LUNANEXA_RUNTIME_ENDPOINTS_PATH="$simulation_directory/runtime-endpoints.json" \
    LUNANEXA_RUNTIME_CREDENTIAL="$runtime_token" \
    LUNANEXA_RUNTIME_VERSION='sim-runtime-v1' \
    LUNANEXA_RUNTIME_IMAGE_DIGEST="$image_digest" \
    LUNANEXA_MODEL_ARTIFACT_DIGEST="$artifact_digest" \
    LUNANEXA_ALLOW_HTTP_LOOPBACK=1 \
    LUNANEXA_CONTROLLER_EPOCH="$epoch" \
    LUNANEXA_RECONCILIATION_ONLY=0 \
    LUNANEXA_OPERATOR_TOKEN="$operator_token" \
    LUNANEXA_INFERENCE_TOKEN="$inference_token" \
    LUNANEXA_AUDIT_TOKEN="$audit_token" \
    LUNANEXA_MONITORING_TOKEN="$monitoring_token" \
    LUNANEXA_ASSIGNMENT_SIGNING_SECRET="$assignment_secret" \
    LUNANEXA_CATALOG_SIGNING_SECRET="simulation-catalog-authority" \
    LUNANEXA_EXCLUSIVE_LEASE_SIGNING_SECRET="simulation-exclusive-lease-authority" \
    LUNANEXA_API_KEY_ISSUER_SECRET="simulation-api-key-authority-0123456789" \
    LUNANEXA_COSIGN_BINARY='/usr/bin/cosign' \
    LUNANEXA_COSIGN_PUBLIC_KEY_PATH="$simulation_directory/cosign.pub" \
    LUNANEXA_RUNTIME_CONCURRENCY=1 \
    "$control_binary" >>"$simulation_directory/controller-epoch-$epoch.log" 2>&1 &
  control_pid=$!
}

wait_controller() {
  attempts=0
  while [ "$attempts" -lt 160 ]; do
    if curl --fail --silent --max-time 1 "$base_url/health" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$control_pid" 2>/dev/null; then
      printf '%s\n' 'simulated controller exited before becoming ready' >&2
      return 1
    fi
    attempts=$((attempts + 1))
    sleep 0.05
  done
  return 1
}

start_controller_until_ready() {
  epoch=$1
  attempt=0
  while [ "$attempt" -lt 40 ]; do
    start_controller "$epoch"
    if wait_controller; then
      return 0
    fi
    if [ -n "$control_pid" ] && kill -0 "$control_pid" 2>/dev/null; then
      kill "$control_pid" 2>/dev/null || true
    fi
    wait "$control_pid" 2>/dev/null || true
    control_pid=''
    attempt=$((attempt + 1))
    sleep 0.1
  done
  printf '%s\n' "simulated controller failed to bind or become ready after $attempt attempts" >&2
  return 1
}

start_node() {
  index=$1
  node_id="sim-dgx-$index"
  node_token="simulation-node-$index-authority"
  env \
    LUNANEXA_SIMULATION_ONLY=1 \
    LUNANEXA_ENDPOINT="$base_url" \
    LUNANEXA_NODE_ID="$node_id" \
    LUNANEXA_NODE_TOKEN="$node_token" \
    LUNANEXA_BOOTSTRAP_TOKEN_ID="bootstrap-$index" \
    LUNANEXA_BOOTSTRAP_TOKEN="bootstrap-$index-authority" \
    LUNANEXA_NODE_INVENTORY_PATH="$simulation_directory/$node_id-inventory.json" \
    LUNANEXA_NODE_STATE_PATH="$simulation_directory/$node_id-state.json" \
    LUNANEXA_NODE_CERTIFICATE_PATH="$simulation_directory/$node_id-certificate.json" \
    LUNANEXA_ASSIGNMENT_SIGNING_SECRET="$assignment_secret" \
    LUNANEXA_SIM_RUNTIME_HEALTH_ENDPOINT="http://127.0.0.1:$((base_port + index))/health" \
    LUNANEXA_SIM_POLL_MS=100 \
    "$node_binary" >"$simulation_directory/$node_id-node.log" 2>&1 &
  started_node_pid=$!
  node_pids="$node_pids $started_node_pid"
}

operator_post() {
  path=$1
  body=$2
  output=$3
  status=$(curl --silent --output "$output" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $operator_token" \
    --header 'Content-Type: application/json' \
    --data "$body" "$base_url$path")
  case "$status" in
    200|201|202) ;;
    *) printf '%s\n' "operator request $path failed with HTTP $status" >&2; return 1 ;;
  esac
}

operator_put() {
  path=$1
  body=$2
  output=$3
  status=$(curl --silent --output "$output" --write-out '%{http_code}' \
    --request PUT \
    --header "Authorization: Bearer $operator_token" \
    --header 'Content-Type: application/json' \
    --data "$body" "$base_url$path")
  case "$status" in
    200|201|202) ;;
    *) printf '%s\n' "operator request $path failed with HTTP $status" >&2; return 1 ;;
  esac
}

wait_for_pattern() {
  path=$1
  pattern=$2
  attempts=0
  # Process scheduling under the complete release gate can be materially slower
  # than a focused run. Keep the wait bounded, but allow 30 seconds for the
  # controller -> node -> heartbeat reconciliation loop to complete.
  while [ "$attempts" -lt 600 ]; do
    curl --fail --silent --max-time 1 \
      --header "Authorization: Bearer $operator_token" \
      "$base_url$path" >"$simulation_directory/poll.json" 2>/dev/null || true
    if rg -q "$pattern" "$simulation_directory/poll.json"; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.05
  done
  printf '%s\n' "timed out waiting for $pattern at $path" >&2
  tail -n 30 "$simulation_directory"/controller-epoch-*.log >&2 || true
  tail -n 20 "$simulation_directory"/sim-dgx-*-node.log >&2 || true
  return 1
}

assignment_body() {
  index=$1
  expiry=$2
  printf '%s' \
    "{\"assignment_id\":\"assignment-sim-$index\",\"deployment_id\":\"deployment-sim-$index\",\"node_id\":\"sim-dgx-$index\",\"artifact\":{\"digest\":\"$artifact_digest\",\"uri\":\"s3://simulator/model.text/v1\",\"size_bytes\":\"1024\",\"signature_ref\":\"simulator-evidence:model.text:v1\"},\"runtime\":{\"name\":\"text-runtime\",\"image_digest\":\"$image_digest\",\"version\":\"sim-runtime-v1\",\"architectures\":[\"nvidia-gb10\"],\"capabilities\":[\"TextGenerate\"],\"supports_batching\":false,\"supports_multi_node\":false},\"resources\":{\"accelerator_count\":1,\"accelerator_memory_mib\":8192,\"cpu_millis\":2000,\"memory_mib\":16384},\"devices\":[\"gpu-0\"],\"network\":{\"allow_controller\":true,\"allow_artifact_store\":true,\"allowed_egress\":[]},\"health\":{\"readiness_path\":\"/health\",\"interval_ms\":1000,\"failure_threshold\":3,\"termination_grace_ms\":5000},\"data_policy\":{\"classification\":\"Confidential\",\"retention\":\"Ephemeral\",\"allow_cache\":false,\"allow_training_reuse\":false},\"generation\":\"1\",\"lease_expires_unix_ms\":\"$expiry\",\"controller_epoch\":\"1\",\"signature\":\"\"}"
}

invoke() {
  id=$1
  output=$2
  now_ms=$(($(date +%s) * 1000))
  deadline=$((now_ms + 15000))
  body="{\"version\":\"lunanexa.v1\",\"idempotency_key\":\"idem-$id\",\"workload_id\":\"workload-$id\",\"tenant_ref\":\"simulated-tenant\",\"credential_scope\":\"inference\",\"capability\":\"TextGenerate\",\"model_selector\":\"text.default\",\"payload\":{\"input\":\"functional simulator request\"},\"data_policy\":{\"classification\":\"Confidential\",\"retention\":\"Ephemeral\",\"allow_cache\":false,\"allow_training_reuse\":false},\"deadline_unix_ms\":\"$deadline\",\"priority\":\"Interactive\",\"latency_class\":\"Realtime\",\"resource_ceiling\":{\"max_input_units\":64,\"max_output_units\":32,\"max_runtime_ms\":\"5000\",\"max_accelerator_memory_mib\":8192},\"stream\":false,\"output_format\":\"text\",\"trace_token\":\"simulation-trace-$id\"}"
  status=$(curl --silent --output "$output" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $inference_token" \
    --header "X-LunaNexa-Subject: $workspace_subject" \
    --header 'Content-Type: application/json' \
    --data "$body" "$base_url/v1/workloads")
  test "$status" = '200'
  rg -q '"state":"Succeeded"' "$output"
}

start_controller_until_ready 1

now_ms=$(($(date +%s) * 1000))
bootstrap_expiry=$((now_ms + 600000))
assignment_expiry=$((now_ms + 600000))
for index in 1 2 3 4; do
  operator_post '/v1/enrollment/tokens' \
    "{\"token_id\":\"bootstrap-$index\",\"secret\":\"bootstrap-$index-authority\",\"expires_unix_ms\":\"$bootstrap_expiry\"}" \
    "$simulation_directory/bootstrap-$index.json"
  start_node "$index"
done
wait_for_pattern '/v1/nodes' 'sim-dgx-4'

catalog_template="{\"template_id\":\"text-small\",\"version\":\"v1\",\"display_name\":\"Text small\",\"description\":\"Simulation-only approved text service\",\"model_selector\":\"text.default\",\"model_id\":\"model.text\",\"model_version\":\"v1\",\"artifact\":{\"digest\":\"$artifact_digest\",\"uri\":\"s3://simulator/model.text/v1\",\"size_bytes\":\"1024\",\"signature_ref\":\"simulator-evidence:model.text:v1\"},\"runtime\":{\"name\":\"text-runtime\",\"image_digest\":\"$image_digest\",\"version\":\"sim-runtime-v1\",\"architectures\":[\"nvidia-gb10\"],\"capabilities\":[\"TextGenerate\"],\"supports_batching\":false,\"supports_multi_node\":false},\"capability\":\"TextGenerate\",\"architecture\":\"nvidia-gb10\",\"resources\":{\"accelerator_count\":1,\"accelerator_memory_mib\":8192,\"cpu_millis\":2000,\"memory_mib\":16384},\"network\":{\"allow_controller\":true,\"allow_artifact_store\":true,\"allowed_egress\":[]},\"health\":{\"readiness_path\":\"/health\",\"interval_ms\":1000,\"failure_threshold\":3,\"termination_grace_ms\":5000},\"data_policy\":{\"classification\":\"Confidential\",\"retention\":\"Ephemeral\",\"allow_cache\":false,\"allow_training_reuse\":false},\"secret_refs\":[],\"rollout\":{\"canary_replicas\":1,\"automatic_promotion\":false,\"automatic_rollback\":true,\"readiness_timeout_ms\":\"60000\"},\"approval_receipt\":\"\",\"signature\":\"\"}"
deployment_intent='{"version":"lunanexa.v1","idempotency_key":"console:deployment-one-click","deployment_id":"deployment-one-click","template":{"template_id":"text-small","version":"v1"},"replicas":1,"data_class":"Confidential","lease_duration_ms":"600000","promote_when_ready":false}'
operator_post '/v1/catalog/templates' "$catalog_template" \
  "$simulation_directory/catalog-template.json"
operator_post '/v1/deployment-plans' "$deployment_intent" \
  "$simulation_directory/deployment-plan.json"
rg -q '"executable":true' "$simulation_directory/deployment-plan.json"
rg -q '"node_id":"sim-dgx-1"' "$simulation_directory/deployment-plan.json"
if rg -q '"node_id":"sim-dgx-[234]"' "$simulation_directory/deployment-plan.json"; then
  printf '%s\n' 'one-click plan selected more than its assigned DGX' >&2
  exit 1
fi
operator_post '/v1/service-deployments' "$deployment_intent" \
  "$simulation_directory/deployment-one-click.json"
wait_for_pattern '/v1/nodes' 'deployment-one-click'
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $operator_token" \
  "$base_url/v1/assignments" >"$simulation_directory/one-click-assignments.json"
rg -q '"assignment_id":"deployment-one-click-r1","deployment_id":"deployment-one-click","node_id":"sim-dgx-1"' \
  "$simulation_directory/one-click-assignments.json"
if rg -q '"deployment_id":"deployment-one-click","node_id":"sim-dgx-[234]"' \
  "$simulation_directory/one-click-assignments.json"; then
  printf '%s\n' 'one-click assignment escaped its selected DGX' >&2
  exit 1
fi
operator_post '/v1/service-deployments' "$deployment_intent" \
  "$simulation_directory/deployment-one-click-replay.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $operator_token" \
  "$base_url/v1/assignments" >"$simulation_directory/one-click-assignments-replay.json"
test "$(rg -o 'deployment-one-click-r1' "$simulation_directory/one-click-assignments-replay.json" | wc -l | tr -d ' ')" -eq 1
conflicting_intent=$(printf '%s' "$deployment_intent" | sed 's/"lease_duration_ms":"600000"/"lease_duration_ms":"610000"/')
status=$(curl --silent --output "$simulation_directory/deployment-one-click-conflict.json" \
  --write-out '%{http_code}' --request POST \
  --header "Authorization: Bearer $operator_token" \
  --header 'Content-Type: application/json' \
  --data "$conflicting_intent" "$base_url/v1/service-deployments")
test "$status" = '409'
rg -q 'IdempotencyConflict' "$simulation_directory/deployment-one-click-conflict.json"
status=$(curl --silent --output "$simulation_directory/deployment-one-click-unauthorized.json" \
  --write-out '%{http_code}' --request POST \
  --header 'Content-Type: application/json' \
  --data "$deployment_intent" "$base_url/v1/service-deployments")
test "$status" = '401'
status=$(curl --silent --output "$simulation_directory/deployment-one-click-malformed.json" \
  --write-out '%{http_code}' --request POST \
  --header "Authorization: Bearer $operator_token" \
  --header 'Content-Type: application/json' \
  --data '{' "$base_url/v1/service-deployments")
test "$status" = '400'

for index in 1 2 3 4; do
  body=$(assignment_body "$index" "$assignment_expiry")
  status=$(curl --silent --output "$simulation_directory/assignment-$index.json" \
    --write-out '%{http_code}' --request PUT \
    --header "Authorization: Bearer $operator_token" \
    --header 'Content-Type: application/json' \
    --data "$body" "$base_url/v1/assignments")
  test "$status" = '202'
done
wait_for_pattern '/v1/nodes' 'deployment-sim-4'

status=$(curl --silent --output "$simulation_directory/quota.json" \
  --write-out '%{http_code}' --request PUT \
  --header "Authorization: Bearer $operator_token" \
  --header 'Content-Type: application/json' \
  --data '{"tenant_ref":"simulated-tenant","max_inflight":8,"max_accelerator_ms":"600000","window_ms":"60000"}' \
  "$base_url/v1/quotas")
test "$status" = '202'

workspace_starts=$((now_ms - 1000))
workspace_expires=$((now_ms + 600000))
operator_post '/v1/workspace/users' \
  "{\"version\":\"lunanexa.workspace.v1\",\"user_id\":\"sim-user\",\"subject_ref\":\"$workspace_subject\",\"display_name\":\"Simulation Developer\",\"email\":\"simulation@example.invalid\",\"state\":\"UserInvited\",\"created_unix_ms\":\"$workspace_starts\",\"identity_receipt\":\"identity-sim-user\"}" \
  "$simulation_directory/workspace-user.json"
operator_post '/v1/workspace/users/sim-user:activate' '' \
  "$simulation_directory/workspace-user-activated.json"
operator_post '/v1/workspace/access-grants' \
  "{\"version\":\"lunanexa.workspace.v1\",\"grant_id\":\"grant-sim-user\",\"user_id\":\"sim-user\",\"tenant_ref\":\"simulated-tenant\",\"access\":\"Developer\",\"starts_unix_ms\":\"$workspace_starts\",\"expires_unix_ms\":\"$workspace_expires\",\"state\":\"GrantActive\",\"policy_receipt\":\"grant-sim-user\"}" \
  "$simulation_directory/workspace-grant.json"
operator_post '/v1/workspace/leases' \
  "{\"version\":\"lunanexa.workspace.v1\",\"lease_id\":\"lease-sim-user\",\"tenant_ref\":\"simulated-tenant\",\"subject_ref\":\"$workspace_subject\",\"access\":\"Developer\",\"limits\":{\"max_active_sessions\":2,\"max_session_duration_ms\":\"600000\",\"capabilities\":[{\"capability\":\"TextGenerate\",\"max_concurrent_requests\":2,\"max_requests_per_hour\":100,\"max_input_units_per_request\":64,\"max_output_units_per_request\":64}]},\"starts_unix_ms\":\"$workspace_starts\",\"expires_unix_ms\":\"$workspace_expires\",\"state\":\"Requested\",\"policy_receipt\":\"lease-sim-user\"}" \
  "$simulation_directory/workspace-lease.json"
operator_post '/v1/workspace/leases/lease-sim-user:activate' '' \
  "$simulation_directory/workspace-lease-activated.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $inference_token" \
  --header "X-LunaNexa-Subject: $workspace_subject" \
  "$base_url/v1/workspace/self" >"$simulation_directory/workspace-self.json"
rg -q '"authorized":true' "$simulation_directory/workspace-self.json"
rg -q '"lease_id":"lease-sim-user"' "$simulation_directory/workspace-self.json"

invoke 'initial' "$simulation_directory/workload-initial.json"
test "$(wc -l <"$simulation_directory/sim-dgx-1-invocations.log" | tr -d ' ')" -eq 1

printf '%s\n' 'delay:300' >"$simulation_directory/sim-dgx-1-control"
invoke 'saturation-a' "$simulation_directory/workload-saturation-a.json" &
saturation_a_pid=$!
sleep 0.05
invoke 'saturation-b' "$simulation_directory/workload-saturation-b.json" &
saturation_b_pid=$!
wait "$saturation_a_pid"
wait "$saturation_b_pid"
rg -q '"queue_ms":"[1-9][0-9]*"' "$simulation_directory/workload-saturation-b.json"
printf '%s\n' 'ready' >"$simulation_directory/sim-dgx-1-control"

printf '%s\n' 'fail' >"$simulation_directory/sim-dgx-1-control"
invoke 'runtime-failover' "$simulation_directory/workload-runtime-failover.json"
test "$(wc -l <"$simulation_directory/sim-dgx-2-invocations.log" | tr -d ' ')" -eq 1
printf '%s\n' 'ready' >"$simulation_directory/sim-dgx-1-control"

operator_put '/v1/nodes/directive' \
  "{\"node_id\":\"sim-dgx-1\",\"desired_state\":\"Draining\",\"generation\":\"1\",\"issued_unix_ms\":\"$(($(date +%s) * 1000))\",\"receipt\":\"simulation-drain-1\"}" \
  "$simulation_directory/drain.json"
wait_for_pattern '/v1/nodes' 'Draining'
invoke 'after-drain' "$simulation_directory/workload-after-drain.json"
test "$(wc -l <"$simulation_directory/sim-dgx-2-invocations.log" | tr -d ' ')" -eq 2

node_two_pid=$(printf '%s\n' "$node_pids" | awk '{print $2}')
kill -9 "$node_two_pid"
wait "$node_two_pid" 2>/dev/null || true
start_node 2

kill -9 "$control_pid"
wait "$control_pid" 2>/dev/null || true
control_pid=''
start_controller_until_ready 2
wait_for_pattern '/v1/nodes' 'deployment-sim-2'
invoke 'after-restart' "$simulation_directory/workload-after-restart.json"

curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $operator_token" \
  "$base_url/v1/nodes" >"$simulation_directory/nodes.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $operator_token" \
  "$base_url/v1/assignments" >"$simulation_directory/assignments.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $audit_token" \
  "$base_url/v1/audit" >"$simulation_directory/audit.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $operator_token" \
  "$base_url/v1/telemetry" >"$simulation_directory/telemetry.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $operator_token" \
  "$base_url/v1/workspace" >"$simulation_directory/workspace.json.read"
rg -q '"grant_id":"grant-sim-user"' "$simulation_directory/workspace.json.read"
rg -q '"lease_id":"lease-sim-user"' "$simulation_directory/workspace.json.read"

operator_post '/v1/workspace/access-grants/grant-sim-user:revoke' '' \
  "$simulation_directory/workspace-grant-revoked.json"
operator_post '/v1/workspace/leases/lease-sim-user:end' '' \
  "$simulation_directory/workspace-lease-ended.json"
denied_now_ms=$(($(date +%s) * 1000))
denied_deadline=$((denied_now_ms + 15000))
denied_body="{\"version\":\"lunanexa.v1\",\"idempotency_key\":\"idem-after-revoke\",\"workload_id\":\"workload-after-revoke\",\"tenant_ref\":\"simulated-tenant\",\"credential_scope\":\"inference\",\"capability\":\"TextGenerate\",\"model_selector\":\"text.default\",\"payload\":{\"input\":\"revoked workspace request\"},\"data_policy\":{\"classification\":\"Confidential\",\"retention\":\"Ephemeral\",\"allow_cache\":false,\"allow_training_reuse\":false},\"deadline_unix_ms\":\"$denied_deadline\",\"priority\":\"Interactive\",\"latency_class\":\"Realtime\",\"resource_ceiling\":{\"max_input_units\":64,\"max_output_units\":32,\"max_runtime_ms\":\"5000\",\"max_accelerator_memory_mib\":8192},\"stream\":false,\"output_format\":\"text\",\"trace_token\":\"simulation-trace-after-revoke\"}"
status=$(curl --silent --output "$simulation_directory/workload-after-revoke.json" \
  --write-out '%{http_code}' --request POST \
  --header "Authorization: Bearer $inference_token" \
  --header "X-LunaNexa-Subject: $workspace_subject" \
  --header 'Content-Type: application/json' \
  --data "$denied_body" "$base_url/v1/workloads")
test "$status" = '403'
rg -q 'WorkspaceAccessDenied' "$simulation_directory/workload-after-revoke.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $inference_token" \
  --header "X-LunaNexa-Subject: $workspace_subject" \
  "$base_url/v1/workspace/self" >"$simulation_directory/workspace-self-revoked.json"
rg -q '"authorized":false' "$simulation_directory/workspace-self-revoked.json"
curl --fail --silent --max-time 2 \
  --header "Authorization: Bearer $audit_token" \
  "$base_url/v1/audit" >"$simulation_directory/audit.json"
rg -q 'workspace.user.activate' "$simulation_directory/audit.json"
rg -q 'workspace.lease.activate' "$simulation_directory/audit.json"
rg -q 'workspace.access.revoke' "$simulation_directory/audit.json"
rg -q 'workspace.lease.end' "$simulation_directory/audit.json"

for index in 1 2 3 4; do
  rg -q "sim-dgx-$index" "$simulation_directory/nodes.json"
  rg -q "assignment-sim-$index" "$simulation_directory/assignments.json"
done
for response in "$simulation_directory"/workload-*.json; do
  if rg -q 'sim-dgx-|127\.0\.0\.1|simulation-.*-authority|/Users/' "$response"; then
    printf '%s\n' "public response leaked simulator topology or authority: $response" >&2
    exit 1
  fi
done

printf '%s\n' \
  "{\"schema_version\":\"lunanexa.simulation.v1\",\"nodes\":4,\"enrollment\":\"passed\",\"one_click_preflight\":\"passed\",\"one_click_single_node_assignment\":\"passed\",\"one_click_idempotency\":\"passed\",\"workspace_authority\":\"passed\",\"signed_assignment_reconciliation\":\"passed\",\"bounded_queueing\":\"passed\",\"runtime_failover\":\"passed\",\"drain_reroute\":\"passed\",\"controller_restart\":\"passed\",\"node_restart\":\"passed\",\"public_response_scan\":\"passed\",\"hardware_performance_validated\":false}" \
  >"$simulation_directory/summary.json"

printf '%s\n' 'four-node functional DGX simulation passed'
if [ "$keep_artifacts" -eq 1 ]; then
  printf '%s\n' "evidence retained at $simulation_directory"
fi
