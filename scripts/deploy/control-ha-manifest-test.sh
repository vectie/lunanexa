#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
manifest="$repo_root/deploy/controller.yaml"
network_policy="$repo_root/deploy/network-policy.yaml"

grep -q '^  replicas: 3$' "$manifest"
grep -q 'name: LUNANEXA_DATABASE_HA_MODE' "$manifest"
grep -q 'value: external-managed' "$manifest"
grep -q 'name: LUNANEXA_CONTROLLER_INSTANCE_ID' "$manifest"
grep -q 'fieldPath: metadata.uid' "$manifest"
grep -q 'preferredDuringSchedulingIgnoredDuringExecution:' "$manifest"
grep -q 'emptyDir: {}' "$manifest"
if grep -q 'claimName: lunanexa-control-state' "$manifest"; then
  printf '%s\n' 'controller HA manifest must not mount the RWO state PVC' >&2
  exit 1
fi
if grep -q 'LUNANEXA_MODEL_STORE_ROOT\|name: model-store\|path: /data/models' "$manifest"; then
  printf '%s\n' 'production controller must not mount or proxy node-local model bytes' >&2
  exit 1
fi
grep -q 'lunanexa.io/service: postgres-ha' "$network_policy"
grep -q 'lunanexa.io/service: commercial-provider-adapter' "$network_policy"
grep -q 'app.kubernetes.io/name: commercial-provider-adapter' "$network_policy"
grep -q 'lunanexa.io/service: credential-issuer-adapter' "$network_policy"
grep -q 'app.kubernetes.io/name: credential-issuer-adapter' "$network_policy"

printf '%s\n' 'controller HA manifest tests passed'
