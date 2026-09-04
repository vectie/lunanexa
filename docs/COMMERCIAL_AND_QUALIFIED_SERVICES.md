# Commercial, technical and qualified-service expansion

## What is implemented

LunaNexa now contains three deliberately separate layers:

1. `technical/` is a deterministic policy package for prewarm state, health
   probes, cache telemetry, bounded admission, short-lived transfer grants and
   reviewed sidecar profiles. The production profile has no autoscaler.
2. `commercial/` is a provider-neutral management core for organization,
   cost-center and project hierarchy, usage rating, ledger periods, budgets,
   quotas, capacity commitments, RBAC and digital agreements.
3. `commercial/integrations/` normalizes external identity, payment, invoice and
   qualified-signature evidence. `testsupport/lunafide/` is the isolated test
   double for that boundary.

The operator API exposes management operations under `/v1/technical/*` and
`/v1/commercial/*`. Every management route requires the configured operator
bearer authority. Provider state transitions use the separate signed
`POST /v1/provider-callbacks/commercial` transport and cannot be asserted by an
operator request body. The Rabbita console adds **Cost centers**, **Agreements**, and
**Qualified services** routes using the existing typed state and navigation.
In the console connection drawer, set the optional opaque commercial
organization identifier before refreshing to load that tenant's cost centers,
agreements and privacy-safe external evidence. Leaving it empty skips those
tenant-scoped reads.

## Management workflow

For an organization-scoped commercial workflow:

1. Create the organization, then its cost centers and projects.
2. Grant the minimum commercial role to an opaque operator identity.
3. Ingest a signed, tenant-bound usage observation exactly once.
4. Rate it using an effective fixed-point rate card.
5. Evaluate quota, budget, agreement and capacity commitment admission.
6. Finalize a closed period only after every included usage event is rated.
7. Record later corrections as linked adjustments; never mutate a finalized
   entry.
8. Export tenant-scoped, formula-safe ledger evidence using a finance-authorized
   actor.

Agreement templates are immutable by version. Clickwrap acceptance records the
specific version and evidence receipt. E-signature agreements move only through
the typed state machine, and callback reconciliation is idempotent and bound to
the expected tenant, agreement and evidence.

## Qualified-service boundary

Production providers remain outside LunaNexa. LunaNexa exposes a durable,
machine-authenticated pull outbox rather than calling a provider-selected URL:

- `GET /internal/v1/commercial-provider/requests` returns pending provider
  intents. The machine view omits organization, tenant, human-subject,
  agreement-content and entitlement identifiers.
- `POST /internal/v1/commercial-provider/dispatch-receipts` records the exact
  provider/environment/external-reference binding and a bounded HTTPS browser
  action. It can advance only `Pending -> Submitted`.
- enterprise users create payment intents at
  `POST /v1/portal/payment-checkouts`, request signing at
  `POST /v1/portal/signature-requests`, and read organization-scoped state at
  `GET /v1/portal/self/provider-requests`.

Payment checkout input contains only a finalized `period_id` and a browser
idempotency key. The server resolves the authenticated organization, exact
positive period total, currency and scale and fixes the entitlement reference
to `billing-period:<period-id>`. Organization plus period identify one stable
record, so new browser keys cannot create parallel checkouts; authorized or
settled records are never reopened.

Payment and signature action expiry is a controlled renewal of that same
provider record and external reference. Under the commercial-store mutex the
expired receipt is moved to durable audit history, the record is made pending,
and only then may the adapter rotate its provider session. Retired receipts are
rejected on replay. Signature renewal does not change agreement generation,
document hash, signer or legal state, and a retry repairs a crash that persisted
`SignatureRequested` before the outbox write.

The pull design has no controller-side provider URL and no user-controlled
SSRF surface. Adapter tokens, callback secrets and browser action URLs are
separate authorities. Action URLs reject HTTP, user-info, fragments,
backslashes, whitespace, excessive length and post-acceptance mutation.
The tenant projection is role-filtered: payment and invoice actions require
`BillingViewer`, identity verification requires `OrganizationAdministrator`,
and a qualified-signature action is visible only to the agreement's bound
`LegalSigner`. A same-organization `Developer` cannot retrieve those URLs.

The callback listener validates
an HMAC over provider, environment, event ID, event timestamp and the exact raw
body, enforces a five-minute window, then binds those headers back to the
normalized callback. Only this boundary sets `signature_verified=true`. An
outbox dispatch receipt is never payment, identity or signature evidence.
Callback IDs replay idempotently, identity verification can activate only a
pending organization, and a verified qualified-signature record linked as
`portal-agreement:<agreement-id>` executes the matching portal agreement.
Payment and tax-invoice records use the same evidence and transition rules;
the external provider still owns funds and legal invoice issuance.

LunaFide is named `Luna` + `Fide`. It reports:

```text
service_name=LunaFide
protocol_version=qualified-services.v1
mode=TestOnly
production_ready=false
state_backend=ephemeral-in-memory
trust_claim=none
```

Run its deterministic JSONL scenario with:

```sh
moon run --target native cmd/lunafide
```

It uses only opaque synthetic references and a scheme named
`HMAC-SHA256-TEST-ONLY`. It is not a qualified trust service, payment processor,
tax platform, production authenticator or source of legal assurance.

## Technical execution boundary

The technical boundary is deliberately split between policy and execution:

- persist prewarm operations and reservations;
- persist consumed transfer nonces atomically before allowing an
  assignment-scoped `/data/models` transfer;
- feed node probe and cache observations into the policy core; and
- resolve reviewed sidecar keys to deployment-owned, digest-pinned OCI images.

Autoscaling and batch jobs are explicit non-goals. There is no autoscale route,
decision core or operator action in the production surface.

## Production blockers

Commercial, integration, enterprise portal and access state have PostgreSQL
persistence and restart tests. Before production:

- map trusted ingress identities to tenant-scoped commercial roles;
- deploy approved external providers and keys, never LunaFide;
- validate real tax, finance, privacy, retention and legal requirements;
- validate callback key rotation and provider-specific retry behavior;
- validate the allowlisted `nvidia-smi` sensor collector and artifact gateway
  on each physical DGX; and
- pass the physical four-DGX and named human acceptance gates in
  [the phased plan](PLAN.md).
