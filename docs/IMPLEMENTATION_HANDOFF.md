# Implementation handoff

## Start here

The repository implementation baseline is complete enough for deployment
integration. A deployment owner should work in `/Users/kq/Workspace/lunanexa`,
run `scripts/release-gate.sh`, review `docs/IMPLEMENTATION_STATUS.md`, and then
collect the private inventory below. Do not install on DGX machines until the
one-node overlay, trust roots, immutable digests and rollback evidence have been
reviewed.

Read in this order:

1. `AGENTS.md`
2. `docs/PRODUCT_CONTRACT.md`
3. `docs/ARCHITECTURE.md`
4. `docs/DECISIONS.md`
5. `docs/PLAN.md`
6. `docs/SIMULATION.md`

## Frozen decisions

- Product name: LunaNexa.
- Product form: one product with multiple deployable components.
- Position: below MoonGate and above the hardware cluster.
- Dependency direction: clients may consume LunaNexa contracts; LunaNexa never
  imports a MoonSuite product.
- Backend and node implementation: MoonBit native.
- Operator interface: Rabbita, with an optional later Lepusa wrapper.
- Node behavior: deterministic infrastructure reconciliation, not an agent
  runtime.
- Initial topology: four independent DGX Spark nodes; no unproven shared-memory
  or distributed-inference assumption.
- First-party Python: prohibited. Third-party serving containers are isolated
  adapters and are not copied into LunaNexa source.
- Test cadence: phase gate after each substantial phase, then one consolidated
  real-cluster validation.

## Facts to collect before touching hardware

Record these in a private deployment inventory, never in the repository:

- node hostnames, management addresses and physical location;
- exact DGX Spark OS, driver, firmware and container-runtime versions;
- network switch, link speed, VLAN/firewall and any direct interconnect layout;
- management host and durable metadata database location;
- OCI registry, artifact store and backup targets;
- NGC/model-provider credentials as secret references;
- approved initial model, artifact digest, license and evaluation dataset;
- administrative identity provider and certificate authority choice;
- acceptable downtime, payload classification and retention defaults;
- power, cooling and physical-access ownership.

Do not commit this inventory if it contains addresses, serials, credentials or
security topology.

## Implemented first slice

The repository contains this tested contract and reconciliation shape:

```text
contracts v1
→ durable native controller/registry/scheduler/enrollment/telemetry
→ authenticated node reconciliation and rootless OCI supervision
→ deterministic fake plus digest-pinned remote text adapters
→ health/register/deploy/invoke/stream/status/cancel/stop APIs
→ native process-boundary, restart, placement, leak and UI tests
```

The next step is deployment integration: terminate mTLS at the trusted
management boundary, configure the real CA/identity/S3/OCI/metrics providers,
and enroll one real DGX. Keep fake adapters as deterministic test providers.
Before hardware is available, run `scripts/four-node-simulation.sh` to validate
the four-node control-plane and failure workflow without treating its output as
hardware, model-license or performance evidence.

## Questions that remain open

The implementation thread may choose these behind ports without changing the
product boundary:

- metadata database and migration mechanism;
- OCI/S3 products already available on the management network;
- first real model-serving runtime and model;
- container supervision layer on the DGX nodes;
- certificate authority and operator identity integration;
- initial service objectives and benchmark prompts;
- whether the controller runs on a dedicated management host or an existing
  non-GPU operations host.

Choices that change the frozen product boundary or introduce a MoonSuite
dependency require an explicit architecture decision before implementation.

## Definition of a useful first milestone

A named operator can enroll one DGX, register a verified model artifact, deploy
it through declarative desired state, send one generic request, inspect usage
and an audit receipt, restart the node agent, and observe correct reconciliation.
The DGX contains no MoonSuite repository, application binary, pack manifest or
product credential.
