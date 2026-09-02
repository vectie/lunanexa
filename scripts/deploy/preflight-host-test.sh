#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-host-preflight-test.XXXXXX")
cleanup() { rm -rf "$test_directory"; }
trap cleanup EXIT HUP INT TERM

common_bin=$test_directory/common
mkdir -p "$common_bin"
for command_name in hostname uname sudo; do
  command_path=$common_bin/$command_name
  case "$command_name" in
    hostname) script='#!/bin/sh
printf "%s\n" test-compute' ;;
    uname) script='#!/bin/sh
printf "%s\n" "Linux 6.8"' ;;
    sudo) script='#!/bin/sh
test "${1:-}" = -n
test "${2:-}" = /usr/libexec/lunanexa-install-node-material
test "${3:-}" = --check' ;;
  esac
  printf '%s\n' "$script" > "$command_path"
  chmod +x "$command_path"
done

ascend_bin=$test_directory/ascend
mkdir -p "$ascend_bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "310P3 Health OK"' > "$ascend_bin/npu-smi"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "Docker version test"' > "$ascend_bin/docker"
chmod +x "$ascend_bin/npu-smi" "$ascend_bin/docker"
set +e
PATH="$ascend_bin:$common_bin:/usr/bin:/bin" \
  sh "$repo_root/scripts/deploy/preflight-host.sh" compute compute-01 \
  > "$test_directory/ascend.log" 2>&1
ascend_status=$?
set -e
test "$ascend_status" -ne 0
grep -q '^\[hardware\] Ascend accelerator detected$' "$test_directory/ascend.log"
grep -q '^\[blocked\] Ascend host enrollment is disabled until ' "$test_directory/ascend.log"

nvidia_bin=$test_directory/nvidia
mkdir -p "$nvidia_bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "NVIDIA GB10, 119000 MiB, test-driver"' > "$nvidia_bin/nvidia-smi"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "podman version test"' > "$nvidia_bin/podman"
chmod +x "$nvidia_bin/nvidia-smi" "$nvidia_bin/podman"
PATH="$nvidia_bin:$common_bin:/usr/bin:/bin" \
  sh "$repo_root/scripts/deploy/preflight-host.sh" compute compute-01 \
  > "$test_directory/nvidia.log" 2>&1
grep -q '^\[hardware\] NVIDIA accelerator detected$' "$test_directory/nvidia.log"
grep -q '^\[ok\] remote preflight complete$' "$test_directory/nvidia.log"

printf '%s\n' 'host preflight qualification tests passed'
