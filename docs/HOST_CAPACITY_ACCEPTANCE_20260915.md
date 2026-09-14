# Host capacity validation acceptance

Node heartbeats now measure Linux `/proc/cpuinfo` and `/proc/meminfo` before
signing, replacing the reserved `lunanexa.io/host-cpu-count` and
`lunanexa.io/host-memory-mib` labels. Measurements are host totals, not cgroup
limits or free/allocatable memory. Static inventory remains unchanged.

Paid machine matching requires fresh active inventory, no inventory taints,
sufficient measured host CPU/RAM, matching region and healthy accelerator
architecture/count, and existing lease/reservation checks. Missing or malformed
host labels fail closed; older nodes must be upgraded before becoming sellable.
Do not populate these labels from an offering to bypass measurement.

Validation on the isolated Linux native toolchain:

- Node and API packages: 146 tests passed, zero failed.
- Node command native typecheck: passed.
- Covered parser malformed/duplicate/missing fields, resource-label replacement
  without mutation, insufficient CPU/RAM, invalid measurements and tainted-node
  rejection. Existing paid-order tests still pass with explicit test inventory.
- Existing deprecated API warnings remain; this is not a warning-clean release.

Not yet validated: rollout to the physical node, signed live heartbeat collection,
propagation of Kubernetes disk pressure into LunaNexa inventory taints, cgroup
resource constraints, real paid provisioning, or GPU model deployment. Kubernetes
Ready alone does not establish resource availability. Test inventory is not
hardware evidence. This change does not complete overall platform acceptance.

## Read-only native executable check

`lunanexa-node --inspect-host-resources` exits after reading Linux procfs; it
does not load enrollment credentials, contact the controller or start workloads.
Native release build exposed a missing `-ldl` in the node executable link flags;
the flag was added and the release build then succeeded.

Executed on management host ubuntu: `{"cpu_count":24,"memory_total_mib":"64073"}`.
Independent system readings were `_NPROCESSORS_ONLN=24` and
`MemTotal=65610872 kB`, whose integer MiB conversion is 64073. This verifies
actual host collection on that AMD64 Linux machine, not the compute node or Spark.
