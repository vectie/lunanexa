#!/bin/sh
set -eu

cluster_name=lunanexa-sim
colima_profile=lunanexa
kubeconfig_path=${LUNANEXA_SIM_KUBECONFIG:-$HOME/.kube/lunanexa-sim}

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$cluster_name"; then
  kind delete cluster --name "$cluster_name"
fi
case "$kubeconfig_path" in
  /*) rm -f "$kubeconfig_path" ;;
  *) printf '%s\n' 'LUNANEXA_SIM_KUBECONFIG must be an absolute path' >&2; exit 1 ;;
esac

if [ "${1:-}" = "--stop-colima" ]; then
  colima stop "$colima_profile"
fi
