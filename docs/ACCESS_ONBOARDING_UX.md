# Access onboarding UX

The complete LunaNexa access procedure remains a useful operational and audit
runbook, but it is not the product journey. Human users should not copy opaque
identifiers between account, portal, contract, workspace, credential and
desktop forms.

## Product journey

### Private-cloud workspace

The customer-facing path is **sign in/register → administrator grants resources
→ open ComfyUI or WebIDE**. In the explicit private-cloud profile, no rental
contract is requested for the owner's resources. The administrator selects an
existing account, resource scope and expiry; dependent grant, lease and handoff
records remain behind that action. The existing raw identity/tenant form is an
advanced bootstrap path, not the target normal journey.

One role-aware workspace preserves three delivery mechanisms: IaaS bare-machine
rentals, PaaS WebIDE/ComfyUI workspaces, and MaaS model APIs. Sharing the interface
does not share all users' processes or files. Project collaboration must be
explicit. Administrator controls are visible by role, not granted by a UI switch.

Backend private-cloud admission is implemented; the simplified existing-account
selection, unified role-aware navigation and live browser journey still require
implementation/acceptance. Do not present this target journey as already tested.

### Individual trial user

1. Choose **Sign in / register** and complete the external OIDC login.
2. LunaNexa creates the account and a 24-hour shared-inference trial; no
   invitation, opaque identifier entry, or operator action is required.
3. Review the expiry, approved model aliases, hourly limit and total request
   allowance, then create the single trial API key.
4. Use the approved model through the shared workspace. The trial does not
   create SSH credentials, an exclusive-node lease, or access to a physical
   machine.
5. To continue, accept an organization invitation. LunaNexa replaces the trial
   membership and immediately revokes the trial lease and trial-key authority.

### Operator

1. Open **Users & access** and choose **Create WebIDE access**.
2. Enter the verified identity-provider subject, person, organization and
   tenant. Select the reviewed WebIDE developer template and an access period.
3. Review the derived scope and create the package. LunaNexa derives stable
   identifiers and creates the account, enterprise membership, workspace user,
   Developer grant and requested workspace lease as one durable saga.
4. Choose **Enable WebIDE** after resource readiness. In the commercial profile,
   the customer's MasterLease must also be effective; private-cloud access does
   not require that contract.

### Enterprise user

1. Sign in with the organization's identity provider.
2. Complete the MasterLease only when the readiness page identifies it as the
   remaining gate.
3. Open **Desktop IDE**, review the granted tenant, models and expiry, and
   choose **Open desktop WebIDE**.
4. Work in MoonCode. The one-time handoff installs a lease-scoped
   `lunanexa-lease` provider in MoonGate without exposing its reusable secret to
   the browser.

## What remains automated and logged

The guided flow does not weaken the underlying controls. It records the same
account, membership, workspace, grant, lease, contract, handoff and inference
events with their resource references and operator identity. The ordinary view
shows five milestones:

1. identity;
2. organization access;
3. contract;
4. workspace and models;
5. desktop connection.

The operator can expand **Technical evidence** to see the derived identifiers,
per-resource state, correlation receipts and recovery guidance. Existing
granular mutation routes remain available under advanced operations for
exception repair and migration; they are not the default onboarding journey.

The saga commits a redacted intent before creating any cross-store resource.
It checkpoints `AccountReady`, `MembershipReady`, `WorkspaceUserReady`,
`GrantReady`, `LeaseReady` and `Prepared`. If the controller stops after a
resource commit but before its checkpoint, deterministic identifiers let the
next controller verify that resource and continue without duplication. A
background reconciler runs immediately after startup and every 30 seconds.
Transient failures remain `RecoverableFailure` with a bounded error and
attempt count; authoritative mismatches become `Conflicted` for explicit
operator recovery. `GET /v1/onboarding/access-packages/operations` exposes
this evidence. The journal stores the OIDC subject digest, not the raw subject.

## Safety boundaries

- The identity provider still owns passwords, MFA and recovery.
- A human must verify the external identity before the access package is
  created.
- Open registration uses gateway-signed email and display-name claims. Browser
  form fields never become account identity by themselves.
- The default free trial is 24 hours, one concurrent inference, 20 requests per
  hour, 100 requests total, and the `text.qwen` allowlist. Deployment owners
  may reduce these bounds through reviewed environment configuration.
- LunaNexa never fabricates an effective MasterLease or a model approval.
- WebIDE access is enabled only when account, Developer membership, active
  grant, requested lease and approved model alias agree. An effective MasterLease
  is additionally required by commercial admission, not private-cloud admission.
- Model prompts travel through MoonGate. OIDC, contract and handoff control
  traffic remains on its separate authenticated control path.
- Ending a lease, closing the MasterLease, removing EnterpriseUser authority or
  suspending the account continues to fail closed.

## Journey acceptance

The common operator path should require no opaque identifier entry and no raw
JSON editing. It should fit in one form, one scope review and one later enable
action. The enterprise path should show one blocking action at a time and one
dominant launch action when ready. Partial orchestration must be safe to retry
without creating duplicate records. No partial resource may exist without a
durable operation naming its expected owner, last confirmed step and recovery
disposition.
