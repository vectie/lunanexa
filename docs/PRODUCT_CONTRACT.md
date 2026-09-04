# LunaNexa product contract

## 1. Purpose

LunaNexa turns an explicitly inventoried accelerator fleet into a governed
model provider. The first named acceptance profile contains the owner's four
DGX Spark nodes, but that inventory is test input rather than product topology.
The architecture must continue to work when node count, placement,
accelerators, serving runtimes and tenants change.

LunaNexa is an infrastructure product, not a MoonSuite pack and not an agent
runtime. MoonSuite is an initial consumer, not part of LunaNexa's execution
environment.

## 2. Placement in the system

MoonSuite applications ask MoonGate for a model capability. MoonGate applies
product authority, client compatibility, provider selection and commercial
policy. If LunaNexa is selected, MoonGate sends a provider-neutral request to
LunaNexa. LunaNexa admits and schedules that request without knowing which
MoonSuite product originated it.

LunaNexa owns the northbound contract. A MoonGate adapter may depend on the
published LunaNexa contract package; LunaNexa has no reverse dependency on
MoonGate.

## 3. One product, multiple components

The initial distribution may produce several binaries or services:

| Component | Responsibility | Runs in the compute role? |
|---|---|---:|
| API | Authentication, validation, admission and streaming | No |
| Controller | Desired state, reconciliation, rollout and recovery | No |
| Scheduler | Placement, queues, capacity and failover | No |
| Registry | Models, artifacts, runtimes, licenses and evaluations | No |
| Model-source adapter | Reviewed catalog discovery and durable artifact import | No |
| Metering | Usage, quotas, timing and infrastructure audit | No |
| Commercial control | Organizations, cost centers, rating, ledger, budgets, commitments and agreements | No |
| Technical policy | Prewarm, probes, cache reconciliation, backpressure and transfer grants | No |
| Qualified-service ports | Normalized identity, signature, payment and invoice evidence | No |
| Management console | Rabbita cluster operations, access and lease administration | No |
| Deployment manager | Catalog, preflight, durable model-service operations and service readiness | No |
| Enterprise portal | Rabbita onboarding, agreements, lease requests, cost/model views | No |
| Developer workbench | Rabbita user workspace and provider-neutral model tooling inside the enterprise site | No |
| Exclusive lease manager | Node reservation, access lifecycle, expiry and sanitization authority | No |
| Node agent | Inventory, assignment-scoped model materialization, runtime supervision and heartbeats | Yes |
| Runtime adapter | Starts and observes an approved serving runtime | Yes |

These components share one product contract, release train, operator console
and version. Do not brand them as separate products.

The model-source adapter never approves a model. It supplies bounded catalog
metadata and verified import evidence to the controller, which remains the
license, evaluation, signature and publication authority.

The browser sites have different authorities. The management console is
for cluster operators and administrators. The enterprise site is for customer
administrators, legal signers, lease requesters, billing viewers and developers;
it includes the WebIDE. Both sites read one authoritative management API.
The sites run in the management role. A constrained profile may explicitly
co-locate that role with compute, but co-location never makes management
services compute capacity. Enterprise users cannot select or activate a
hardware node.

Human identity has two supported deployment shapes. A public platform identity
provider may allow any eligible person to create an account, while an enterprise
deployment may federate a customer's existing identity provider. Both terminate
at the same signed OIDC assertion boundary; LunaNexa does not store passwords.
An account is not a customer organization and grants no machine authority by
itself. After sign-in, a person may create an `Individual` or `Company` legal
customer record, or join an existing organization with a one-time invitation.
Organization verification, membership roles, agreements, budgets, projects and
orders remain LunaNexa authorities. Multi-organization requests must carry an
explicit selected organization and fail closed when selection is ambiguous.

The enterprise portal accepts only tenant-scoped commercial intent. It never
accepts a node ID, GPU ID, host address or raw access secret. It offers shared
MaaS, a prepaid dedicated model endpoint, and a prepaid bare accelerator
machine. For the two machine-backed paths the customer selects an active SKU and
duration, receives an immutable signed quote, accepts the current readable
machine terms, and completes an external checkout. Capacity is assigned only
after an authenticated exact-amount payment callback. `DedicatedEndpoint`
creates a managed deployment and never an exclusive lease; `BareMachine`
creates an exclusive-node lease. Cancellation, provisioning failure and
capacity timeout enter durable compensation. Prepaid usage remains evidence and
is not rated into a second payable ledger. A dedicated API key is durably bound
to the exact active order and deployment; inference cannot fall back to shared
capacity when that order ends or its routing cannot be enforced. See
`docs/SELF_SERVICE_MACHINE_ORDERING.md`.

### Topology contract

Management placement, compute enrollment, operator-network ingress, database
placement and model storage are independent deployment inputs. LunaNexa does
not infer any of them from accelerator presence, a network interface, a
hostname or another selected role.

- A management and compute role may use separate machines or be explicitly
  co-located after the operator accepts the resource and failure-domain risk.
- A bastion, access node, VPN or `ProxyJump` may solve operator reachability,
  but is not a LunaNexa role and is never required by the node protocol.
- Node count, accelerator vendor, Kubernetes distribution, public ingress and
  external-Internet availability belong to a named deployment profile, not the
  product contract.
- Every mutating workflow acts only on the roles and hosts explicitly selected
  in that request. Detection and convenience defaults never enroll a node.

Commercial control is infrastructure governance, not application billing
logic. It accepts opaque organization, project, actor and provider references;
raw prompts, identity documents, payment credentials and provider secrets are
not commercial state. Qualified-service implementations remain external
providers behind normalized ports. A test double may exercise the port only
when it identifies itself as non-production.

VS Code extensions and integrations with external developer tools are clients
of the published LunaNexa contract. In managed-service mode they receive
scoped, expiring provider access and do not place repository checkouts, editor
agents, arbitrary shells, application credentials or product-specific control
paths on GPU nodes. Exclusive-node mode is a separate infrastructure contract:
one subject receives time-bounded access to one named node after managed
placement has been disabled.

## 4. Northbound contract

The canonical v1 request is a typed, versioned workload envelope. It should
carry only infrastructure-relevant information:

- contract version, idempotency key and opaque workload identifier;
- opaque tenant reference and credential scope;
- capability such as `text.generate`, `embedding.create`, `image.generate`,
  `video.generate`, `audio.generate`, `model.evaluate` or `model.train`;
- model alias or policy selector, never a source repository path;
- payload plus its data classification and retention policy;
- deadline, priority, latency class and resource ceiling;
- streaming preference and normalized output requirements;
- trace correlation token that reveals no application identity.

Responses contain a stable status, normalized output, usage, model artifact
digest, runtime version, timing, retryability and an auditable receipt. Public
error bodies must not contain node addresses, filesystem paths, container IDs,
provider credentials, stack traces or internal topology.

OpenAI-, Anthropic- or other compatibility endpoints are adapters. They do not
replace the canonical LunaNexa contract.

## 5. Southbound contract

The node agent accepts only signed desired-state assignments from an
authenticated LunaNexa controller. An assignment identifies:

- deployment and model artifact digests;
- approved runtime image and immutable runtime configuration;
- resource limits, device placement and network policy;
- health, readiness and termination rules;
- data, cache and retention policy;
- rollout generation and lease expiry.

For every accepted assignment, only the named node downloads the referenced
model blob and detached signature from deployment-owned S3-compatible storage.
The node verifies the exact size, SHA-256 digest and signature before atomically
publishing the blob in its content-addressed local cache. The runtime receives
a read-only local bind mount; it never receives the artifact-store credential
or downloads the model itself. Nodes without an assignment do not materialize
the artifact. Removing the last local assignment for a digest removes that
node's cached copy.

Nodes report typed inventory, heartbeat, deployment state, capacity, runtime
health and bounded telemetry. They never receive MoonSuite workflows, domain
records or product credentials.

An exclusive-node directive is distinct from a model-service assignment. It
names one node, one opaque subject, one validated local username, one host-owned
credential reference, one expiry and one generation. Raw passwords and private
keys are not contract fields. A node under a non-terminal exclusive lease is
ineligible for managed assignments until access revocation and sanitization
have produced accepted receipts.

## 6. Authority and security

- Mutual authentication is required between controller and nodes.
- Node agents initiate or maintain a narrow management channel. Interactive
  access exists only in explicit exclusive-node mode and is provisioned through
  a typed lease directive, never arbitrary controller-supplied shell text.
- Desired state is signed and generation-numbered. A stale controller cannot
  silently overwrite a newer deployment.
- Model artifacts and runtime images are pinned by an exact 64-hexadecimal-digit
  SHA-256 digest and verified before use; prefix-only digest lookalikes are
  rejected.
- Raw prompts and outputs are absent from logs by default.
- Secrets are referenced through deployment-owned secret stores and delivered
  only to the runtime that requires them.
- Every consequential operation creates an immutable audit event with actor,
  policy, target, prior state, next state and result.
- Administrative and inference credentials are separate.
- Production enterprise registration and workspace authority are committed to
  PostgreSQL; authentication passwords remain owned by the external identity
  provider and are never LunaNexa database fields.

## 6a. Management-plane deployment contract

The one-click path accepts only a compact, idempotent model-service intent that
references a controller-signed catalog template. Templates pin model artifacts
and runtime images, policy, resource and health profiles, secret references,
and rollout rules. The management plane expands accepted intent into ordinary
signed node assignments; nodes never receive the catalog, operator identity,
or management credentials.

One-click deployment is fail-closed. Unapproved models, unverified artifacts or
images, failed evaluations, missing license acceptance, missing secret
references, incompatible data classes, or insufficient capacity create typed
preflight blockers rather than partially launching a runtime.

The v1 one-click materialization contract keeps stable `s3://bucket/object`
references. Production nodes resolve them directly against the reviewed
Moongate S3-compatible HTTPS origin and authenticate with node-local,
least-privilege SigV4 credentials that are never passed to runtimes. A detached
signature may have its own reference; an opaque Cosign evidence reference
resolves to the sibling `<model-object>.sig` object. OCI remains the
digest-pinned runtime-image transport. Artifact transfer is pull-based by the
selected node and bound to its live signed assignment; the controller never
opens an SSH, copy or arbitrary shell channel and does not mount model bytes in
the production HA profile.

## 7. Explicit non-goals for v1

- Building a new container orchestrator, object store or metrics engine.
- Transparent shared memory or mandatory distributed inference across an
  entire selected fleet.
- Autonomous model promotion or policy mutation.
- A general workflow, pack or agent system.
- MoonSuite-specific dashboards on cluster nodes.
- Public multi-tenant hosting before the private cluster passes its operational
  and security gates.
- Batch jobs, task groups, spot queues, and an autonomous autoscaler. Capacity
  changes are explicit operator actions against the selected inventory.
- Hosting source repositories, arbitrary development containers or IDE agent
  runtimes while a node is in managed-service mode. An exclusive lessee may run
  their own development workload inside the separately governed lease boundary.

## 8. Release acceptance

The first usable release must demonstrate through the operator UI and APIs:

1. enroll every compute node in the named acceptance inventory without
   installing a MoonSuite application on any node;
2. register and verify a licensed model artifact;
3. deploy it to a selected node and obtain a healthy readiness state;
4. route a generic request through MoonGate to LunaNexa and stream the result;
5. meter the request and return a replayable receipt;
6. for a profile that claims failover, drain or stop one node and route
   subsequent eligible work to another explicitly eligible node;
7. restart the controller and reconcile durable desired state;
8. prove that public responses and node assignments contain no forbidden
   MoonSuite identifiers or internal secrets.
