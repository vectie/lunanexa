#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

temporary_root=${TMPDIR:-/tmp}
temporary_root=${temporary_root%/}
simulation_directory=$(mktemp -d "$temporary_root/lunanexa-lease-cleanup.XXXXXX")
cleanup() {
  rm -rf -- "$simulation_directory"
}
trap cleanup EXIT INT TERM

moon build cmd/lease-helper --target native
helper="$repo_root/_build/native/debug/build/cmd/lease-helper/lease-helper.exe"
fake_bin="$simulation_directory/bin"
mkdir -p "$fake_bin"
for program in id getent useradd usermod userdel loginctl pkill pgrep runuser podman chown; do
  cp tests/fixtures/fake-lease-host-command.sh "$fake_bin/$program"
  chmod 0755 "$fake_bin/$program"
done

state_root="$simulation_directory/state"
home_root="$simulation_directory/homes"
credential_root="$simulation_directory/credentials"
quarantine_root="$simulation_directory/quarantine"
mkdir -p "$credential_root"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILunaNexaLeaseSimulationOnly tenant1' > "$credential_root/lease-1.authorized_keys"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILunaNexaLeaseSimulationOnly tenant2' > "$credential_root/lease-2.authorized_keys"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILunaNexaLeaseSimulationOnly tenant3' > "$credential_root/lease-3.authorized_keys"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILunaNexaLeaseSimulationOnly tenant4' > "$credential_root/lease-4.authorized_keys"
expires_unix_ms=$(( $(date +%s) * 1000 + 600000 ))

run_helper() {
  env \
    LUNANEXA_LEASE_HELPER_ENABLE=1 \
    LUNANEXA_LEASE_STATE_ROOT="$state_root" \
    LUNANEXA_LEASE_HOME_ROOT="$home_root" \
    LUNANEXA_LEASE_CREDENTIAL_ROOT="$credential_root" \
    LUNANEXA_LEASE_QUARANTINE_ROOT="$quarantine_root" \
    LUNANEXA_ID_PROGRAM="$fake_bin/id" \
    LUNANEXA_USERADD_PROGRAM="$fake_bin/useradd" \
    LUNANEXA_USERMOD_PROGRAM="$fake_bin/usermod" \
    LUNANEXA_USERDEL_PROGRAM="$fake_bin/userdel" \
    LUNANEXA_GETENT_PROGRAM="$fake_bin/getent" \
    LUNANEXA_LOGINCTL_PROGRAM="$fake_bin/loginctl" \
    LUNANEXA_PKILL_PROGRAM="$fake_bin/pkill" \
    LUNANEXA_PGREP_PROGRAM="$fake_bin/pgrep" \
    LUNANEXA_RUNUSER_PROGRAM="$fake_bin/runuser" \
    LUNANEXA_CONTAINER_PROGRAM="$fake_bin/podman" \
    LUNANEXA_CHOWN_PROGRAM="$fake_bin/chown" \
    "$helper" "$@"
}

if run_helper provision --lease-id missing-credential --username no_credential --credential-ref ssh-cert:missing-credential --expires-unix-ms "$expires_unix_ms" --generation 1 >/dev/null 2>&1; then
  printf '%s\n' 'missing credential provisioning unexpectedly succeeded' >&2
  exit 1
fi
test ! -e "$home_root/no_credential"
test ! -e "$state_root/missing-credential"

provision_receipt=$(run_helper provision --lease-id lease-1 --username tenant1 --credential-ref ssh-cert:lease-1 --expires-unix-ms "$expires_unix_ms" --generation 3)
printf '%s' "$provision_receipt" | rg -q '^lunanexa-helper-v1:provision:lease-1:3:verified:[0-9]+$'
test -f "$home_root/tenant1/.ssh/authorized_keys"
printf '%s\n' 'container123' > "$fake_bin/.fake-state/containers"
printf '%s\n' 'volume.lease-1' > "$fake_bin/.fake-state/volumes"

revoke_receipt=$(run_helper revoke --lease-id lease-1 --username tenant1 --generation 4)
printf '%s' "$revoke_receipt" | rg -q '^lunanexa-helper-v1:revoke:lease-1:4:verified:[0-9]+$'
sanitize_receipt=$(run_helper sanitize --lease-id lease-1 --username tenant1 --generation 6)
printf '%s' "$sanitize_receipt" | rg -q '^lunanexa-helper-v1:sanitize:lease-1:6:verified:[0-9]+$'
test ! -e "$home_root/tenant1"
test ! -e "$state_root/lease-1"
test ! -e "$credential_root/lease-1.authorized_keys"
test ! -s "$fake_bin/.fake-state/containers"
test ! -s "$fake_bin/.fake-state/volumes"
repeat_sanitize_receipt=$(run_helper sanitize --lease-id lease-1 --username tenant1 --generation 6)
printf '%s' "$repeat_sanitize_receipt" | rg -q '^lunanexa-helper-v1:sanitize:lease-1:6:verified:[0-9]+$'

touch "$fake_bin/.fake-state/lookup-failure"
if run_helper revoke --lease-id lease-4 --username tenant4 --generation 2 >/dev/null 2>&1; then
  printf '%s\n' 'account lookup failure was mistaken for a clean host' >&2
  exit 1
fi
rm -f -- "$fake_bin/.fake-state/lookup-failure"
run_helper revoke --lease-id lease-4 --username tenant4 --generation 2 >/dev/null
preprovision_sanitize_receipt=$(run_helper sanitize --lease-id lease-4 --username tenant4 --generation 3)
printf '%s' "$preprovision_sanitize_receipt" | rg -q '^lunanexa-helper-v1:sanitize:lease-4:3:verified:[0-9]+$'
test ! -e "$credential_root/lease-4.authorized_keys"

if ! second_provision_receipt=$(run_helper provision --lease-id lease-2 --username tenant2 --credential-ref ssh-cert:lease-2 --expires-unix-ms "$expires_unix_ms" --generation 1); then
  printf '%s\n' "$second_provision_receipt" >&2
  exit 1
fi
if run_helper revoke --lease-id lease-4 --username tenant2 --generation 2 >/dev/null 2>&1; then
  printf '%s\n' 'cross-lease revocation unexpectedly succeeded' >&2
  exit 1
fi
test -f "$fake_bin/.fake-state/account"
printf '%s\n' 'lease-2:999' > "$home_root/tenant2/.lunanexa-lease"
if run_helper sanitize --lease-id lease-2 --username tenant2 --generation 2 >/dev/null 2>&1; then
  printf '%s\n' 'home-marker mutation unexpectedly authorized cleanup' >&2
  exit 1
fi
test -f "$fake_bin/.fake-state/account"
test -d "$home_root/tenant2"
printf '%s\n' 'lease-2:1' > "$home_root/tenant2/.lunanexa-lease"
touch "$fake_bin/.fake-state/process-inventory-failure"
if run_helper revoke --lease-id lease-2 --username tenant2 --generation 2 >/dev/null 2>&1; then
  printf '%s\n' 'process inventory failure was mistaken for revocation' >&2
  exit 1
fi
rm -f -- "$fake_bin/.fake-state/process-inventory-failure"
touch "$fake_bin/.fake-state/stuck-process"
if run_helper revoke --lease-id lease-2 --username tenant2 --generation 2 >/dev/null 2>&1; then
  printf '%s\n' 'stuck-process revocation unexpectedly succeeded' >&2
  exit 1
fi
quarantine_receipt=$(run_helper quarantine --lease-id lease-2 --generation 2)
printf '%s' "$quarantine_receipt" | rg -q '^lunanexa-helper-v1:quarantine:lease-2:2:verified:[0-9]+$'
test -f "$quarantine_root/lease-2-g2.quarantined"

rm -f -- "$fake_bin/.fake-state/stuck-process"
run_helper sanitize --lease-id lease-2 --username tenant2 --generation 3 >/dev/null
run_helper provision --lease-id lease-3 --username tenant3 --credential-ref ssh-cert:lease-3 --expires-unix-ms "$expires_unix_ms" --generation 1 >/dev/null
printf '%s\n' 'container456' > "$fake_bin/.fake-state/containers"
printf '%s\n' 'volume.lease-3' > "$fake_bin/.fake-state/volumes"
touch "$fake_bin/.fake-state/stuck-runtime"
if run_helper sanitize --lease-id lease-3 --username tenant3 --generation 3 >/dev/null 2>&1; then
  printf '%s\n' 'stuck-runtime sanitization unexpectedly succeeded' >&2
  exit 1
fi
test -e "$home_root/tenant3"
test -e "$state_root/lease-3"
runtime_quarantine_receipt=$(run_helper quarantine --lease-id lease-3 --generation 3)
printf '%s' "$runtime_quarantine_receipt" | rg -q '^lunanexa-helper-v1:quarantine:lease-3:3:verified:[0-9]+$'
test -f "$quarantine_root/lease-3-g3.quarantined"

printf '%s\n' 'exclusive lease cleanup simulation passed'
