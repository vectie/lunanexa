# LunaNexa deployment guide

This guide deploys LunaNexa on one management node with an 8 TB model disk at
`/data/models` and four DGX Spark compute nodes. It covers the currently
implemented managed model-service path and the management-plane portion of
exclusive node leasing.

## 1. Supported deployment shape

The repository templates assume one Kubernetes cluster containing the
management node and the four DGX workers:

```mermaid
flowchart TB
    subgraph Management["Management node"]
      K["Kubernetes control plane"]
      C["LunaNexa controller"]
      UI["Console and workbench"]
      DB["Durable metadata PVC"]
      MS["S3-compatible artifact service"]
      MD["/data/models · 8 TB"]
      OR["OCI registry"]
      MD --> MS
      K --> C
      C --> DB
      UI --> C
    end

    subgraph Compute["DGX Spark workers"]
      D1["DGX 1 · node agent · Podman"]
      D2["DGX 2 · node agent · Podman"]
      D3["DGX 3 · node agent · Podman"]
      D4["DGX 4 · node agent · Podman"]
    end

    C <-->|"desired state and heartbeat"| D1
    C <-->|"desired state and heartbeat"| D2
    C <-->|"desired state and heartbeat"| D3
    C <-->|"desired state and heartbeat"| D4
    MS -->|"assignment-scoped model pull"| D1
    MS -->|"assignment-scoped model pull"| D2
    MS -->|"assignment-scoped model pull"| D3
    MS -->|"assignment-scoped model pull"| D4
    OR -->|"digest-pinned image pull"| D1
    OR -->|"digest-pinned image pull"| D2
    OR -->|"digest-pinned image pull"| D3
    OR -->|"digest-pinned image pull"| D4
```

The management node does not copy every model to every DGX. A selected node
pulls the exact artifact referenced by its signed assignment. The artifact is
verified and cached locally before its runtime container starts.

### Deployment readiness

| Capability | Status | Deployment implication |
| --- | --- | --- |
| Controller, scheduler, registry, API and audit | Implemented | Deploy on the management node |
| Rabbita console and workbench | Implemented | Serve behind the trusted TLS ingress |
| DGX heartbeat, telemetry and assignment reconciliation | Implemented | Deploy one protected agent per DGX |
| Selected-node model pull and local verification | Implemented | Requires an external S3-compatible HTTPS artifact service |
| Digest-pinned runtime supervision | Implemented | Requires Podman/Docker, an OCI registry and an approved runtime image |
| Controller/node transport mTLS termination | External | Provide a trusted service-mesh or loopback proxy; do not expose controller HTTP directly |
| Exclusive lease reservation and managed-placement fence | Implemented | Safe for control-plane testing |
| Exclusive user account/SSH provisioning and sanitization | Not implemented | Do not offer production interactive leases yet |
| OCI registry, CA, secret manager and metrics backend | External | Provision independently; they are not LunaNexa services |

## 2. Non-negotiable boundaries

- `/data/models` remains on the management node. Do not NFS-mount it into DGX
  runtime containers or expose its host path through the public API.
- Publish model objects through a protected S3-compatible HTTPS endpoint. The
  node agent maps an approved `s3://bucket/object` reference to that endpoint.
- Runtime images are immutable OCI images pinned by full SHA-256 digest.
- Every DGX has a unique node credential. Bootstrap tokens are one-use and
  expire within 15 minutes.
- Controller signing keys, node tokens, artifact credentials, operator tokens
  and TLS private keys must come from a secret manager or protected host files.
  Do not store them in Git, ConfigMaps, command history or lease JSON.
- A node is either available for managed services or fenced for an exclusive
  lease. These modes must never overlap.

## 3. Prerequisites

### Management node

- Linux host with the 8 TB filesystem already formatted and mounted at
  `/data/models`;
- a supported Kubernetes control plane and persistent storage provisioner;
- ingress-nginx or an equivalent identity-aware TLS ingress;
- OCI build/publish tooling and Cosign;
- a deployment-owned S3-compatible artifact service backed by `/data/models`;
- an OCI registry reachable by every DGX;
- a certificate authority, secret manager and backup target;
- a service-mesh or node-local proxy able to establish mTLS from every DGX to
  the management plane;
- DNS records for the LunaNexa API/UI, artifact service, registry and runtime
  endpoints.

Creating or formatting the 8 TB filesystem is outside this repository. Verify
the intended device and mount before installing LunaNexa:

```sh
findmnt /data/models
df -h /data/models
sudo install -d -m 0750 -o ARTIFACT_USER -g ARTIFACT_GROUP /data/models
```

Replace `ARTIFACT_USER` and `ARTIFACT_GROUP` with the identity used by the
artifact service. Do not run a filesystem formatter as part of an automated
LunaNexa install.

### DGX Spark nodes

Each DGX needs:

- a unique, stable Kubernetes node name such as `dgx-spark-01`;
- the NVIDIA driver/toolkit required by the approved runtime image;
- Podman or Docker at an allowlisted path;
- a protected engine socket at `unix:///run/podman/podman.sock` or an approved
  equivalent below `/run`;
- a pre-created OCI network named `lunanexa-runtime`;
- host directories `/etc/lunanexa` and `/var/lib/lunanexa`;
- network access to the controller, artifact HTTPS endpoint, OCI registry and
  approved runtime route only;
- synchronized time. Heartbeats outside the controller replay window are
  rejected.

The supplied DaemonSet uses host paths for configuration, state and the Podman
socket. Confirm that its non-root process identity can read the configuration
files, write `/var/lib/lunanexa`, and access only the intended engine socket.

### Node transport boundary

The controller process listens on HTTP inside its trusted deployment boundary.
The node executable accepts an HTTPS controller URL, or loopback HTTP for a
local proxy, but it does not currently load an X.509 client key into its native
HTTP transport. Deploy one of these patterns:

1. a node-local sidecar listening on `127.0.0.1` that establishes mTLS to the
   management service; or
2. an equivalent service-mesh path that transparently authenticates and
   encrypts node traffic.

Set the node's `controller-endpoint` to the protected endpoint for that pattern.
The per-node `Node` credential, heartbeat HMAC and replay fence remain required
inside the mTLS channel. The enrollment certificate record does not replace
transport TLS configuration. The base DaemonSet does not include this proxy;
add it in the reviewed production overlay. Do not make the public ingress
accept unauthenticated node traffic as a workaround.

## 4. Build and publish immutable images

From the repository root:

```sh
sh scripts/release-gate.sh
moon build cmd/control cmd/node cmd/cli --target native --release
sh scripts/build-browser-bundles.sh
```

Build controller, node, console and workbench images in the deployment-owned
image pipeline. Bundle the allowlisted Cosign binary in the controller and node
images. Sign each image, publish it to the private registry, and record its full
digest.

The files in `deploy/` intentionally contain values such as
`${CONTROLLER_IMAGE_DIGEST}` and `registry.invalid`. They are templates and
must not be applied until a reviewed overlay has replaced every placeholder
with a production value.

## 5. Prepare model and runtime distribution

### Model storage

Use a deterministic layout under `/data/models`; for example:

```text
/data/models/
  models/
    model.text/
      v1/
        model.blob
        model.blob.sig
  manifests/
  quarantine/
```

The S3-compatible service should expose the model above as an object such as
`s3://models/model.text/v1/model.blob`. Configure the service so the node's
scoped artifact credential can read approved model objects and detached
signatures but cannot write, list unrelated buckets or administer the service.

Before registration:

1. calculate and record the complete SHA-256 digest and byte size;
2. sign the blob with the deployment artifact-signing authority;
3. store the detached signature beside the blob;
4. verify the signature from a clean host;
5. retain license, provenance and evaluation evidence outside the model blob.

Set `ARTIFACT_ENDPOINT` to the HTTPS base URL that maps S3 object keys to these
objects. The node agent constructs
`$ARTIFACT_ENDPOINT/<bucket>/<object>`; the endpoint must support ordinary GET
and byte ranges for resumable downloads.

### Runtime images and routes

Publish each approved model server as a digest-pinned OCI image with an
image-defined health check. The current node supervisor does not publish a host
port. Production routing therefore requires an approved node-local HTTPS
gateway or equivalent endpoint attached to the `lunanexa-runtime` network.
That gateway must route only to the assigned, healthy container and must be
measured as part of cluster acceptance.

Create the strict route document used by the controller:

```json
[
  {
    "node_id": "dgx-spark-01",
    "endpoint": "https://runtime-01.cluster.example/v1/responses"
  },
  {
    "node_id": "dgx-spark-02",
    "endpoint": "https://runtime-02.cluster.example/v1/responses"
  },
  {
    "node_id": "dgx-spark-03",
    "endpoint": "https://runtime-03.cluster.example/v1/responses"
  },
  {
    "node_id": "dgx-spark-04",
    "endpoint": "https://runtime-04.cluster.example/v1/responses"
  }
]
```

Every schedulable node must have exactly one HTTPS mapping. There is no fallback
from an unmapped node to the generic runtime URL in strict mode.

## 6. Prepare Kubernetes placement and identity

Label nodes explicitly:

```sh
kubectl label node MANAGEMENT_NODE lunanexa.io/role=management
kubectl label node dgx-spark-01 lunanexa.io/role=gpu
kubectl label node dgx-spark-02 lunanexa.io/role=gpu
kubectl label node dgx-spark-03 lunanexa.io/role=gpu
kubectl label node dgx-spark-04 lunanexa.io/role=gpu
```

Replace `MANAGEMENT_NODE` with the real Kubernetes node name. Add a reviewed
deployment overlay with:

- `nodeSelector: {lunanexa.io/role: management}` for the controller, console,
  workbench and management-owned artifact components;
- `nodeSelector: {lunanexa.io/role: gpu}` for the node-agent DaemonSet;
- tolerations only for the taints deliberately assigned to those nodes.

This overlay is required: the base manifests do not currently enforce these
selectors, so applying them unchanged could run an agent on the management node
or a management component on a DGX.

Create a dedicated namespace and label only the trusted ingress namespace:

```sh
kubectl create namespace lunanexa
kubectl label namespace INGRESS_NAMESPACE lunanexa.io/ingress=trusted
```

Label the namespaces containing external runtime and artifact services as
required by `deploy/network-policy.yaml`:

```sh
kubectl label namespace ARTIFACT_NAMESPACE lunanexa.io/service=artifact-store
kubectl label namespace RUNTIME_NAMESPACE lunanexa.io/service=runtime
```

If services use host addresses rather than namespaces, replace the namespace
selectors with narrowly scoped `ipBlock` rules. Never add unrestricted egress.

## 7. Provision secrets and trust

Use the deployment secret provider to create these Kubernetes Secrets. Secret
manifests and literal values are intentionally absent from the repository.

### Controller credential keys

The `lunanexa-control-credentials` Secret must provide:

- `runtime-token`;
- `operator-token`;
- `inference-token`;
- `audit-token`;
- `monitoring-token`;
- `assignment-signing-secret`;
- `catalog-signing-secret`;
- `exclusive-lease-signing-secret`.

Use independent random values. `assignment-signing-secret` is also provisioned
to each node as the protected assignment verification key. Treat disclosure of
that shared verifier as cluster-wide signing-authority compromise.

### TLS and Cosign trust

Provision:

- `lunanexa-ingress-tls` for the public TLS endpoint;
- `lunanexa-client-ca` for ingress client-certificate validation;
- `lunanexa-cosign-trust` containing `cosign.pub`;
- the same read-only artifact verification public key on each DGX.

The native controller is designed to sit behind this trusted ingress. Do not
publish its port directly to an untrusted network.

## 8. Prepare each DGX host

Create the protected directories and rootless runtime network according to the
local OS and container-engine policy. Each host must contain:

```text
/etc/lunanexa/
  inventory.json
  node-token
  node-public-key
  assignment-verification-key
  artifact-credential
  cosign.pub
  bootstrap-token-id       # temporary, one use
  bootstrap-token          # temporary, one use
/var/lib/lunanexa/
  node-state.json           # created by the agent
  node-certificate.json     # created by enrollment
  models/                   # disposable verified local cache
```

Set credential files to mode `0600` and the directory to a protected owner/group
readable by the node agent. Do not use the same `node-token` on two DGX hosts.

Example inventory for `dgx-spark-01`:

```json
{
  "node_id": "dgx-spark-01",
  "agent_version": "0.1.0",
  "os_release": "ubuntu",
  "runtime_names": ["registry.example/model-runtime"],
  "accelerators": [
    {
      "device_id": "gpu-0",
      "architecture": "nvidia-gb10",
      "memory_total_mib": 128000,
      "memory_free_mib": 128000,
      "healthy": true
    }
  ],
  "labels": {
    "lunanexa.models": "model.text@v1",
    "lunanexa.warm-models": "",
    "lunanexa.data-classes": "Public,Internal,Confidential",
    "lunanexa.queue-depth": "0",
    "lunanexa.reliability-per-mille": "1000",
    "lunanexa.accelerator-utilization-per-mille": "0"
  },
  "taints": []
}
```

Inventory must be generated from the real host. Do not copy memory or device
values from this example without verifying them.

## 9. Render and apply the management plane

Render a private overlay that replaces:

- all image digests and registry names;
- controller epoch and runtime/model digests;
- controller, artifact and strict runtime endpoints;
- TLS hostname and namespace placeholders;
- storage class and PVC requirements;
- the management/GPU node selectors;
- any deployment-specific network-policy addresses.

Keep rendered manifests outside Git if they contain private inventory. Review
them for unresolved placeholders before applying:

```sh
rg '\$\{[A-Z0-9_]+\}|registry\.invalid|lunanexa\.invalid' RENDERED_DIRECTORY
```

The command must return no unresolved production placeholder. Apply in this
order:

1. namespace labels, service accounts, PVC, ConfigMaps and secret-provider
   resources derived from `deploy/prerequisites.yaml`;
2. controller from `deploy/controller.yaml`;
3. console and workbench;
4. network policies;
5. ingress;
6. the node-agent DaemonSet after the first DGX has been prepared.

Check the management plane before enrollment:

```sh
kubectl -n lunanexa rollout status deployment/lunanexa-control
kubectl -n lunanexa get pods,svc,ingress,pvc
curl --fail --cacert SERVER_CA_FILE \
  --cert OPERATOR_CLIENT_CERT --key OPERATOR_CLIENT_KEY \
  https://LUNANEXA_HOST/health
```

Client-certificate options depend on the chosen identity system; supply them
without putting private-key material in shell history.

## 10. Enroll the DGX nodes

Configure the CLI on a trusted operator host:

```sh
export LUNANEXA_ENDPOINT=https://LUNANEXA_HOST
export LUNANEXA_OPERATOR_TOKEN=FROM_SECRET_PROVIDER
```

For each DGX, generate a distinct bootstrap secret of at least 20 characters
and an expiry no more than 15 minutes in the future. Create a private JSON file:

```json
{
  "token_id": "bootstrap-dgx-spark-01",
  "secret": "REFERENCE_TO_A_FRESH_ONE_USE_VALUE",
  "expires_unix_ms": "REPLACE_WITH_UNIX_MILLISECONDS"
}
```

The JSON file passed to the CLI must contain the actual one-use value, but it
must be created with mode `0600`, excluded from Git, transferred through the
private operations channel and destroyed after enrollment.

Issue it:

```sh
lunanexa issue-enrollment-token bootstrap-dgx-spark-01.json
```

Place the matching ID and secret in the selected node's temporary
`/etc/lunanexa/bootstrap-token-id` and `/etc/lunanexa/bootstrap-token` files,
then enable the node-agent pod on that node. The agent enrolls, stores its
certificate under `/var/lib/lunanexa`, starts heartbeats and rotates the
certificate before expiry. Remove both bootstrap files after successful
enrollment.

Enroll and validate one DGX before enabling the other three:

```sh
lunanexa nodes
kubectl -n lunanexa logs daemonset/lunanexa-node --tail=100
```

Repeat with new bootstrap and node credentials for each remaining DGX.

## 11. Register and deploy the first model service

Use the operator sequence in `docs/OPERATIONS.md` to register the runtime,
model, license, verification and evaluation evidence, then approve and promote
an alias.

Update the example catalog template and intent with real digests, S3 object
references, resources and policies. Then run:

```sh
lunanexa register-template deploy/model-service-template.example.json
lunanexa plan-deployment deploy/model-service-intent.example.json
lunanexa deploy deploy/model-service-intent.example.json
lunanexa deployments
```

The same governed deployment is available from the Rabbita console after the
management plane is reachable:

1. open the console through the trusted TLS ingress and expand **Controller
   connection**;
2. enter the operator and audit credentials from the deployment secret
   provider, then select **Connect and refresh**;
3. on **Overview**, require all four **Deployment launchpad** checks to be
   green;
4. select **Open one-click deployment**;
5. choose the approved immutable template, enter a unique service name and the
   replica count;
6. select **Deploy model service** once. The controller performs the
   authoritative preflight and creates one durable, idempotent operation;
7. follow the operation in **Service operations** until it is ready, then
   promote it if the template requires explicit promotion.

The browser keeps credentials in memory and does not persist them in cluster
metadata. Retrying the same service name uses the same console idempotency key.
A different desired deployment must use a different service name.

“One click” begins after the deployment prerequisites are satisfied. It does
not silently install Kubernetes, configure TLS, create secret-provider
material, expose `/data/models`, enroll DGX hosts or approve a model license.
Those high-authority steps remain explicit because they require
deployment-specific trust and human approval.

The dry-run plan must be executable and name only eligible capacity. After the
deployment is accepted, verify:

- only the selected DGX downloads the model;
- the cache entry matches the declared size, digest and signature;
- the runtime receives a read-only mount at
  `/var/lib/lunanexa/model/model`;
- no artifact credential or S3 URI appears in the runtime environment;
- the node heartbeat reports the deployment only after runtime health succeeds;
- inference routing reaches the endpoint mapped to that DGX.

Do not pre-copy the model to the other three nodes. Their caches should remain
unchanged until an assignment explicitly selects them.

## 12. Exclusive node leases

The implemented management-plane lease API can reserve one DGX, generation-
fence its lifecycle and remove it immediately from managed placement:

```sh
lunanexa lease-node deploy/exclusive-node-lease.example.json
lunanexa exclusive-leases
lunanexa transition-node-lease LEASE_ID TRANSITION_FILE.json
```

The lease body contains a validated username and an `ssh-cert:` or `secret:`
reference. It never contains a password, private key or certificate value.

Production interactive access is not ready until the protected DGX daemon can
perform typed account provisioning, install short-lived SSH access, enforce
offline expiry, revoke access, stop tenant containers, sanitize lease data and
report cleanup evidence. Until that node-side slice is implemented and tested,
do not transition real leases to `Active` or give users DGX login access.

## 13. Acceptance checklist

Before production use, record evidence that:

- all four nodes have distinct credentials and truthful inventory;
- TLS client identity, controller-to-node authority and heartbeat replay fences
  reject invalid callers;
- controller state survives restart under a higher fencing epoch;
- an approved model deploys to exactly one selected DGX;
- digest/signature failure prevents runtime launch;
- an unlicensed or failed-evaluation model is blocked before assignment;
- draining one node prevents new placement there;
- strict runtime routing cannot reach an unmapped node;
- prompts, outputs, secrets, internal paths and node addresses do not appear in
  public responses or ordinary logs;
- backup and clean-host restore meet the declared RPO/RTO;
- measured DGX performance and model-license acceptance have named human
  approval.

Run the repository-owned validation before every image promotion:

```sh
sh scripts/release-gate.sh
```

The adversarial corpus, exact commands, evidence interpretation and remaining
blockers are recorded in `docs/PRODUCTION_READINESS.md`. This gate does not
replace the physical four-node acceptance campaign.

## 14. Backup, upgrade and rollback

Back up all controller snapshots together:

- controller/audit;
- registry;
- enrollment/certificate authority state;
- scheduler/quota state;
- telemetry evidence;
- workspace authority and admission state;
- model-service deployment operations;
- exclusive-node lease authority.

Back up `/data/models` separately by immutable digest, including detached
signatures, license/provenance manifests and the artifact service's object
metadata. Test restoration on a clean management node.

The current native `lunanexa.backup.v2` recovery bundle covers the five core
controller, registry, enrollment, scheduler and telemetry snapshots. Until that
format is extended, the deployment backup system must separately capture the
workspace/admission files, model-service operations and exclusive-lease state
while the controller is fenced. A five-file bundle alone is not a complete
backup of this deployment.

For an upgrade:

1. fence the previous controller;
2. back up and verify state;
3. deploy the new controller in reconciliation-only mode with a higher epoch;
4. inspect `lunanexa recovery-plan`;
5. enable mutations after node reconciliation;
6. cordon and upgrade one DGX agent at a time.

Rollback is permitted only when on-disk schemas remain compatible. A rolled-
back controller still needs a newer epoch; never reuse an older fencing epoch.

## 15. Common deployment failures

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Controller does not start | Missing required secret/config reference | Pod events and controller environment references |
| Node enrollment rejected | Expired/reused bootstrap or weak node token | Token expiry, one-use status and unique host files |
| Heartbeat rejected | Clock skew, wrong node ID/token or stale generation | NTP, inventory ID and node credentials |
| No placement | Node cordoned, leased, unhealthy or incompatible | `lunanexa nodes`, lease list and dry-run findings |
| Model download fails | HTTPS/S3 mapping, scoped credential, size or range handling | Artifact endpoint logs without exposing the credential |
| Model never reaches runtime | Digest or detached signature verification failed | Node agent evidence and quarantine path |
| Runtime never becomes ready | Image digest, health check, engine socket or gateway mismatch | Podman inspection and strict route mapping |
| Controller cannot invoke runtime | Missing/incorrect node endpoint or network policy | Runtime endpoint document, DNS and allowed egress |
| DGX remains unavailable after lease | Lease is non-terminal or quarantined | Lease generation and revocation/sanitization evidence |

For security rotation and recovery details, also read
`docs/SECURITY_OPERATIONS.md`, `docs/RECOVERY_RUNBOOK.md` and
`docs/EXCLUSIVE_NODE_LEASES.md`.
