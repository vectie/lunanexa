#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

if [ "$#" -gt 1 ]; then
  printf '%s\n' 'usage: scripts/production-fault-simulation.sh [NEW_EVIDENCE_DIRECTORY]' >&2
  exit 1
fi

if [ "$#" -eq 1 ]; then
  campaign_directory=$1
  if [ -e "$campaign_directory" ]; then
    printf '%s\n' "simulation output already exists: $campaign_directory" >&2
    exit 1
  fi
  mkdir -p "$campaign_directory"
else
  campaign_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-production-faults.XXXXXX")
fi

failed_step=''
failure_log=''
on_exit() {
  status=$?
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "production fault simulation failed: $failed_step" >&2
    if [ -n "$failure_log" ] && [ -f "$failure_log" ]; then
      tail -n 80 "$failure_log" >&2 || true
    fi
    printf '%s\n' "partial evidence retained at $campaign_directory" >&2
  fi
  exit "$status"
}
trap on_exit EXIT INT TERM

run_logged() {
  step=$1
  shift
  failed_step=$step
  failure_log="$campaign_directory/$step.log"
  "$@" >"$failure_log" 2>&1
  printf '%s\n' "$step: passed"
}

run_logged contract-fuzz \
  moon test deployment/adversarial_test.mbt --target native --deny-warn
run_logged artifact-isolation \
  moon test node/artifact_materializer_test.mbt --target native --deny-warn
run_logged runtime-confinement \
  moon test node/runtime_supervisor_test.mbt node/runtime_supervisor_wbtest.mbt \
    --target native --deny-warn
run_logged authentication-and-backup \
  moon test tests/security_test.mbt --target native --deny-warn
run_logged deployment-api-adversarial \
  moon test api/deployment_http_test.mbt --target native --deny-warn
run_logged exclusive-lease-control-plane \
  moon test nodelease api/nodelease_http_test.mbt --target native --deny-warn
run_logged process-recovery sh scripts/process-recovery-test.sh
run_logged release-scans sh scripts/check-release.sh

failed_step='four-node-disruption'
failure_log="$campaign_directory/four-node-disruption.log"
sh scripts/four-node-simulation.sh "$campaign_directory/four-node" \
  >"$failure_log" 2>&1
printf '%s\n' 'four-node-disruption: passed'

printf '%s\n' \
  '{"schema_version":"lunanexa.synthetic-production.v1","synthetic":true,"contract_mutation_fuzz":"passed","selected_node_artifact_isolation":"passed","corrupt_artifact_quarantine":"passed","assigned_cache_pressure_protection":"passed","runtime_argument_confinement":"passed","generic_container_network_rejection":"passed","node_authentication_and_replay_fences":"passed","deployment_api_adversarial":"passed","core_backup_integrity":"passed","process_restart_and_epoch_fencing":"passed","four_node_disruption":"passed","public_release_scans":"passed","exclusive_lease_control_plane":"passed","real_mtls_validated":false,"real_container_engine_validated":false,"complete_management_backup_validated":false,"dgx_hardware_validated":false,"thermal_and_power_validated":false,"human_approval_obtained":false}' \
  >"$campaign_directory/summary.json"

failed_step=''
failure_log=''
printf '%s\n' 'synthetic production fault simulation passed'
printf '%s\n' "evidence retained at $campaign_directory"
