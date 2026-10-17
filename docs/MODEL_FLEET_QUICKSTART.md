# Explore model declarations against a saved fleet

`cmd/model-fleet` answers a small practical question: which individual observed
devices match a saved model's declared architecture and minimum memory, with an
explicit extra memory reserve? It joins an existing saved registry or Candidate
intake draft with the existing saved node response. Change a requirement in your
ordinary intake spreadsheet, regenerate its draft, or edit the reserve and rerun.
The matrix keeps every selected model/version and device, including shortfalls,
unhealthy observations, stale nodes and nodes with no accelerator observations.

This is an offline comparison, not a placement plan. No registration, allocation,
model execution, model download, provider call or controller access occurs.

## Run the invented example

Build under the repository's qualified MoonBit environment, retaining its declared
dependencies and MoonLeaf workspace companion. Keep targets outside source:

```text
moon build --frozen --target native --strip -j1 --target-dir /absolute/private/build cmd/model-fleet --deny-warn
```

Set `EXPLORER` to the built `cmd/model-fleet/model-fleet.exe` and `FIXTURES` to
the `tests/fixtures` directory. Use a separate writable output directory:

```text
$EXPLORER json registry $FIXTURES/model-fleet-registry.synthetic.json $FIXTURES/fleet-nodes.synthetic.json $FIXTURES/model-fleet-query.synthetic.json > comparison.json
$EXPLORER matrix registry $FIXTURES/model-fleet-registry.synthetic.json $FIXTURES/fleet-nodes.synthetic.json $FIXTURES/model-fleet-query.synthetic.json > matrix.csv
```

The three invented model versions and three invented nodes produce 12 rows:

- `synthetic-model/v1` declares 7000 MiB plus the query's 1000 MiB reserve.
  Both architecture-A devices match those declarations; one is explicitly
  recorded unhealthy. The model is still Candidate.
- `synthetic-model/v2` requires 13000 MiB including reserve. Neither A device
  individually has enough reported free memory, although their sum is larger.
  An Approved label cannot remove that shortfall.
- `synthetic-other/v1` matches node B's single architecture-B device, but that
  model is Revoked, the node Cordoned, and the observation stale.
- The CPU-only node produces one `no-device-observation` row per model. Its
  future heartbeat stays visible. Missing device metrics are absent, never zero.

Nothing in this fixture authenticates a real model, measurement or GPU.
Set `memory_reserve_mib` to 6000 in a copy of the query and rerun: no example
device then matches. Restore 1000 to reproduce the original comparison.

## Use saved inputs

1. Retain an already-authorized JSON body from operator `GET /v1/registry`
   (`schema_version: "lunanexa.registry.v1"`) and `GET /v1/nodes` (the existing
   heartbeat array). Acquisition is outside this tool. Keep credentials out of
   files and store the original privately.
2. Alternatively, use the `draft` source kind with the schema-version-1 Candidate
   JSON produced by the existing [CSV intake](MODEL_INTAKE_QUICKSTART.md) or
   [local artifact intake](LOCAL_ARTIFACT_INTAKE_QUICKSTART.md). These are complete
   model records. An OpenAI model list or an inventory-only file is not accepted.
3. Supply explicit `now_unix_ms`, `maximum_age_ms` and nonnegative integer
   `memory_reserve_mib`. Times are quoted decimal milliseconds. Nothing uses the
   wall clock or supplies a default memory overhead. `model_id`, `version`, and
   `node_id` are exact case-sensitive AND filters; empty strings select all.
4. Inspect JSON or open the matrix CSV in a spreadsheet. Filter or sort the
   exported projection as needed. The tool's ordering is model ID/version,
   node ID, then device ID, not placement priority. Narrow a query and rerun to
   explore a different version or node. All input rows validate before filters.
5. Save the original inputs, query and desired reports to reproduce the result.
   Outputs are report projections, not importable registry or deployment plans.
   CSV formula-like identity text is apostrophe-prefixed and every text cell is
   quoted. Unicode, quotes, commas and embedded newlines are retained. JSON
   preserves exact strings and Int64 decimal-string arithmetic.

## Interpret the comparison

Architecture matching is exact membership in `compatible_architectures`.
Required memory is the declared model minimum plus the selected reserve.
`memory_margin_mib = reported_device_free_mib - required_with_reserve_mib`.
Zero margin matches; negative margin is the exact shortfall. Arithmetic is Int64
and memory is never summed across devices or nodes. The tool does not infer
sharding, memory sharing or hardware equivalence.

`matches-declarations` means only that these two comparisons passed. Summary
`devices_matching_declarations` counts exactly those rows, including rows with
health, state or freshness cautions; it is not available capacity. The report
keeps recorded model/node state and health separate from comparison results.
Fresh means `0 <= query_now - heartbeat_time <= maximum_age_ms`. Exact age limit
is fresh; older is stale and later timestamps are future. Saved state may be
obsolete, incomplete, or operator-declared. Signatures are not authenticated.

The live scheduler additionally evaluates runtime support and readiness, license,
data class, deadline, admission/quota and reservation authority; multi-node
placement has separately validated topology. This report does not perform those
checks, score or choose a node. Runtime identity, measured workload memory,
workload overhead, performance, SLA, entitlement, artifact verification and
licensing remain unassessed. A chosen reserve is an operator scenario assumption,
not an estimate. Use the existing benchmark workbench for recorded performance.

Missing required memory, architecture or device-health fields are errors, not
inferred values. Nonpositive model memory and empty model architecture lists are
rejected explicitly; an empty list is not a wildcard. An empty accelerator array
means no supplied device observation, not proof that a node has no hardware.
Other model metadata is decoded without approving or revalidating licenses,
provenance or artifact possession. Other registry domains are not inspected.

## Bounds and local verification

The synchronous CLI reads each selected ordinary local file into memory before
checking its byte bound: 16 MiB per model/node source and 16 KiB for the query.
These are post-read limits, not streaming acquisition caps. Do not supply pipes,
special files, changing files or untrusted unbounded files. Strict UTF-8 decoding
then precedes parsing. Stable-file acquisition and private source retention are
the caller's responsibility; concurrent or same-size replacement is not detected.

Portable limits: 8 Mi UTF-16 characters per source, 16 Ki per query, 1000 models,
10000 nodes, 20000 device records, 32 architectures per model, 512 characters per
exported identity, 50000 comparison rows, and 16 Mi characters per output. Model
minimum and reserve are nonnegative Int-sized MiB (minimum must be positive).
Duplicate identities, invalid memory, unknown query/model fields, malformed
inputs and output bounds reject the whole result. The existing heartbeat decoder
governs node fields. Errors exit nonzero with stderr and empty stdout. Empty
selections produce empty JSON rows or header-only CSV.

Native/JS portable tests exercise comparison, boundaries, ordering, CSV and
invalid inputs. The companion `.mbtx` workflow test invokes the actual native
executable on saved fixtures, edits and reopens queries, checks exact exports and
unchanged inputs, and verifies failures produce no partial output. This does not
qualify the complete workspace, live API/auth, UI, cluster or native installer.
