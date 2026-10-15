# LunaNexa implementation guide

This is a documentation-first MoonBit repository. Read `README.mbt.md`,
`docs/PRODUCT_CONTRACT.md`, `docs/ARCHITECTURE.md`, and `docs/PLAN.md` before
adding implementation.

## Supported public sites

Optimize and validate the deployed sites at
`https://suanli.kechuangfuwu.com:8443/user/`, `/mana/`, and `/docs/`.
These are the customer portal, management portal, and documentation site.
Do not deploy or use a standalone enterprise/console demo or `?demo=1`
browser session as a product preview or acceptance target. Demo state helpers
are test fixtures only. Internal `enterprise` and `console` bundle names still
serve the supported portals; do not remove their production services.

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
moon run scripts/test-native.mbtx
```

The native runner builds the CLI fixture executables and invokes the complete
native workspace test suite, including workspace dependency tests.

Any contract or cluster-boundary change additionally runs contract fixtures,
dependency isolation checks, response leak scans, restart reconciliation, and
the relevant UI-to-UI scenario described in `docs/PLAN.md`.

### Prerequisites the toolchain does not supply

Linux native links and the large API test binary need these settings:

- **`-pthread -ldl` on every native link.** These flags are declared in the
  module's package manifests. Preserve them when adding or changing a native
  package. Other workspace modules may still need a host compiler wrapper
  supplying these flags when running the complete workspace suite.
- **A large stack for the linker, plus `ulimit -s unlimited`.** Linking the
  `api` test binary otherwise kills `moonc` with a `Stack overflow` ICE.

`ulimit -s unlimited` matters even with a generous soft limit: `moonc` sets its
own thread stack, and the ICE only disappears once the shell's limit is lifted.

