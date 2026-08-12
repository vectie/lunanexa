# Operations, offline commerce, machine access and guide diagnostics

Status: implementation contract; notification and observability phases implemented
Last reviewed: 2026-08-12

This document closes the five product gaps found during the pre-deployment
review. It is an implementation contract: each section identifies the durable
authority, public projection, required notification and audit behavior, and the
acceptance evidence needed before the feature may be described as production
ready.

## Product boundary

LunaNexa remains the management and model-service plane. Management services,
PostgreSQL, document generation, object storage, notification delivery and the
coursebook guide run on the management side. Managed DGX nodes receive only
typed lease or workload directives and never host commercial records, raw
documents, notification credentials, the guide agent, or MoonSuite application
state.

The controller is the only writer of authoritative business state. External
identity, payment, invoice, signature, mail/SMS, object-storage and malware-scan
systems are adapters. Their callbacks carry evidence; they do not replace the
LunaNexa state machine.

Raw passwords, private keys, SSH certificates, contracts, scans, receipts,
invoices, prompts and model outputs are not PostgreSQL fields or audit payloads.
State stores opaque references, SHA-256 digests, byte counts, media types,
bounded labels and evidence receipts.

## 1. Durable notifications and alerts

The platform owns a single durable notification authority with two projections:

- an operator alert center for cluster, security, reconciliation and capacity
  events;
- a tenant inbox for agreement, payment, invoice, lease, access and expiry
  events.

Every event has a stable ID, tenant scope (or explicit platform scope), typed
topic and severity, audience, source receipt, creation time, optional expiry,
deduplication key and bounded localization parameters. Delivery channels are
in-app, email, SMS and webhook. Only in-app is intrinsic; other channels are
deployment adapters with retryable delivery records.

Alerts support acknowledgement, assignment, bounded silence windows and
resolution. Notifications support read/unread state. Neither user dismissal nor
channel delivery deletes the immutable source event. The outbox is idempotent by
`source_receipt + topic + audience`; retries cannot produce duplicate inbox
items.

Minimum rules:

- node unreachable, quarantined, sanitization failed and controller recovery;
- artifact capacity threshold and artifact verification failure;
- workload admission/rate/concurrency rejection thresholds;
- agreement awaiting offline action, evidence rejected and review overdue;
- payment/invoice reconciliation failure;
- lease approved, access ready, 72/24/1-hour expiry warnings, user termination,
  forced revocation and completed sanitization;
- guide diagnostic adapter unavailable or knowledge revision stale.

Notification delivery failure is itself an operator alert after the configured
retry budget. Secrets for email/SMS/webhook adapters are deployment references.

Acceptance requires restart persistence, idempotent replay, cross-tenant denial,
acknowledge/silence expiry, channel retry/dead-letter behavior, bilingual
rendering and both console and enterprise-portal UI-to-UI scenarios.

Implemented in the current phase: the typed notification contract, file and
PostgreSQL-backed snapshot authority, in-app plus retry/dead-letter delivery
records, preferences, operator alert actions, stale-heartbeat reconciliation,
exclusive-lease access/expiry/termination reconciliation, operator alert UI and
bilingual tenant inbox. External mail/SMS/webhook provider workers remain a
deployment integration prerequisite and cannot be advertised until configured.

## 2. Logs, metrics and triggers

Audit evidence remains the immutable business/security chain. Operational logs
are a separate bounded JSON stream written to stdout and collected by the
deployment. Every record includes timestamp, severity, component, stable event
code, request/correlation ID, actor class, tenant hash when applicable, target
type and outcome. It must not include bearer tokens, subject DNs, raw prompts,
model output, callback bodies, document bytes, SSH material or provider secrets.

Metrics expose counts, gauges and latency histograms with bounded labels. Raw
tenant, user, request, lease and workload IDs are never metric labels. Alert
rules consume typed state/metrics and enqueue notification events; they do not
parse human prose logs.

Required observability includes API outcome/latency, controller reconciliation,
node health and heartbeat age, scheduler queue/admission, runtime invocation,
artifact storage and verification, PostgreSQL availability, outbox backlog and
delivery failures, commercial reconciliation exceptions, document scan/review
age, exclusive-lease lifecycle, sanitization, and guide requests by outcome
code. Trace/correlation IDs propagate from ingress to audit and adapter calls.

The deployment must provide an OpenTelemetry-compatible collector path plus
Prometheus scrape and starter alert rules. External destinations are optional;
the local operator alert center remains functional when they are absent.

Implemented in the current phase: bounded restart-durable operational events,
JSON-lines stdout emission, correlation preservation, tenant hashing,
monitoring/audit-protected event export, low-cardinality Prometheus counters,
outbox gauges, rejection-burst and dead-letter trigger integration, and starter
Prometheus/OpenTelemetry deployment resources. Production collector/Prometheus
operators and the external OTLP/log destination remain deployment prerequisites.

## 3. Hybrid digital-to-offline commerce

### Aggregate and states

`CommercialOrder` binds organization, project, selected service/SLA, immutable
quote, agreement, required offline evidence, payment/invoice records and the
resulting capacity or exclusive-machine entitlement.

The normal interim workflow is:

```text
Draft -> Quoted -> PendingInternalApproval -> PendingOfflineExecution
      -> PendingEvidenceUpload -> UnderReconciliation -> Fulfilled
```

Terminal or corrective states are `NeedsCorrection`, `Rejected`, `Cancelled`
and `Expired`. A configurable fulfillment policy declares which verified items
are prerequisites: executed agreement, payment, invoice, identity verification
and internal approval. Invoice-before-service and invoice-after-service are both
representable; the controller must never infer local legal policy.

### Documents

Templates are versioned and immutable. Generation produces a DOCX source, an
XLSX quote/cost schedule where requested, and a print-ready PDF. The artifact
worker runs on the management plane. MoonLeaf validates bounded OOXML packages,
extracts a neutral preview/diagnostic result and verifies controlled template
edits. It is not treated as a full layout or formula engine.

Each `DocumentArtifact` stores kind, template/version, locale, media type, byte
size, SHA-256 digest, object reference, generation state, scan state, creator
receipt and creation time. The object store owns bytes. Generated artifacts are
not downloadable until digest verification and malware/active-content policy
pass. User uploads use a two-step, size-bounded grant; the callback records the
verified digest rather than accepting a caller-asserted object reference.

DOCX and PDF require deterministic render-and-visual regression fixtures. XLSX
requires formula inspection, error scan and rendered-sheet verification. PDF is
the offline execution copy; DOCX is an explicitly labeled editable source and
is never accepted as executed evidence without upload/reconciliation.

### Reconciliation and gating

Offline evidence kinds include executed contract scan, payment receipt, issued
invoice and internal approval evidence. A submitter cannot approve the same
evidence. Review records expected artifact digest, prior/next state, reviewer,
bounded reason code and audit receipt. Rejected evidence never silently replaces
the prior file; a new revision is uploaded and linked.

Fulfillment creates the commitment/lease only after the configured policy is
satisfied in one controller transaction with the durable business snapshot and
notification outbox. Revocation, refund, void or contract expiry triggers the
configured access action and alerts; provider evidence alone cannot directly
activate or terminate a node account.

Acceptance requires happy path, every missing-evidence combination, duplicate
upload/callback, forged digest, oversized/ZIP-bomb/active-content document,
malware-scan failure, reviewer conflict, stale generation, restart at every
state, refund/void after fulfillment and cross-tenant artifact denial.

## 4. Exclusive-machine customer experience

### Authentication and access handoff

Production login is owned by an approved OIDC/SAML identity provider at trusted
ingress. LunaNexa receives an opaque subject and tenant membership. Static shared
browser tokens are local-development only.

After approval and node provisioning, the user sees a subject-bound lease view:

- state, node display name, start/expiry and live countdown;
- access profile (`ExclusiveNonRoot` initially), username, host alias, SSH port,
  host-key fingerprint and a copyable connection command;
- credential state and a short-lived, one-time retrieval action or certificate
  issuance redirect;
- model/image requests allowed by the lease;
- terminate-now action with confirmation, reason and generation fencing;
- lifecycle timeline, sanitization status and support correlation ID.

The API never returns a private key or stored password. A credential broker
returns a single-use envelope or redirects to an approved SSH CA. The broker
binds subject, lease, node, username, expiry and retrieval count. Access material
expires no later than the lease and can be revoked independently.

“Full machine” initially means an exclusive non-root Linux account with the
documented filesystem boundary and rootless container runtime. It does not mean
root/sudo, management-node access, LunaNexa daemon credentials or other tenants'
data. A root-capable offering requires a separately approved bare-metal reimage
and attestation product; it is not silently enabled by this workflow.

### Expiry and termination

The management authority and node-local guard both enforce expiry. The user may
terminate an active lease; operators may force termination under audited policy.
Both converge through `Draining -> RevokingAccess -> Sanitizing`. Scheduling is
restored only after a verified sanitization receipt. Failed cleanup quarantines
the node and raises a critical alert.

Agreement cancellation, failed payment or policy revocation requests termination
through the same generation-fenced authority. They do not bypass drain, revoke
or sanitize stages.

Acceptance requires credential replay denial, wrong-subject/wrong-node denial,
host-key display, restart-safe one-time retrieval, local expiry during controller
outage, manual termination, forced revocation, active sessions at expiry, stuck
process/container, sanitize failure/quarantine, clean next-tenant reuse and UI
tests at every lifecycle state.

## 5. Guide pet and administrator diagnostics

The public coursebook pet remains documentation-first. It answers from a
versioned coursebook index and does not expose internal implementation process,
private evidence or live cluster state.

An authenticated administrator mode may call a separate read-only diagnostics
adapter. The adapter returns only allowlisted summaries: component health,
active alert codes/counts, reconciliation backlog, node/lease state counts,
knowledge revision, enabled skill names/versions and links to the matching
runbook. It cannot execute commands, mutate state, read secrets, fetch raw logs,
return prompts/model output or cross tenant boundaries.

Every admin diagnostic request records actor, role, query category, knowledge
revision, adapter outcome, latency and correlation receipt; the question text is
not logged. Skill manifests declare ID, version, audience, required evidence,
allowed tools/data and runbook routes. The admin UI shows installed revision,
last successful index build, adapter health and missing evidence—not hidden
chain-of-thought or evaluator judgment.

Acceptance requires role denial, public/admin response separation, prompt
injection and secret-exfiltration attacks, stale-index warning, adapter outage,
bounded output, audit/metric evidence, and verified links from every diagnostic
code to a bilingual runbook.

## Delivery phases

1. Durable notification contracts/store, in-app inboxes and starter alert rules.
2. Structured operational events, expanded metrics and deployment collector/rules.
3. Commercial order/offline reconciliation and artifact metadata/upload boundary.
4. Management-plane document worker contract with DOCX/XLSX/PDF fixtures and
   MoonLeaf verification.
5. Subject-bound machine-access handoff, self-termination and lifecycle UI.
6. Read-only admin diagnostics adapter plus skill/version inventory.
7. PostgreSQL/restart/adversarial/UI/document-render/physical-cluster gates.

The first six phases are repository implementation work. Approved IdP, SSH CA,
mail/SMS providers, object store, malware scanner, legal templates, payment/tax
providers and destructive physical-DGX validation are deployment prerequisites;
the product must expose them as explicit readiness gates rather than simulate
success.
