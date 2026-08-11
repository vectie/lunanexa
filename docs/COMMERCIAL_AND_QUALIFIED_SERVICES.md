# Commercial, technical and qualified-service expansion

## What is implemented

LunaNexa now contains three deliberately separate layers:

1. `technical/` is a pure deterministic policy package for prewarm state,
   health probes, cache telemetry, autoscaling, bounded admission, short-lived
   transfer grants and reviewed sidecar profiles.
2. `commercial/` is a provider-neutral management core for organization,
   cost-center and project hierarchy, usage rating, ledger periods, budgets,
   quotas, capacity commitments, RBAC and digital agreements.
3. `commercial/integrations/` normalizes external identity, payment, invoice and
   qualified-signature evidence. `testsupport/lunafide/` is the isolated test
   double for that boundary.

The operator API exposes these under `/v1/technical/*` and
`/v1/commercial/*`. Every route requires the configured operator bearer
authority. The Rabbita console adds **Cost centers**, **Agreements**, and
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

Production providers remain outside LunaNexa. An adapter must validate its
transport signature, timestamp, replay key and tenant/aggregate binding before
setting normalized `signature_verified` evidence. Callback acceptance and the
resulting commercial transition must commit atomically or through an explicitly
recoverable transaction.

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

The `/v1/technical/*` endpoints return decisions; they do not directly mutate a
node. The controller integration must:

- persist prewarm operations and reservations;
- persist consumed transfer nonces atomically before allowing a transfer;
- feed signed node probe and cache observations into the policy core;
- translate scale decisions into idempotent deployment operations under the
  current lease/deployment generation fence; and
- resolve reviewed sidecar keys to deployment-owned, digest-pinned OCI images.

## Production blockers

The current commercial stores are intentionally in-memory. Restart durability,
multi-controller concurrency and callback/business atomicity are therefore not
yet production claims. Before production:

- add a transactional persistent adapter and crash-recovery suite;
- map trusted ingress identities to tenant-scoped commercial roles;
- deploy approved external providers and keys, never LunaFide;
- validate real tax, finance, privacy, retention and legal requirements;
- connect technical decisions to durable reconciliation and live signed node
  telemetry; and
- pass the physical four-DGX and named human acceptance gates in
  [the phased plan](PLAN.md).
