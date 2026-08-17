#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-installer-test.XXXXXX")
cleanup() {
  rm -rf "$test_directory"
}
trap cleanup EXIT HUP INT TERM

fake_bin=$test_directory/bin
mkdir -p "$fake_bin"

cat > "$fake_bin/ssh" <<'EOF'
#!/bin/sh
cat >/dev/null || true
EOF
cat > "$fake_bin/scp" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$fake_bin/kubectl" <<'EOF'
#!/bin/sh
case " $* " in
  *' create namespace '*) printf '%s\n' 'apiVersion: v1' 'kind: Namespace' ;;
  *' get nodes -l lunanexa.io/role=management --no-headers '*)
    printf '%s\n' 'lunanexa-sim-control-plane Ready'
    ;;
  *' get nodes -l lunanexa.io/role=gpu --no-headers '*)
    printf '%s\n' 'lunanexa-sim-worker Ready' 'lunanexa-sim-worker2 Ready' 'lunanexa-sim-worker3 Ready' 'lunanexa-sim-worker4 Ready'
    ;;
esac
exit 0
EOF
cat > "$fake_bin/colima" <<'EOF'
#!/bin/sh
case "${1:-}" in
  status) test -f "${FAKE_COLIMA_STATE:?}" ;;
  start)
    printf '%s\n' "$*" >> "${FAKE_COLIMA_LOG:?}"
    : > "${FAKE_COLIMA_STATE:?}"
    ;;
  *) exit 64 ;;
esac
EOF
cat > "$fake_bin/docker" <<'EOF'
#!/bin/sh
test "${1:-}" = info
test -f "${FAKE_COLIMA_STATE:?}"
EOF
cat > "$fake_bin/kind" <<'EOF'
#!/bin/sh
case "${1:-} ${2:-}" in
  'get clusters')
    if test -f "${FAKE_KIND_STATE:?}"; then printf '%s\n' lunanexa-sim; fi
    ;;
  'create cluster')
    : > "${FAKE_KIND_STATE:?}"
    ;;
  'delete cluster')
    rm -f "${FAKE_KIND_STATE:?}"
    ;;
  'get kubeconfig')
    printf '%s\n' 'apiVersion: v1' 'kind: Config'
    ;;
  *) exit 64 ;;
esac
EOF
cat > "$fake_bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$fake_bin/ssh" "$fake_bin/scp" "$fake_bin/kubectl" "$fake_bin/sleep"
chmod +x "$fake_bin/colima" "$fake_bin/docker" "$fake_bin/kind"

local_directory=$test_directory/local-simulation
local_home=$local_directory/home
local_kubeconfig=$local_home/.kube/lunanexa-sim
local_colima_state=$local_directory/colima-running
local_colima_log=$local_directory/colima.log
local_kind_state=$local_directory/kind-running
mkdir -p "$local_home/.kube"

PATH="$fake_bin:$PATH" HOME="$local_home" \
  FAKE_COLIMA_STATE="$local_colima_state" \
  FAKE_COLIMA_LOG="$local_colima_log" \
  FAKE_KIND_STATE="$local_kind_state" \
  sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
    --mode preview \
    --namespace lunanexa \
    --kubeconfig "$local_kubeconfig" \
    --confirmation '' \
    --local-simulation > "$local_directory-preview.log" 2>&1
grep -q 'will be started during apply' "$local_directory-preview.log"
test ! -f "$local_colima_state"

PATH="$fake_bin:$PATH" HOME="$local_home" \
  FAKE_COLIMA_STATE="$local_colima_state" \
  FAKE_COLIMA_LOG="$local_colima_log" \
  FAKE_KIND_STATE="$local_kind_state" \
  sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
    --mode apply \
    --namespace lunanexa \
    --kubeconfig "$local_kubeconfig" \
    --confirmation 'DEPLOY 4 NODES' \
    --local-simulation > "$local_directory-apply.log" 2>&1
grep -q '^start lunanexa --cpus 4 --memory 6 --disk 30 --runtime docker$' "$local_colima_log"
grep -q 'one management and four compute placements verified' "$local_directory-apply.log"
test -f "$local_colima_state"
test -f "$local_kind_state"

make_cli() {
  cli=$1
  cat > "$cli" <<'EOF'
#!/bin/sh
if [ "${1:-}" != nodes ]; then
  printf '%s\n' '{"accepted":true}'
  exit 0
fi
now_unix_ms="$(date +%s)000"
stale_unix_ms=$((now_unix_ms - 16000))
# Keep this well beyond the installer's 5-second allowance even if the wall
# clock advances between the fixture response and verification.
future_unix_ms=$((now_unix_ms + 15000))
case "${TEST_SCENARIO:-healthy}" in
  healthy)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-04","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$now_unix_ms" "$now_unix_ms"
    ;;
  missing)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$now_unix_ms"
    ;;
  extra)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-04","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-05","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$now_unix_ms" "$now_unix_ms" "$now_unix_ms"
    ;;
  wrong_id)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-99","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$now_unix_ms" "$now_unix_ms"
    ;;
  duplicate)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$now_unix_ms" "$now_unix_ms"
    ;;
  inactive)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Cordoned","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-04","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$now_unix_ms" "$now_unix_ms"
    ;;
  stale)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-04","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$stale_unix_ms" "$now_unix_ms"
    ;;
  future)
    printf '[{"node_id":"dgx-01","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-02","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-03","state":"Active","timestamp_unix_ms":"%s"},{"node_id":"dgx-04","state":"Active","timestamp_unix_ms":"%s"}]\n' "$now_unix_ms" "$now_unix_ms" "$future_unix_ms" "$now_unix_ms"
    ;;
  malformed)
    printf '%s\n' '{"node_id":"dgx-01"}'
    ;;
  *) exit 70 ;;
esac
EOF
  chmod +x "$cli"
}

run_case() {
  scenario=$1
  expected_result=$2
  case_directory=$test_directory/$scenario
  rendered_directory=$case_directory/rendered
  secret_directory=$case_directory/secrets
  case_tmp=$case_directory/tmp
  mkdir -p "$rendered_directory" "$secret_directory" "$case_tmp"
  : > "$case_directory/id_key"
  : > "$case_directory/known_hosts"
  : > "$case_directory/kubeconfig"
  for manifest in prerequisites postgres controller console enterprise network-policy ingress; do
    : > "$rendered_directory/$manifest.yaml"
  done
  printf '%s\n' 'nodeSelector: {lunanexa.io/role: gpu}' > "$rendered_directory/node-daemonset.yaml"
  for node_name in dgx-01 dgx-02 dgx-03 dgx-04; do
    mkdir -p "$secret_directory/$node_name"
    for name in node-token assignment-verification-key cosign.pub inventory.json bootstrap-token-id bootstrap-token bootstrap.json; do
      : > "$secret_directory/$node_name/$name"
    done
  done
  cli_path=$case_directory/lunanexa
  make_cli "$cli_path"
  output=$case_directory/output

  set +e
  PATH="$fake_bin:$PATH" TMPDIR="$case_tmp" TEST_SCENARIO="$scenario" \
    LUNANEXA_ENDPOINT=http://controller.example \
    LUNANEXA_OPERATOR_TOKEN=test-operator-token \
    sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
      --mode apply \
      --ssh-user deploy \
      --ssh-key "$case_directory/id_key" \
      --known-hosts "$case_directory/known_hosts" \
      --management-node management-01 \
      --management-host management.example \
      --namespace lunanexa \
      --kubeconfig "$case_directory/kubeconfig" \
      --rendered-directory "$rendered_directory" \
      --secret-directory "$secret_directory" \
      --cli-path "$cli_path" \
      --confirmation 'DEPLOY 4 NODES' \
      --compute dgx-01=dgx-01.example \
      --compute dgx-02=dgx-02.example \
      --compute dgx-03=dgx-03.example \
      --compute dgx-04=dgx-04.example > "$output" 2>&1
  status=$?
  set -e

  if [ "$expected_result" = pass ]; then
    test "$status" -eq 0
    grep -q '^\[ok\] exactly four expected compute nodes are Active with fresh heartbeats$' "$output"
    grep -q '^\[complete\] LunaNexa management plane and four compute nodes are deployed$' "$output"
  else
    test "$status" -ne 0
    grep -q '^\[blocked\] expected four distinct Active compute nodes with heartbeats no older than 15 seconds$' "$output"
    if grep -q '^\[complete\]' "$output"; then
      printf 'scenario %s printed a false completion marker\n' "$scenario" >&2
      exit 1
    fi
  fi
}

run_case healthy pass
run_case missing fail
run_case extra fail
run_case wrong_id fail
run_case duplicate fail
run_case inactive fail
run_case stale fail
run_case future fail
run_case malformed fail

printf '%s\n' 'cluster installer heartbeat gate tests passed'
