# UI production validation: 50-scenario campaign

Date: 2026-08-20  
Target: LunaNexa management console, enterprise portal, developer workbench,
cluster installer, contract/MoonLeaf workflow, and documentation site

## Verdict

This campaign is **not** a production certification. It records 50 browser
journeys with deliberately different evidence classes:

- `UI-LOCAL-PASS` (10): the browser exercised a real local boundary, such as
  the installer companion, locale persistence, or fail-closed client checks.
- `UI-DEMO-PASS` (32): the browser exercised Rabbita state, rendering, guards,
  and role separation against an explicitly labelled read-only demo snapshot.
  No controller mutation, hardware effect, credential issuance, payment, or
  legal effect is implied.
- `UI-BLOCKED-EXTERNAL` (7): the exact UI journey is defined, but a required
  physical or external authority was unavailable. These are failures to prove,
  not passes.
- `UI-BLOCKED-HARNESS` (1): the requested responsive viewport could not be
  applied reliably to the already controlled tabs. Automated CSS tests exist,
  but the browser observation was not promoted to a pass.

Therefore the honest result is **42 UI observations passed at their stated
scope, 8 production observations remain blocked, and 0 real-cluster claims
were manufactured**.

## Evidence rules

1. Every consequential action must show scope, effect, and an explicit
   confirmation before mutation.
2. Demo mode must say that it is a demo and must never fabricate a controller
   receipt or external credential.
3. A disabled control proves only that the current view blocks the action. The
   API and durable store remain the authority.
4. A local Colima preview proves only the local tooling and installer boundary;
   it does not prove NVIDIA, ARM64, physical networking, or sanitization.
5. External blockers are retained in this ledger until the exact UI journey is
   repeated against production-like dependencies and evidence is archived.

## The 50 scenarios

### 1. Demo provenance cannot be mistaken for live authority

- **Atomic UI steps:** Open `/console/?demo=1`; inspect the strip above the
  navigation; read the fleet summary; attempt no mutation.
- **Expected:** `DEMO`, `read-only demo snapshot`, and controller changes
  disabled are visible before the 4/4 and 9-model figures.
- **Observed:** The provenance strip was visible and unambiguous.
- **Result:** `UI-DEMO-PASS`.

### 2. Every operator route renders without losing the shell

- **Atomic UI steps:** Click Overview, Alerts, Users, Leases, Cost centers,
  Agreements, Offline commerce, Contract documents, Qualified services, Nodes,
  Models, Catalog, Deployments, Requests, Benchmarks, Policies, and Audit.
- **Expected:** The route heading changes; the language control, demo provenance,
  navigation, and refresh control remain; no unhandled exception appears.
- **Observed:** All 17 routes rendered. Failure-state records on Leases,
  Requests, Benchmarks, and Offline commerce remained typed domain data rather
  than page crashes.
- **Result:** `UI-DEMO-PASS`.

### 3. Every customer route renders within one tenant shell

- **Atomic UI steps:** Click Overview, Agreements, Lease requests, My machine,
  Orders and documents, Contract forms, Notifications, Usage and costs, and
  Model catalog.
- **Expected:** The organization scope stays `org-northstar`; the customer
  boundary remains visible; no node identifier or internal credential reference
  appears.
- **Observed:** All nine routes rendered under the same tenant scope.
- **Result:** `UI-DEMO-PASS`.

### 4. Language preference follows the user across surfaces

- **Atomic UI steps:** Select English in the console; reload the enterprise
  portal; inspect root language and title; switch back to Simplified Chinese;
  reload again.
- **Expected:** Console and portal use the same preference; root `lang` and
  document title change together; opaque identifiers stay unchanged.
- **Observed:** `en` propagated with English titles; `zh-CN` propagated with
  Chinese titles.
- **Result:** `UI-LOCAL-PASS`.

### 5. Narrow-screen layout at 390 px

- **Atomic UI steps:** Set a 390×844 browser viewport; reload console, portal,
  workbench, and installer; compare `scrollWidth` with `innerWidth`; inspect
  contract preview stacking and action wrapping.
- **Expected:** No document-level horizontal overflow and no inaccessible action.
- **Observed:** The installer was observed at 390 px without overflow. The
  browser harness kept the other controlled tabs at 1280 px despite the
  override, so those three observations were not accepted. Repository
  responsive tests are supporting evidence only.
- **Result:** `UI-BLOCKED-HARNESS`.

### 6. Demo readiness is visibly scoped to the demo

- **Atomic UI steps:** Open console Overview; read the production-gate card and
  the page-level provenance strip.
- **Expected:** A green demo card cannot obscure the fact that the data is a
  read-only snapshot.
- **Observed:** The card showed all demo checks green while the persistent demo
  strip remained visible.
- **Bypass note:** Demo readiness is a fixture, not `/v1/readiness` evidence.
- **Result:** `UI-DEMO-PASS`.

### 7. Four-node inventory and nine-model catalog are internally consistent

- **Atomic UI steps:** Read Overview; open Nodes; count node cards; open Models;
  count model artifacts.
- **Expected:** Overview says 4/4 and 9; Nodes shows four distinct DGX Spark
  entries; Models shows nine artifacts.
- **Observed:** Counts matched across the three views.
- **Result:** `UI-DEMO-PASS`.

### 8. A leased node cannot be cordoned casually in the demo

- **Atomic UI steps:** Open Nodes; expand each node's actions; inspect Cordon.
- **Expected:** Demo controller mutations are disabled; a leased node is not
  presented as an unguarded maintenance target.
- **Observed:** Cordon controls were disabled on the read-only snapshot.
- **Result:** `UI-DEMO-PASS`.

### 9. A leased node cannot be drained casually in the demo

- **Atomic UI steps:** Open Nodes; inspect Drain on all four nodes.
- **Expected:** Demo mutation is disabled; production must require a guarded
  drain and placement reconciliation.
- **Observed:** Drain controls were disabled.
- **Result:** `UI-DEMO-PASS`.

### 10. Suspending a user requires explicit scope confirmation

- **Atomic UI steps:** Open Users; click Suspend for Alice; inspect the dialog;
  click Cancel.
- **Expected:** The dialog names user ID, display name, email, access effect,
  and confirmation receipt.
- **Observed:** All were present; Cancel returned without mutation.
- **Result:** `UI-DEMO-PASS`.

### 11. Revoking a user is identified as terminal

- **Atomic UI steps:** Open Users; click Revoke; inspect the terminal-action
  warning and receipt; cancel.
- **Expected:** The UI distinguishes revoke from suspend and does not execute on
  the first click.
- **Observed:** Terminal wording and exact user scope were present.
- **Result:** `UI-DEMO-PASS`.

### 12. Ending a workspace lease is distinct from machine access

- **Atomic UI steps:** Open Leases; click End lease for
  `workspace-lease-alice`; inspect; cancel.
- **Expected:** The dialog says inference capacity/workspace access will be
  revoked and does not describe host sanitization.
- **Observed:** The control-plane capacity boundary was explicit.
- **Result:** `UI-DEMO-PASS`.

### 13. Terminating an exclusive lease binds lease, machine, user, and generation

- **Atomic UI steps:** Open Leases; click Terminate and clean; inspect scope and
  receipt; cancel.
- **Expected:** The dialog binds lease, DGX, Unix user, and generation and states
  revoke → stop → sanitize → verify → release.
- **Observed:** Scope included `lease-northstar-alice`, `dgx-spark-01`, `alice`,
  and generation 4; failure-to-clean was described as quarantine.
- **Result:** `UI-DEMO-PASS`.

### 14. Only a requested compute lease offers activation

- **Atomic UI steps:** Open Leases; compare the Active Alice lease with the
  Requested Mina lease.
- **Expected:** Active offers End; Requested offers Activate; neither offers an
  illegal transition.
- **Observed:** Actions matched their states.
- **Result:** `UI-DEMO-PASS`.

### 15. Script-shaped deployment input cannot create markup or enable submit

- **Atomic UI steps:** Open Catalog; type `<script>alert(1)</script>` as the
  service name; inspect DOM and Deploy button.
- **Expected:** No script element is created and deployment remains disabled.
- **Observed:** Zero script elements; Deploy remained disabled.
- **Result:** `UI-DEMO-PASS`.

### 16. Service-name length is enforced at both sides of the boundary

- **Atomic UI steps:** Enter 128 allowed characters; inspect Deploy; enter 129;
  inspect again.
- **Expected:** 128 is accepted by the form and 129 is rejected.
- **Observed:** The button enabled at 128 and disabled at 129.
- **Result:** `UI-DEMO-PASS`.

### 17. One-click deployment demo cannot invent an operation

- **Atomic UI steps:** Enter `readiness-service-50`; click Deploy model service;
  read the result and service-operations table.
- **Expected:** The result says the demo preflight passed but no controller
  operation was created.
- **Observed:** Exact disclaimer shown; no new authoritative receipt was claimed.
- **Result:** `UI-DEMO-PASS`.

### 18. Model-service rollback has a guarded scope

- **Atomic UI steps:** Open Catalog; click Roll back on `text-service`; inspect
  dialog; cancel.
- **Expected:** Only signed assignments owned by that service are described as
  removable; exact service scope and receipt are shown.
- **Observed:** Guard and receipt were present.
- **Result:** `UI-DEMO-PASS`.

### 19. Model-service deletion preserves audit history

- **Atomic UI steps:** Click Delete on `text-service`; inspect; cancel.
- **Expected:** The dialog distinguishes stopping service execution from
  deleting immutable operation/audit evidence.
- **Observed:** It explicitly retained immutable evidence.
- **Result:** `UI-DEMO-PASS`.

### 20. Stopping a deployment requires assignment-level confirmation

- **Atomic UI steps:** Open Deployments; click Stop for the ready assignment;
  inspect scope and receipt; cancel.
- **Expected:** The selected assignment, not an unrelated service, is named.
- **Observed:** `assignment-qwen-eval-r1` was bound into the receipt.
- **Result:** `UI-DEMO-PASS`.

### 21. Model lifecycle evidence stays visible

- **Atomic UI steps:** Open Models; compare lifecycle, license, evaluation,
  compatibility, alias, and rollback action for all nine rows.
- **Expected:** Approval is not inferred from alias text alone; evidence columns
  remain visible.
- **Observed:** The table exposed the expected evidence dimensions.
- **Result:** `UI-DEMO-PASS`.

### 22. Request monitoring does not expose prompts or outputs

- **Atomic UI steps:** Open Requests; inspect summary and request-detail rows;
  search visible text for prompt/output bodies and secret-shaped values.
- **Expected:** Only time, operation, selector, outcome, and bounded receipt are
  visible.
- **Observed:** No raw prompt or output was displayed.
- **Result:** `UI-DEMO-PASS`.

### 23. Operator audit remains evidence-oriented

- **Atomic UI steps:** Open Audit; inspect actor, decision, evidence, outcome,
  receipt; scan visible text for private keys, bearer values, and host paths.
- **Expected:** No secret or managed-node path appears.
- **Observed:** Only the bounded demo audit record was visible.
- **Result:** `UI-DEMO-PASS`.

### 24. Installer cannot preview an incomplete inventory

- **Atomic UI steps:** Open Installer with an empty token and incomplete remote
  hosts; inspect Preview and Apply.
- **Expected:** Both are disabled before network activity.
- **Observed:** Both were disabled.
- **Result:** `UI-LOCAL-PASS`.

### 25. Colima mode removes production-only requirements

- **Atomic UI steps:** Enter a valid local companion token; select Local Colima
  simulation; inspect form and stage list.
- **Expected:** SSH, NVIDIA, secrets, production manifests, and ingress are
  explicitly skipped; only isolated kubeconfig/local tooling is required.
- **Observed:** The UI reduced the run from nine remote stages to five local
  stages and stated every skipped boundary.
- **Result:** `UI-LOCAL-PASS`.

### 26. Installer preview reaches the real loopback companion

- **Atomic UI steps:** Start the native companion on `127.0.0.1:4198`; enter the
  64-character session token; choose Colima; click Preview and validate; wait
  for terminal completion.
- **Expected:** No resource is changed; tooling and topology intentions are
  checked; terminal ends in success.
- **Observed:** The companion reported stopped dedicated Colima profile,
  installed Colima/Docker/kind/kubectl, topology to be created during apply,
  no resources changed, and successful exit.
- **Result:** `UI-LOCAL-PASS`.

### 27. Wrong installer token cannot retain a stale success transcript

- **Atomic UI steps:** After a successful preview, replace the token with a
  different valid-length token; preview again; inspect banner and terminal.
- **Expected:** Request is rejected before execution; previous success is gone.
- **Observed before fix:** Error banner appeared, but old `[complete]` lines
  remained in the terminal.
- **Fix and retest:** Rejected runs now replace the transcript with
  `[blocked] companion rejected the request before execution`; no stale success
  remains.
- **Result:** `UI-LOCAL-PASS` after fix.

### 28. Installer apply requires preview plus the exact phrase

- **Atomic UI steps:** Select Local Colima simulation; complete a successful
  preview; leave confirmation empty; enter `DEPLOY 4 NODES`; enter
  `RECONCILE SIMULATION`; inspect Apply each time.
- **Expected:** Disabled for empty/wrong values and enabled only for the exact
  phrase after a current successful preview.
- **Observed:** Guard behaved exactly as expected.
- **Bypass note:** Apply was not clicked because it changes the local Colima
  system and requires a separate action-time safety confirmation.
- **Result:** `UI-LOCAL-PASS` for the guard, not for deployment.

### 29. Remote installer teaches strict SSH trust

- **Atomic UI steps:** Select Remote DGX cluster; inspect key path, pinned
  `known_hosts`, management host, and four compute mappings.
- **Expected:** No password field, no arbitrary shell, no TOFU; text states
  `StrictHostKeyChecking=yes` and `BatchMode=yes`.
- **Observed:** All trust controls and the nine reviewed stages were visible.
- **Result:** `UI-LOCAL-PASS` for form behavior.

### 30. Real remote enrollment with host-key mismatch and partial fleet

- **Atomic UI steps:** Use deployment-owned hosts; preview once with a wrong
  pinned key, then correct it; apply; observe zero/partial/four fresh nodes in
  the terminal and console.
- **Expected:** Wrong key, missing node, extra node, duplicate node, inactive
  node, stale/future heartbeat, and malformed inventory all fail without a
  completion marker.
- **Observed:** No physical five-host environment was available. Shell-level
  deterministic fixtures cover these cases but are not UI evidence.
- **Result:** `UI-BLOCKED-EXTERNAL`.

### 31. Workbench cannot connect without a scoped token

- **Atomic UI steps:** Open Workbench with no token; inspect Connect/refresh.
- **Expected:** Disabled; trust-boundary explanation remains visible.
- **Observed:** Disabled and explanatory copy shown.
- **Result:** `UI-LOCAL-PASS`.

### 32. Workbench rejects insecure remote origins before sending a token

- **Atomic UI steps:** Enter a valid-length synthetic token; set controller to
  `http://example.com`; click Connect.
- **Expected:** Client rejects non-loopback HTTP and stays unready.
- **Observed:** UI required HTTPS or loopback HTTP and made no request.
- **Result:** `UI-LOCAL-PASS`.

### 33. Workbench failure does not disclose the token

- **Atomic UI steps:** Set loopback controller and synthetic subject; connect to
  the static server, which cannot satisfy `/v1/workspace/self`; inspect page and
  browser error log.
- **Expected:** Bounded recovery text, stale lease invalidated, no token echoed.
- **Observed:** Bounded error shown; token absent from UI and logs.
- **Result:** `UI-LOCAL-PASS`.

### 34. Authorized inference, streaming, cancellation, and ownership

- **Atomic UI steps:** Sign in through production identity; connect; select a
  model; send; observe streaming; cancel; query receipt; retry another tenant's
  workload ID.
- **Expected:** Owned request works; cancel is generation/owner bound; cross-
  tenant status/cancel returns not found; prompts do not enter logs.
- **Observed:** No production identity, active lease, or real model runtime was
  available. Native/API tests are supporting evidence only.
- **Result:** `UI-BLOCKED-EXTERNAL`.

### 35. Rate-limit recovery preserves a valid lease

- **Atomic UI steps:** Connect with a low hourly quota; exhaust it; send again;
  observe 429; wait for window/reconcile; retry.
- **Expected:** 429 does not clear the valid lease; Send becomes usable after
  authoritative recovery.
- **Observed:** Component tests cover the state rule, but no live UI quota
  authority was available.
- **Result:** `UI-BLOCKED-EXTERNAL`.

### 36. Lease expiry closes the workbench while the page stays open

- **Atomic UI steps:** Connect with a lease expiring in under two minutes; keep
  the page open; observe countdown; cross expiry; attempt Send; refresh.
- **Expected:** One generation-fenced clock disables Send at expiry and the
  server rejects any race.
- **Observed:** Automated clock tests exist; live UI expiry was not exercised
  against a real authority.
- **Result:** `UI-BLOCKED-EXTERNAL`.

### 37. Operator and customer cannot fill each other's contract fields

- **Atomic UI steps:** Open the master contract in operator console and customer
  portal; list editable fields on each side.
- **Expected:** Operator sees contract/lessor/commercial fields; customer sees
  lessee identity fields; both see the same document preview.
- **Observed:** Operator form showed 12 operator-owned fields; customer form
  showed five customer-owned fields; cross-side fields were not editable.
- **Result:** `UI-DEMO-PASS`.

### 38. All seven source forms render the expected 18 pages

- **Atomic UI steps:** In operator Contract documents, click all seven tabs;
  after each click count physical preview pages and scan for the failure banner.
- **Expected:** Master 11, Reservation 2, and five one-page forms; Chinese text
  present; no stale tab preview.
- **Observed:** Counts were `11+2+1+1+1+1+1=18`; every tab contained Chinese;
  no MoonLeaf failure appeared. Customer-owned tabs rendered the same source
  pages for the three customer-active forms.
- **Result:** `UI-DEMO-PASS`.

### 39. MoonLeaf preview updates without a render button

- **Atomic UI steps:** Type `星河智能科技有限公司` into the customer company
  field; wait for debounce; inspect preview; do not click Save.
- **Expected:** The preview updates automatically and no manual Render current
  draft button exists.
- **Observed:** Updated text appeared after the generation-fenced debounce.
- **Result:** `UI-DEMO-PASS`.

### 40. Four-eyes approval shows what the second person is approving

- **Atomic UI steps:** Open the pending approval; click Review and approve;
  inspect action, initiator, expected revision, date, amount, values digest,
  evidence digest, and reason; return without executing.
- **Expected:** No blind approval button.
- **Observed:** Every evidence field was visible and human-formatted.
- **Result:** `UI-DEMO-PASS`.

### 41. Rejection requires a durable reason

- **Atomic UI steps:** Click Reject; inspect Confirm; enter no reason; enter a
  reason; inspect again; return.
- **Expected:** Confirm disabled when empty and enabled only with a reason.
- **Observed:** Guard behaved as expected.
- **Result:** `UI-DEMO-PASS`.

### 42. Demo approval cannot mutate authoritative contract state

- **Atomic UI steps:** Confirm a demo approval; inspect success notice and task
  inbox afterward.
- **Expected:** It says previewed/not sent and leaves approval pending.
- **Observed:** Exact read-only notice shown; pending item remained.
- **Result:** `UI-DEMO-PASS`.

### 43. Self-approval and stale-revision recovery with two real operators

- **Atomic UI steps:** Operator A creates a high-value action; A attempts to
  approve; B loads it; mutate packet revision in another session; B approves;
  refresh and resolve the stale decision; repeat reject/reopen.
- **Expected:** A is denied; B sees immutable evidence; stale revision cannot
  apply; UI refreshes without duplicate effect; crash recovery resumes an
  approved-but-not-applied action.
- **Observed:** Backend and shell tests cover these rules, but no two real
  operator identities were available in the browser.
- **Result:** `UI-BLOCKED-EXTERNAL`.

### 44. Customer sees pending approval, obligation, and expiry

- **Atomic UI steps:** Select the effective packet in customer Contract forms;
  inspect pending second-person review, Nudge, payment milestone, amount, expiry,
  countdown, disabled fields, and timeline.
- **Expected:** Customer is not told merely to wait with no context.
- **Observed:** All items were visible with human dates and CNY amount.
- **Result:** `UI-DEMO-PASS`.

### 45. Renewal creates a new draft and preserves the effective predecessor

- **Atomic UI steps:** Select effective packet; click Request renewal; inspect
  confirmation; confirm; inspect packet selector and copied values.
- **Expected:** New InformationDraft selected, predecessor remains read-only,
  and initial customer data is carried forward without mutating history.
- **Observed:** A `contract-renewal-*` draft was created and selected; the
  effective packet remained available.
- **Result:** `UI-DEMO-PASS`.

### 46. Credential redemption cannot spin forever or display a secret

- **Atomic UI steps:** Open My machine; click Redeem SSH access; inspect result.
- **Expected:** Demo explicitly issues no credential, returns safe synthetic
  host/port/fingerprint/command, contains no password/private key, and clears
  loading.
- **Observed before fix:** Demo set loading forever and showed no result.
- **Fix and retest:** It now displays `.invalid` demo metadata, a non-secret
  disclaimer, and no raw secret.
- **Result:** `UI-DEMO-PASS` after fix.

### 47. Early termination requires the exact lease phrase

- **Atomic UI steps:** Click End access early; inspect interruption warning;
  leave phrase empty; enter wrong lease; enter `TERMINATE
  exclusive-lease-demo`; confirm.
- **Expected:** Disabled until exact; after confirm, credential details vanish,
  handoff closes, generation advances, and access enters verified cleanup.
- **Observed:** Empty/wrong disabled; exact enabled; state became Expiring,
  handoff Closed, cleanup in progress, with explicit demo disclaimer.
- **Result:** `UI-DEMO-PASS`.

### 48. Physical revoke, sanitize, quarantine, and managed-fleet reclaim

- **Atomic UI steps:** Terminate a real lease; watch customer and operator UIs;
  verify issuer revocation, session/process stop, storage cleanup, signed helper
  receipt, quarantine on failure, and only then return to managed placement.
- **Expected:** No node becomes schedulable before current-generation cleanup
  evidence; any failure remains quarantined and alerts operators.
- **Observed:** The UI controls and demo transition were exercised, but no
  physical host helper, SSH CA, tenant process, or DGX image was available.
- **Result:** `UI-BLOCKED-EXTERNAL`.

### 49. Notification preferences and read state are independent

- **Atomic UI steps:** Open Notifications; disable machine-lifecycle email;
  verify in-app remains; mark the unread item read; inspect receipt and date.
- **Expected:** Preference changes do not delete records; read state changes
  generation; receipt persists; date is human-readable.
- **Observed:** Email toggled off, in-app remained, unread count cleared, receipt
  remained. The raw epoch timestamp discovered during the run was changed to a
  UTC date and covered by a regression test.
- **Result:** `UI-DEMO-PASS` after fix.

### 50. Offline commerce closes the digital-to-offline loop

- **Atomic UI steps:** Customer creates order, downloads exact PDF, uploads
  signed contract/payment/invoice, waits for scan; operator quotes, generates,
  reviews exact digests, reconciles payment/invoice, activates entitlement;
  then exercise cancellation, expiry, reversal, failed reversal, retry fencing,
  and restart at each state.
- **Expected:** One-time byte-bound transfer sessions, exact artifact evidence,
  no activation before gates, no unbounded reversal loop, and complete customer/
  operator notifications.
- **Observed:** Demo pages render the states; store/API/worker tests exist. Real
  object storage, scanner, renderer with approved CJK fonts, legal templates,
  finance authority, dispatcher, and entitlement authority were unavailable.
- **Result:** `UI-BLOCKED-EXTERNAL`.

## Bugs found and fixed during the browser campaign

1. **Stale installer success after rejected rerun.** A wrong-token run displayed
   an error banner but retained the previous successful transcript. Rejected
   runs now replace terminal output with a bounded blocked record.
2. **Demo credential redemption stuck forever.** The demo set loading without
   producing a result. It now renders clearly synthetic `.invalid` metadata,
   explicitly says no credential was issued, and never includes a raw secret.
3. **Reserved Unix username accepted by the lease UI.** The backend rejected
   `root`, but the form/demo accepted it. UI and backend now share the public
   username rule; the field is `aria-invalid` and submit is disabled.
4. **Raw epoch in customer notifications.** The portal now uses the canonical
   UTC formatter and retains the opaque receipt unchanged.

## What good production practice looks like

AWS is a useful comparison for operating discipline, not a realistic immediate
feature-parity target. The [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/definitions.html)
organizes practice around operational excellence, security, reliability,
performance efficiency, cost optimization, and sustainability. LunaNexa needs
an acceptance owner and measurable gates in every pillar, not one large green
"release" light.

The following are the main gaps between today's private fixed-fleet LunaNexa
and a broadly usable GPU cloud:

| Capability | LunaNexa today | AWS-like production bar |
| --- | --- | --- |
| Control plane | One management plane with restart reconciliation | Multi-instance HA, quorum/fencing, zero-downtime upgrade, multi-failure and region recovery |
| Identity | Scoped tokens, mTLS-derived subjects, tenant membership | Account/organization hierarchy, SSO/MFA, delegated administration, policy simulation and organization guardrails comparable to [SCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html) |
| Compute lifecycle | Managed model deployments plus separate exclusive leases | A single comprehensible instance lifecycle, termination protection, stop/start/rebuild semantics and attached-resource policy comparable to [EC2 instance states](https://docs.aws.amazon.com/us_en/AWSEC2/latest/UserGuide/ec2-instance-lifecycle.html) |
| Capacity | Four fixed DGX Spark nodes, one-machine assignments | Quota inventory and increase workflow, reservations, waiting lists, fragmentation policy, overbooking rules, capacity health and future commitments comparable to [Capacity Reservations](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html) |
| Network | Deployment-specific ingress and NetworkPolicy | Tenant VPC/subnet/security-group equivalents, private endpoints, egress governance, IP/DNS/LB lifecycle, DDoS and flow logs |
| Images | Approved runtime/model artifacts | Customer and platform image catalogs, patch/vulnerability lifecycle, signing, provenance, rollback, deprecation and emergency revocation |
| Storage | PostgreSQL/control snapshots and model cache | Tenant block/object/file services, encryption keys, snapshots, backup policy, restore, secure deletion, quotas and lifecycle costs |
| Metering and billing | Provisional ledger, cost centers, hybrid offline documents | Immutable usage line items, pricing versions, tax/invoice/refund/credit/dispute paths, reconciliation and export comparable to [AWS Cost and Usage Reports](https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html) |
| Audit | Typed bounded audit and observability events | Organization-wide immutable activity history, long retention, query/export, anomaly detection, independent log authority and coverage comparable to [CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html) |
| Reliability | Simulated restart/failure tests | Published SLOs, error budgets, HA database, backup restore RPO/RTO, chaos drills, capacity evacuation and dependency failure exercises |
| Operations | Runbooks, notifications, readiness gates | 24×7 ownership, paging escalation, incident commander process, status page, maintenance windows, customer communication, support tiers and postmortems |
| Security | Strong typed boundaries and secret separation | Independent penetration test, host hardening, vulnerability/patch SLA, KMS/HSM, secret manager, supply-chain controls, abuse/fraud response and compliance evidence |
| Customer experience | Console, enterprise portal, workbench, VS Code | Stable versioned API/SDK/CLI, IAM self-service, quotas, support cases, usage exports, notifications, resource tagging/search and bulk operations |
| Geographic scale | One private site | Failure domains, multi-site placement, data residency, replication policy, regional capacity and disaster-recovery routing |

AWS's Service Quotas documentation treats quotas as explicit account/resource
limits with utilization and increase workflows. LunaNexa has per-lease request
limits but does not yet have a complete tenant-visible quota inventory and
capacity request process. AWS CloudTrail treats console, CLI, SDK, and API
actions as one auditable activity stream. LunaNexa should likewise make every
UI action resolve to the same durable API event rather than allowing demo or
shell-only side paths to become implicit authorities.

## Recommended order of work

### P0 — make the four-node private cloud genuinely operable

1. Complete a physical four-DGX acceptance run, including real ARM64/NVIDIA
   runtime images, model licenses, thermals, long streams, saturation and drain.
2. Deploy production identity/mTLS, separate authorities, SSH CA/credential
   issuer, root helper, network enforcement, and a destructive sanitization
   drill on the exact host image.
3. Deploy HA PostgreSQL or a managed equivalent, encrypted backups, restore
   drills, fencing and a documented RPO/RTO.
4. Integrate real object storage, scanner, MoonLeaf renderer/font baseline,
   finance/legal evidence, entitlement authority and notification delivery.
5. Establish named 24×7 operators, incident response, paging, customer status
   communication, maintenance windows and a release-acceptance board.

### P1 — make it a usable private GPU cloud product

1. Add tenant-visible quotas/capacity requests, reservations and admission
   forecasts.
2. Add real billing line items, pricing versions, invoices, refunds, credits,
   disputes and an immutable usage export.
3. Add customer network/storage/image lifecycle services or explicitly narrow
   the product contract to dedicated-host access plus managed inference.
4. Provide stable public SDK/CLI contracts, bulk operations, tags, search,
   support cases and audit export.

### P2 — only then pursue AWS-like breadth

Multi-site regions, autoscaling, spot/preemptible capacity, marketplace,
organization federation, advanced FinOps, managed training, and broad hardware
families should follow only after P0/P1 evidence is repeatable. With four fixed
machines, the most credible near-term product is a **well-operated private GPU
cloud**, not an AWS-equivalent public cloud.

## Next acceptance run

Repeat all 50 scenarios against a production-like environment. Replace every
`UI-DEMO-PASS` with an authoritative controller receipt or leave it as demo.
Replace every blocker only with retained evidence from the actual dependency.
Archive browser screenshots, operator identity, timestamps, request/audit
receipts, runtime/image/model digests, cluster revision, and external evidence
references in one signed acceptance bundle.
