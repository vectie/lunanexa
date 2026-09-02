#!/bin/sh
set -eu

role=${1:-}
expected_name=${2:-}

case "$role" in
  management|compute) ;;
  *) printf '%s\n' 'invalid host role' >&2; exit 64 ;;
esac

case "$expected_name" in
  ''|*[!A-Za-z0-9._-]*) printf '%s\n' 'invalid expected node name' >&2; exit 64 ;;
esac

printf '[remote] role=%s expected-node=%s host=%s\n' "$role" "$expected_name" "$(hostname)"
uname -sr

if [ "$role" = management ]; then
  df -h /
  if test -d /data/models; then
    findmnt /data/models || printf '%s\n' '[notice] /data/models is a directory on the root filesystem'
    df -h /data/models
  else
    printf '%s\n' '[notice] /data/models is not provisioned yet'
  fi
else
  node_material_installer=/usr/libexec/lunanexa-install-node-material
  if ! command -v sudo >/dev/null 2>&1 ||
    ! sudo -n "$node_material_installer" --check; then
    printf '%s\n' '[blocked] compute enrollment requires the reviewed LunaNexa node-material helper and narrowly-scoped non-interactive sudo authorization' >&2
    exit 1
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    printf '%s\n' '[hardware] NVIDIA accelerator detected'
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
  elif command -v npu-smi >/dev/null 2>&1; then
    printf '%s\n' '[hardware] Ascend accelerator detected'
    npu-smi info
    printf '%s\n' '[blocked] Ascend host enrollment is disabled until a reviewed CANN runtime, Kubernetes device plugin, node telemetry collector and OCI supervisor adapter are installed and qualified' >&2
    exit 1
  else
    printf '%s\n' '[blocked] no supported accelerator inventory command was found' >&2
    exit 1
  fi
  if command -v podman >/dev/null 2>&1; then
    podman --version
  elif command -v docker >/dev/null 2>&1; then
    docker --version
  else
    printf '%s\n' '[blocked] Podman or Docker is required' >&2
    exit 1
  fi
  test -d /etc/lunanexa || printf '%s\n' '[notice] /etc/lunanexa will be created during apply'
fi

printf '%s\n' '[ok] remote preflight complete'
