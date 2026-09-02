#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
listen_address=${LUNANEXA_INSTALLER_LISTEN_ADDRESS:-127.0.0.1:4198}
token_file=${LUNANEXA_INSTALLER_TOKEN_FILE:-}

if [ -z "${LUNANEXA_INSTALLER_TOKEN:-}" ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    printf '%s\n' 'openssl is required to generate a local installer token' >&2
    exit 1
  fi
  LUNANEXA_INSTALLER_TOKEN=$(openssl rand -hex 32)
  export LUNANEXA_INSTALLER_TOKEN
fi

export LUNANEXA_INSTALLER_LISTEN_ADDRESS=$listen_address
printf 'Deployment companion: http://%s\n' "$listen_address"
if [ -n "$token_file" ]; then
  case "$token_file" in /*) ;; *) printf '%s\n' 'installer token file must be absolute' >&2; exit 64 ;; esac
  case "/$token_file/" in */../*) printf '%s\n' 'installer token file may not traverse parent directories' >&2; exit 64 ;; esac
  if [ -e "$token_file" ] || [ -L "$token_file" ]; then
    printf '%s\n' 'installer token file already exists' >&2
    exit 1
  fi
  umask 077
  (set -C; printf '%s\n' "$LUNANEXA_INSTALLER_TOKEN" > "$token_file")
  printf 'Session token written to protected file: %s\n' "$token_file"
else
  printf 'Session token: %s\n' "$LUNANEXA_INSTALLER_TOKEN"
fi
printf '%s\n' 'Keep this terminal open. The companion accepts loopback connections only.'
cd "$repo_root"
exec moon run cmd/installer --target native
