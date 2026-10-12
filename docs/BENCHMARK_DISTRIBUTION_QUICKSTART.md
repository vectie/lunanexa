# Explore recorded benchmark distributions

Use a saved capacity-planning packet to see how many observations fall within
editable latency, queue, first-output, load or duration ranges. Separate failed
and successful samples and export a CSV for plotting. This complements p95
summaries and raw sample exploration; it never measures a model or changes a run.

## Prepare, bin, edit and plot

The native `cmd/capacity-plan` executable has two new commands:

```sh
capacity-plan prepare tests/fixtures/benchmark-distribution-input.synthetic.json > saved-packet.json
capacity-plan distribution saved-packet.json synthetic-concurrency-4 tests/fixtures/benchmark-distribution-plan.v1.json > latency-distribution.json
capacity-plan distribution-csv saved-packet.json synthetic-concurrency-4 tests/fixtures/benchmark-distribution-plan.v1.json > latency-distribution.csv
```

Always choose fresh output filenames, never an input filename. Check exit status
before consuming output. Failures produce stderr and no partial stdout artifact.
These examples are synthetic, not measured production performance.

Copy the plan to a new file and edit it:

```json
{
  "schema_version": 1,
  "metric": "QueueMs",
  "upper_bounds_ms": [0, 4, 10, 50]
}
```

Rerun with the edited plan to inspect queueing. Accepted metric names are
`LatencyMs`, `QueueMs`, `FirstOutputMs`, `LoadMs`, and `DurationMs`. Every value
and every boundary is an integer number of milliseconds. Unknown names, extra
fields, fractional numbers and invalid versions reject. Plans are capped at
64 KiB and 1..32 strictly increasing, unique, nonnegative Int32 upper bounds.

## Exact bucket semantics

For bounds `[0,10,20]`, buckets are `[0,0]`, `(0,10]`, `(10,20]` and `(20,+∞)`.
The first bucket includes zero. Each other finite bucket excludes its lower
bound and includes its upper bound. The final overflow bucket is always present.

JSON represents the first open lower bound and final open upper bound as null;
CSV represents them as empty cells. A null boundary means unbounded, not missing
measurement. All sample measurements are required in the existing packet
schema. A missing/null metric rejects the packet; it never becomes zero.
An empty bucket's count is legitimately zero because every selected sample was
placed into exactly one bucket.

Each row includes sample, succeeded and failed counts, plus cumulative counts
through that bucket. Success/failure uses the captured `failed` flag; a recorded
false flag does not prove answer quality or protocol completion. Failed samples
retain their recorded metrics instead of disappearing from the latency view.
No percentiles are estimated from buckets. Existing sample-derived summaries
and objectives remain unchanged.

The synthetic example has five selected samples, with latencies 0,10,11,20,21 ms
and two recorded failures. Bounds `[0,10,20]` yield total counts `[1,1,2,1]` and
failure counts `[0,1,1,0]`. The second run remains separate. Choose an exact run
ID; this command never pools runs with differing concurrency or other context.

## Evidence and output

The original planning packet is reopened and recomputed before exploration.
Tampered packet IDs or recommendations fail. Reports retain the packet ID,
selected run ID, canonical observation hash, declared origin, source/workload,
model/runtime/hardware identity, benchmark kind and tested concurrency.
Changing the plan changes the bins without changing the packet or its samples.
Source, workload and hardware labels may contain private operator metadata;
review them before sharing a report. No prompts or model responses are added.

JSON is a derived distribution report, not a reopenable planning packet. Keep
the original packet and plan to reproduce it. CSV contains one row per bucket
and explicit run totals, allowing bar charts and cumulative plots without
discarding provenance. Text cells use RFC 4180 quoting and prefix formula-like
spreadsheet values with an apostrophe; JSON preserves their exact strings.

Existing packet limits remain: at most eight runs and 10,000 samples per run,
with validated metrics and bounded arithmetic. This workflow is native offline
CLI only. No UI interaction, GPU, provider, controller, allocation, throughput
remeasurement, production SLA or physical-cluster qualification is implied.
