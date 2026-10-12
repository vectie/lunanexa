# Explore a saved fleet inventory

For adjacent differences across multiple saved inventories, use the separate
[fleet capture-history workflow](FLEET_HISTORY_QUICKSTART.md).

`cmd/fleet-report` reads a saved operator node response and an editable query,
then writes node inventory, accelerator detail, or grouped CSV/JSON to stdout.
It is an offline file workflow. It never connects to a controller or node,
changes registry state, reserves capacity, or executes a workload.

## Try the invented example

```text
moon run cmd/fleet-report --target native -- nodes tests/fixtures/fleet-nodes.synthetic.json tests/fixtures/fleet-query.synthetic.json > nodes.csv
moon run cmd/fleet-report --target native -- devices tests/fixtures/fleet-nodes.synthetic.json tests/fixtures/fleet-query.synthetic.json > devices.csv
moon run cmd/fleet-report --target native -- summary tests/fixtures/fleet-nodes.synthetic.json tests/fixtures/fleet-query.synthetic.json > summary.csv
moon run cmd/fleet-report --target native -- json tests/fixtures/fleet-nodes.synthetic.json tests/fixtures/fleet-query.synthetic.json > report.json
```

The synthetic input has three nodes and three accelerator records. Node A has
one healthy and one unhealthy device; its heartbeat is exactly 60 seconds old.
Node B is cordoned and 60,001 ms old. The CPU-only node has a future timestamp.
The summary keeps the three device groups separate. These invented memory values
are not hardware measurements or delivered-service evidence.

## Import your existing snapshot and explore

1. Save the JSON body of `GET /v1/nodes` using an existing authorized operator
   session or client. This tool grants no access and performs no acquisition.
   The expected shape is the existing array of `contracts.NodeHeartbeat`, not a
   durable-store wrapper, inventory-only file, or customer endpoint response.
   Keep the original in approved private storage; do not copy credentials.
2. Copy the example query and set `now_unix_ms` to your explicit analysis instant
   and `maximum_age_ms` to your chosen nonnegative age threshold. Both are quoted
   decimal millisecond values, not seconds or a local date. There is no hidden
   wall clock, timezone conversion, freshness default, or current-state claim.
3. Set exact `node_id`, `state`, `architecture`, or `runtime` filters, or leave
   them empty for all values. States are Enrolling, Active, Cordoned, Draining,
   Unreachable, and Retired. `freshness` is all/fresh/stale/future; `health` is
   all/healthy/unhealthy. Values are case-sensitive.
4. Run `nodes` to inspect nodes, `devices` for accelerator drill-down, `summary`
   for architecture/state/freshness/health groups, or `json` for all three views
   plus the exact query and original node count. Change the query and rerun to
   explore another slice without modifying the snapshot.

Fresh means `0 <= now - observed <= maximum_age`. Exactly at the threshold is
fresh. A later timestamp is separately marked future; its age is absent in JSON
and blank in CSV. The freshness label only compares supplied times; it does not
verify clock synchronization, node reachability, or measurement authenticity.

Architecture and health filters must match the same device. Node rows retain
both reported and matching device counts. CPU-only nodes remain in unfiltered
node output, but are excluded by a device architecture/health filter. Runtime
filtering checks a reported runtime name, not runtime readiness. Empty matches
produce empty JSON arrays and header-only CSV. Ordering is deterministic using
the MoonBit key comparator; it does not rank capacity or operational priority.

## Read the memory and state columns correctly

- Memory is the reported per-device total/free MiB in the saved heartbeat.
  Groups sum device values in 64-bit integers, separately by architecture,
  node state, freshness and device health. They never pool healthy with unhealthy
  or fresh with stale observations.
- Summed device memory is an inventory arithmetic total. Devices may share a
  unified memory pool, so the sum can double-count physical memory. It is not
  deployable memory, aggregate usable capacity, or a model-fit recommendation.
- Active, healthy, fresh, runtime present, and free memory do not imply that a
  node is unleased, unreserved, schedulable or permitted for a workload. This
  source contains no complete reservation, entitlement, license or placement
  context. No availability, allocation, service objective, cost or performance
  is inferred. Reported running-deployment count is not readiness evidence.
- Reports omit signatures, runtime endpoint addresses, arbitrary labels, taints,
  OS release and deployment identifiers. They still contain node/device IDs,
  runtime names, versions and memory data; treat them as private operator reports.
  Export omission does not sanitize the original snapshot.

CSV uses UTF-8, CRLF records and quoted text with doubled quotes. Formula-like
text gets a leading apostrophe for spreadsheet viewing. JSON preserves exact
strings and decimal-string 64-bit values. Spreadsheet applications can round
large integers; use JSON or import numeric columns as text when exactness matters.
CSV is a report projection, not a source heartbeat or importable saved report.
Retain the original source and query to reproduce a report. No cryptographic
verification, source signature validation, or snapshot-completeness certificate
is provided.

## Bounds and failures

The CLI reads at most 16 MiB of snapshot bytes and 16 KiB of query bytes with
strict UTF-8 decoding. The portable importer also caps snapshots at 8 Mi UTF-16
characters and queries at 16 Ki characters. Supported timestamps and thresholds
are nonnegative and at most 9007199254740991 ms. There are at most 10,000 nodes
and 20,000 accelerator records, so 64-bit memory sums cannot overflow for valid
Int-sized device values. Zero total/free memory is retained, not guessed.

Duplicate/empty node or device IDs, mismatched inventory identity, empty device
architecture, invalid time, and memory outside `0 <= free <= total` reject the
whole report, including invalid rows excluded by filters. Query typos/unknown
fields are rejected. Existing heartbeat decoding governs snapshot fields;
other domains, labels, signature trust, endpoint validity and deployment state
are not revalidated. Malformed files and invalid queries exit nonzero with a
stderr diagnostic and no partial stdout. This is an explorer, not a recovery
validator. Native and JavaScript callers share the portable `fleet` package;
there is no new browser interface or server endpoint.
