# Installation, upgrade, rollback, and handoff

For the concrete management-node plus four-DGX installation sequence, use
`docs/DEPLOYMENT.md`. This document remains the detailed configuration and
operator reference.

## Build and repository gate

Use the pinned dependencies in `moon.mod`:

```sh
sh scripts/release-gate.sh
moon build cmd/control cmd/node cmd/cli cmd/benchmark cmd/evidence cmd/recovery --target native
moon build cmd/console cmd/enterprise cmd/workbench --target js
sh scripts/build-browser-bundles.sh
```

The browser bundle command produces self-contained static roots at
`_build/browser-dist/console`, `_build/browser-dist/enterprise` and
`_build/browser-dist/workbench`. Serve the console on the operator origin and
serve `/enterprise/` plus `/workbench/` on the enterprise origin. Both origins
proxy `/v1` to the same controller and default to their page origin unless
`globalThis.LUNANEXA_API_ENDPOINT` is injected before their module script.

The console image copies the contents of `browser-dist/console` to its document
root. The workbench image copies the complete `browser-dist` directory to its
document root, so `/workbench/index.html` and `/workbench/workbench.js` exist
without an ingress rewrite. Its readiness probe deliberately checks
`/workbench/`. Keep this path contract when replacing the static server image;
the release gate verifies the bundle layout, while the deployment pipeline is
responsible for building and signing the immutable images referenced by the
templates.

The repository gate is necessary but does not replace cluster acceptance.

## Evidence export

After benchmark runs have been recorded, export capacity and objective evidence
from a telemetry snapshot and a reviewed input manifest:

```sh
lunanexa-evidence recommend telemetry.json recommendation-input.json recommendation.json
lunanexa-evidence bundle telemetry.json evidence-input.json evidence-bundle.json
```

The recommendation input names one benchmark run, its service objective, tested
concurrency, and measured total/peak memory. The bundle input supplies the
release version, scenario/isolation results, report references, and optional
named acceptor. Output is written atomically with mode `0600`. The tool reports
`release-ready` only when `EvidenceBundle.release_ready()` succeeds; an
incomplete bundle is still exported for review without being presented as an
accepted release.

## Controller configuration

The controller requires these deployment values. Values named as credentials
must come from the secret provider, not a committed file:

| Variable | Meaning |
| --- | --- |
| `LUNANEXA_LISTEN_ADDRESS` | Bind address; defaults to `127.0.0.1:8080` |
| `LUNANEXA_STATE_PATH` | Durable controller/audit snapshot |
| `LUNANEXA_REGISTRY_PATH` | Durable registry snapshot |
| `LUNANEXA_ENROLLMENT_PATH` | Durable enrollment/certificate snapshot |
| `LUNANEXA_SCHEDULER_PATH` | Durable quota/usage/placement snapshot |
| `LUNANEXA_TELEMETRY_PATH` | Durable bounded telemetry/evidence snapshot |
| `LUNANEXA_WORKSPACE_PATH` | Durable user, access-grant and workspace-lease snapshot |
| `LUNANEXA_DEPLOYMENT_PATH` | Durable catalog and model-service operation snapshot |
| `LUNANEXA_EXCLUSIVE_LEASE_PATH` | Durable exclusive-node lease snapshot |
| `LUNANEXA_PORTAL_PATH` | Durable enterprise memberships, agreement projections and lease requests |
| `LUNANEXA_PERSISTENCE_BACKEND` | `postgres` in production; `file` is an explicit development fallback |
| `LUNANEXA_DATABASE_URL` | Secret-provided PostgreSQL URL; required when the backend is `postgres` |
| `LUNANEXA_AVAILABLE_SECRET_REFS` | Comma-separated deployment-owned secret reference names available to preflight; never secret values |
| `LUNANEXA_REQUIRE_WORKSPACE_LEASE` | `1` requires trusted subject, active grant and active lease before workload admission |
| `LUNANEXA_CONTROLLER_EPOCH` | Positive fencing epoch, monotonically raised |
| `LUNANEXA_ADMISSION_CAPACITY` | Maximum concurrent admitted workloads |
| `LUNANEXA_RUNTIME_CONCURRENCY` | Maximum actively executing adapter calls; additional admitted work waits in the bounded queue |
| `LUNANEXA_RECONCILIATION_ONLY` | `1` disables inference/operator writes during recovery |
| `LUNANEXA_RUNTIME_ENDPOINT` | HTTPS serving-adapter endpoint |
| `LUNANEXA_RUNTIME_ENDPOINTS_PATH` | Optional JSON array mapping scheduler node IDs to concrete HTTPS adapter endpoints; when present, routing is strict |
| `LUNANEXA_RUNTIME_CREDENTIAL` | Serving-adapter credential value |
| `LUNANEXA_RUNTIME_VERSION` | Registered runtime version |
| `LUNANEXA_RUNTIME_IMAGE_DIGEST` | Exact `sha256:` runtime image digest |
| `LUNANEXA_MODEL_ARTIFACT_DIGEST` | Exact `sha256:` model artifact digest |
| `LUNANEXA_OPERATOR_TOKEN` | Operator authority |
| `LUNANEXA_INFERENCE_TOKEN` | Inference authority |
| `LUNANEXA_AUDIT_TOKEN` | Read-only audit authority |
| `LUNANEXA_MONITORING_TOKEN` | Read-only `/metrics` authority |
| `LUNANEXA_ASSIGNMENT_SIGNING_SECRET` | Controller HMAC signer; matching verifier key is host-owned on nodes |
| `LUNANEXA_CATALOG_SIGNING_SECRET` | Independent controller HMAC authority for immutable management-plane templates |
| `LUNANEXA_EXCLUSIVE_LEASE_SIGNING_SECRET` | Independent controller HMAC authority for exclusive-node lease generations |
| `LUNANEXA_COSIGN_BINARY` | Allowlisted absolute Cosign binary path |
| `LUNANEXA_COSIGN_PUBLIC_KEY_PATH` | Read-only mounted public trust key |

PostgreSQL stores enterprise registrations, portal agreements and lease
requests, workspace users, grants, leases and admission snapshots. It never
stores login passwords. See `docs/DATABASE.md` for migrations, least-privilege
roles, backup and recovery.

Expose the operator console and enterprise portal/WebIDE as separate sites as
shown in `deploy/ingress.yaml`; both proxy the same `/v1` API. Keep `/metrics`
management-only. Production ingress or a
service mesh owns server TLS, client-certificate validation and identity
translation; the native process accepts traffic only from that trusted
management boundary.

With ingress-nginx client-certificate authentication, the controller accepts
only `ssl-client-verify: SUCCESS` and derives the subject reference as
`mtls:sha256:<hex(sha256(utf8(trim(ssl-client-subject-dn))))>`. The raw
distinguished name is not persisted. A different identity-aware proxy must
strip any client-supplied `X-LunaNexa-Subject` and inject its own opaque mapped
value through an authenticated transport signal understood by the controller.
The explicit subject header is accepted only when the controller observes an
actual loopback TCP peer. Native CLI and benchmark acceptance runs may set
`LUNANEXA_SUBJECT_REF` for that loopback path; remote callers cannot use the
header as a production identity assertion.

When workspace enforcement is enabled, the controller also writes
`$LUNANEXA_WORKSPACE_PATH.admissions`. Back up and restore that `0600` file with
the main workspace directory and controller workload state: it carries rolling
hour counts, crash-recoverable concurrency reservations, and durable
subject/tenant ownership for status and cancellation. Admission measures
`resource_ceiling.max_input_units` and the lease input limit as UTF-8 bytes of
canonical payload JSON. The current browser-local workbench does not create a
server-side `WorkspaceSession`, so session-count and session-duration fields
remain validated policy rather than enforced runtime limits.

For direct four-node routing, mount a route document at
`LUNANEXA_RUNTIME_ENDPOINTS_PATH`:

```json
[
  {"node_id":"dgx-01","endpoint":"https://runtime-01.cluster.invalid/v1/responses"},
  {"node_id":"dgx-02","endpoint":"https://runtime-02.cluster.invalid/v1/responses"}
]
```

Every schedulable node must have exactly one HTTPS entry. An unmapped selected
node fails closed and is eligible only for the normal bounded alternate-node
retry; it never falls back to the generic URL. If this file is omitted,
`LUNANEXA_RUNTIME_ENDPOINT` must be a trusted node-aware gateway that enforces
the `X-LunaNexa-Target-Node` routing hint. The supplied deployment template uses
the strict map and requires `${RUNTIME_ENDPOINTS_JSON}` substitution.
In strict mode, routing begins only after the node heartbeat reports the exact
deployment ID from a live, non-expired desired assignment whose artifact and
runtime digests match the approved alias. Inventory labels express eligibility;
they do not substitute for runtime readiness.
Direct runtime services outside the LunaNexa namespace must live behind a
namespace labelled `lunanexa.io/service=runtime` and listen on TLS port 443, or
the controller's default egress policy will reject the connection. Host-level
endpoints require an equivalent deployment-specific `ipBlock` rule constrained
to the private runtime addresses; do not add unrestricted controller egress.

## Node configuration

Every node has host-owned `/etc/lunanexa` material and a unique node token.
`inventory.json` is a canonical `NodeInventory`. Scheduler-relevant labels are:

```json
{
  "lunanexa.models": "model.text@v1",
  "lunanexa.warm-models": "model.text@v1",
  "lunanexa.data-classes": "Public,Internal,Confidential",
  "lunanexa.queue-depth": "0",
  "lunanexa.reliability-per-mille": "1000"
}
```

Inventory must also name runtime adapters and every accelerator's truthful
architecture, total/free memory and health. Missing license/data-class labels
fail closed during placement. The node token becomes that node's authority at
enrollment and is stored only as a digest by the controller. Remove or revoke
the one-use bootstrap material after enrollment.

The pre-created rootless OCI network and engine socket are deployment
prerequisites. The agent invokes only an allowlisted Podman/Docker binary with a
fixed argument vector, digest-pinned pull, read-only root filesystem, dropped
capabilities, private IPC, bounded PIDs/CPU/memory, and no arbitrary egress.

Each node also requires these materialization values:

| Variable | Meaning |
| --- | --- |
| `LUNANEXA_MODEL_CACHE_PATH` | Absolute host-backed cache root; defaults to `/var/lib/lunanexa/models` |
| `LUNANEXA_ARTIFACT_ENDPOINT` | Protected controller base ending in `/v1/artifacts` |
| `LUNANEXA_ARTIFACT_CREDENTIAL_PATH` | The node's own protected Node credential file; its value is never passed to runtimes |
| `LUNANEXA_ARTIFACT_MAX_SIZE_BYTES` | Per-artifact safety ceiling; defaults to 1 TiB |
| `LUNANEXA_NVIDIA_SMI_BINARY` | Allowlisted `/usr/bin/nvidia-smi` or `/usr/local/bin/nvidia-smi` sensor executable |
| `LUNANEXA_COSIGN_BINARY` | Allowlisted Cosign path in the node-agent image |
| `LUNANEXA_COSIGN_PUBLIC_KEY_PATH` | Read-only node-local public key used for detached model signatures |

The model reference in an approved template is a logical
`s3://bucket/object` value. Its detached signature may be another logical
reference; an opaque Cosign evidence reference resolves to the sibling
`<model-object>.sig` object. The selected node maps these beneath the controller
gateway, which authorizes only its live assignment, resumes an incomplete
transfer using strict `Range`, verifies the declared size, SHA-256
digest and detached Cosign signature, and atomically publishes the model under
the cache root. The runtime receives only `/var/lib/lunanexa/model/model` as a
read-only bind mount. When no local desired assignment references the digest,
reconciliation prunes that node's copy.

## Operator sequence

Set `LUNANEXA_ENDPOINT` and the appropriate token environment variables, then
use the native CLI:

```sh
lunanexa health
lunanexa issue-enrollment-token bootstrap.json
lunanexa nodes
lunanexa register-runtime runtime.json
lunanexa register-model model.json
lunanexa record-license license.json
lunanexa record-verification verification.json
lunanexa record-evaluation evaluation.json
lunanexa approve approval.json
lunanexa promote promotion.json
lunanexa set-quota quota.json
lunanexa assign unsigned-assignment.json
lunanexa invoke workload.json
lunanexa stop-assignment assignment-id
```

For the management-plane deployment path, first register an unsigned approved
template candidate and then submit one compact intent:

```sh
lunanexa register-template deploy/model-service-template.example.json
lunanexa plan-deployment deploy/model-service-intent.example.json
lunanexa deploy deploy/model-service-intent.example.json
lunanexa deployments
lunanexa deployment text-small-service
```

For an exclusive machine lease, submit a credential reference rather than a
password or private key, then advance only with receipts from the node-side
provisioning and cleanup workflow:

```sh
lunanexa lease-node exclusive-lease.json
lunanexa exclusive-leases
lunanexa terminate-node-lease lease-id current-generation operator-request
```

The first request immediately removes the selected node from managed placement
and publishes a cordon or drain directive. The controller automatically enters
`Provisioning` only after desired assignments and observed deployments are
empty. Direct operator lifecycle transitions are rejected; activation and
cleanup require verified node-helper evidence. See
`docs/EXCLUSIVE_NODE_LEASES.md` and `docs/EXCLUSIVE_LEASE_USE_CASES.md`.

Expiry and early termination follow the same fail-closed sequence. The node is
not schedulable after the termination request and becomes available only after
a fresh generation-bound sanitization receipt proves the dedicated account,
sessions/processes, rootless containers/volumes, home, access material and lease
state are absent. A helper failure or forged/stale receipt quarantines the node.

The controller fills the template approval receipt and signature. The example
digests and artifact location are placeholders and must be replaced by the
already registered, verified, evaluated and approved deployment inventory.

`record-verification` accepts a verification request, never a successful
verification claim. For an image, provide `kind`, the registry `subject`
without a digest, the expected `digest`, and `provenance_verified`. For a blob,
use `kind: "blob"`, an absolute staged artifact path as `subject`, and an
absolute `signature_path`. The controller invokes its fixed-command Cosign
adapter and mints the durable verification record itself. Hand-authored
`signature_verified` booleans are rejected. Runtime image and model artifact
digests must both have successful signature and provenance records before an
assignment can deploy.

Assignment input must contain an empty `signature`. The controller validates
the registry, epoch, generation, lease, resources, and network policy, then
signs the accepted desired state with the management-plane authority. Operator
and CLI hosts must never receive the assignment signing secret. Nodes hold the
matching host-owned HMAC verifier key; compromise of that key is therefore a
node/assignment trust-root incident and requires cluster-wide rotation.

The console Policies view exposes the same typed operations for enrollment,
registry, approval, promotion, quota, workspace users/grants/leases,
controller-signed assignment submission, invocation and benchmark JSON. Its
Users and Leases routes read the durable workspace snapshot and require
confirmation before revocation or early termination. Draft bodies and the
operator, inference, and audit password inputs exist only in browser memory;
console state deliberately has no JSON/debug serialization. Prefer the
CLI for repeatable automation and never paste deployment credentials into an
operation body.

Run measured evidence with:

```sh
lunanexa-benchmark workload.json text-short-v1 concurrency 100 8
lunanexa-benchmark workload.json text-long-v1 long-stream 20 2
```

Mixed runs additionally set `LUNANEXA_MIXED_WORKLOAD_FILES` to a comma-separated
list of at least two canonical workload files. Cold-start runs require the
operator to stop and redeploy the assignment before the measured run. Join
external Prometheus evidence to the generated run ID before acceptance. The
driver also joins the peak allowlisted node utilization sample observed during
the run into every submitted benchmark summary; absence of such a sample leaves
the value at zero and must be called out in the acceptance report.

## Install

1. Collect the private deployment inventory listed in
   `IMPLEMENTATION_HANDOFF.md`; do not commit it.
2. Provision the transactional metadata service, OCI registry, S3-compatible
   artifact store, metrics backend, certificate authority, and secret provider.
3. Build native control, node, and CLI binaries and both JavaScript Rabbita
   browser components. Bundle the allowlisted Cosign binary in the controller image, mount
   the public trust key as the read-only `lunanexa-cosign-trust` Secret, sign
   images, and substitute immutable digests in the deployment overlay.
4. Apply management-plane identity/RBAC, controller, console, workbench and
   default-deny policies. Create a short-lived enrollment token for one node
   only.
5. Complete the one-node acceptance slice before enrolling the remaining three
   nodes.

Apply `deploy/prerequisites.yaml`, controller, console, workbench, ingress,
node DaemonSet and network policies only after substituting immutable digests,
endpoints, epochs, host inventory and TLS names. Secret objects are intentionally absent
from the repository templates. Provision the `lunanexa-client-ca` Secret in the
target namespace and substitute `${LUNANEXA_NAMESPACE}` in the NGINX ingress
annotation. Label the ingress-controller namespace
`lunanexa.io/ingress=trusted`; no other namespace receives direct controller,
console or workbench ingress through the default network policies.

## Upgrade

Back up controller, registry, enrollment, scheduler, telemetry, workspace and
deployment-operation state,
validate the recomputed audit hash chain and signed manifest, deploy the new
controller in reconciliation-only mode with a higher epoch, inspect its plan,
using `lunanexa recovery-plan`, then enable mutations. Upgrade node agents one
at a time while the node is
cordoned. Promote runtime images through canary using immutable digests.

## Rollback

Roll back model aliases with the recorded promotion receipt. Roll back a
controller only if its schema remains compatible and it can acquire a newer
epoch; an older epoch must never mutate assignments. Restore a signed backup on
a clean management host when schema rollback is unsafe.

## Operator handoff

Transfer deployment inventory, CA/secret ownership, backup locations, on-call
contacts, approved model licenses, named benchmark profiles, current service
objectives, open alerts, and the latest evidence bundle through the private
operations channel. No credential values belong in the handoff document.
