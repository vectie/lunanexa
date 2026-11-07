# GLM startup verification — 2026-11-07

The live management Start button issues a real lifecycle request through
`/v1/model-services/service-company-text:start`. The common resource authority
checks company ownership before the configured process-group adapter starts the
worker on `.179`, followed by the coordinator on `.178`. It does not create a
new model, replace weights, alter the 1M context or start another engine.

## Measured result

The authenticated `/mana/` button was exercised once. Both existing TensorFold
rank units started at approximately 23:32:38 CST. At 23:33:19 the coordinator
exited with an allocation error: one 1,048,576-token stream requires 12.76 GiB of
KV pages, while the CUDA budget left 12.44 GiB. The supervisor retired the peer.
The model endpoint never became healthy, so this was **a failed startup after
about 41 seconds**, not a successful 41-second startup measurement.

Both ranks were stopped before the test. Qwen/MiniMax were untouched. Files,
keys, model precision, context, concurrency, host reserve and resource ownership
were retained. The startup deficiency is about 0.32 GiB; reducing context or
precision is not an accepted workaround for this investigation.

The two hosts' user-level WirePlumber services hold approximately 580/960 MiB.
Restarting them could recover sufficient headroom, but is a separate host-service
operation, requested for confirmation. No audio/desktop service was restarted.
There is no successful cold-start time to promise until that condition is fixed
and a new test reaches health, model discovery and a valid small inference output.
The historical 14-minute million-token prefill is request processing, not startup.

## Readiness

A systemd unit becoming active is process evidence only. Both portal projections
now require the configured model endpoint's health and model-list checks before
reporting ready. The management page shows Starting while the process runs but
the endpoint is not ready. It refreshes through the existing cluster tick during
that transition, allows only one outstanding read, and stops those extra reads
when ready or stopped.

The check is bounded and does not change inference, per-token work or durable
service snapshots. Native fixtures cover endpoint-not-ready, stopped state,
response privacy, and refresh termination/overlap prevention. Live snapshots and
startup logs are private release evidence; they are not committed here.
