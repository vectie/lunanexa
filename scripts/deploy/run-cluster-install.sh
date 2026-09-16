#!/bin/sh
set -eu
umask 077

mode= deployment_target= ssh_user= ssh_key= known_hosts=
ssh_port=22
management_node= management_host= cluster_namespace= kubeconfig=
rendered_directory= secret_directory= cli_path= compute_targets= confirmation=
management_secret_manifest=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) mode=$2; shift 2 ;;
    --deployment-target) deployment_target=$2; shift 2 ;;
    --ssh-user) ssh_user=$2; shift 2 ;;
    --ssh-port) ssh_port=$2; shift 2 ;;
    --ssh-key) ssh_key=$2; shift 2 ;;
    --known-hosts) known_hosts=$2; shift 2 ;;
    --management-node) management_node=$2; shift 2 ;;
    --management-host) management_host=$2; shift 2 ;;
    --namespace) cluster_namespace=$2; shift 2 ;;
    --kubeconfig) kubeconfig=$2; shift 2 ;;
    --rendered-directory) rendered_directory=$2; shift 2 ;;
    --management-secret-manifest) management_secret_manifest=$2; shift 2 ;;
    --secret-directory) secret_directory=$2; shift 2 ;;
    --cli-path) cli_path=$2; shift 2 ;;
    --confirmation) confirmation=$2; shift 2 ;;
    --compute) compute_targets="${compute_targets}${compute_targets:+
}$2"; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

safe_identifier() { case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac; }
safe_host() { case "$1" in ''|*[!A-Za-z0-9.:[\]-]*) return 1 ;; esac; }
absolute_path() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "/$1/" in */../*) return 1 ;; esac
}

case "$mode" in preview|apply) ;; *) printf '%s\n' 'mode must be preview or apply' >&2; exit 64 ;; esac
case "$deployment_target" in
  management-foundation|compute-expansion|management-and-compute|local-simulation) ;;
  *) printf '%s\n' 'deployment target is invalid' >&2; exit 64 ;;
esac
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

if [ "$deployment_target" = local-simulation ]; then
  case "$kubeconfig" in '~/'*) kubeconfig="$HOME/${kubeconfig#\~/}" ;; esac
  absolute_path "$kubeconfig"
  for command_name in colima docker kind kubectl; do command -v "$command_name" >/dev/null; done
  if ! colima status lunanexa >/dev/null 2>&1; then
    if [ "$mode" = preview ]; then
      printf '%s\n' '[local 1/5] dedicated Colima profile will start during apply'
      printf '%s\n' '[local 2/5] required local tools are installed'
      printf '%s\n' '[local 3/5] simulation topology will be created during apply'
      printf '%s\n' '[preview] local simulation can be created; no resources were changed'
      exit 0
    fi
    test "$confirmation" = 'RECONCILE SIMULATION'
    printf '%s\n' '[local 1/5] starting dedicated minimal Colima profile'
    colima start lunanexa --cpus 4 --memory 6 --disk 30 --runtime docker
  fi
  export DOCKER_CONTEXT=colima-lunanexa
  docker info >/dev/null
  printf '%s\n' '[local 1/5] dedicated Colima profile is ready'
  printf '%s\n' '[local 2/5] Docker and kind tooling are ready'
  printf '%s\n' '[local 3/5] simulation topology inspected'
  if [ "$mode" = preview ]; then
    printf '%s\n' '[preview] local simulation is ready; no resources were changed'
    exit 0
  fi
  test "$confirmation" = 'RECONCILE SIMULATION'
  printf '%s\n' '[local 4/5] reconciling simulation-only placement probes'
  LUNANEXA_SIM_KUBECONFIG="$kubeconfig" sh "$repo_root/scripts/start-local-kubernetes-simulation.sh"
  printf '%s\n' '[local 5/5] simulated management and compute placements verified'
  exit 0
fi

for value in "$ssh_user" "$ssh_key" "$known_hosts" "$cluster_namespace" "$kubeconfig" \
  "$rendered_directory"; do test -n "$value"; done
safe_identifier "$ssh_user"; safe_identifier "$cluster_namespace"
case "$ssh_port" in ''|*[!0-9]*) exit 64 ;; esac
test "$ssh_port" -ge 1 && test "$ssh_port" -le 65535
absolute_path "$ssh_key"; absolute_path "$known_hosts"; absolute_path "$kubeconfig"; absolute_path "$rendered_directory"

installs_management=0 installs_compute=0
case "$deployment_target" in
  management-foundation) installs_management=1; expected_confirmation='DEPLOY MANAGEMENT'; stage_total=6 ;;
  compute-expansion) installs_compute=1; expected_confirmation='ADD COMPUTE'; stage_total=7 ;;
  management-and-compute) installs_management=1; installs_compute=1; expected_confirmation='DEPLOY MANAGEMENT AND COMPUTE'; stage_total=10 ;;
esac
if [ "$installs_compute" -eq 1 ]; then
  test -n "$secret_directory" && test -n "$cli_path"
  absolute_path "$secret_directory"; absolute_path "$cli_path"
fi
if [ "$installs_management" -eq 1 ]; then
  test -n "$management_node" && test -n "$management_host"
  safe_identifier "$management_node"; safe_host "$management_host"
  test -n "$management_secret_manifest"
  absolute_path "$management_secret_manifest"
fi
if [ "$mode" = apply ]; then
  test "$confirmation" = "$expected_confirmation"
  if [ "$installs_compute" -eq 1 ]; then
    test -n "${LUNANEXA_ENDPOINT:-}" && test -n "${LUNANEXA_OPERATOR_TOKEN:-}"
  fi
fi

lock_directory=${TMPDIR:-/tmp}/lunanexa-installer.lock
if ! mkdir -m 0700 -- "$lock_directory" 2>/dev/null; then
  printf '%s\n' '[blocked] another deployment session is active' >&2; exit 1
fi
cleanup_lock() {
  rm -f "$lock_directory/nodes.json" "$lock_directory/expected-node-ids" \
    "$lock_directory/management.diff"
  rmdir "$lock_directory" 2>/dev/null || true
}
trap cleanup_lock EXIT HUP INT TERM

ssh_options="-o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10"
run_ssh() {
  # shellcheck disable=SC2086
  if ssh $ssh_options -p "$ssh_port" -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
    "$ssh_user@$1" sh -s -- "$2" "$3" < "$repo_root/scripts/deploy/preflight-host.sh"; then
    return 0
  fi
  printf '[blocked] pinned SSH preflight failed for the selected %s target; restore SSH service or operator forwarding, verify the pinned host identity, and rerun Preview\n' "$2" >&2
  return 1
}
stage_index=0
stage() { stage_index=$((stage_index + 1)); printf '[stage %s/%s] %s\n' "$stage_index" "$stage_total" "$1"; }

verify_management_manifests() {
  if [ -f "$rendered_directory/management.yaml" ]; then
    return
  fi
  for manifest in prerequisites.yaml controller.yaml console.yaml enterprise.yaml workbench.yaml network-policy.yaml; do
    test -f "$rendered_directory/$manifest"
  done
}

verify_management_secret_manifest() {
  if ! KUBECONFIG="$kubeconfig" kubectl create --dry-run=client \
    --validate=false --namespace "$cluster_namespace" \
    -f "$management_secret_manifest" -o json |
    jq -se --arg namespace "$cluster_namespace" '
      def resources:
        [.[] | if .kind == "List" then .items[] else . end];
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
      ] as $control_keys |
      [
        "lunanexa-control-credentials",
        "lunanexa-cosign-trust",
        "lunanexa-database",
        "lunanexa-model-source-credentials",
        "lunanexa-offline-commerce-readiness"
      ] as $secret_names |
      resources as $resources |
      ($resources | length) == 5 and
      ([$resources[].metadata.name] | sort) == ($secret_names | sort) and
      all($resources[];
        .apiVersion == "v1" and .kind == "Secret" and
        (.type == null or .type == "Opaque") and
        (.metadata.namespace == null or .metadata.namespace == $namespace)) and
      ([$resources[] | select(.metadata.name == "lunanexa-control-credentials")] | length) == 1 and
      ($resources[] | select(.metadata.name == "lunanexa-control-credentials") | .data) as $control |
      ($control | keys | sort) == ($control_keys | sort) and
      ([$control[]] | unique | length) == ($control_keys | length) and
      all($control | to_entries[];
        try ((.value | @base64d) as $decoded |
          if .key == "provider-callback-secret" then
            ($decoded | length) == 64 and ($decoded | test("^[0-9a-f]{64}$"))
          else
            (($decoded | length) == 64 and ($decoded | test("^[0-9a-f]{64}$"))) or
            (($decoded | length) == 65 and ($decoded | test("^[0-9a-f]{64}\\n$")))
          end)
        catch false) and
      (($resources[] | select(.metadata.name == "lunanexa-database") | .data | keys | sort) ==
        (["database", "password", "url", "username"] | sort)) and
      (($resources[] | select(.metadata.name == "lunanexa-cosign-trust") | .data | keys) ==
        ["cosign.pub"]) and
      (($resources[] | select(.metadata.name == "lunanexa-offline-commerce-readiness") | .data | keys) ==
        ["pending"]) and
      (($resources[] | select(.metadata.name == "lunanexa-model-source-credentials") | .data | keys) ==
        ["token"])
    ' >/dev/null; then
    printf '%s\n' '[blocked] management secret manifest violates the exact resource, authority, or printable-byte contract' >&2
    return 1
  fi
}

placeholder_output=
scan_manifest_for_placeholders() {
  manifest_path=$1
  matches=$(rg -l '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' "$manifest_path" || true)
  if [ -n "$matches" ]; then
    placeholder_output="${placeholder_output}${placeholder_output:+
}${matches}"
  fi
}

verify_compute_heartbeats() {
  expected_node_ids=$1 expected_count=$2 nodes_output=$lock_directory/nodes.json attempt=1
  while [ "$attempt" -le 30 ]; do
    if (ulimit -f 2048; "$cli_path" nodes > "$nodes_output") 2>/dev/null; then
      output_bytes=$(wc -c < "$nodes_output" | tr -d ' ')
      now_unix_ms=$(($(date +%s) * 1000))
      if [ "$output_bytes" -le 1048576 ] && jq -e \
        --rawfile expected "$expected_node_ids" --argjson count "$expected_count" --argjson now "$now_unix_ms" '
          ($expected | split("\n") | map(select(length > 0))) as $ids
          | ([.[] | select(.node_id as $id | $ids | index($id))]) as $selected
          | ($ids | length) == $count and ($ids | unique | length) == $count
          and ($selected | length) == $count
          and ($selected | map(.node_id) | unique | length) == $count
          and all($selected[];
            .state == "Active" and (.timestamp_unix_ms | test("^[0-9]+$"))
            and ((.timestamp_unix_ms | tonumber) >= ($now - 15000))
            and ((.timestamp_unix_ms | tonumber) <= ($now + 5000)))
        ' "$nodes_output" >/dev/null; then
        printf '[ok] %s selected compute node(s) are Active with fresh heartbeats\n' "$expected_count"; return 0
      fi
    fi
    [ "$attempt" -eq 30 ] || sleep 2
    attempt=$((attempt + 1))
  done
  printf '%s\n' '[blocked] selected compute nodes did not produce fresh Active heartbeats' >&2; return 1
}

verify_kubernetes_accelerator() {
  accelerator_node=$1
  accelerator_kind=$(KUBECONFIG="$kubeconfig" kubectl get node "$accelerator_node" -o json | jq -r '
    (.status.allocatable // {}) as $resources
    | if (($resources["nvidia.com/gpu"] // "0") | tonumber? // 0) > 0
      then "nvidia"
      elif ([
        $resources
        | to_entries[]
        | select(.key | startswith("huawei.com/Ascend"))
        | (.value | tonumber? // 0)
      ] | add // 0) > 0
      then "ascend"
      else ""
      end
  ')
  case "$accelerator_kind" in
    nvidia)
      printf '[ok] node %s exposes a schedulable NVIDIA resource through Kubernetes\n' "$accelerator_node"
      ;;
    ascend)
      printf '%s\n' '[blocked] Kubernetes exposes Ascend capacity, but this release has no qualified Ascend node runtime adapter' >&2
      return 1
      ;;
    *)
      printf '[blocked] node %s exposes no supported schedulable accelerator resource through Kubernetes\n' "$accelerator_node" >&2
      return 1
      ;;
  esac
}

wait_for_management_rollouts() {
  printf '%s\n' '[wait] deployment/lunanexa-control elected leader endpoint'
  KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" wait \
    --for=jsonpath='{.status.updatedReplicas}'=3 \
    deployment/lunanexa-control --timeout=5m
  KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" wait \
    --for=jsonpath='{.status.replicas}'=3 \
    deployment/lunanexa-control --timeout=5m
  KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" wait \
    --for=jsonpath='{.status.availableReplicas}'=1 \
    deployment/lunanexa-control --timeout=5m
  for deployment_name in lunanexa-console lunanexa-enterprise lunanexa-workbench lunanexa-model-source; do
    printf '[wait] deployment/%s\n' "$deployment_name"
    KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" rollout status \
      "deployment/$deployment_name" --timeout=5m
  done
}

verify_management_services() {
  KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" get \
    statefulsets,deployments,pods,services
  for service_name in lunanexa-control lunanexa-console lunanexa-enterprise lunanexa-workbench lunanexa-model-source; do
    endpoint_addresses=$(KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" get \
      "endpoints/$service_name" \
      -o 'jsonpath={range .subsets[*].addresses[*]}{.ip}{"\n"}{end}')
    if [ -z "$endpoint_addresses" ]; then
      printf '[blocked] service/%s has no ready endpoint\n' "$service_name" >&2
      return 1
    fi
    printf '[ok] service/%s has a ready endpoint\n' "$service_name"
  done
}

preview_management_changes() {
  management_diff=$lock_directory/management.diff
  : > "$management_diff"
  chmod 0600 "$management_diff"
  difference_found=0
  if [ -f "$rendered_directory/management.yaml" ]; then
    preview_manifests=$rendered_directory/management.yaml
  else
    preview_manifests=
    for manifest in prerequisites.yaml controller.yaml console.yaml enterprise.yaml workbench.yaml network-policy.yaml; do
      preview_manifests="${preview_manifests}${preview_manifests:+
}$rendered_directory/$manifest"
    done
    if [ -f "$rendered_directory/ingress.yaml" ]; then
      preview_manifests="${preview_manifests}
$rendered_directory/ingress.yaml"
    fi
  fi

  previous_ifs=$IFS
  IFS='
'
  for preview_manifest in $preview_manifests; do
    if (ulimit -f 2048; KUBECONFIG="$kubeconfig" kubectl \
      -n "$cluster_namespace" diff -f "$preview_manifest") \
      >> "$management_diff" 2>&1; then
      :
    else
      diff_status=$?
      if [ "$diff_status" -eq 1 ]; then
        difference_found=1
      else
        IFS=$previous_ifs
        printf '[blocked] Kubernetes diff failed for %s; no resources were changed\n' \
          "$(basename "$preview_manifest")" >&2
        return 1
      fi
    fi
  done
  IFS=$previous_ifs

  if [ "$difference_found" -eq 0 ]; then
    printf '%s\n' '[plan] reviewed management manifest already matches the live cluster'
    return 0
  fi

  changed_resources=$(awk '/^diff -u -N / { print $NF }' "$management_diff" |
    sed 's#^.*/##' | LC_ALL=C sort -u)
  if [ -z "$changed_resources" ]; then
    printf '%s\n' '[blocked] Kubernetes reported changes but their resource identities could not be summarized; no resources were changed' >&2
    return 1
  fi
  changed_count=$(printf '%s\n' "$changed_resources" | wc -l | tr -d ' ')
  if [ "$changed_count" -gt 256 ]; then
    printf '%s\n' '[blocked] Kubernetes change plan exceeded 256 resource identities; no resources were changed' >&2
    return 1
  fi
  if printf '%s\n' "$changed_resources" | rg -qv '^[A-Za-z0-9._-]{1,512}$'; then
    printf '%s\n' '[blocked] Kubernetes change plan contained an invalid resource identity; no resources were changed' >&2
    return 1
  fi
  printf '%s\n' "$changed_resources" | while IFS= read -r resource; do
    printf '[plan] management change %s\n' "$resource"
  done
  printf '[plan] %s non-secret management resource(s) differ; Secret data was not diffed\n' \
    "$changed_count"
}

stage 'validate operator-side paths'
test -f "$ssh_key"; test -f "$known_hosts"; test -f "$kubeconfig"; test -d "$rendered_directory"
if [ "$installs_management" -eq 1 ]; then
  command -v jq >/dev/null
  test -f "$management_secret_manifest"; test ! -L "$management_secret_manifest"
  secret_mode=$(stat -f '%Lp' "$management_secret_manifest" 2>/dev/null || stat -c '%a' "$management_secret_manifest")
  case "$secret_mode" in 400|600) ;; *) printf '%s\n' '[blocked] management secret manifest must have mode 0400 or 0600' >&2; exit 1 ;; esac
  verify_management_secret_manifest
  verify_management_manifests
  if [ -f "$rendered_directory/management.yaml" ]; then
    scan_manifest_for_placeholders "$rendered_directory/management.yaml"
  else
    for manifest in prerequisites.yaml controller.yaml console.yaml enterprise.yaml workbench.yaml network-policy.yaml; do
      scan_manifest_for_placeholders "$rendered_directory/$manifest"
    done
  fi
  if [ -f "$rendered_directory/ingress.yaml" ]; then
    scan_manifest_for_placeholders "$rendered_directory/ingress.yaml"
  fi
fi
node_agent_layout=kubernetes-daemonset
if [ -f "$rendered_directory/node-agent-layout" ]; then
  node_agent_layout=$(sed -n '1p' "$rendered_directory/node-agent-layout")
fi
case "$node_agent_layout" in
  kubernetes-daemonset|host-systemd) ;;
  *) printf '%s\n' '[blocked] node-agent-layout must be kubernetes-daemonset or host-systemd' >&2; exit 1 ;;
esac
if [ "$installs_compute" -eq 1 ]; then
  command -v jq >/dev/null; test -d "$secret_directory"; test -x "$cli_path"
  if [ "$node_agent_layout" = kubernetes-daemonset ]; then
    test -f "$rendered_directory/node-daemonset.yaml"
    scan_manifest_for_placeholders "$rendered_directory/node-daemonset.yaml"
  else
    test -f "$rendered_directory/lunanexa-node"
    test -f "$rendered_directory/lunanexa-node.service"
    test -f "$rendered_directory/admin-settings.json"
  fi
fi
if [ -n "$placeholder_output" ]; then
  printf '%s\n%s\n' '[blocked] rendered manifests still contain placeholders' "$placeholder_output" >&2; exit 1
fi

if [ "$installs_management" -eq 1 ]; then
  stage 'inspect selected management host over pinned SSH'
  run_ssh "$management_host" management "$management_node"
  KUBECONFIG="$kubeconfig" kubectl get node "$management_node" -o wide
fi

old_ifs=$IFS
IFS='
'
compute_count=0
: > "$lock_directory/expected-node-ids"
if [ "$installs_compute" -eq 1 ]; then
  stage 'inspect selected compute hosts'
  for target in $compute_targets; do
    node_name=${target%%=*}; host=${target#*=}
    safe_identifier "$node_name"; safe_host "$host"
    compute_count=$((compute_count + 1)); printf '%s\n' "$node_name" >> "$lock_directory/expected-node-ids"
    run_ssh "$host" compute "$node_name"
    KUBECONFIG="$kubeconfig" kubectl get node "$node_name" -o wide
    verify_kubernetes_accelerator "$node_name"
    for name in node-token assignment-verification-key cosign.pub inventory.json bootstrap-token-id bootstrap-token bootstrap.json; do
      test -f "$secret_directory/$node_name/$name"
    done
    if [ "$node_agent_layout" = host-systemd ]; then
      for name in node.env lunanexa-controller-tunnel.service tunnel-identity tunnel-known-hosts; do
        test -f "$secret_directory/$node_name/$name"
      done
    fi
  done
  test "$compute_count" -ge 1 && test "$compute_count" -le 256
  if [ "$deployment_target" = compute-expansion ]; then
    stage 'verify management-plane readiness'
    KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" get deployment/lunanexa-control
  fi
fi
IFS=$old_ifs

if [ "$installs_management" -eq 1 ]; then
  stage 'verify selected Kubernetes context'
  KUBECONFIG="$kubeconfig" kubectl cluster-info
fi
if [ "$mode" = preview ]; then
  if [ "$installs_management" -eq 1 ]; then
    preview_management_changes
  fi
  printf '[preview] %s validation passed; no resources were changed\n' "$deployment_target"; exit 0
fi

if [ "$installs_management" -eq 1 ]; then
  if [ "$deployment_target" = management-and-compute ]; then stage 'label management and compute nodes'; else stage 'label management node'; fi
  KUBECONFIG="$kubeconfig" kubectl label node "$management_node" lunanexa.io/role=management --overwrite
fi
if [ "$installs_compute" -eq 1 ]; then
  [ "$deployment_target" = management-and-compute ] || stage 'label selected compute nodes'
  IFS='
'
  for target in $compute_targets; do
    node_name=${target%%=*}; KUBECONFIG="$kubeconfig" kubectl label node "$node_name" lunanexa.io/role=gpu --overwrite
  done
  IFS=$old_ifs
fi

if [ "$installs_management" -eq 1 ]; then
  stage 'apply reviewed management manifests'
  KUBECONFIG="$kubeconfig" kubectl create namespace "$cluster_namespace" --dry-run=client -o yaml | KUBECONFIG="$kubeconfig" kubectl apply -f -
  KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" apply -f "$management_secret_manifest"
  if [ -f "$rendered_directory/management.yaml" ]; then
    KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" apply -f "$rendered_directory/management.yaml"
  else
    for manifest in prerequisites.yaml controller.yaml console.yaml enterprise.yaml workbench.yaml network-policy.yaml; do
      KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" apply -f "$rendered_directory/$manifest"
    done
  fi
  if [ -f "$rendered_directory/ingress.yaml" ]; then
    KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" apply -f "$rendered_directory/ingress.yaml"
  else
    printf '%s\n' '[info] ingress omitted; use a protected port-forward until the reviewed TLS edge is rendered'
  fi
  wait_for_management_rollouts
  stage 'verify management services'
  verify_management_services
fi

if [ "$installs_compute" -eq 1 ]; then
  stage 'install protected node material'
  IFS='
'
  for target in $compute_targets; do
    node_name=${target%%=*}; host=${target#*=}; remote_stage="/tmp/lunanexa-install-$node_name"
    # shellcheck disable=SC2086
    ssh $ssh_options -p "$ssh_port" -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" "$ssh_user@$host" mkdir -m 0700 -- "$remote_stage"
    # shellcheck disable=SC2086
    scp $ssh_options -P "$ssh_port" -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
      "$secret_directory/$node_name/node-token" "$secret_directory/$node_name/assignment-verification-key" \
      "$secret_directory/$node_name/cosign.pub" "$secret_directory/$node_name/inventory.json" \
      "$secret_directory/$node_name/bootstrap-token-id" "$secret_directory/$node_name/bootstrap-token" \
      "$ssh_user@$host:$remote_stage/"
    if [ "$node_agent_layout" = host-systemd ]; then
      # shellcheck disable=SC2086
      scp $ssh_options -P "$ssh_port" -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
        "$rendered_directory/lunanexa-node" "$rendered_directory/lunanexa-node.service" \
        "$rendered_directory/admin-settings.json" "$secret_directory/$node_name/node.env" \
        "$secret_directory/$node_name/lunanexa-controller-tunnel.service" \
        "$secret_directory/$node_name/tunnel-identity" "$secret_directory/$node_name/tunnel-known-hosts" \
        "$ssh_user@$host:$remote_stage/"
    fi
    # shellcheck disable=SC2086
    ssh $ssh_options -p "$ssh_port" -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
      "$ssh_user@$host" sudo -n /usr/libexec/lunanexa-install-node-material "$remote_stage"
  done
  IFS=$old_ifs
  stage 'issue one-use enrollment tokens'
  IFS='
'
  for target in $compute_targets; do node_name=${target%%=*}; "$cli_path" issue-enrollment-token "$secret_directory/$node_name/bootstrap.json"; done
  IFS=$old_ifs
  stage 'apply node agent and verify selected heartbeats'
  if [ "$node_agent_layout" = kubernetes-daemonset ]; then
    test -f "$rendered_directory/node-daemonset.yaml"
    rg -q 'lunanexa.io/role:[[:space:]]*gpu' "$rendered_directory/node-daemonset.yaml"
    KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" apply -f "$rendered_directory/node-daemonset.yaml"
    KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" rollout status daemonset/lunanexa-node --timeout=10m
  else
    IFS='
'
    for target in $compute_targets; do
      host=${target#*=}
      # shellcheck disable=SC2086
      ssh $ssh_options -p "$ssh_port" -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
        "$ssh_user@$host" sudo -n /usr/libexec/lunanexa-install-node-material --start
    done
    IFS=$old_ifs
  fi
  verify_compute_heartbeats "$lock_directory/expected-node-ids" "$compute_count"
  IFS='
'
  for target in $compute_targets; do
    host=${target#*=}
    # shellcheck disable=SC2086
    ssh $ssh_options -p "$ssh_port" -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
      "$ssh_user@$host" sudo -n /usr/libexec/lunanexa-install-node-material --cleanup-bootstrap
  done
  IFS=$old_ifs
fi
printf '[complete] deployment target %s is reconciled\n' "$deployment_target"
