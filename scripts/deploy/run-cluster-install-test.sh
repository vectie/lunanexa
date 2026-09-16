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
if [ "${TEST_SCENARIO:-}" = ssh_unavailable ]; then
  printf '%s\n' 'kex_exchange_identification: Connection closed by remote host' >&2
  exit 255
fi
EOF
cat > "$fake_bin/scp" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$fake_bin/kubectl" <<'EOF'
#!/bin/sh
if [ -n "${FAKE_KUBECTL_LOG:-}" ]; then printf '%s\n' "$*" >> "$FAKE_KUBECTL_LOG"; fi
case " $* " in
  *' diff -f '*)
    if [ "${TEST_SCENARIO:-}" = preview_diff_failure ]; then
      exit 2
    fi
    if [ "${TEST_SCENARIO:-}" = preview_no_change ]; then
      exit 0
    fi
    if [ "${TEST_SCENARIO:-}" = preview_diff_many ]; then
      index=1
      while [ "$index" -le 257 ]; do
        printf 'diff -u -N /tmp/LIVE-1/v1.ConfigMap.lunanexa.item-%s /tmp/MERGED-1/v1.ConfigMap.lunanexa.item-%s\n' \
          "$index" "$index"
        index=$((index + 1))
      done
      exit 1
    fi
    printf '%s\n' \
      'diff -u -N /tmp/LIVE-1/networking.k8s.io.v1.NetworkPolicy.lunanexa.lunanexa-control /tmp/MERGED-1/networking.k8s.io.v1.NetworkPolicy.lunanexa.lunanexa-control'
    exit 1
    ;;
  *' create --dry-run=client '*' -f '*' -o json '*)
    jq -nc --arg scenario "${TEST_SCENARIO:-healthy}" '
      [
        "account-session-issuer-secret",
        "api-key-issuer-secret",
        "artifact-scanner-callback-token",
        "artifact-worker-callback-token",
        "assignment-signing-secret",
        "audit-token",
        "catalog-signing-secret",
        "machine-commerce-signing-secret",
        "commercial-provider-adapter-token",
        "credential-handoff-issuer-secret",
        "credential-issuer-adapter-token",
        "entitlement-authority-callback-token",
        "exclusive-lease-signing-secret",
        "guide-admin-auth-key",
        "guide-diagnostics-token",
        "guide-observation-secret",
        "inference-token",
        "lease-helper-receipt-secret",
        "monitoring-token",
        "operator-token",
        "provider-callback-secret",
        "runtime-token"
      ] as $keys |
      (reduce range(0; ($keys | length)) as $index ({};
        .[$keys[$index]] =
          (("a" * 62 + (($index | tostring) as $suffix |
            if ($suffix | length) == 1 then "0" + $suffix else $suffix end)) | @base64)
      )) as $generated |
      (if $scenario == "management_secret_newline" then
        $generated + {"provider-callback-secret": (("a" * 64 + "\n") | @base64)}
      elif $scenario == "legacy_signing_secret" then
        $generated + {"catalog-signing-secret": (("a" * 64 + "\n") | @base64)}
      else $generated end) as $control |
      {
        apiVersion: "v1",
        kind: "List",
        items: [
          {apiVersion:"v1",kind:"Secret",metadata:{name:"lunanexa-control-credentials"},type:"Opaque",data:$control},
          {apiVersion:"v1",kind:"Secret",metadata:{name:"lunanexa-database"},type:"Opaque",data:{database:"bHVuYW5leGE=",password:"YQ==",url:"YQ==",username:"bHVuYW5leGE="}},
          {apiVersion:"v1",kind:"Secret",metadata:{name:"lunanexa-cosign-trust"},type:"Opaque",data:{"cosign.pub":"YQ=="}},
          {apiVersion:"v1",kind:"Secret",metadata:{name:"lunanexa-offline-commerce-readiness"},type:"Opaque",data:{pending:"cGVuZGluZw=="}},
          {apiVersion:"v1",kind:"Secret",metadata:{name:"lunanexa-model-source-credentials"},type:"Opaque",data:{token:"YQ=="}}
        ]
      }
    '
    ;;
  *' get node '*' -o json '*)
    if [ "${TEST_SCENARIO:-}" = missing_accelerator_resource ]; then
      printf '%s\n' '{"status":{"allocatable":{"cpu":"8","memory":"32Gi"}}}'
    else
      printf '%s\n' '{"status":{"allocatable":{"cpu":"8","memory":"32Gi","nvidia.com/gpu":"1"}}}'
    fi
    ;;
  *' create namespace '*) printf '%s\n' 'apiVersion: v1' 'kind: Namespace' ;;
  *' get nodes -l lunanexa.io/role=management --no-headers '*)
    printf '%s\n' 'lunanexa-sim-control-plane Ready'
    ;;
  *' get nodes -l lunanexa.io/role=gpu --no-headers '*)
    printf '%s\n' 'lunanexa-sim-worker Ready' 'lunanexa-sim-worker2 Ready' 'lunanexa-sim-worker3 Ready' 'lunanexa-sim-worker4 Ready'
    ;;
  *' get endpoints/lunanexa-'*) printf '%s\n' '10.42.0.10' ;;
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
    --deployment-target local-simulation > "$local_directory-preview.log" 2>&1
grep -q 'will start during apply' "$local_directory-preview.log"
test ! -f "$local_colima_state"

PATH="$fake_bin:$PATH" HOME="$local_home" \
  FAKE_COLIMA_STATE="$local_colima_state" \
  FAKE_COLIMA_LOG="$local_colima_log" \
  FAKE_KIND_STATE="$local_kind_state" \
  sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
    --mode apply \
    --namespace lunanexa \
    --kubeconfig "$local_kubeconfig" \
    --confirmation 'RECONCILE SIMULATION' \
    --deployment-target local-simulation > "$local_directory-apply.log" 2>&1
grep -q '^start lunanexa --cpus 4 --memory 6 --disk 30 --runtime docker$' "$local_colima_log"
grep -q 'simulated management and compute placements verified' "$local_directory-apply.log"
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
  healthy|no_ingress|combined_manifest|legacy_signing_secret|host_systemd)
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
  management_secret_manifest=$case_directory/management-secrets.yaml
  printf '%s\n' 'apiVersion: v1' 'kind: Secret' > "$management_secret_manifest"
  chmod 0600 "$management_secret_manifest"
  if [ "$scenario" = combined_manifest ]; then
    : > "$rendered_directory/management.yaml"
  else
    for manifest in prerequisites postgres controller console enterprise workbench network-policy ingress; do
      if [ "$scenario" = no_ingress ] && [ "$manifest" = ingress ]; then continue; fi
      if [ "$scenario" = missing_workbench ] && [ "$manifest" = workbench ]; then continue; fi
      : > "$rendered_directory/$manifest.yaml"
    done
  fi
  if [ "$scenario" = host_systemd ]; then
    printf '%s\n' host-systemd > "$rendered_directory/node-agent-layout"
    for name in lunanexa-node lunanexa-node.service admin-settings.json; do : > "$rendered_directory/$name"; done
    chmod +x "$rendered_directory/lunanexa-node"
  else
    printf '%s\n' 'nodeSelector: {lunanexa.io/role: gpu}' > "$rendered_directory/node-daemonset.yaml"
  fi
  for node_name in dgx-01 dgx-02 dgx-03 dgx-04; do
    mkdir -p "$secret_directory/$node_name"
    for name in node-token assignment-verification-key cosign.pub inventory.json bootstrap-token-id bootstrap-token bootstrap.json; do
      : > "$secret_directory/$node_name/$name"
    done
    if [ "$scenario" = host_systemd ]; then
      for name in node.env lunanexa-controller-tunnel.service tunnel-identity tunnel-known-hosts; do
        : > "$secret_directory/$node_name/$name"
      done
    fi
  done
  cli_path=$case_directory/lunanexa
  make_cli "$cli_path"
  output=$case_directory/output
  kubectl_log=$case_directory/kubectl.log

  set +e
  PATH="$fake_bin:$PATH" TMPDIR="$case_tmp" TEST_SCENARIO="$scenario" \
    FAKE_KUBECTL_LOG="$kubectl_log" \
    LUNANEXA_ENDPOINT=http://controller.example \
    LUNANEXA_OPERATOR_TOKEN=test-operator-token \
    sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
      --mode apply \
      --deployment-target management-and-compute \
      --ssh-user deploy \
      --ssh-key "$case_directory/id_key" \
      --known-hosts "$case_directory/known_hosts" \
      --management-node management-01 \
      --management-host management.example \
      --namespace lunanexa \
      --kubeconfig "$case_directory/kubeconfig" \
      --rendered-directory "$rendered_directory" \
      --management-secret-manifest "$management_secret_manifest" \
      --secret-directory "$secret_directory" \
      --cli-path "$cli_path" \
      --confirmation 'DEPLOY MANAGEMENT AND COMPUTE' \
      --compute dgx-01=dgx-01.example \
      --compute dgx-02=dgx-02.example \
      --compute dgx-03=dgx-03.example \
      --compute dgx-04=dgx-04.example > "$output" 2>&1
  status=$?
  set -e

  if [ "$expected_result" = pass ]; then
    test "$status" -eq 0
    grep -q '^\[ok\] 4 selected compute node(s) are Active with fresh heartbeats$' "$output"
    grep -q '^\[complete\] deployment target management-and-compute is reconciled$' "$output"
    if grep -q 'statefulset/lunanexa-postgres' "$kubectl_log"; then
      printf '%s\n' 'production installer unexpectedly managed bundled PostgreSQL' >&2
      exit 1
    fi
    grep -q 'create --dry-run=client --validate=false --namespace lunanexa' "$kubectl_log"
    if grep -q 'get endpoints/lunanexa-postgres' "$kubectl_log"; then
      printf '%s\n' 'production installer unexpectedly required bundled PostgreSQL' >&2
      exit 1
    fi
    grep -q "wait --for=jsonpath={.status.updatedReplicas}=3 deployment/lunanexa-control --timeout=5m" "$kubectl_log"
    grep -q "wait --for=jsonpath={.status.replicas}=3 deployment/lunanexa-control --timeout=5m" "$kubectl_log"
    grep -q "wait --for=jsonpath={.status.availableReplicas}=1 deployment/lunanexa-control --timeout=5m" "$kubectl_log"
    for deployment_name in lunanexa-console lunanexa-enterprise lunanexa-workbench lunanexa-model-source; do
      grep -q "rollout status deployment/$deployment_name --timeout=5m" "$kubectl_log"
      grep -q "get endpoints/$deployment_name" "$kubectl_log"
    done
    if [ "$scenario" = no_ingress ]; then
      grep -q '^\[info\] ingress omitted;' "$output"
    fi
    if [ "$scenario" = host_systemd ]; then
      if grep -q 'apply -f .*/node-daemonset.yaml' "$kubectl_log"; then
        printf '%s\n' 'host-systemd scenario unexpectedly applied the DaemonSet' >&2
        exit 1
      fi
    fi
  elif [ "$expected_result" = heartbeat_fail ]; then
    test "$status" -ne 0
    grep -q '^\[blocked\] selected compute nodes did not produce fresh Active heartbeats$' "$output"
    if grep -q '^\[complete\]' "$output"; then
      printf 'scenario %s printed a false completion marker\n' "$scenario" >&2
      exit 1
    fi
  elif [ "$expected_result" = accelerator_fail ]; then
    test "$status" -ne 0
    grep -q '^\[blocked\] node dgx-01 exposes no supported schedulable accelerator resource through Kubernetes$' "$output"
    if grep -q '^\[complete\]' "$output"; then
      printf 'scenario %s printed a false completion marker\n' "$scenario" >&2
      exit 1
    fi
  elif [ "$expected_result" = ssh_fail ]; then
    test "$status" -ne 0
    grep -q '^\[blocked\] pinned SSH preflight failed for the selected management target;' "$output"
    if grep -q '^\[complete\]' "$output"; then
      printf 'scenario %s printed a false completion marker\n' "$scenario" >&2
      exit 1
    fi
  elif [ "$expected_result" = secret_fail ]; then
    test "$status" -ne 0
    if ! grep -q '^\[blocked\] management secret manifest violates the exact resource, authority, or printable-byte contract$' "$output"; then
      printf 'scenario %s did not report the secret-contract blocker\n' "$scenario" >&2
      sed -n '1,80p' "$output" >&2
      exit 1
    fi
    if grep -q '^\[stage 2/' "$output"; then
      printf 'scenario %s contacted a remote target after secret rejection\n' "$scenario" >&2
      exit 1
    fi
  else
    test "$status" -ne 0
    if grep -q '^\[complete\]' "$output"; then
      printf 'scenario %s printed a false completion marker\n' "$scenario" >&2
      exit 1
    fi
  fi
}

run_case healthy pass
run_case no_ingress pass
run_case combined_manifest pass
run_case legacy_signing_secret pass
run_case host_systemd pass
run_case missing_workbench manifest_fail
run_case missing heartbeat_fail
run_case extra pass
run_case wrong_id heartbeat_fail
run_case duplicate heartbeat_fail
run_case inactive heartbeat_fail
run_case stale heartbeat_fail
run_case future heartbeat_fail
run_case malformed heartbeat_fail
run_case missing_accelerator_resource accelerator_fail
run_case ssh_unavailable ssh_fail
run_case management_secret_newline secret_fail

# Management Preview must report bounded resource identities without diffing
# the protected Secret manifest or printing raw manifest values.
preview_management_directory=$test_directory/preview-management
mkdir -p "$preview_management_directory/tmp"
preview_management_output=$preview_management_directory/output
preview_management_log=$preview_management_directory/kubectl.log
PATH="$fake_bin:$PATH" TMPDIR="$preview_management_directory/tmp" \
  TEST_SCENARIO=preview_policy_change FAKE_KUBECTL_LOG="$preview_management_log" \
  sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
    --mode preview \
    --deployment-target management-foundation \
    --ssh-user deploy \
    --ssh-key "$test_directory/combined_manifest/id_key" \
    --known-hosts "$test_directory/combined_manifest/known_hosts" \
    --management-node management-01 \
    --management-host management.example \
    --namespace lunanexa \
    --kubeconfig "$test_directory/combined_manifest/kubeconfig" \
    --rendered-directory "$test_directory/combined_manifest/rendered" \
    --management-secret-manifest "$test_directory/combined_manifest/management-secrets.yaml" \
    --confirmation '' > "$preview_management_output" 2>&1
grep -q '^\[plan\] management change networking.k8s.io.v1.NetworkPolicy.lunanexa.lunanexa-control$' \
  "$preview_management_output"
grep -q '^\[plan\] 1 non-secret management resource(s) differ; Secret data was not diffed$' \
  "$preview_management_output"
grep -q '^\[preview\] management-foundation validation passed; no resources were changed$' \
  "$preview_management_output"
grep ' diff -f ' "$preview_management_log" |
  grep -q '/combined_manifest/rendered/management.yaml$'
if grep ' diff -f ' "$preview_management_log" | grep -q 'management-secrets.yaml'; then
  printf '%s\n' 'management Preview diffed the protected Secret manifest' >&2
  exit 1
fi

set +e
PATH="$fake_bin:$PATH" TMPDIR="$preview_management_directory/tmp" \
  TEST_SCENARIO=preview_diff_failure FAKE_KUBECTL_LOG="$preview_management_log" \
  sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
    --mode preview \
    --deployment-target management-foundation \
    --ssh-user deploy \
    --ssh-key "$test_directory/combined_manifest/id_key" \
    --known-hosts "$test_directory/combined_manifest/known_hosts" \
    --management-node management-01 \
    --management-host management.example \
    --namespace lunanexa \
    --kubeconfig "$test_directory/combined_manifest/kubeconfig" \
    --rendered-directory "$test_directory/combined_manifest/rendered" \
    --management-secret-manifest "$test_directory/combined_manifest/management-secrets.yaml" \
    --confirmation '' > "$preview_management_directory/failure-output" 2>&1
preview_diff_failure_status=$?
set -e
test "$preview_diff_failure_status" -ne 0
grep -q '^\[blocked\] Kubernetes diff failed for management.yaml; no resources were changed$' \
  "$preview_management_directory/failure-output"
if grep -q '^\[preview\]' "$preview_management_directory/failure-output"; then
  printf '%s\n' 'failed Kubernetes diff printed a false Preview success marker' >&2
  exit 1
fi

set +e
PATH="$fake_bin:$PATH" TMPDIR="$preview_management_directory/tmp" \
  TEST_SCENARIO=preview_diff_many FAKE_KUBECTL_LOG="$preview_management_log" \
  sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
    --mode preview \
    --deployment-target management-foundation \
    --ssh-user deploy \
    --ssh-key "$test_directory/combined_manifest/id_key" \
    --known-hosts "$test_directory/combined_manifest/known_hosts" \
    --management-node management-01 \
    --management-host management.example \
    --namespace lunanexa \
    --kubeconfig "$test_directory/combined_manifest/kubeconfig" \
    --rendered-directory "$test_directory/combined_manifest/rendered" \
    --management-secret-manifest "$test_directory/combined_manifest/management-secrets.yaml" \
    --confirmation '' > "$preview_management_directory/many-output" 2>&1
preview_diff_many_status=$?
set -e
test "$preview_diff_many_status" -ne 0
grep -q '^\[blocked\] Kubernetes change plan exceeded 256 resource identities; no resources were changed$' \
  "$preview_management_directory/many-output"
if grep -q '^\[plan\] management change ' "$preview_management_directory/many-output"; then
  printf '%s\n' 'oversized Kubernetes diff printed a partial resource plan' >&2
  exit 1
fi

# Adding compute capacity depends on the existing Kubernetes/API context and
# the selected compute hosts. It must not invent or require a management-host
# SSH endpoint.
compute_only_directory=$test_directory/compute-only
mkdir -p "$compute_only_directory/tmp"
printf '%s\n' 'image: ${UNRELATED_MANAGEMENT_IMAGE}' > \
  "$test_directory/healthy/rendered/unselected-template.yaml"
PATH="$fake_bin:$PATH" TMPDIR="$compute_only_directory/tmp" \
  sh "$repo_root/scripts/deploy/run-cluster-install.sh" \
    --mode preview \
    --deployment-target compute-expansion \
    --ssh-user deploy \
    --ssh-key "$test_directory/healthy/id_key" \
    --known-hosts "$test_directory/healthy/known_hosts" \
    --namespace lunanexa \
    --kubeconfig "$test_directory/healthy/kubeconfig" \
    --rendered-directory "$test_directory/healthy/rendered" \
    --secret-directory "$test_directory/healthy/secrets" \
    --cli-path "$test_directory/healthy/lunanexa" \
    --confirmation '' \
    --compute dgx-01=dgx-01.example > "$compute_only_directory/output" 2>&1
grep -q '^\[preview\] compute-expansion validation passed; no resources were changed$' \
  "$compute_only_directory/output"

printf '%s\n' 'cluster installer heartbeat gate tests passed'
