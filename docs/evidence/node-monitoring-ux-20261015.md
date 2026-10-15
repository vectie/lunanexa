# Node monitoring and management layout — 2026-10-15

## Diagnosis and recovery

One compute node repeatedly received HTTP 401 from certificate renewal. Its
local certificate matched the controller's durable record, but had expired
beyond the bounded automatic-renewal grace period. The agent's failed renewal
prevented reconciliation and fresh heartbeats; missing memory and utilization
were therefore displayed as unknown rather than invented measurements.

The existing node authority was compared against its durable digest. A current
named operator issued a short-lived, one-use bootstrap, and only the affected
node agent was paused for enrollment and certificate installation. Its node
secret, permissions, identity, workloads and resource ownership were preserved.
Original enrollment and certificate records remain private recovery references.
The API subsequently reported all enrolled compute nodes Active, with current
host-memory and accelerator-utilization samples for the recovered node.
Its historical heartbeat-loss alerts are now Resolved by the controller.
The node subsequently completed its next automatic certificate renewal; host
and controller records agree on the renewed serial.

## Management page

- Topology is the first section and cannot be collapsed.
- Compute inventory follows; storage monitoring is last.
- Storage capacity scales through KiB, MiB, GiB, TiB and PiB.
- Large file-entry counts use K/M/B in English and 万/亿 in Chinese.
- Heartbeat age uses minutes, hours and days without changing stale thresholds.
- Device labels use GPU numbers with the full identifier available on hover.
  An unreachable node explicitly labels device health as its last inventory.
- Power readings retain up to two decimal places.
- Topology fits the available content width; narrow containers use a vertical
  layout. Storage fields wrap rather than truncating timestamps or totals.

The deployed management image is
`sha256:64c1e577f97e7d2bbcdccc8464b5816bd18c2b9d7e231fd20b1867d84877d2af`.
Its publicly served console bundle matches the tested build:
`ae30a1706fa3f5dec783e21450275b648bec20ce3d985520937b9e2d68e5a18a`.

## Validation

The node and console JS suite passes 189 tests with warnings denied, including
storage order, visible topology, scaled units and heartbeat-age boundaries.
The full native check passes with warnings denied. The complete Linux workspace
suite passes 1,822 tests, including workspace dependency tests. The final layout
also passes all 104 management UI native tests after the responsive refinement.
Linux validation uses an unlimited stack and the host compiler wrapper needed
by workspace dependency test executables.

Authenticated live visual acceptance confirms topology, compute inventory and
storage in that order, with all four current node heartbeats and no unresolved
heartbeat-loss alerts. The original overview card shows fresh measured memory,
GPU utilization, a recent heartbeat and its existing reserved allocation. At
the browser's current width, topology content and visible widths both measure
687 pixels: no horizontal clipping. All storage values are visible in the
refined layout. Screenshots remain private local artifacts.

Release tooling pins its async imports to the module's 0.22.4 version; a newer
standalone-script dependency used an unsupported package-manifest key. Native
runtime link flags are now declared in the 37 remaining package manifests.
The canonical native runner retains the complete workspace suite, including
workspace dependency tests. Managed-endpoint identity fixtures use an explicit
observation clock so filesystem delays cannot consume their freshness window;
production discovery retains its live clock.
Gateway examples use explicit projected service-account mounts. The secret
scanner validates TLS resource names separately from secret values, including
regressions for shell substitutions and concatenated credentials. All release
scans pass; the gateway manifests pass Kubernetes client-side validation.

Credentials, raw enrollment snapshots and production telemetry remain private
and are excluded from this repository.
