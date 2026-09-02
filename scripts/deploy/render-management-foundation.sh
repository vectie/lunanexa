#!/bin/sh
set -eu
umask 077

output_directory= management_node= control_image= web_image= model_source_image=
workbench_public_image= coursebook_public_image= postgres_image=
model_store_root= control_uid= control_gid= runtime_endpoint=
public_api_base_url= controller_epoch=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output_directory=$2; shift 2 ;;
    --management-node) management_node=$2; shift 2 ;;
    --control-image) control_image=$2; shift 2 ;;
    --web-image) web_image=$2; shift 2 ;;
    --model-source-image) model_source_image=$2; shift 2 ;;
    --workbench-public-image) workbench_public_image=$2; shift 2 ;;
    --coursebook-public-image) coursebook_public_image=$2; shift 2 ;;
    --postgres-image) postgres_image=$2; shift 2 ;;
    --model-store-root) model_store_root=$2; shift 2 ;;
    --control-uid) control_uid=$2; shift 2 ;;
    --control-gid) control_gid=$2; shift 2 ;;
    --runtime-endpoint) runtime_endpoint=$2; shift 2 ;;
    --public-api-base-url) public_api_base_url=$2; shift 2 ;;
    --controller-epoch) controller_epoch=$2; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

safe_identifier() { case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac; }
safe_image() { case "$1" in ''|*[!A-Za-z0-9._/@:+-]*) return 1 ;; esac; }
safe_integer() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
safe_path() {
  case "$1" in /*) ;; *) return 1 ;; esac
  case "/$1/" in */../*) return 1 ;; esac
  case "$1" in *'|'*|*'&'*|*'\'*|*'$'*|*'{'*|*'}'*) return 1 ;; esac
}
safe_endpoint() {
  case "$1" in http://127.0.0.1:[0-9]*/v1/responses) ;; *) return 1 ;; esac
  case "$1" in *'|'*|*'&'*|*'\'*|*'$'*|*'{'*|*'}'*) return 1 ;; esac
}
safe_public_api_base_url() {
  case "$1" in
    https://*|http://127.0.0.1:*|http://localhost:*) ;;
    *) return 1 ;;
  esac
  case "$1" in *'|'*|*'&'*|*'\'*|*'$'*|*'{'*|*'}'*|*'@'*|*'?'*|*'#'*) return 1 ;; esac
}

safe_path "$output_directory"
safe_identifier "$management_node"
safe_image "$control_image"; safe_image "$web_image"
safe_image "$model_source_image"; safe_image "$workbench_public_image"
safe_image "$coursebook_public_image"; safe_image "$postgres_image"
safe_path "$model_store_root"
safe_integer "$control_uid"; safe_integer "$control_gid"; safe_integer "$controller_epoch"
safe_endpoint "$runtime_endpoint"
safe_public_api_base_url "$public_api_base_url"
test "$control_uid" -gt 0; test "$control_gid" -gt 0; test "$controller_epoch" -gt 0
command -v kubectl >/dev/null
command -v rg >/dev/null

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work_directory=$(mktemp -d "${TMPDIR:-/tmp}/lunanexa-management-render.XXXXXX")
cleanup() { rm -rf "$work_directory"; }
trap cleanup EXIT HUP INT TERM

for manifest in prerequisites postgres controller console enterprise workbench model-source network-policy; do
  cp "$repo_root/deploy/$manifest.yaml" "$work_directory/$manifest.yaml"
done
for template in kustomization prerequisites-patch controller-patch workloads-patch model-source-patch network-policy-dev-browser-patch console-public-service public-sites; do
  cp "$repo_root/deploy/management-foundation/$template.yaml" "$work_directory/$template.yaml"
done

replace() {
  placeholder=$1 value=$2 file=$3 next=$file.next
  sed "s|$placeholder|$value|g" "$file" > "$next"
  mv "$next" "$file"
}

sha256_files() {
  if command -v sha256sum >/dev/null 2>&1; then
    cat "$@" | sha256sum | awk '{print $1}'
  else
    cat "$@" | shasum -a 256 | awk '{print $1}'
  fi
}

controller_endpoint=http://lunanexa-control:8080
artifact_endpoint=http://lunanexa-control:8080/v1/artifacts
replace '\${CONTROLLER_EPOCH}' "$controller_epoch" "$work_directory/prerequisites-patch.yaml"
replace '\${RUNTIME_ENDPOINT}' "$runtime_endpoint" "$work_directory/prerequisites-patch.yaml"
replace '\${CONTROLLER_ENDPOINT}' "$controller_endpoint" "$work_directory/prerequisites-patch.yaml"
replace '\${ARTIFACT_ENDPOINT}' "$artifact_endpoint" "$work_directory/prerequisites-patch.yaml"
replace '\${LUNANEXA_PUBLIC_API_BASE_URL}' "$public_api_base_url" "$work_directory/controller.yaml"
management_config_digest=$(sha256_files \
  "$work_directory/prerequisites.yaml" \
  "$work_directory/prerequisites-patch.yaml")
replace '\${MANAGEMENT_CONFIG_DIGEST}' "$management_config_digest" "$work_directory/controller-patch.yaml"
replace '\${MANAGEMENT_NODE}' "$management_node" "$work_directory/controller-patch.yaml"
replace '\${CONTROL_UID}' "$control_uid" "$work_directory/controller-patch.yaml"
replace '\${CONTROL_GID}' "$control_gid" "$work_directory/controller-patch.yaml"
replace '\${CONTROL_IMAGE}' "$control_image" "$work_directory/controller-patch.yaml"
replace '\${MODEL_STORE_ROOT}' "$model_store_root" "$work_directory/controller-patch.yaml"
replace '\${MANAGEMENT_NODE}' "$management_node" "$work_directory/workloads-patch.yaml"
replace '\${POSTGRES_IMAGE}' "$postgres_image" "$work_directory/workloads-patch.yaml"
replace '\${WEB_IMAGE}' "$web_image" "$work_directory/workloads-patch.yaml"
replace '\${MANAGEMENT_NODE}' "$management_node" "$work_directory/model-source-patch.yaml"
replace '\${CONTROL_UID}' "$control_uid" "$work_directory/model-source-patch.yaml"
replace '\${CONTROL_GID}' "$control_gid" "$work_directory/model-source-patch.yaml"
replace '\${MODEL_SOURCE_IMAGE}' "$model_source_image" "$work_directory/model-source-patch.yaml"
replace '\${MODEL_STORE_ROOT}' "$model_store_root" "$work_directory/model-source-patch.yaml"
replace '\${MANAGEMENT_NODE}' "$management_node" "$work_directory/console-public-service.yaml"
replace '\${WEB_IMAGE}' "$web_image" "$work_directory/console-public-service.yaml"
replace '\${MANAGEMENT_NODE}' "$management_node" "$work_directory/public-sites.yaml"
replace '\${WORKBENCH_PUBLIC_IMAGE}' "$workbench_public_image" "$work_directory/public-sites.yaml"
replace '\${COURSEBOOK_PUBLIC_IMAGE}' "$coursebook_public_image" "$work_directory/public-sites.yaml"

mkdir -p "$output_directory"
rendered_next=$output_directory/management.yaml.next
kubectl kustomize "$work_directory" > "$rendered_next"
if rg -q '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' "$rendered_next"; then
  printf '%s\n' '[blocked] rendered management manifest contains unresolved placeholders' >&2
  exit 1
fi
chmod 0600 "$rendered_next"
mv "$rendered_next" "$output_directory/management.yaml"
printf 'rendered management foundation: %s\n' "$output_directory/management.yaml"
