# LunaFide

LunaFide is an ephemeral, deterministic integration-test double for qualified
external services. It is **not production-ready** and performs no real identity
verification, qualified electronic signing, payment processing, tax-invoice
issuance, or cryptographic trust service. Tests and scenarios must use only
opaque synthetic references—never real PII, identity documents, payment
credentials, taxpayer data, or signing keys.

The service identifies itself as:

    service_name: LunaFide
    protocol_version: qualified-services.v1
    mode: TestOnly
    production_ready: false
    state_backend: ephemeral-in-memory

## Deterministic core API

Import `vectie/lunanexa/testsupport/lunafide` only from tests,
simulations, or an explicitly test-only adapter.

- `service_identity()` and `LunaFide::health(now_unix_ms)` expose test identity.
- `request_verification` and `resolve_verification` simulate organization or
  individual verification.
- `create_envelope` and `record_signature` simulate signer and optional
  platform countersigner state transitions.
- `request_payment` deterministically selects settlement, decline, or review
  from `simulated_outcome`.
- `issue_invoice`, `void_invoice`, and `reissue_invoice` preserve invoice
  lineage and prevent destructive replacement.
- `events()` returns a copy of signed JSON-friendly callbacks in emission order.

Every mutation requires `protocol_version`, a tenant-scoped idempotency key,
opaque references, and an explicit synthetic timestamp. Replaying an identical
request returns the original record without another event. Reusing the same
scope and idempotency key with different content raises `IdempotencyConflict`.
References are deterministic SHA-256-derived fixture IDs.

## Callback protocol

`WebhookEvent` is serializable with `ToJson` and `FromJson` and contains:

    protocol_version, provider, environment, event_id, kind,
    tenant_ref, aggregate_ref, sequence, occurred_unix_ms,
    idempotency_key, payload, key_id, auth_scheme, signature

Callbacks use `auth_scheme=HMAC-SHA256-TEST-ONLY`, key ID
`lunafide-ephemeral-v1`, and the domain-separated canonical material:

    lunafide.webhook-test-mac.v1|<canonical JSON with signature set to empty>

This MAC exists only to exercise callback validation paths. It is not a
qualified signature, certificate, seal, timestamp, or production authentication
recommendation.

`WebhookReceiver::accept` requires the event, test secret, expected tenant,
expected aggregate, current timestamp, and maximum clock skew. It rejects a
wrong protocol/provider/environment/key scheme, invalid MAC, tenant or aggregate
misbinding, expired timestamp, duplicate event ID, and non-increasing aggregate
sequence. Replay state is updated only after every check succeeds.

## Scenario runner

Run:

    moon run --target native cmd/lunafide

It prints one health JSON object followed by JSON webhook events for a complete
synthetic verification, countersigned agreement, successful payment, and
invoice issue/void/reissue scenario.

## Integration boundary

LunaNexa commercial code should depend on a provider-neutral qualified-service
port, not this package. A test adapter may translate that port's commands into
the request records above and feed returned callbacks through the normal
production callback-ingress validation path.

The integrating side must persist its own expected tenant/aggregate binding,
idempotency outcomes, callback cursor, and business transition. Accepting a
valid callback must not itself grant capacity: entitlement creation and ledger
reconciliation remain an atomic or explicitly recoverable LunaNexa operation.
Production adapters must replace LunaFide with qualified providers and their
approved key management, identity, evidence, retention, legal, tax, and payment
controls.
