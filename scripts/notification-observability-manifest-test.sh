#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
network_policy="$repository_root/deploy/network-policy.yaml"
observability="$repository_root/deploy/observability.yaml"
controller="$repository_root/deploy/controller.yaml"

grep -q 'lunanexa.io/service: notification-adapter' "$network_policy"
grep -q 'lunanexa.io/service: telemetry-sink' "$network_policy"
grep -q 'lunanexa.io/service: observability-proof' "$network_policy"
grep -q 'lunanexa.io/service: prometheus' "$network_policy"
grep -q 'app.kubernetes.io/name: prometheus' "$network_policy"
grep -q 'app.kubernetes.io/instance: lunanexa-management' "$network_policy"
grep -q 'otel/opentelemetry-collector-contrib@${OTEL_COLLECTOR_IMAGE_DIGEST}' "$observability"
grep -q 'kind: ServiceAccount' "$observability"
grep -q 'name: lunanexa-observability' "$observability"
grep -q 'automountServiceAccountToken: false' "$observability"
grep -q 'serviceAccount: lunanexa-observability' "$observability"
grep -q 'podSecurityContext:' "$observability"
grep -q 'runAsNonRoot: true' "$observability"
grep -q 'seccompProfile:' "$observability"
grep -q 'allowPrivilegeEscalation: false' "$observability"
grep -q 'readOnlyRootFilesystem: true' "$observability"
grep -q 'drop: \["ALL"\]' "$observability"
grep -q 'retry_on_failure:' "$observability"
grep -q 'LunaNexaNotificationWorkerStale' "$observability"
grep -q 'GuideDiagnosticsProbeCompleted' "$observability"
grep -q 'LUNANEXA_EXTERNAL_EXPORT_PROOF_TOKEN' "$controller"
grep -q 'key: external-export-proof-token' "$controller"
grep -q 'LUNANEXA_EXTERNAL_EXPORT_PROOF_TOKEN only' "$observability"
grep -q 'Monitoring/audit-reader authority is intentionally insufficient' "$observability"

if grep -q 'export-proof with monitoring authority' "$observability"; then
  echo "external export proof incorrectly delegates monitoring authority" >&2
  exit 1
fi

# The explicit Prometheus peer and controller port must remain in the same
# management ingress rule. This bounded range ends before the egress section.
if ! sed -n '/  ingress:/,/  egress:/p' "$network_policy" |
  grep -q 'port: 8080'; then
  echo "Prometheus ingress does not expose the controller metrics port" >&2
  exit 1
fi

# Both public UI gateways proxy bounded controller routes. Their egress rules
# are insufficient unless the controller independently admits each gateway.
control_ingress="$(sed -n '1,/^  egress:/p' "$network_policy")"
for gateway in lunanexa-console-public-gateway lunanexa-workbench-public-gateway; do
  if ! printf '%s\n' "$control_ingress" | grep -q "app: $gateway"; then
    echo "controller ingress does not admit $gateway" >&2
    exit 1
  fi
done

if grep -q '# TYPE lunanexa_operational_request_duration_ms histogram' "$observability"; then
  echo "legacy non-monotonic histogram declaration remains" >&2
  exit 1
fi

echo "notification/observability manifest invariants passed"
