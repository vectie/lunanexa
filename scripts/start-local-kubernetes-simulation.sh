#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cluster_name=lunanexa-sim
context_name=kind-lunanexa-sim
colima_profile=lunanexa
kubeconfig_path=${LUNANEXA_SIM_KUBECONFIG:-$HOME/.kube/lunanexa-sim}

case "$kubeconfig_path" in
  /*) ;;
  *) printf '%s\n' 'LUNANEXA_SIM_KUBECONFIG must be an absolute path' >&2; exit 1 ;;
esac
umask 077

for command_name in colima docker kind kubectl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

if ! colima status "$colima_profile" >/dev/null 2>&1; then
  printf 'Colima profile %s is not running. Start it before this script.\n' "$colima_profile" >&2
  exit 1
fi

export DOCKER_CONTEXT="colima-$colima_profile"
docker info >/dev/null
mkdir -p "${kubeconfig_path%/*}"

if ! kind get clusters 2>/dev/null | grep -qx "$cluster_name"; then
  kind create cluster \
    --name "$cluster_name" \
    --config "$repo_root/deploy/local-simulation/kind.yaml" \
    --kubeconfig "$kubeconfig_path" \
    --wait 180s
fi

temporary_kubeconfig="$kubeconfig_path.tmp.$$"
kind get kubeconfig --name "$cluster_name" > "$temporary_kubeconfig"
chmod 0600 "$temporary_kubeconfig"
mv "$temporary_kubeconfig" "$kubeconfig_path"

kubectl_sim() {
  KUBECONFIG="$kubeconfig_path" kubectl --context "$context_name" "$@"
}

kubectl_sim create namespace lunanexa --dry-run=client -o yaml | kubectl_sim apply -f -
kubectl_sim create namespace lunanexa-runtimes --dry-run=client -o yaml | kubectl_sim apply -f -
kubectl_sim apply -f "$repo_root/deploy/local-simulation/topology-smoke.yaml"
kubectl_sim -n lunanexa rollout status deployment/lunanexa-management-sim --timeout=180s
kubectl_sim -n lunanexa rollout status daemonset/lunanexa-compute-sim --timeout=180s

management_count=$(kubectl_sim get nodes -l lunanexa.io/role=management --no-headers | wc -l | tr -d ' ')
compute_count=$(kubectl_sim get nodes -l lunanexa.io/role=gpu --no-headers | wc -l | tr -d ' ')
test "$management_count" -eq 1
test "$compute_count" -eq 4

printf '\n%s\n' 'LunaNexa local Kubernetes topology is ready.'
kubectl_sim get nodes -L lunanexa.io/role,lunanexa.io/simulation
printf '\n'
kubectl_sim -n lunanexa get pods -o wide
printf '\nContext: %s\n' "$context_name"
printf 'Kubeconfig: %s\n' "$kubeconfig_path"
printf '%s\n' 'This is placement simulation only; it has no NVIDIA devices or production credentials.'
