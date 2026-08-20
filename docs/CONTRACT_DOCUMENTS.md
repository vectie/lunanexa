# Contract document system

LunaNexa contract documents are a dedicated long-horizon subsystem within the
hybrid digital-to-offline commercial workflow. It collects supplied data,
retains immutable template versions, generates fidelity-checked DOCX/PDF pairs,
and preserves every later execution form as a separate revision and artifact.

## Authority boundary

The retained DOCX is the legal wording and formatting authority. LunaNexa owns
only typed collection, validation, lifecycle state, digest confirmation,
generation requests, evidence, and audit. It does not author clauses, provide
legal advice, infer a missing value, or calculate language that the source
expects a person to supply.

```mermaid
flowchart LR
  T["Immutable source DOCX + slot manifest"] --> C["Authenticated data collection"]
  C --> V["Required-field and source-choice validation"]
  V --> H["Human digest confirmation"]
  H --> J["Durable generation request"]
  J --> D["DOCX in-place OOXML patch"]
  D --> R["MoonLeaf approved-font PDF renderer"]
  R --> Q["18-page visual + structural fidelity gate"]
  Q --> A["Immutable DOCX/PDF artifacts and evidence"]
```

## Durable lifecycle

`contractdoc.ContractPacket` is revision- and digest-fenced. The full state
machine has nine states:

`InformationDraft -> ReadyForConfirmation -> InformationConfirmed -> GenerationRequested -> Generated -> Effective -> Closed`

`GenerationFailed` is a retryable branch off `GenerationRequested`, and
`Superseded` is a terminal branch reachable from every pre-`Effective` state.

| From | Action | To | Actor | Preconditions |
| --- | --- | --- | --- | --- |
| — | create packet | `InformationDraft` | CustomerMessenger | initial-stage forms start freely; effective-stage forms require a `preceding_packet_ref` naming a same-tenant packet in `Effective` state |
| `InformationDraft`, `ReadyForConfirmation`, or `InformationConfirmed` | save information | `InformationDraft`, or `ReadyForConfirmation` once all required fields are complete | CustomerMessenger or ManagerOperator, own fields only | editable states only; any change clears the prior confirmation and values digest |
| `ReadyForConfirmation` | confirm information | `InformationConfirmed` | CustomerMessenger | no missing required fields; records the confirmed values digest |
| `InformationConfirmed` | request generation | `GenerationRequested` | CustomerMessenger | the expected values digest must equal the confirmed digest |
| `GenerationFailed` | retry generation | `GenerationRequested` | CustomerMessenger | same digest fencing; the confirmed values are unchanged |
| `GenerationRequested` | complete generation | `Generated` | renderer worker | a DOCX/PDF pair with valid digests, one shared render-evidence digest, matching page counts, and the declared source page count for known templates |
| `GenerationRequested` | fail generation | `GenerationFailed` | renderer worker | a non-empty failure reason |
| `Generated` | register execution | `Effective` | ManagerOperator | a valid evidence digest and a `YYYY-MM-DD` signing date; `registered_by` is fixed server-side to the authenticated operator identity |
| `Effective` | close packet | `Closed` | ManagerOperator | closure kind `Expired`, `EarlyTermination`, or `Settled`; early termination additionally requires a settlement (see cross-packet rules below) |
| any pre-`Effective` state | supersede packet | `Superseded` | ManagerOperator | a successor reference and reason; an `Effective` packet is superseded only by its linked successor when that successor registers execution; `Closed` and `Superseded` packets are terminal |

Generated artifacts are never mutated. A later reservation, access, incident,
settlement, or early termination task creates a new packet bound to the same
source template digest, the appropriate form subset, and the effective
predecessor packet.

## Lifecycle management rules (合同全生命周期管理)

Each state represents one period of the underlying paper contract:

| State | Contract period | What it means |
| --- | --- | --- |
| `InformationDraft` | drafting | either side is filling its owned fields; nothing is generated from blank or invented values |
| `ReadyForConfirmation` | review/confirmation | all required online fields are complete; the customer reviews the preview against the source wording |
| `InformationConfirmed` | attested | the customer has attested the values; the confirmed digest is pinned and the packet awaits a generation request |
| `GenerationRequested` | rendering | the packet is frozen while the renderer worker produces the DOCX/PDF pair under the fidelity gate |
| `Generated` | awaiting offline signature | the DOCX/PDF pair is retained and read-only; signing and stamping happen offline |
| `GenerationFailed` | rendering failed | the confirmed values are unchanged; the customer may retry generation |
| `Effective` | in force | the operator registered the offline signed-and-stamped evidence; the packet is read-only and may anchor follow-up forms |
| `Closed` | closed | terminal; the closure records its kind (`Expired`, `EarlyTermination`, or `Settled`), reason, and closing identity (operator id or `scheduler` for the automatic expiry closure) |
| `Superseded` | replaced before effect | terminal; the supersession records the successor packet, reason, and operator identity |

The action bar in both browser surfaces renders exactly the capability list
the lifecycle allows, so the role-by-state matrix is enforced by construction:

| Capability | CustomerMessenger | ManagerOperator | State precondition |
| --- | --- | --- | --- |
| `SaveInformation` | yes | yes | `InformationDraft`, `ReadyForConfirmation`, or `InformationConfirmed` |
| `ConfirmInformation` | yes | no | `ReadyForConfirmation` |
| `RequestGeneration` | yes | no | `InformationConfirmed` with a confirmed values digest |
| `RetryGeneration` | yes | no | `GenerationFailed` with a confirmed values digest |
| `RegisterExecution` | no | yes | `Generated` |
| `ClosePacket` | no | yes | `Effective` |
| `SupersedePacket` | no | yes | any state except `Effective`, `Closed`, or `Superseded` |
| `RequestRenewal` | yes | yes | `Effective` |

The responsibility split mirrors the offline contract process. The customer
owns information confirmation and generation requests — their attestation of
the supplied values. The operator owns execution registration, closure, and
supersession — the facts of the signed paper contract. The renderer worker
owns generation results and failures. The step bar condenses the machine into
five customer-visible steps (fill information, review and confirm, generate
documents, signed and effective, closed and archived) and shows a terminal
badge for superseded packets; per-state guidance text explains what each state
means and what happens next.

Two cross-packet rules bind packets together:

- Effective-stage forms (`AccessConfirmation`, `ViolationNotice`,
  `DamageAssessment`, `SettlementConfirmation`, `EarlyTerminationApplication`)
  may only be created with a `preceding_packet_ref` naming a same-tenant
  packet already in `Effective` state. Initial-stage forms (`MasterLease`,
  `ReservationApplication`) open the relationship and need no predecessor.
- An `EarlyTermination` closure requires a same-tenant
  `SettlementConfirmation` packet in `Effective` or `Closed` state; a merely
  generated settlement is unsigned and the store rejects the close. `Expired`
  and `Settled` closures have no settlement precondition. When the
  organization has commercial ledger entries, the close additionally
  reconciles the settlement's `settlement.amount_due` against the ledger's
  provisional total for the organization; a mismatch is rejected with
  `SettlementMismatch` (HTTP 409 `ContractSettlementMismatch`). When the
  organization has no ledger entries the comparison is skipped and an audit
  note records that the ledger was not in use.
- An `Effective` packet can be renewed (`POST …/self/{id}:renew` for the
  owning customer, `POST …/operator/packets/{id}:renew` for the operator).
  The renewal is a fresh `InformationDraft` packet that links back through
  `preceding_packet_ref`, carries only the initial-stage forms, and copies
  the source values as a drafting starting point — except offline-completed
  fields (signatures and seals are redone offline) and platform-derived
  fields (the server re-derives them). A source that is not `Effective`, or
  that has no initial-stage forms, is rejected with `ContractNotRenewable`
  (HTTP 409 `ContractRenewalRejected`).

Every mutation carries an `expected_revision` fence; a stale revision is
rejected with a conflict. Generation requests additionally carry the expected
values digest, so a packet can only be rendered from exactly the values the
customer confirmed. Any information change clears the confirmation and its
digest, forcing a fresh review before generation. Preview is available in any
state: it applies only the requesting role's draft to a verified copy of the
fillable DOCX and is revision-fenced like every other operation.

A scheduled reconciler scans `Effective` packets and reminds both the
customer subject and platform operators of upcoming lease end dates
(`lease.end_date` / `reservation.end_date`) at the 30-day, 7-day, and 1-day
windows, with per-window deduplication. The control plane runs it every
`LUNANEXA_CONTRACT_EXPIRY_RECONCILE_INTERVAL_MS` (default one hour). Once
the end date is more than `LUNANEXA_CONTRACT_EXPIRY_GRACE_DAYS` (default 7)
whole days in the past, the reconciler closes the packet automatically with
kind `Expired` under the `scheduler` identity, runs the same MasterLease
closure effects as an operator close (API credential revocation plus the
`AccessCredentialsRevoked` notification), and notifies both the subject and
the platform operators with `ContractExpiredClosed`. A packet that changed
between the scan and the close is left for the next pass.

## Privacy

Business data is tenant scoped. Audit events exclude raw values. Signing and
sealing remain offline. Passwords and other access credentials never enter the
contract packet, artifact substitutions, logs, or audit. PostgreSQL stores the
typed packet snapshot in production; artifacts use the existing opaque
transfer/object-storage boundary.

## Current source collection

The first manifest is the exact 18-page youthpolicy DGX Spark remote-lease
packet described in
[`contracts/youthpolicy-dgx-spark-remote-lease-v1.md`](contracts/youthpolicy-dgx-spark-remote-lease-v1.md).
The collection currently contains one DOCX file and seven distinct forms.

Every declared source slot has one authoritative owner:

- `CustomerMessenger` — the authenticated customer or designated messenger;
- `ManagerOperator` — the authenticated manager/operator console;
- `PlatformDerived` — a value synchronized from durable LunaNexa order or
  lifecycle authority and read-only in both browsers;
- `OfflineParticipant` — signatures, seals, passwords, and other values that
  never enter online packet state.

Both browser surfaces edit the same generation-fenced packet revision. Every
persisted value carries its owner, source reference, updating actor, and update
time. A customer cannot submit a manager field, an operator cannot overwrite a
customer field, and neither can author a platform-derived or offline-only
field. Packet confirmation remains blocked until all required online owners
have completed their fields.

The enterprise portal and operator console show the same authoritative DOCX
preview beside their respective input form. The customer sees only
customer/messenger-owned inputs; the operator sees only manager/operator-owned
inputs. Neither browser renders the other party's controls, even as disabled
fields. Preview requests apply only the current role's draft to a verified copy
of the fillable DOCX, reopen it with MoonLeaf, and return MoonLeaf's bounded
neutral text/table scene for Rabbita rendering. No raster screenshot or
alternate HTML contract is used. Demo mode serves a field-free
MoonLeaf scene generated from that same DOCX at build time. The release gate
regenerates it and requires byte-for-byte equality, so it cannot become a
second editable contract template.

The customer portal exposes the collection as **Contract forms / 合同表单**.
Its subject-scoped native API is:

- `GET /v1/contract-documents/manifest` — the template manifest and slot
  definitions;
- `GET /v1/contract-documents/self` — the subject's packets;
- `POST /v1/contract-documents/self` — create a packet; effective-stage forms
  require a `preceding_packet_ref` naming a same-tenant `Effective` packet;
- `PUT /v1/contract-documents/self/{packet_id}:information` — save owned
  fields; only in `InformationDraft`, `ReadyForConfirmation`, or
  `InformationConfirmed`;
- `POST /v1/contract-documents/self/{packet_id}:preview` — role-scoped
  MoonLeaf preview; any state, revision-fenced;
- `POST /v1/contract-documents/self/{packet_id}:confirm` — confirm
  information; only from `ReadyForConfirmation`;
- `POST /v1/contract-documents/self/{packet_id}:generate` — request or retry
  generation (202); only from `InformationConfirmed` or `GenerationFailed`,
  digest-fenced;
- `POST /v1/contract-documents/self/{packet_id}:renew` — open a renewal draft
  from an `Effective` packet owned by the subject (201).

The operator side uses the same packets through an operator-token API.
Operator identity comes from `LUNANEXA_OPERATOR_TOKENS`, a comma-separated
list of `id=token` pairs (for example `alice=<token1>,bob=<token2>`);
malformed entries, duplicate identities, and duplicate tokens are rejected
at startup. When the variable is unset, the legacy `LUNANEXA_OPERATOR_TOKEN`
authenticates as the single `operator` identity. Every operator-side
mutation — information updates, execution registration, closure,
supersession, renewal — records the authenticated operator id as its actor,
and so do the audit entries those actions emit. The scheduled automatic
expiry closure is recorded under the `scheduler` identity instead.

- `GET /v1/contract-documents/operator/packets` — all packets;
- `PUT /v1/contract-documents/operator/packets/{packet_id}:information` —
  save operator-owned fields; editable states only;
- `POST /v1/contract-documents/operator/packets/{packet_id}:preview` —
  operator-scoped preview; any state, revision-fenced;
- `POST /v1/contract-documents/operator/packets/{packet_id}:execute` —
  register the offline signed evidence; only from `Generated`;
- `POST /v1/contract-documents/operator/packets/{packet_id}:close` — close
  with kind `Expired`, `EarlyTermination`, or `Settled`; only from
  `Effective`, with the settlement and ledger-reconciliation rules for early
  termination. Closing a packet whose forms include `MasterLease` also
  revokes the subject's still-active API credentials and notifies the
  subject; `Superseded` packets never trigger revocation, because the
  successor packet continues the relationship;
- `POST /v1/contract-documents/operator/packets/{packet_id}:renew` — open a
  renewal draft from an `Effective` packet (201);
- `POST /v1/contract-documents/operator/packets/{packet_id}:supersede` —
  supersede by a successor packet; any state except `Effective`, `Closed`,
  or `Superseded`.

The renderer worker authenticates with its own token and drives the
asynchronous generation leg:

- `GET /v1/contract-documents/worker/pending` — packets in
  `GenerationRequested`;
- `POST /v1/contract-documents/worker/results` — complete generation with the
  DOCX/PDF artifact pair and a worker receipt; only from
  `GenerationRequested`;
- `POST /v1/contract-documents/worker/failures` — record a generation failure
  with a reason and worker receipt; only from `GenerationRequested`.

The store uses PostgreSQL when management PostgreSQL is configured. Otherwise
it uses `LUNANEXA_CONTRACT_DOCUMENT_PATH` (default
`lunanexa-contract-documents.json`) with atomic mode-0600 snapshots.

Generation is asynchronous. A request advances only after the controller
derives a digest from the exact confirmed values. Completion requires a DOCX
and PDF pair with one shared render-evidence digest and the source page count.
MoonLeaf's semantic browser preview does not claim Word-compatible pagination.
A released PDF still requires the approved exact production font set and
retained page-level evidence.

The preview UI places the current role's form and the MoonLeaf scene side by
side on wide screens and stacks them on narrow screens. Source-authored manual
page breaks are preserved. Automatic Word pagination remains part of the final
DOCX/PDF render gate, not a browser approximation.

This retained DOCX declares A4 dimensions but omits `w:pgMar`. Its verified WPS
layout uses the Chinese document default: 1440 twips at the top and bottom and
1800 twips at the left and right. LunaNexa passes that explicit profile to
MoonLeaf and records the resulting effective margins in the browser scene. The
Rabbita renderer scales every font, line, indent, cell inset, and paragraph gap
against the resulting 8305-twip content box. It preserves source-authored ASCII
spaces with `white-space: pre-wrap`, uses inter-character justification for
Chinese justified lines, and leaves kerning enabled. The current source has
`w:kern="2"` throughout but has no explicit run-level `w:spacing` or `w:w`;
LunaNexa therefore does not invent global tracking or character scaling.

### Licensed font installation

The browser and MoonLeaf renderer consume the same organization-approved font
files. They are deployment inputs and must not be committed to this repository.
On a management Mac, install verified files with:

```sh
scripts/install-contract-fonts.sh \
  /licensed-fonts/FangSong_GB2312.ttf \
  /licensed-fonts/FZXiaoBiaoSong-B05S.ttf \
  /licensed-fonts/SimHei.ttf
sh scripts/build-browser-bundles.sh
```

The installer verifies each font's internal family and rejects a restricted
OS/2 embedding flag. It copies accepted files into the Git-ignored
`assets/fonts/private/` build input and the current macOS user's
`~/Library/Fonts/LunaNexa/` directory. The static browser bundle then serves
them from its own origin through `assets/fonts/contract-fonts.css`; no third
party font CDN receives contract text. Supplying a renamed substitute is an
error, not a fallback. Production renderer images mount the same approved
files from a deployment secret or read-only volume rather than baking them
into a public image layer.

## Contract-governance API surface

The operator console uses the same durable store for the long-horizon business
controls. All routes below require a mapped operator identity; every mutation
is tenant checked and audit attributed to that identity:

- `POST /v1/contract-governance/operator/dashboard` — return the effective
  contract, pending approval, overdue obligation, closure-proposal, ledger
  amount, and next-expiry read model for one tenant;
- `POST /v1/contract-governance/operator/admission` — evaluate the effective
  `MasterLease`, workspace-lease configuration, exclusive-machine presence,
  and whether API-key issuance is allowed;
- `POST /v1/contract-governance/operator/amendments` plus
  `…/{amendment_id}:approve` and `…:materialize` — request a manager-owned
  amendment, require a different operator to approve it, then create a fresh
  renewal draft whose `preceding_packet_ref` is the immutable version link;
- `POST /v1/contract-governance/operator/obligations` and
  `…/{obligation_id}:complete` / `…:waive` — create, complete, or explicitly
  waive payment or acceptance obligations; the controller reconciler marks
  missed open obligations `Overdue`;
- `POST …/packets/{packet_id}:draft-settlement` — hash the current commercial
  ledger summary into a pending settlement draft; the explicit
  `…/settlement-drafts` route is available for an already verified ledger
  snapshot, with `…/settlement-drafts/{draft_id}:approve` and `:apply`
  transitions;
- `POST …/packets/{packet_id}/closure-proposals` — link a same-tenant
  `ViolationNotice` packet to a pending closure proposal without closing the
  contract implicitly; `…/closure-proposals/{proposal_id}:approve` and
  `:apply` provide the explicit review lifecycle;
- `POST …/packets/{packet_id}:number` — allocate one tenant-scoped immutable
  contract number (retries return the existing number for that packet).

The amendment and closure paths deliberately enforce ownership boundaries:
manager/operator routes cannot write customer/messenger fields, and the
customer portal never receives operator controls. Settlement amounts remain
ledger-derived or explicitly supplied as a verified digest; the contract
document store does not invent prices, legal terms, signatures, seals, or
offline evidence.

## Known gaps

The contract governance layer now covers the implementation plan in dependency
order:

- operator identity is resolved from `LUNANEXA_OPERATOR_TOKENS` and written to
  contract audit records; the contract expiry reconciler uses a configurable
  interval and grace period and runs the same credential-revocation effects as
  a manual close;
- high-value execute/close transitions use the durable four-eyes approval
  queue when `LUNANEXA_CONTRACT_APPROVAL_THRESHOLD_CNY` is configured; the
  initiator cannot approve their own action;
- access-key issuance is gated by an unexpired `Effective` `MasterLease` when
  the contract store is configured. `/v1/contract-governance/operator/admission`
  exposes the effective-contract, workspace, and exclusive-lease admission
  projection used to converge the three tracks;
- settlement drafts can be created from the commercial ledger summary with a
  digest of that snapshot, and violation packets can create durable close
  proposals for approval rather than closing a packet implicitly;
- amendments are immutable records attached to an effective packet. An
  approved amendment can be materialized into a new renewal packet whose
  `preceding_packet_ref` forms the version chain. The source remains effective
  while the successor is a draft, then is atomically marked `Superseded` when
  the successor registers execution;
- payment milestones and acceptance obligations are durable objects with
  owners, due times, evidence, completion, overdue reconciliation, and a
  restart-safe operator dashboard projection;
- contract numbers are allocated by a tenant-scoped server sequence, and the
  operator browser includes a compact governance view for effective packets
  and pending approvals.
- governance creation routes derive stable request fingerprints, so an exact
  retry replays the existing amendment, obligation, settlement draft, or
  closure proposal instead of creating a second record. Materializing an
  approved amendment is likewise replay-safe and rejects a second successor
  for the same version link.
- dashboard and admission projections are `POST` routes because their inputs
  are JSON; clients must not send a JSON body with `GET`. Approval actions show
  a confirmation dialog, require a different operator, and compensate a
  failed guarded transition by reopening the approval.
- enabling an approval threshold in a single-operator deployment deliberately
  blocks high-value execute/close actions until a second mapped operator is
  available. Treat that configuration as a rollout check, not as a silent
  fallback to one-person approval.

The following production integrations remain explicit boundaries rather than
silent defaults: a real ledger/provider identity, legal/finance approval of
settlement and amendment policy, and an external notification/delivery setup.
Existing API keys issued before contract gating was enabled are not retroactively
revoked unless their MasterLease is closed or the access store is reconciled;
operators should run the admission projection during rollout.

## Production blockers

- approved Chinese fonts matching `仿宋_GB2312`, `黑体`, and
  `方正小标宋简体` must be licensed and installed in the renderer image;
- an approved DOCX/PDF rendering image must produce and retain page-level
  fidelity evidence;
- the rendering image must be MoonLeaf and emit a typed
  `moonleaf.render-evidence.v1` receipt; LibreOffice, Word, and other office
  engines are not substitutes;
- legal/finance owners must approve the exact source digest and slot manifest;
- real contract values must be supplied and confirmed. Test/demo values are
  prohibited for released contracts.
