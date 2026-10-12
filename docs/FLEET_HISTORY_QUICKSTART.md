# Compare a history of saved fleet captures

`cmd/fleet-history` imports 2–16 saved operator heartbeat responses and produces
an adjacent-capture change timeline. Use it to investigate which nodes changed
state or agent version, where reported accelerator health or free memory
changed, and which identities are newly observed or absent from each export.
It is a native offline file workflow: no controller request, telemetry write,
benchmark, provisioning, placement, lease change or GPU execution occurs.

## Run the invented three-capture example

From the LunaNexa module with its dependencies available:

```text
moon run cmd/fleet-history --target native -- json tests/fixtures/fleet-history-manifest.synthetic.json tests/fixtures/fleet-history-query.synthetic.json > history.json
moon run cmd/fleet-history --target native -- changes tests/fixtures/fleet-history-manifest.synthetic.json tests/fixtures/fleet-history-query.synthetic.json > changes.csv
moon run cmd/fleet-history --target native -- summary tests/fixtures/fleet-history-manifest.synthetic.json tests/fixtures/fleet-history-query.synthetic.json > transitions.csv
```

The first transition produces 10 changes: the invented node A changes state,
agent version, reported runtimes, deployment count and two device attributes;
one device becomes absent and another is newly observed. Node B becomes absent
and D is newly observed. The second transition produces 5 changes, including
three more differences on A, B newly observed again, and the CPU node absent.
Device differences are only compared when their node exists in both captures.

The report separately counts one repeated heartbeat in the first transition,
one regressed heartbeat in the second, and one future-dated heartbeat in the
first capture. These deliberate examples show why capture order is not proof
of observation order. All identities, measurements and changes are synthetic;
they are not evidence of physical events, service delivery or usable capacity.

## Use your existing captures

1. Keep JSON responses from `GET /v1/nodes` that you are already authorized to
   read in approved private storage. The format is the existing array of
   `contracts.NodeHeartbeat`, exactly as for `cmd/fleet-report`. The tool does
   not acquire data, grant access, decode a durable-store wrapper or accept CSV
   reports as source. Never put credentials or authentication headers in files.
2. Copy the example manifest. Give each source a unique, nonempty `capture_id`,
   the explicit `captured_unix_ms`, and its `path`. Paths are resolved relative
   to the manifest file, not the current working directory; absolute paths also
   work. Capture IDs are operator labels, not authenticated snapshot identities.
   The tool reads referenced files but never writes them or follows remote URLs.
3. Put captures in strictly increasing capture-time order. Milliseconds use
   quoted decimal strings. Equal/reversed times, repeated IDs, missing inputs
   and an unknown schema fail; the tool never sorts or guesses time for you.
   A capture time is your declared export/observation boundary. Heartbeat times
   remain distinct and can repeat, go backward, or be later than capture time.
4. Copy the query and choose an exact `node_id` or empty for all. Choose `scope`
   `all`, `node`, or `device`. Set `field` to empty or one of: `presence`,
   `state`, `agent_version`, `runtime_names`, `running_deployment_count`,
   `architecture`, `healthy`, `observed_total_mib`, `observed_free_mib`.
   A valid field outside the selected scope simply has no matching changes.
5. Run `changes` for drill-down CSV, `summary` for adjacent-transition counts,
   or `json` for the query, capture counts/times, transitions and selected
   changes together. For example `node_id: "synthetic-a"`, `scope: "device"`,
   `field: "observed_free_mib"` yields the two recorded free-memory differences
   on A's device 0. Change the query and rerun without modifying the sources.

## Interpret the timeline

- Every change names both capture IDs and capture times. It also retains the
  before/after heartbeat timestamps of its node. The difference is observed
  between files; its true event time and cause are unknown. Repeated or regressed
  heartbeat counts are diagnostic counts across matched nodes, not events.
  Future heartbeat counts compare source times to the declared capture time.
  These counters are not filtered by the query and do not certify clock sync.
- For a newly observed identity, a `presence` row has `after: "observed"`
  and omits `before`. For an absent identity it has `before: "observed"`
  and omits `after`. Absence is not evidence of
  decommissioning, device removal, physical failure, or capture completeness.
  Reappearance after a gap is newly observed in the adjacent pair; the tool
  does not bridge the gap or assume continuity. Changing an identity yields
  two presence observations, never an inferred rename or replacement.
- A whole node becoming absent/newly observed produces one node-presence row,
  rather than inventing device-by-device events without both node snapshots.
  For matched nodes, device IDs are scoped to the node ID. CPU-only nodes work.
  Missing or malformed required heartbeat fields fail; an explicit empty
  source array is a valid empty capture and still does not imply a complete one.
- State, agent version, runtime names and deployment count are node fields.
  Architecture, health and total/free MiB are device fields. Runtime ordering,
  node ordering and device ordering do not create differences; runtime-name
  duplicates, if present, are retained. Deployment identity changes with the
  same count are intentionally outside the projection. Ordinary advancing
  heartbeat timestamps alone do not create noisy change rows.
- No latency, capacity trend, rate, utilization, memory-pool uniqueness,
  reservation, availability, scheduling permission, model readiness, entitlement,
  billing, performance or production qualification is inferred. Memory is a
  reported per-device value, not a measurement of usable or exclusively owned
  memory. Unchanged projections can hide changes in omitted source fields.
- `total_change_count` describes all projected field/presence differences in
  that pair; `selected_change_count` describes the query result. These are
  field counts, not changed-node counts. Empty matching output is header-only
  CSV or an empty JSON change array; capture and transition context remains.

CSV uses UTF-8, CRLF, quoted/escaped text and spreadsheet-formula escaping.
Blank unquoted CSV cells denote absent optional values, while `""` retains a real
empty string. JSON omits absent optional properties; it does not emit `null`.
Node-level changes omit `device_id`. A whole-node presence row also omits the
heartbeat timestamp for its absent side, while device presence rows retain both
heartbeat timestamps because the node exists in both captures. Exact 64-bit
timestamps use quoted decimal strings. Attribute before/after values are strings in both formats;
`runtime_names` contains canonical sorted JSON-array text. Spreadsheet apps may
round long integers: import timestamp columns as text or retain JSON.

Reports omit source file paths, signatures, endpoint addresses, OS release,
arbitrary labels/taints and deployment identities. They retain private operator
node/device IDs, capture labels, versions, runtimes and inventory differences.
This projection is not a sanitizer for arbitrary text or the original files.
No signatures or measurements are authenticated. A report is not a reopenable
source or completeness certificate: retain the original manifest, query and
all source files in private storage to reproduce it. File changes during or
between runs can change results; size checks do not provide an atomic snapshot
or detect same-size replacement.

## Bounds and verification scope

CLI inputs are strict UTF-8: manifest ≤64 KiB, query ≤16 KiB, each snapshot
≤16 MiB, all referenced snapshot bytes together ≤32 MiB. Pure import limits are
64 Ki/16 Ki/8 Mi UTF-16 characters respectively. There are 2–16 captures, at
most 10,000 nodes and 20,000 devices per capture, and 20,000 node records plus
40,000 device records total across the history. Capture and heartbeat times are
nonnegative and ≤9007199254740991 ms. Each source uses the existing fleet
identity, time and memory validator before filtering. Unknown manifest/query
fields are rejected; heartbeat field decoding remains the existing contract
behavior, not a new full-schema validator.

Invalid sources, duplicates, out-of-order captures, malformed files, limits and
bad queries fail nonzero with a stderr diagnostic and no partial stdout. The
portable `fleet.import_history_manifest`, `import_history_query` and
`explore_history` functions share the same native/JavaScript core; the CLI
alone reads local files. Focused native/JS tests and native file-workflow tests
cover this explorer. No new browser UI, whole-workspace validation, live service,
physical hardware or production acceptance is established.
