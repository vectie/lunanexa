#!/bin/sh
set -eu
umask 077

mode=
ssh_user=
ssh_key=
known_hosts=
management_node=
management_host=
cluster_namespace=
kubeconfig=
rendered_directory=
secret_directory=
cli_path=
compute_targets=
confirmation=
local_simulation=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) mode=$2; shift 2 ;;
    --ssh-user) ssh_user=$2; shift 2 ;;
    --ssh-key) ssh_key=$2; shift 2 ;;
    --known-hosts) known_hosts=$2; shift 2 ;;
    --management-node) management_node=$2; shift 2 ;;
    --management-host) management_host=$2; shift 2 ;;
    --namespace) cluster_namespace=$2; shift 2 ;;
    --kubeconfig) kubeconfig=$2; shift 2 ;;
    --rendered-directory) rendered_directory=$2; shift 2 ;;
    --secret-directory) secret_directory=$2; shift 2 ;;
    --cli-path) cli_path=$2; shift 2 ;;
    --confirmation) confirmation=$2; shift 2 ;;
    --compute) compute_targets="${compute_targets}${compute_targets:+
}$2"; shift 2 ;;
    --local-simulation) local_simulation=1; shift ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

safe_identifier() {
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; *) return 0 ;; esac
}

safe_host() {
  case "$1" in ''|*[!A-Za-z0-9.:[\]-]*) return 1 ;; *) return 0 ;; esac
}

absolute_path() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "/$1/" in */../*) return 1 ;; esac
  return 0
}

case "$mode" in preview|apply) ;; *) printf '%s\n' 'mode must be preview or apply' >&2; exit 64 ;; esac
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

if [ "$local_simulation" -eq 1 ]; then
  case "$kubeconfig" in
    '~/'*) kubeconfig="$HOME/${kubeconfig#\~/}" ;;
  esac
  absolute_path "$kubeconfig"
  for command_name in colima docker kind kubectl; do
    command -v "$command_name" >/dev/null 2>&1
  done
  colima status lunanexa >/dev/null
  export DOCKER_CONTEXT=colima-lunanexa
  docker info >/dev/null
  printf '%s\n' '[local 1/5] dedicated Colima profile is ready'
  printf '%s\n' '[local 2/5] Docker and kind tooling are ready'
  if kind get clusters 2>/dev/null | grep -qx lunanexa-sim; then
    test -f "$kubeconfig"
    management_count=$(KUBECONFIG="$kubeconfig" kubectl --context kind-lunanexa-sim get nodes -l lunanexa.io/role=management --no-headers | wc -l | tr -d ' ')
    compute_count=$(KUBECONFIG="$kubeconfig" kubectl --context kind-lunanexa-sim get nodes -l lunanexa.io/role=gpu --no-headers | wc -l | tr -d ' ')
    test "$management_count" -eq 1
    test "$compute_count" -eq 4
    printf '%s\n' '[local 3/5] five-node Kubernetes topology is ready'
  else
    printf '%s\n' '[local 3/5] five-node Kubernetes topology will be created during apply'
  fi
  if [ "$mode" = preview ]; then
    printf '%s\n' '[preview] local Colima simulation is ready; no resources were changed'
    exit 0
  fi
  test "$confirmation" = 'DEPLOY 4 NODES'
  printf '%s\n' '[local 4/5] reconciling simulation-only placement probes'
  LUNANEXA_SIM_KUBECONFIG="$kubeconfig" sh "$repo_root/scripts/start-local-kubernetes-simulation.sh"
  printf '%s\n' '[local 5/5] one management and four compute placements verified'
  exit 0
fi

for value in "$ssh_user" "$ssh_key" "$known_hosts" "$management_node" "$management_host" \
  "$cluster_namespace" "$kubeconfig" "$rendered_directory" "$secret_directory" "$cli_path"; do
  test -n "$value"
done
safe_identifier "$ssh_user"
safe_identifier "$management_node"
safe_identifier "$cluster_namespace"
safe_host "$management_host"
absolute_path "$ssh_key"
absolute_path "$known_hosts"
absolute_path "$kubeconfig"
absolute_path "$rendered_directory"
absolute_path "$secret_directory"
absolute_path "$cli_path"
if [ "$mode" = apply ]; then
  test "$confirmation" = 'DEPLOY 4 NODES'
  test -n "${LUNANEXA_ENDPOINT:-}"
  test -n "${LUNANEXA_OPERATOR_TOKEN:-}"
fi

lock_directory=${TMPDIR:-/tmp}/lunanexa-installer.lock
if ! mkdir -m 0700 -- "$lock_directory" 2>/dev/null; then
  printf '%s\n' '[blocked] another deployment session is active' >&2
  exit 1
fi
cleanup_lock() {
  rmdir "$lock_directory" 2>/dev/null || true
}
trap cleanup_lock EXIT HUP INT TERM

ssh_options="-o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10"

run_ssh() {
  host=$1
  role=$2
  node_name=$3
  # shellcheck disable=SC2086
  ssh $ssh_options -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
    "$ssh_user@$host" sh -s -- "$role" "$node_name" < "$repo_root/scripts/deploy/preflight-host.sh"
}

printf '%s\n' '[stage 1/9] validate local paths'
test -f "$ssh_key"
test -f "$known_hosts"
test -f "$kubeconfig"
test -d "$rendered_directory"
test -d "$secret_directory"
test -x "$cli_path"
placeholder_output=$(rg -l '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' "$rendered_directory" || true)
if [ -n "$placeholder_output" ]; then
  printf '%s\n' '[blocked] rendered manifests still contain placeholders' >&2
  printf '%s\n' "$placeholder_output" >&2
  exit 1
fi

printf '%s\n' '[stage 2/9] verify pinned SSH host keys'
# BatchMode + StrictHostKeyChecking makes this a non-interactive trust check.
run_ssh "$management_host" management "$management_node"
printf '%s\n' '[stage 3/9] inspect management disk and Kubernetes inventory'
KUBECONFIG="$kubeconfig" kubectl get node "$management_node" -o wide

printf '%s\n' '[stage 4/9] inspect four DGX GPU workers'
old_ifs=$IFS
IFS='
'
compute_count=0
for target in $compute_targets; do
  node_name=${target%%=*}
  host=${target#*=}
  safe_identifier "$node_name"
  safe_host "$host"
  compute_count=$((compute_count + 1))
  run_ssh "$host" compute "$node_name"
  KUBECONFIG="$kubeconfig" kubectl get node "$node_name" -o wide
  for name in node-token assignment-verification-key cosign.pub inventory.json bootstrap-token-id bootstrap-token bootstrap.json; do
    test -f "$secret_directory/$node_name/$name"
  done
done
IFS=$old_ifs
test "$compute_count" -eq 4

if [ "$mode" = preview ]; then
  printf '%s\n' '[preview] validation passed; no hosts or Kubernetes resources were changed'
  printf '%s\n' '[preview] apply will label 1 management + 4 GPU nodes, apply reviewed manifests, install protected node files, issue enrollment tokens, and verify heartbeats'
  exit 0
fi

printf '%s\n' '[stage 5/9] label management and GPU nodes'
KUBECONFIG="$kubeconfig" kubectl label node "$management_node" lunanexa.io/role=management --overwrite
IFS='
'
for target in $compute_targets; do
  node_name=${target%%=*}
  KUBECONFIG="$kubeconfig" kubectl label node "$node_name" lunanexa.io/role=gpu --overwrite
done
IFS=$old_ifs

printf '%s\n' '[stage 6/9] apply rendered management manifests'
KUBECONFIG="$kubeconfig" kubectl create namespace "$cluster_namespace" --dry-run=client -o yaml | KUBECONFIG="$kubeconfig" kubectl apply -f -
for manifest in prerequisites.yaml postgres.yaml controller.yaml console.yaml enterprise.yaml network-policy.yaml ingress.yaml; do
  test -f "$rendered_directory/$manifest"
  KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" apply -f "$rendered_directory/$manifest"
done
KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" rollout status deployment/lunanexa-control --timeout=5m

printf '%s\n' '[stage 7/9] install protected node material'
IFS='
'
for target in $compute_targets; do
  node_name=${target%%=*}
  host=${target#*=}
  remote_stage="/tmp/lunanexa-install-$node_name"
  # shellcheck disable=SC2086
  ssh $ssh_options -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" "$ssh_user@$host" mkdir -m 0700 -- "$remote_stage"
  # shellcheck disable=SC2086
  scp $ssh_options -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
    "$secret_directory/$node_name/node-token" \
    "$secret_directory/$node_name/assignment-verification-key" \
    "$secret_directory/$node_name/cosign.pub" \
    "$secret_directory/$node_name/inventory.json" \
    "$secret_directory/$node_name/bootstrap-token-id" \
    "$secret_directory/$node_name/bootstrap-token" \
    "$repo_root/scripts/deploy/install-node-material.sh" \
    "$ssh_user@$host:$remote_stage/"
  # shellcheck disable=SC2086
  ssh $ssh_options -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
    "$ssh_user@$host" sh "$remote_stage/install-node-material.sh" "$remote_stage"
done
IFS=$old_ifs

printf '%s\n' '[stage 8/9] issue one-use enrollment tokens'
IFS='
'
for target in $compute_targets; do
  node_name=${target%%=*}
  "$cli_path" issue-enrollment-token "$secret_directory/$node_name/bootstrap.json"
done
IFS=$old_ifs

printf '%s\n' '[stage 9/9] apply node agent and verify heartbeats'
test -f "$rendered_directory/node-daemonset.yaml"
rg -q 'lunanexa.io/role:[[:space:]]*gpu' "$rendered_directory/node-daemonset.yaml"
KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" apply -f "$rendered_directory/node-daemonset.yaml"
KUBECONFIG="$kubeconfig" kubectl -n "$cluster_namespace" rollout status daemonset/lunanexa-node --timeout=10m
"$cli_path" nodes

IFS='
'
for target in $compute_targets; do
  host=${target#*=}
  # shellcheck disable=SC2086
  ssh $ssh_options -i "$ssh_key" -o "UserKnownHostsFile=$known_hosts" \
    "$ssh_user@$host" sh -s < "$repo_root/scripts/deploy/remove-bootstrap-material.sh"
done
IFS=$old_ifs
printf '%s\n' '[complete] LunaNexa management plane and four compute nodes are deployed'
