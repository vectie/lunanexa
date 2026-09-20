#!/usr/bin/env bash
# LunaNexa cluster layout: converge this cluster to deploy/cluster/cluster.json.
#
#   one-click.sh --phases preflight
#   one-click.sh --phases config,rbac,apply,verify
#   one-click.sh                      # every phase, in order
#
# Runs on the management node, from a checkout of this repository, as a user
# that can sudo. Every phase is idempotent and safe to re-run; none of them
# touches a host file except `fabric` (a netplan declaration, never applied)
# and the node agent's own state directory.
#
# Phases, in the order they run:
#   preflight  assert the cluster, the nodes and the toolchain are what the
#              manifest claims, before anything is changed
#   build      build the control binary from this checkout
#   images     rebuild and import the control image (node image only on request)
#   dra        make the DRA kubelet plugin image present on every GPU node, so
#              the device class a runtime claims actually exists
#   config     per node: credentials secret (only if absent), inventory
#              ConfigMap, runtime adapter ConfigMap, host state directory, and
#              the netplan declaration for the private fabric
#   rbac       runtime namespace and the role that lets the agent start a runtime
#   apply      the node agent Deployments, and roll them
#   verify     rollouts, heartbeats, the labels the manifest declares, endpoints
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${REPO_ROOT}/deploy/cluster/cluster.json"
CREDENTIALS="${LUNANEXA_CLUSTER_CREDENTIALS:-${HOME}/lunanexa-cluster-credentials.json}"
WORK_ROOT="${LUNANEXA_CLUSTER_WORK:-/tmp/lunanexa-cluster}"
SOURCE_TREE="${LUNANEXA_SOURCE_TREE:-${HOME}/control-build/src}"
PHASES="preflight,build,images,dra,config,rbac,apply,verify"
DRY_RUN=0
ONLY_NODES=()
REBUILD_NODE_IMAGE=0
ACCEPT_BACKEND_CHANGE=0
NODE_IMAGE_TAR=""

note() { printf '\n=== %s\n' "$*" >&2; }
step() { printf '  - %s\n' "$*" >&2; }
die() { printf 'FAILED: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat >&2 <<'EOF'
Options:
  --manifest FILE        cluster description (default deploy/cluster/cluster.json)
  --credentials FILE     sudo passwords (default ~/lunanexa-cluster-credentials.json)
  --phases LIST          comma separated subset of the phases above
  --node ID              act on one node only (repeatable)
  --rebuild-node-image   rebuild the arm64 node agent image (needs a Spark)
  --node-image-tar FILE  import this node agent image archive instead
  --accept-runtime-backend-change
                         allow apply to change a node's runtime backend; only
                         correct once the node image was built from this tree
  --accept-runtime-backend-change
                         allow apply to change a node's runtime backend; only
                         correct once the node image was built from this tree
  --dry-run              render and print everything, change nothing
  --help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --credentials) CREDENTIALS="$2"; shift 2 ;;
    --phases) PHASES="$2"; shift 2 ;;
    --node) ONLY_NODES+=("$2"); shift 2 ;;
    --rebuild-node-image) REBUILD_NODE_IMAGE=1; shift ;;
    --node-image-tar) NODE_IMAGE_TAR="$2"; shift 2 ;;
    --accept-runtime-backend-change) ACCEPT_BACKEND_CHANGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -f "${MANIFEST}" ] || die "no manifest at ${MANIFEST}"
command -v python3 >/dev/null || die "python3 is required"

# ---------------------------------------------------------------- credentials
# Nothing secret lives in the repository or the manifest. Sudo passwords come
# from a file outside it, so the manifest stays safe to commit and review.
MANAGEMENT_SUDO=""
declare -A NODE_SUDO=()
if [ -f "${CREDENTIALS}" ]; then
  eval "$(python3 - "${CREDENTIALS}" <<'PY'
import json, shlex, sys
with open(sys.argv[1]) as handle:
    credentials = json.load(handle)
print(f"MANAGEMENT_SUDO={shlex.quote(credentials.get('management', ''))}")
for user, password in (credentials.get('nodes') or {}).items():
    print(f"NODE_SUDO[{user}]={shlex.quote(password)}")
PY
)"
else
  step "no credentials file at ${CREDENTIALS}; sudo will prompt"
fi

# ------------------------------------------------------------------- cluster
cluster() { python3 - "$MANIFEST" "$@" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
node = sys.argv[2]
keys = sys.argv[3:]
if node == "-":
    value = manifest
else:
    value = next(item for item in manifest["nodes"] if item["id"] == node)
for key in keys:
    value = value[key]
print(value)
PY
}

NODE_IDS_FROM_MANIFEST=""
node_ids() {
  python3 - "$MANIFEST" <<'PY'
import json, sys
for node in json.load(open(sys.argv[1]))["nodes"]:
    print(node["id"])
PY
}
selected_nodes() {
  local all
  all=$(node_ids)
  if [ ${#ONLY_NODES[@]} -eq 0 ]; then
    printf '%s\n' "${all}"
    return
  fi
  local node
  for node in "${ONLY_NODES[@]}"; do
    printf '%s\n' "${all}" | grep -qx "${node}" || die "--node ${node} is not in the manifest"
    printf '%s\n' "${node}"
  done
}

# A node field that may legitimately be absent, reported as "-" when it is.
manifest_field() {
  python3 - "$MANIFEST" "$1" "$2" <<'PY'
import json, sys
node = next(n for n in json.load(open(sys.argv[1]))["nodes"] if n["id"] == sys.argv[2])
value = node.get(sys.argv[3])
print("-" if value in (None, "") else value)
PY
}

NAMESPACE=$(cluster - namespace)
RUNTIME_NAMESPACE=$(cluster - runtime namespace)
CONTROL_IMAGE=$(cluster - images control)
NODE_IMAGE=$(cluster - images node)
FRONT_DOOR_HOST=$(cluster - frontDoor host)
FRONT_DOOR_PORT=$(cluster - frontDoor port)
CONTROL_POD_IP=""
declare -A NODE_ADDRESS NODE_USER NODE_FABRIC NODE_FABRIC_INTERFACE
for node in $(selected_nodes); do
  NODE_ADDRESS["${node}"]=$(cluster "${node}" address)
  NODE_USER["${node}"]=$(cluster "${node}" sshUser)
  NODE_FABRIC["${node}"]=$(manifest_field "${node}" fabricAddress)
  NODE_FABRIC_INTERFACE["${node}"]=$(manifest_field "${node}" fabricInterface)
done

# ------------------------------------------------------------------ primitives
# The management sudo password is handed to sudo through an askpass helper
# rather than a pipe: several commands here read their own stdin (kubectl
# apply -f -), and a password on stdin would be consumed as input.
ASKPASS=""
if [ -n "${MANAGEMENT_SUDO}" ]; then
  ASKPASS="$(mktemp -t lunanexa-askpass.XXXXXX)"
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$(printf '%q' "${MANAGEMENT_SUDO}")" >"${ASKPASS}"
  chmod 700 "${ASKPASS}"
  export SUDO_ASKPASS="${ASKPASS}"
fi
cleanup() { [ -n "${ASKPASS}" ] && rm -f "${ASKPASS}"; }
trap cleanup EXIT

as_root() {
  if [ -n "${MANAGEMENT_SUDO}" ]; then
    sudo -A -k "$@"
  else
    sudo "$@"
  fi
}

kubectl_() { as_root kubectl "$@"; }

mutate() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '  [dry-run] %s\n' "$*" >&2
    return 0
  fi
  "$@"
}

node_ssh() {
  local node="$1"; shift
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      "${NODE_USER[${node}]}@${NODE_ADDRESS[${node}]}" "$@"
}

# The runtime backend a node's agent is currently configured with, or the empty
# string when the Deployment does not set it (which means the agent's default).
node_backend() {
  kubectl_ -n "${NAMESPACE}" get deploy "lunanexa-node-agent-$1" -o json 2>/dev/null |
    python3 -c '
import json, sys
try:
    deployment = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
for container in deployment["spec"]["template"]["spec"]["containers"]:
    if container["name"] != "node-agent":
        continue
    for entry in container.get("env", []):
        if entry["name"] == "LUNANEXA_RUNTIME_BACKEND":
            print(entry.get("value", ""))
            sys.exit(0)
print("")
'
}

node_sudo() {
  local node="$1"; shift
  local password="${NODE_SUDO[${NODE_USER[${node}]}]:-}"
  if [ -z "${password}" ]; then
    printf '  ! no sudo password for %s (%s); skipping\n' "${node}" "${NODE_USER[${node}]}" >&2
    return 0
  fi
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '  [dry-run] %s: sudo %s\n' "${node}" "$*" >&2
    return 0
  fi
  # The whole command has to run as root, not just its first word: a chain like
  # `mkdir ... && chown ...` would otherwise elevate only the mkdir. Encoding it
  # keeps the caller's quoting out of the remote shell's reach.
  local payload
  payload=$(printf '%s' "$*" | base64 -w0)
  printf '%s\n' "${password}" |
    node_ssh "${node}" "sudo -S -p '' bash -c \"echo ${payload} | base64 -d | bash\""
}

WORK="${WORK_ROOT}/current"
RENDERED="${WORK}/rendered"

# ------------------------------------------------------------------- preflight
phase_preflight() {
  note "preflight"
  command -v kubectl >/dev/null || die "kubectl is not on PATH"
  kubectl_ get --raw=/version >/dev/null || die "kubectl cannot reach the cluster"
  step "cluster reachable"

  local declared actual
  declared=$(node_ids | sort)
  actual=$(kubectl_ get nodes -o jsonpath='{range .items[*]}{.metadata.labels.kubernetes\.io/hostname}{"\n"}{end}' | sort)
  for node in ${declared}; do
    printf '%s\n' "${actual}" | grep -qx "${node}" ||
      die "node ${node} is declared in the manifest but not a cluster member"
    local ready role
    ready=$(kubectl_ get node "${node}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}')
    [ "${ready}" = "True" ] || die "node ${node} is not Ready (${ready})"
    role=$(kubectl_ get node "${node}" -o jsonpath='{.metadata.labels.lunanexa\.io/role}')
    if [ "${role}" != "gpu" ]; then
      step "node ${node} is missing the lunanexa.io/role=gpu label; labelling it"
      mutate kubectl_ label node "${node}" lunanexa.io/role=gpu --overwrite >/dev/null
    fi
  done
  step "$(printf '%s\n' "${declared}" | wc -l) declared nodes are Ready and labelled"

  CONTROL_POD_IP=$(kubectl_ -n "${NAMESPACE}" get pod -l app=lunanexa-control \
    -o jsonpath='{.items[0].status.podIP}' || true)
  [ -n "${CONTROL_POD_IP}" ] || die "the control plane has no running pod"
  local host_network
  host_network=$(kubectl_ -n "${NAMESPACE}" get deploy lunanexa-control \
    -o jsonpath='{.spec.template.spec.hostNetwork}')
  step "control pod is ${CONTROL_POD_IP} (hostNetwork=${host_network:-false})"
  if [ "${host_network}" != "true" ]; then
    step "note: the runtime NetworkPolicy will name ${CONTROL_POD_IP}, which is a pod"
    step "      address and therefore changes when the control pod is replaced"
  fi

  local service_account
  service_account=$(kubectl_ -n "${NAMESPACE}" get sa lunanexa-node --ignore-not-found -o name)
  [ -n "${service_account}" ] ||
    die "ServiceAccount ${NAMESPACE}/lunanexa-node is missing (apply deploy/prerequisites.yaml)"

  for node in $(selected_nodes); do
    node_ssh "${node}" true || die "cannot ssh from here to ${node} (${NODE_ADDRESS[${node}]})"
  done
  step "ssh reaches every selected node"

  local dra_ready
  dra_ready=$(kubectl_ -n dra-driver-nvidia-gpu get pods \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null || true)
  for node in $(selected_nodes); do
    if printf '%s\n' "${dra_ready}" | grep -q "^${node} Running"; then
      step "DRA kubelet plugin is running on ${node}"
    else
      step "! DRA kubelet plugin is NOT running on ${node}; the 'dra' phase fixes this"
      step "  (a runtime rendered for this node cannot be allocated a GPU until it does)"
    fi
  done
}

# ----------------------------------------------------------------------- build
phase_build() {
  note "build"
  [ -d "${SOURCE_TREE}" ] || die "no source tree at ${SOURCE_TREE}"
  local moon="${HOME}/moon-public/toolchains/moon-linux-amd64/bin"
  [ -d "${moon}" ] || die "no moon toolchain at ${moon}"
  step "building cmd/control in ${SOURCE_TREE}"
  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '  [dry-run] moon build --target native --release cmd/control\n' >&2
    return 0
  fi
  ( cd "${SOURCE_TREE}" && PATH="${moon}:${PATH}" \
      moon build --target native --release cmd/control )
  step "built $(ls -l "${SOURCE_TREE}/_build/native/release/build/cmd/control/control.exe" | awk '{print $5}') bytes"
}

# ---------------------------------------------------------------------- images
phase_images() {
  note "images"
  step "control image ${CONTROL_IMAGE} from the freshly built binary"
  mutate python3 "${REPO_ROOT}/deploy/cluster/build-control-image.py" \
    --image "${CONTROL_IMAGE}" \
    --binary "${SOURCE_TREE}/_build/native/release/build/cmd/control/control.exe" \
    --sudo-password "${MANAGEMENT_SUDO}"

  if [ "${REBUILD_NODE_IMAGE}" -eq 1 ] && [ -z "${NODE_IMAGE_TAR}" ]; then
    local host
    host=$(selected_nodes | head -1)
    step "rebuilding the arm64 node agent image on ${host}"
    node_ssh "${host}" "bash -s" < "${REPO_ROOT}/deploy/cluster/build-node-image.sh" ||
      die "node image build failed on ${host}"
    NODE_IMAGE_TAR=$(node_ssh "${host}" 'ls -t ~/lunanexa-node-*.oci.tar | head -1')
    step "node image archive: ${host}:${NODE_IMAGE_TAR}"
  fi

  if [ -n "${NODE_IMAGE_TAR}" ]; then
    local host
    host=$(selected_nodes | head -1)
    if [ "${DRY_RUN}" -eq 0 ] && [ ! -f "${NODE_IMAGE_TAR}" ]; then
      step "staging ${host}:${NODE_IMAGE_TAR} through this node"
      scp -q -o BatchMode=yes "${NODE_USER[${host}]}@${NODE_ADDRESS[${host}]}:${NODE_IMAGE_TAR}" \
        "${WORK}/node-image.tar"
      NODE_IMAGE_TAR="${WORK}/node-image.tar"
    fi
    for node in $(selected_nodes); do
      step "importing the node image on ${node}"
      if [ "${DRY_RUN}" -eq 1 ]; then
        printf '  [dry-run] import %s on %s and tag %s\n' "${NODE_IMAGE_TAR}" "${node}" "${NODE_IMAGE}" >&2
        continue
      fi
      scp -q -o BatchMode=yes "${NODE_IMAGE_TAR}" \
        "${NODE_USER[${node}]}@${NODE_ADDRESS[${node}]}:/tmp/node-image.tar"
      node_sudo "${node}" "k3s ctr -n k8s.io images import --digests /tmp/node-image.tar >/dev/null 2>&1 && k3s ctr -n k8s.io images tag --force 'docker.io/library/${NODE_IMAGE}' 'docker.io/library/${NODE_IMAGE}' >/dev/null 2>&1; rm -f /tmp/node-image.tar"
    done
  else
    step "node image ${NODE_IMAGE} is used as-is (pass --rebuild-node-image or --node-image-tar to replace it)"
  fi
}

# ------------------------------------------------------------------------- dra
# The Kubernetes runtime backend allocates a GPU through the DRA device class.
# The driver image is large and the GPU nodes have no route to registry.k8s.io,
# so it is pulled once here and imported locally on each of them.
phase_dra() {
  note "dra"
  local image
  image=$(cluster - images dra)
  local platform="linux/arm64"
  local missing=()
  local dra_state
  dra_state=$(kubectl_ -n dra-driver-nvidia-gpu get pods \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null || true)
  for node in $(selected_nodes); do
    printf '%s\n' "${dra_state}" | grep -q "^${node} Running" || missing+=("${node}")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    step "the DRA kubelet plugin is already running on every selected node"
    return 0
  fi
  step "the DRA kubelet plugin is missing on: ${missing[*]}"

  if [ "${DRY_RUN}" -eq 1 ]; then
    printf '  [dry-run] pull %s (%s) here and import it on every node above\n' "${image}" "${platform}" >&2
    return 0
  fi

  # registry.k8s.io resolves but its blob backend does not answer from here, so
  # the mirror is tried first and the canonical name is restored on import: the
  # DaemonSet keeps referencing registry.k8s.io, which is what must be present.
  local sources=()
  while IFS= read -r candidate; do
    [ -n "${candidate}" ] && sources+=("${candidate}")
  done < <(python3 - "$MANIFEST" <<'PY'
import json, sys
images = json.load(open(sys.argv[1]))["images"]
print("\n".join(images.get("draSources") or [images["dra"]]))
PY
)
  local pulled=""
  local attempts=0
  for candidate in "${sources[@]}"; do
    step "pulling ${candidate} for ${platform}"
    if as_root k3s ctr -n k8s.io images pull \
        --platform "${platform}" "${candidate}" >/dev/null 2>&1; then
      pulled="${candidate}"
      break
    fi
    attempts=$((attempts + 1))
    step "  source unreachable; trying the next one"
  done
  [ -n "${pulled}" ] || die "could not pull any configured source for ${image}"

  local archive="${WORK}/dra-driver-arm64.tar"
  as_root k3s ctr -n k8s.io images export \
    --platform "${platform}" "${archive}" "${pulled}" >/dev/null ||
    die "cannot export ${pulled}"
  as_root chmod 644 "${archive}"

  for node in "${missing[@]}"; do
    step "importing ${image} on ${node}"
    scp -q -o BatchMode=yes "${archive}" \
      "${NODE_USER[${node}]}@${NODE_ADDRESS[${node}]}:/tmp/dra-driver.tar"
    node_sudo "${node}" "k3s ctr -n k8s.io images import --digests /tmp/dra-driver.tar >/dev/null 2>&1; k3s ctr -n k8s.io images tag --force '${pulled}' '${image}' >/dev/null 2>&1; rm -f /tmp/dra-driver.tar"
    kubectl_ -n dra-driver-nvidia-gpu delete pod \
      -l "app.kubernetes.io/name=dra-driver-nvidia-gpu" \
      --field-selector "spec.nodeName=${node}" --ignore-not-found >/dev/null 2>&1 || true
  done
  step "imported and tagged as ${image}; the plugin pods will be recreated"
}

# ---------------------------------------------------------------------- config
# Everything a node needs that is not the Deployment itself. Nothing here
# rotates an existing credential: a re-enrolment is a deliberate act.
phase_config() {
  note "config"
  local sudo_password="${MANAGEMENT_SUDO}"
  mkdir -p "${WORK}"

  for node in $(selected_nodes); do
    local existing
    existing=$(kubectl_ -n "${NAMESPACE}" get secret "lunanexa-node-agent-material-${node}" \
      --ignore-not-found -o name)
    if [ -z "${existing}" ]; then
      step "${node}: no credential secret yet; issuing a bootstrap token"
      if [ "${DRY_RUN}" -eq 0 ]; then
        local operator token_id token
        operator=$(kubectl_ -n "${NAMESPACE}" get secret lunanexa-control-credentials \
          -o jsonpath='{.data.operator-token}' | base64 -d)
        token_id="one-click-${node}-$(date +%s)"
        token=$(python3 -c 'import secrets; print(secrets.token_urlsafe(36))')
        curl -sf -X POST "http://127.0.0.1:${FRONT_DOOR_PORT}/v1/enrollment/tokens" \
          -H "Authorization: Bearer ${operator}" -H 'Content-Type: application/json' \
          -d "{\"token_id\":\"${token_id}\",\"secret\":\"${token}\",\"expires_unix_ms\":\"$(( $(date +%s) * 1000 + 840000 ))\"}" \
          >/dev/null || die "could not issue a bootstrap token for ${node}"
        kubectl_ -n "${NAMESPACE}" create secret generic \
          "lunanexa-node-agent-material-${node}" \
          --from-literal="bootstrap-token-id=${token_id}" \
          --from-literal="bootstrap-token=${token}" >/dev/null
        step "${node}: credential secret created"
      else
        printf '  [dry-run] issue a bootstrap token and create the credential secret\n' >&2
      fi
    else
      step "${node}: credential secret already present; left alone"
    fi

    step "${node}: host state directory"
    node_sudo "${node}" "mkdir -p /var/lib/lunanexa/node-agent /var/lib/lunanexa/models && chown -R 65532:65532 /var/lib/lunanexa/node-agent /var/lib/lunanexa/models"
  done

  local render_node_arguments=()
  local node
  for node in "${ONLY_NODES[@]}"; do
    render_node_arguments+=(--node "${node}")
  done
  python3 "${REPO_ROOT}/deploy/cluster/render.py" \
    --manifest "${MANIFEST}" \
    --output "${RENDERED}" \
    --template-dir "${REPO_ROOT}/deploy/cluster" \
    --control-address "${CONTROL_POD_IP}" \
    "${render_node_arguments[@]}"
  step "rendered into ${RENDERED}"

  for node in $(selected_nodes); do
    step "${node}: inventory and runtime configuration"
    if [ "${DRY_RUN}" -eq 0 ]; then
      kubectl_ -n "${NAMESPACE}" create configmap "lunanexa-node-inventory-${node}" \
        --from-file="inventory.json=${RENDERED}/inventory-${node}.json" \
        --dry-run=client -o yaml >"${WORK}/inventory-${node}.yaml"
      kubectl_ -n "${NAMESPACE}" apply -f "${WORK}/inventory-${node}.yaml" >/dev/null
      kubectl_ -n "${NAMESPACE}" create configmap "lunanexa-node-runtime-${node}" \
        --from-file="kubernetes-runtime.json=${RENDERED}/kubernetes-runtime-${node}.json" \
        --dry-run=client -o yaml >"${WORK}/runtime-${node}.yaml"
      kubectl_ -n "${NAMESPACE}" apply -f "${WORK}/runtime-${node}.yaml" >/dev/null
    fi

    if [ -f "${RENDERED}/fabric-${node}.yaml" ]; then
      step "${node}: declaring ${NODE_FABRIC[${node}]} on ${NODE_FABRIC_INTERFACE[${node}]}"
      if [ "${DRY_RUN}" -eq 0 ]; then
        scp -q -o BatchMode=yes "${RENDERED}/fabric-${node}.yaml" \
          "${NODE_USER[${node}]}@${NODE_ADDRESS[${node}]}:/tmp/60-lunanexa-cx7.yaml"
        node_sudo "${node}" "install -m 600 -o root -g root /tmp/60-lunanexa-cx7.yaml /etc/netplan/60-lunanexa-cx7.yaml && rm -f /tmp/60-lunanexa-cx7.yaml && netplan get >/dev/null"
        step "${node}: declared but not applied; the address is already live"
      fi
    fi
  done
}

# ------------------------------------------------------------------------ rbac
phase_rbac() {
  note "rbac"
  [ -f "${RENDERED}/rbac.yaml" ] || die "run the config phase first (or use --phases all)"
  step "runtime namespace ${RUNTIME_NAMESPACE} and the agent's role in it"
  mutate kubectl_ apply -f "${RENDERED}/rbac.yaml" >/dev/null
}

# ----------------------------------------------------------------------- apply
phase_apply() {
  note "apply"
  [ -d "${RENDERED}" ] || die "run the config phase first"

  # Changing a node's runtime backend is not a rendering detail: the agent
  # binary inside the deployed image has to support the backend it is told to
  # use. Flipping it silently is how a fleet ends up in CrashLoop, so it takes
  # an explicit decision.
  local target first deployed
  target=$(cluster - runtime backend)
  first=$(selected_nodes | head -1)
  deployed=$(node_backend "${first}")
  if [ "${deployed}" != "${target}" ] && [ "${ACCEPT_BACKEND_CHANGE}" -eq 0 ]; then
    die "node agent runtime backend would change from '${deployed:-unset}' to '${target}'. \
The image in use must be built from this tree first (see deploy/cluster/README.md, \
'the node image'), then re-run with --accept-runtime-backend-change"
  fi

  for node in $(selected_nodes); do
    step "${node}: applying the node agent"
    mutate kubectl_ -n "${NAMESPACE}" apply -f "${RENDERED}/node-agent-${node}.yaml" >/dev/null
  done
  if [ "${DRY_RUN}" -eq 0 ]; then
    step "waiting for the agents to become available"
    for node in $(selected_nodes); do
      kubectl_ -n "${NAMESPACE}" rollout status "deploy/lunanexa-node-agent-${node}" \
        --timeout=180s >/dev/null || die "${node}: the agent did not become available"
    done
  fi
}

# ---------------------------------------------------------------------- verify
phase_verify() {
  note "verify"
  local nodes_json
  nodes_json=$(curl -sf "http://127.0.0.1:${FRONT_DOOR_PORT}/v1/nodes") ||
    die "the control plane did not answer on the front door"
  python3 - "${MANIFEST}" "${nodes_json}" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
reported = {node["node_id"]: node for node in json.loads(sys.argv[2])}
failures = []
for declared in manifest["nodes"]:
    node = reported.get(declared["id"])
    if node is None:
        failures.append(f"{declared['id']}: not reporting at all")
        continue
    if node["state"] != "Active":
        failures.append(f"{declared['id']}: state {node['state']}")
    labels = node["inventory"]["labels"]
    expected = {
        "lunanexa.io/cx7-peer": declared.get("fabricPeer"),
        "lunanexa.io/cx7-address": declared.get("fabricAddress"),
    }
    for key, value in expected.items():
        if value and labels.get(key) != value:
            failures.append(f"{declared['id']}: label {key} is {labels.get(key)!r}, want {value!r}")
    if declared.get("runtimeNames") and sorted(node["inventory"]["runtime_names"]) != sorted(declared["runtimeNames"]):
        failures.append(
            f"{declared['id']}: runtime_names {node['inventory']['runtime_names']} "
            f"!= {declared['runtimeNames']}"
        )
if failures:
    print("VERIFY FAILED", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)
print(f"  - {len(reported)} node(s) reporting, all matching the manifest")
PY
  step "front door: http://${FRONT_DOOR_HOST}:${FRONT_DOOR_PORT}/  (console /console/)"
  step "rendered artefacts kept in ${WORK}"
}

main() {
  local phase
  IFS=',' read -r -a wanted <<< "${PHASES}"
  for phase in "${wanted[@]}"; do
    case "${phase}" in
      preflight|build|images|dra|config|rbac|apply|verify)
        "phase_${phase}" ;;
      "") ;;
      *) die "unknown phase '${phase}'" ;;
    esac
  done
  if [ "${DRY_RUN}" -eq 1 ]; then
    note "done: ${PHASES} (dry run, nothing was changed)"
  else
    note "done: ${PHASES}"
  fi
}

main
