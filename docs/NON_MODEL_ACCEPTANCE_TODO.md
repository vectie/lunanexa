# Non-model acceptance closure checklist

Baseline: main `31b5be6`, reviewed 2026-09-16. This checklist retains the user's
whole objective. It is not a production-readiness percentage. Historical passes
below are scoped evidence, not assertions that every current deployment path
has been rerun. No actual model deployment or fabricated Spark inventory is
permitted in this campaign.

## Requirement-to-evidence map

| User requirement | Strongest inspected evidence | Remaining closure work |
| --- | --- | --- |
| Registration, organization, permissions | Signed TEST ONLY registration rejects unsigned assertions/nonces; organization creation/replay and suspension checks. Real public Keycloak registration form, password + MFA + controller-session/logout protocol passes via SSH transport, without admin-create. | Public-network/rendered self-registration, actual email/recovery and authenticated browser journey remain unproved. Protocol evidence does not substitute for browser acceptance. |
| Orders and payment callbacks | Isolated quote replay, signed wrong-amount rejection, exact settlement replay, refund/compensation and capacity release. Fake-host helper brought a replacement bare-machine order Active. | Usable browser terms/checkout flow; dedicated-endpoint payment-to-entitlement path with TEST ONLY provider; real machine-access delivery remains unverified. No real money required. |
| Administrator-granted private workspace | Two organizations enabled access without rental contract; foreign handoff denied; distinct Pods/PVCs. | Verify current portal clicks through this authorization and launches the existing gateway, rather than constructing handoffs only in a harness. |
| ComfyUI HTTP/WebSocket and tenant isolation | Authenticated HTTP/WS; foreign outputs and workflow/input reads denied; traversal tests; revocation closes WS and denies saved content. | Complete rendered private-cloud journey after current identity/UI rollout; retain explicit scope of tested network paths. |
| Save, rebuild, reopen, download | Real browser saved workflow and marked videos; Pod replacement retained exact workflow/input/output hashes; browser asset list and download recovered. | Revalidate from the user entry path once public identity navigation works; address recorded slow loading and native video-menu crash without claiming them fixed. |
| ComfyUI → local proxy → MoonGate → LunaNexa → test provider | Actual browser Run traversed the pipeline and played visibly marked TEST ONLY / NO GPU MODEL video, with one usage observation. | Keep runtime and gateway versions tied to evidence; do not substitute actual inference or count readiness alone as this end-to-end proof. |
| Queue, progress, cancellation, timeout, disconnect, restart | Client-response loss, process pause, real provider packet loss/recovery, cancellation retaining capacity, natural assignment expiry, controller/workspace authority HTTP+WS recovery. | Resolve or explicitly provide a product-supported safe disposition for historical r12 missing original exit evidence; do not forge termination or manually mark it complete. Consolidate any untested timeout/queue variants against current harness assertions. |
| Idempotency and metering | Exactly-once marked video observations; real PostgreSQL inference receipt replay and failed-write rollback; paid dedicated usage must not be billed twice. | Deploy reviewed pending backend fixes to the isolated controller and repeat affected live checks; local tests alone do not establish the deployed behavior. |
| Quota, expiry and cleanup | One-job quota remains occupied while cancellation cannot be confirmed; restored capacity after termination; explicit revocation/expiry denial; helper cleanup simulation. | Current production node-agent image readiness/ownership review, actual access cleanup where safe and authorized, and bounded test-resource cleanup inventory. Simulation is not physical sanitization. |

Primary evidence: `PUBLIC_HTTP_TRANSITION.md`,
`PRIVATE_WORKSPACE_VIDEO_ACCEPTANCE.md`, `WEBIDE_TENANT_ISOLATION_ACCEPTANCE.md`,
`PLATFORM_ACCEPTANCE_FOLLOWUP.md`, `LEASE_HELPER_ACCEPTANCE_20260915.md`,
`INFERENCE_BILLING_FAILURE_ACCEPTANCE.md`, `REGISTRY_WRITE_FAILURE_ACCEPTANCE.md`.
Detailed signed-test organization/order receipts are retained in the operator
workspace `/Users/kq/Workspace/aigc-spark-preflight`; they are not public-provider
or physical-hardware evidence.

## Ordered remaining work

- [ ] Isolate public 5005/5006 reachability without bypassing browser safety.
  Management LAN returns 200; workstation proxy returns 503; no-proxy traffic
  still routes through utun4 and receives empty replies. Root cause is not yet
  established. No global proxy/VPN mutation is authorized by this checklist.
- [ ] Verify real self-registration and user-facing identity lifecycle, then
  authenticated organization/resource-grant → launch → reopen/download clicks.
  Preserve MFA, roles, quotas and private/commercial admission distinctions.
  The real self-registration form protocol, MFA and logout replay checks passed
  through SSH transport on 2026-09-16; rendered/public-network steps remain open.
  Live realm inspection found registration enabled but verifyEmail=false,
  resetPasswordAllowed=false and no SMTP host/from/credentials configured.
  This differs from the repository's verified-email profile. SMTP provisioning
  and a designated test mailbox are required for real email/recovery acceptance;
  do not blindly enable mail-dependent gates or claim those paths tested.
- [x] Test logout bearer revocation against the controller directly, not merely
  the deleted gateway cookie. Real password/MFA login issued one session;
  controller-direct `/v1/auth/self` returned 200 before gateway logout and
  401 for the exact same bearer afterwards. See `PUBLIC_HTTP_TRANSITION.md`.
- [ ] Provide usable TEST ONLY checkout/terms fixtures and exercise the rendered
  commercial path; preserve the signed-callback amount/replay checks.
- [ ] Reconcile source/deployed versions: registry staged persistence and
  inference rollback changes are locally tested but not yet rolled into the
  isolated controller. Preserve backup/reader compatibility constraints.
- [ ] Review unresolved r12 cleanup evidence and production node-agent ownership
  before activating any older agent. Never let two agents manage the same node.
- [ ] Finish strict source gate through reviewed cleanup/compatibility fixes and
  regression coverage. Cancellation-safe cleanup and deprecated API fixes have
  removed the earlier strict-check failures. Native 858/858 and JS 153/153 tests
  now pass with warning 73 enabled and no exclusions. Local process kill/restart
  recovery also passed after fixing procfs failure blocking the node heartbeat.
  The remaining complete release-gate sequence is still being verified; see
  `NON_MODEL_SOURCE_GATE_20260916.md`. No blanket warning suppression counts as
  closure.
- [ ] Complete scoped browser responsive/accessibility/error-state checks and
  final temporary-resource inventory, preserving saved user work and evidence.
- [ ] Run one final integrated non-model campaign against the recorded versions,
  reconcile every row above with its output, and report remaining external
  dependencies without claiming completion.

## Explicit hardware/model deferral

ARM64/CUDA/SM121 ABI, model loading/real generation, quality, performance,
memory and two-Spark communication remain pending real hardware. x86 compute
may validate platform workflow but must continue reporting its true inventory.
Model downloads are separately monitored every 30 minutes; partial files and
cached recipes are not runtime qualification, and their monitoring must not
restart healthy downloads or interrupt this platform campaign.
