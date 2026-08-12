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

if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true; then
  printf '%s\n' '[blocked] passwordless narrowly-scoped sudo is required' >&2
  exit 1
fi

if [ "$role" = management ]; then
  test -d /data/models
  findmnt /data/models
  df -h /data/models
else
  command -v nvidia-smi >/dev/null 2>&1
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
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
