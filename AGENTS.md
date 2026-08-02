# LunaNexa implementation guide

This is a documentation-first MoonBit repository. Read `README.mbt.md`,
`docs/PRODUCT_CONTRACT.md`, `docs/ARCHITECTURE.md`, and `docs/PLAN.md` before
adding implementation.

## Non-negotiable boundary

LunaNexa is the model-as-a-service plane between model consumers and the GPU
hardware cluster. No MoonSuite application, pack, domain schema, agent runtime,
repository checkout, application credential, or product-specific control path
may be installed on or coupled into a managed node.

MoonGate may call LunaNexa through LunaNexa's published, provider-neutral
contract. LunaNexa must never import MoonGate or any other MoonSuite product.
The MoonGate adapter owns any translation from MoonSuite concerns into the
generic LunaNexa request envelope.

## Product and language rules

- Keep LunaNexa one product with separately deployable internal components.
- Write LunaNexa-owned backend, contracts, CLI, controller, scheduler, and node
  agent code in MoonBit, targeting native builds.
- Build the operator interface with Rabbita. A Lepusa wrapper may package that
  interface later; it must not become a second source of UI truth.
- Do not add first-party Python services or scripts. Third-party model-serving
  containers may use their native implementation stacks; treat them as opaque,
  pinned runtime adapters rather than LunaNexa source code.
- Do not create a new agent runtime. Scheduling and reconciliation are
  deterministic infrastructure functions.
- Keep secrets as host or deployment references. Never commit credentials,
  model-license tokens, node keys, raw prompts, or production state.

## MoonBit structure

- Use `moon.mod`, not legacy `moon.mod.json`.
- Give each package a focused responsibility and its own `moon.pkg`.
- Put public contract types in the public package that owns them. Do not expose
  public concrete types from `internal/*` packages.
- Prefer cohesive files and `///|` top-level block separators.
- Use `moonbitlang/async` for network and daemon work and `moonbitlang/x` for
  supported system integrations. Discover APIs with `moon ide doc` before use.
- Prefer typed state transitions and checked errors over stringly typed maps.

## Validation cadence

Do not run the entire matrix after every small edit. Use a targeted check while
working, then run the phase gate once the phase is complete:

```sh
moon info
moon fmt
moon check --target native --deny-warn
moon test --target native --deny-warn
```

Any contract or cluster-boundary change additionally runs contract fixtures,
dependency isolation checks, response leak scans, restart reconciliation, and
the relevant UI-to-UI scenario described in `docs/PLAN.md`.

