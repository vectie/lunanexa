# Import a multi-run benchmark CSV without splitting files

The offline capacity CLI can group interleaved observations from one ordinary
CSV into the existing benchmark evidence array. Each group is one independently
described run, with its own tested concurrency, origin, source reference and
measured memory. Statistics are still calculated per run; no samples are pooled.
This imports saved observations only. It does not execute a benchmark, upload
anything, contact a controller, provision capacity or authenticate measurements.

## Try the synthetic example

Build `cmd/capacity-plan` with the project's pinned compiler and real Leaf R58
workspace companion. Keep generated targets outside the source tree:

```sh
moon --target-dir /absolute/private/build build cmd/capacity-plan --target native --frozen --strip -j 1 --deny-warn
```

Set `PLAN` to the resulting `native/debug/build/vectie/lunanexa/cmd/capacity-plan/capacity-plan.exe`
inside that external build directory. From the repository root:

```sh
$PLAN import-grouped-csv tests/fixtures/benchmark-grouped.synthetic.csv tests/fixtures/benchmark-grouped-mapping.v1.json > grouped-evidence.json
```

Open this file in **Benchmarks → Capacity-plan workbench → Or import a complete
producer evidence file**, then select the runs and declare an objective normally.
The existing single-run `import-csv` command and browser mapping form are unchanged;
the grouped mapping is authored as a file for this CLI workflow.

For a reproducible offline comparison, the supplied plan template contains the
same fixture context, minimum tested concurrency 4, p95 limit 350 ms, throughput
minimum 350 tokens/s, and zero permitted failures. Insert the evidence array
into its `evidence` field. For example, with `jq` already available:

```sh
jq --slurpfile runs grouped-evidence.json '.evidence = $runs[0]' tests/fixtures/benchmark-grouped-plan-template.v1.json > planning-input.json
$PLAN prepare planning-input.json > planning-packet.json
$PLAN reopen planning-packet.json > reopened-packet.json
$PLAN summary reopened-packet.json > comparison.csv
$PLAN samples reopened-packet.json synthetic-csv-concurrency-8 failed latency > failed-samples.csv
```

The template alone is intentionally incomplete: empty evidence cannot prepare a
packet. All six observations are invented. The concurrency-4 run has three samples,
p95 280 ms, throughput 400 tokens/s and zero failures; the concurrency-8 run has
three samples, p95 420 ms, throughput 533 tokens/s and one failure. Only the first
meets that fixture objective. These values are never hardware performance claims.
The source CSV begins with the concurrency-8 run and interleaves both groups;
the mapping determines output run order. Reopening retains both runs separately.

Edit a metric in the source CSV and repeat import/prepare to produce a new packet.
An edit to one group does not change the other group's observations. Keep previous
packets if you want to compare versions through the existing `analyze` workflow.

## Describe your groups explicitly

Copy `benchmark-grouped-mapping.v1.json` and update:

- `schema_version`: 1
- `run_id_column`: exact CSV header holding the run ID
- `columns`: all eight metric header mappings, shared across groups
- `runs`: 1–8 context records, each with `run_id`, `profile`, `model_digest`,
  `runtime_digest`, `hardware_profile`, `kind`, `concurrency`, and `metadata`

Each `metadata` object uses the existing `origin`, `source_ref`, `workload_ref`,
`output_unit`, `memory_total_mib`, and `memory_peak_mib` fields. There are no
inferred defaults. Use `SyntheticFixture` for invented data. `LocalObservation`
is your declaration, not evidence that this tool observed or authenticated it.
Each context applies to every CSV row with that exact run ID, so split group IDs
when configuration or measured memory changes. Unmapped columns, including
configuration-looking columns, are ignored and do not override context.

Run IDs are case-sensitive exact decoded CSV strings. Data keys are not trimmed:
`run-a`, `RUN-A`, and ` run-a` are different. Context IDs must be nonblank and have
no surrounding whitespace. Quoted commas, quotes, internal newlines and Unicode
are supported. Duplicate context IDs, unknown CSV groups and contexts with no
rows reject the entire import. The run-ID column must differ from every metric
column, and every metric must map to a distinct existing header.

Runs are returned in mapping order, independent of first appearance in the CSV.
Within each run, samples retain their original file order, including interleaved
rows. Identical rows remain separate observations; no implicit deduplication,
filtering or sampling occurs. Global row interleaving and ignored columns are not
retained in Evidence. Preserve the original CSV and mapping for reconstruction.
Diagnostic record numbers count logical CSV records, including the header;
quoted embedded newlines do not increment that number.

All groups validate before output. The existing evidence importer enforces the
same per-run arithmetic and context bounds. Different origins/configurations
can be imported as separate evidence, but the unchanged capacity planner refuses
incompatible runs in one comparison. It never silently merges or normalizes them.

## File and failure boundaries

- UTF-8 CSV: 16 MiB file bytes, 4 Mi UTF-16 code units, 128 columns and 1–10000
  total observation records across all groups. This does not multiply the old
  record budget by the number of runs. Every group must have at least one row.
- Existing CSV grammar and metrics are unchanged: BOM and LF/CRLF/CR accepted;
  quoted commas/newlines and doubled quotes accepted; unique trimmed headers;
  ragged/blank records and malformed quoting rejected. All numeric metrics are
  nonnegative whole decimal integers, duration positive, utilization 0–1000 per
  mille. Failure accepts true/false, TRUE/FALSE or 1/0, with 1 meaning failed.
- Mapping JSON: at most 64 Ki UTF-16 code units, strict version and fields,
  including every nested context and metric mapping. The CLI's pre-read file
  bound is 16 MiB; semantic mapping validation applies the tighter character bound.
- Output: the unchanged Evidence[] schema, compact JSON within its existing
  4 Mi-character import bound, without a trailing newline. No new packet version
  or telemetry schema is introduced. Metadata fields retain their usual bounds.
- Any failure exits nonzero with a stderr diagnostic and empty stdout. Input
  files are not edited. Shell redirection can truncate a destination before the
  CLI starts, so always use a new output filename, never an input path. Files
  must stay stable during reading; same-size concurrent replacements are not
  detected by the inherited bounded reader.

Keep raw observations and context private if they contain sensitive operational
references. Importing and preparing a packet neither approves a model nor proves
hardware, throughput, deployment, commercial or production qualification.

## Focused tests

The portable planning/benchmark suites run on native and JavaScript. The native
capacity CLI workflow test requires `CAPACITY_PLAN_EXE`, `CAPACITY_PLAN_FIXTURES`
and an existing writable `CAPACITY_PLAN_EVIDENCE` directory. It performs actual
subprocess/file import, repeated import, prepare, save/reopen, per-run summary,
failed-sample export and edit/reimport, plus nonzero/empty-output failure cases.
It does not run the operator browser, controller, database or physical hardware.
