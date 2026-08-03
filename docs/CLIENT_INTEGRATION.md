# Provider-neutral client integration

The `vectie/lunanexa/client` package is the published consumer surface. It
supports capability discovery, canonical invocation, streaming preference,
cancellation, usage, health, and typed provider errors without importing any
consumer product.

`HttpTransport` enforces the configured timeout on unary calls, capability and
health discovery, cancellation, stream connection setup and every stream read.
Discovery returns currently approved alias selectors. The client validates the
canonical request before transport, and the server repeats validation before
admission.

An integrating provider router should implement `ProviderTransport`, translate
its own authority and data policy into `WorkloadEnvelope`, retain opaque tenant
and workload identifiers, and use health plus typed retryability for fallback.
That adapter lives in the consumer repository. LunaNexa remains buildable and
operable when every consumer repository is absent.

Credential fields are references owned by deployment configuration. Callers
must never put an application credential, repository path, or product identity
in a request payload, trace token, assignment, or runtime environment.

Use a unique opaque idempotency key and workload ID per logical operation. The
server scopes idempotency by opaque tenant and credential scope and persists no
raw output. A same-process replay may return the bounded response cache; after a
restart, status and replay receipts deliberately contain no retained output.
An admitted workload remains queryable as `Queued` or `Running`; submitting the
same workload while it is active returns the typed, retryable
`WorkloadAlreadyActive` conflict instead of launching it again. The serving
adapter receives the same tenant/scope/key tuple in its `Idempotency-Key`
header. Approved adapters must honor that key across their own restart and
retry boundary.

Once admitted, unary and streaming terminal failures use the same canonical
`WorkloadResponse`. Caller cancellation produces `CancelledByCaller`, queue or
runtime timeout produces non-retryable `DeadlineExceeded`, and an adapter
failure produces `RuntimeUnavailable` with retryability derived from the
underlying failure class. Every terminal outcome is receipt-bearing, audited,
and idempotently replayable; timeout is never mislabeled as caller cancellation.

The consumer-side provider adapter and external-provider fallback tests belong
in the consumer repository. LunaNexa publishes the contract and client package
but never imports that adapter.
