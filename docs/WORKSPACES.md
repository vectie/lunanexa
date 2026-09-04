# Developer workspaces and editor integrations

LunaNexa exposes two Rabbita browser components:

- `cmd/console` is the management console for cluster operations, user access,
  quotas, leases, models, deployments and audit evidence.
- `cmd/workbench` is the individual developer surface for lease status, local
  browser editing, provider-neutral model invocation and editor handoff.

The workbench follows a cloud-lab entry pattern: confirm identity and an active
lease, choose the browser Web IDE or an external editor handoff, then enter the
editing surface. The editing surface keeps resource and expiry status visible
so a user understands why launch or invocation is unavailable.

The interaction sequence is informed by
[Huawei HiDevLab's public IDE guide](https://hidevlab.huawei.com/support/userGuide?currentKey=ide):
permission approval, environment/resource selection, an explicit ready state,
connect/disconnect actions, visible remaining time, and handoffs to WebIDE,
VS Code, Trae, and CodeBuddy. LunaNexa intentionally adapts that sequence to its
narrower model-service boundary. It does not clone repositories, mount user
storage, start arbitrary shells, or install editor agents on managed DGX nodes;
those belong in a separate development-environment plane if the platform later
adds one.

For the short operator-to-user journey that replaces manual account,
membership, grant, lease, contract and handoff coordination, see
[Access onboarding UX](ACCESS_ONBOARDING_UX.md).

Access-package creation is a persisted forward-recovery saga, not an impossible
transaction spanning independent authorities. Its `access_onboarding`
PostgreSQL snapshot (or `0600` development file) is committed before the first
resource and after every verified step. Startup reconciliation resumes
non-terminal work. A crash between a resource write and its checkpoint is
repaired by validating the deterministically named resource; failures and
conflicts remain visible rather than becoming silent orphan state.

## Trust boundary

A `WorkspaceLease` is an expiring control-plane entitlement. It declares
session policy and limits generic inference capabilities; it does not grant a
node login, remote shell, repository checkout, filesystem mount or arbitrary
development container on a DGX node.

Web IDE state remains in the browser/workspace trust domain. VS Code,
CodeBuddy, WorkBuddy, Trae and Qoder are client integrations represented by
typed provider-neutral handoff metadata. Product credentials and editor-agent
state remain with those clients. A managed node receives only the normal signed
LunaNexa assignment and generic workload envelope.

## Implemented workspace slice

The public `workspace` package owns validated user, access-grant, lease,
session, capability, editor and integration lifecycle types for native and
JavaScript consumers. A native file-backed directory persists the management
records atomically and reconstructs them across controller restart. Its derived
self contract selects an active lease only when the subject, access grant,
tenant scope, capability and time window all agree.

When lease enforcement is enabled, a separate `0600` atomic admissions sidecar
durably reserves each workload before scheduler admission. It enforces the
capability's held-request concurrency and rolling one-hour request count. The
actual UTF-8 byte length of canonical payload JSON must fit both the request's
declared input ceiling and the lease input limit; the declared output ceiling
must also fit the lease. Completion and cancellation release held concurrency,
while the historical reservation remains as subject-and-tenant ownership
evidence. A controller crash conservatively holds concurrency until the
request deadline, capped at 24 hours, then recovery marks it non-active without
erasing ownership.

`max_active_sessions` and `max_session_duration_ms` apply only to a future
server-side `WorkspaceSession` service. The current browser-local workbench
creates no server-side session, so those two fields are validated policy but
are not enforced by inference admission. Per-capability concurrent-request
limits are the only inference concurrency control in this workspace layer.

The controller exposes operator-authorized workspace reads and mutations under
`/v1/workspace`, and an inference-authorized `/v1/workspace/self` read for the
individual subject. When `LUNANEXA_REQUIRE_WORKSPACE_LEASE=1`, unary and
streaming workload admission fail closed before scheduling unless that self
contract authorizes the request. Revoking a grant or ending a lease changes the
durable state and appends the normal immutable operator audit evidence.
User activation, suspension and revocation, plus requested-lease activation,
are checked lifecycle transitions with exact prior/next states in audit events.

The management console reads these records and sends the same typed mutations
as automation. The workbench loads a live self-authorization view, keeps its
bearer credential in browser memory, and sends an explicit canonical ephemeral
workload. `extensions/vscode` provides the first external client: it stores its
scoped token in VS Code SecretStorage and sends only an explicitly selected
range under the same provider-neutral policy.

## One-click desktop WebIDE handoff

The enterprise portal now supports one deployment-owned desktop client without
coupling LunaNexa source to a particular WebIDE product. The production flow is:

1. the portal verifies the enterprise subject, Developer role, effective
   MasterLease, active workspace lease and approved model aliases;
2. `POST /v1/portal/self/client-handoffs` creates a 30–300 second, single-use
   code and a lease-bounded API credential, persisting only their SHA-256
   digests;
3. the portal puts only `client_id` and the `lnxc_…` one-time code in the
   desktop launch URL fragment—never the reusable `lnx_…` API secret;
4. the local desktop removes the fragment before its first network request and
   forwards the bounded code over its authenticated loopback control channel;
5. the desktop runtime redeems the code from its administrator-pinned LunaNexa
   issuer and installs the returned scoped provider into its local gateway;
6. MoonCode selects that local gateway provider and sends model traffic to the
   LunaNexa OpenAI-compatible endpoint.

Redemption reveals the API secret once. A wrong client, expired/revoked code or
replay fails closed. Every request made with the resulting desktop credential
rechecks both the workspace lease and effective MasterLease, so early lease
termination immediately blocks model discovery and inference. The credential
also remains restricted to the aliases selected at issue time, its request
quota and the lease expiry.

The local receiver must pin the management origin in deployment configuration;
it must not accept an issuer URL from the browser fragment or request body. The
approved MoonDesk/MoonClaw deployment contract uses
`MOONDESK_LUNANEXA_ISSUER`. MoonGate control authority remains a local secret
reference and is never returned to the portal. Production readiness requires
the companion runtime to implement the authenticated redemption/install route;
the LunaNexa controller never imports that product-specific adapter.

This directory is a LunaNexa authorization adapter, not a production identity
provider. Production ingress must authenticate the human and assert the mapped
opaque subject. LunaNexa never stores the upstream password, client
certificate, editor credential or application credential.

## HTTP authority

Operator authority:

- `GET /v1/workspace`
- `POST /v1/workspace/users`
- `POST /v1/workspace/users/{user_id}:activate`
- `POST /v1/workspace/users/{user_id}:suspend`
- `POST /v1/workspace/users/{user_id}:revoke`
- `POST /v1/workspace/access-grants`
- `POST /v1/workspace/leases`
- `POST /v1/workspace/access-grants/{grant_id}:revoke`
- `POST /v1/workspace/leases/{lease_id}:activate`
- `POST /v1/workspace/leases/{lease_id}:end`

Inference authority:

- `GET /v1/workspace/self`
- `POST /v1/workloads` and `POST /v1/workloads:stream`, subject to lease
  admission when enforcement is enabled
- `GET /v1/workloads/{workload_id}` and
  `POST /v1/workloads/{workload_id}/cancel`; with enforcement enabled these
  require the authenticated subject to own the durable admission. The tenant
  scope remains bound to that globally unique workload ID at original
  admission and is not accepted again from a caller-controlled header.

The mutation bodies are the shared typed `WorkspaceUser`,
`WorkspaceAccessGrant` and `WorkspaceLease` JSON contracts rather than
UI-specific forms. Responses contain the persisted public record or bounded
receipt and never return credential or node material.

## Production integration checklist

1. Select the administrative identity provider and map its subjects to the
   opaque LunaNexa subject references stored in the implemented directory.
2. Configure the durable workspace path, back up both it and its
   `.admissions` sidecar, and retain expiry reconciliation and immutable audit
   evidence with the other controller state.
3. Issue separate scoped credentials for management, audit and inference.
4. Serve both browser components behind the trusted TLS management ingress and
   enable lease enforcement. A verified ingress-nginx client-certificate DN is
   reduced to `mtls:sha256:<sha256(DN)>`. The supplied network listener accepts
   `X-LunaNexa-Subject` only from a proved loopback TCP peer; remote production
   identity must arrive through the verified auth-TLS headers, and direct
   controller access must remain blocked by NetworkPolicy.
5. Configure the provider-neutral desktop client launch and public API base,
   and pin the same LunaNexa issuer in the desktop runtime. Never put a reusable
   bearer token in a URL.
6. Validate revoked/expired leases, narrow layouts, keyboard operation and
   built-image isolation before hardware acceptance.

## Open-registration trial boundary

Open registration may create one short-lived shared-inference trial workspace.
That workspace is topology-free and authorizes only its recorded model
allowlist and request limits. It never creates an exclusive-node lease, SSH
access, a machine account, or credential handoff. An enterprise invitation
replaces the trial membership and revokes the trial grant and lease before the
enterprise access path proceeds.
