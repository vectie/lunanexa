# GLM startup verification

## Active 512K configuration — 2026-11-08

At the user's request, both existing TensorFold rank units now use
`--context 524288`. Only that argument changed; precision, output allowance,
reasoning setting, execution-lane configuration, memory reserve, credentials,
model files and company node ownership were preserved. The host's audio services
were not restarted or removed. GNOME 46, PipeWire and WirePlumber are installed
on these Ubuntu 24.04 hosts; WirePlumber is wanted by the PipeWire services and
is not a dependency of LunaNexa or GLM.

The authenticated `/mana/` Start button successfully brought the service online.
Measured unit start to healthy model discovery: **41.788 seconds**, sampled every
1.5 seconds. A small JSON arithmetic request returned the correct result in
324 ms; a separate SSE request returned the expected text and `[DONE]` in 234 ms.
Those are small-request checks, not a 512K-prompt quality/latency benchmark or a
cold-filesystem/reboot benchmark.

Both `/v1/models` aliases and the tokenizer report 524,288 tokens. Runtime load
reports eight execution lanes and a shared paged pool of 528,384 tokens: this
does not promise eight simultaneous full-512K histories. The allocation metadata
now records the verified context, lanes and 1,032 512-token pages; the old 1M
KV-byte estimate was removed rather than reused as a new measurement. The prior
configuration is retained privately for rollback.

The page changed to Ready without a manual refresh. The successful GLM service
is left running. Qwen and MiniMax were retained. No new client key, grant,
consumer application or model-specific controller branch was introduced.

## Previous 1M attempt — 2026-11-07

The live management Start button issues a real lifecycle request through
`/v1/model-services/service-company-text:start`. The common resource authority
checks company ownership before the configured process-group adapter starts the
worker on `.179`, followed by the coordinator on `.178`. It does not create a
new model, replace weights, alter the 1M context or start another engine.

### Measured result

The authenticated `/mana/` button was exercised once. Both existing TensorFold
rank units started at approximately 23:32:38 CST. At 23:33:19 the coordinator
exited with an allocation error: one 1,048,576-token stream requires 12.76 GiB of
KV pages, while the CUDA budget left 12.44 GiB. The supervisor retired the peer.
The model endpoint never became healthy, so this was **a failed startup after
about 41 seconds**, not a successful 41-second startup measurement.

Both ranks were stopped before the test. Qwen/MiniMax were untouched. Files,
keys, model precision, context, concurrency, host reserve and resource ownership
were retained. The startup deficiency was about 0.32 GiB. Context was retained
during that attempt; the user subsequently authorized 512K, as recorded above.

The two hosts' user-level WirePlumber services hold approximately 580/960 MiB.
Restarting them could recover sufficient headroom, but is a separate host-service
operation, requested for confirmation. No audio/desktop service was restarted.
At that point there was no successful startup duration or valid inference output.
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
