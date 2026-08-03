# Four-node DGX functional simulation

LunaNexa includes a local, native four-node simulator for control-plane and
failure testing when DGX hardware is unavailable. It uses separate operating
system processes rather than guest virtual machines because the node protocol,
not an emulated Linux kernel, is the boundary under test.

Run the disposable campaign with:

```sh
sh scripts/four-node-simulation.sh
```

To retain the evidence bundle, provide a path that does not already exist:

```sh
sh scripts/four-node-simulation.sh ./simulation-evidence
```

The campaign builds and starts:

- one durable LunaNexa controller;
- four simulation-only node agents with independent enrollment credentials,
  certificates, inventories and state files;
- four simulation-only OpenAI-compatible runtime endpoints with independent
  ports, control files and invocation journals;
- an approved registry fixture whose verification evidence is explicitly
  labelled `simulator-only`.

It proves four-node enrollment, controller-signed assignment reconciliation,
strict node-to-runtime routing, bounded queueing under an injected delay,
retry to an alternate node after runtime failure, drain rerouting, node-agent
restart, controller restart, durable state recovery and public-response leak
scanning. The retained `summary.json` uses schema
`lunanexa.simulation.v1` and always records
`"hardware_performance_validated": false`.

## Isolation and safety

The `sim-node`, `sim-runtime` and `sim-seed` executables refuse to start unless
`LUNANEXA_SIMULATION_ONLY=1` is present. The harness binds every endpoint to
loopback, creates unique per-run credentials, uses a new state directory and
does not call a container engine. Simulation state must never be copied into a
production registry or accepted as model-license, signature or benchmark
evidence.

## What this cannot validate

This is not a DGX emulator and cannot substantiate CUDA compatibility, GB10
instruction behavior, unified-memory pressure, NVLink or network topology,
container GPU passthrough, thermals, power, model correctness, cold-load time,
tokens per second, latency objectives, or production image and license scans.
Those remain part of the real four-node and named-human release gate in
`docs/PLAN.md`.

If VM or container isolation is later required, each simulation-only process
can be wrapped in a separate guest without changing its LunaNexa protocol. The
functional campaign should remain the portable baseline used in CI.
