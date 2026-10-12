# Recorded-benchmark capacity planning

The operator console's existing **Benchmarks** route now includes a capacity-plan
workbench. The older read-only evidence list remains underneath. The workbench
does not record measurements in the controller or create allocations, quotes,
provider requests, credentials, deployments, node assignments or GPU work.

## Author, compare, export and reopen

1. Open **Benchmarks → Capacity-plan workbench** and choose **Select recorded
   run**. The console keeps the typed raw `benchmark_runs` from the existing
   operator-authenticated `GET /v1/telemetry`; summary strings are never converted
   into observations. Inspect sample counts, concurrency and the collapsed
   model/runtime/hardware identities. **Refresh recorded runs** performs only
   that read and preserves selected evidence, metadata drafts and saved packets.
   Legacy summary-only snapshots still populate existing console/node views,
   while the picker explicitly reports raw observations unavailable. Missing raw
   runs or schema versions are never filled in from summaries.
2. Complete only the context absent from `BenchmarkRun`: explicit provenance,
   source record reference, workload/dataset revision, output unit and measured
   total/peak memory from the same run and pool. Unknown provenance starts blank
   and cannot qualify a run. Choose **Add / update run in comparison**. Adding
   the same ID deliberately replaces that comparison source instead of making
   a duplicate. An already completed/reopened run retains its explicit metadata.
   Alternatively, open **Or import a complete producer evidence file** and choose
   the native export described below. A valid file replaces the draft source
   list; failed imports retain it. Manual JSON is only a collapsed fallback.
3. Select the individual runs to compare. Review the profile, exact model and
   runtime digests, hardware/driver/topology profile, benchmark kind, workload
   revision and output unit. Set the minimum tested concurrency and enter the
   maximum p95 latency, minimum throughput and maximum failures. Objective values
   start empty: the console does not invent a service objective.
4. Choose **Compare and prepare packet**. The table retains every selected run's
   sample count, origin, source, measured statistics and memory headroom. It
   separately shows whether the samples meet the objective and minimum tested
   concurrency. Nothing is pooled or extrapolated across runs.
5. Download the exact planning JSON or copy the collapsed read-only export. The browser
   uses an in-memory data URL; no upload or server write occurs. Drafts survive
   console navigation and core refresh in the same tab, but are not persisted
   across reload, logout or tab closure. Save before leaving.
6. Choose the saved file under **Reopen a saved planning packet**. The shared
   core recomputes the input digest and
   every result before restoring editable fields. Invalid packets leave the
   current draft intact. Editing any authoring field or selected run removes the
   current export; prepare again to produce the new input-derived packet ID.

A selected observation carries its canonical raw-run SHA-256 and observed
benchmark-list SHA-256 in the existing packet `source_ref` as
`recorded-v1:sha256:<run>:snapshot:<list>:source:<operator-reference>`.
The packet keeps all selected samples, not the unselected snapshot payload.
Canonical typed JSON, rather than transport whitespace, defines this identity.
Recorded references whose run digest no longer matches the samples are rejected.
If a run changes or disappears from a refreshed history, the UI flags the
captured evidence without replacing it. To adopt new samples, explicitly select
the current run and add it again. Pending metadata cannot be committed against
a changed/disappeared observation. Duplicate IDs reject the entire refresh and
retain the prior snapshot. Stale refresh/file-read callbacks are ignored; failed
reads preserve the current draft. Core refresh cannot overwrite a newer
planner-owned snapshot; use **Refresh recorded runs** for fresh observations.

The import envelope is limited to 8 runs, 10,000 samples per run and 4 Mi
characters. Exports are checked against the same reopen bound. Run IDs must be
unique. Durations and memory must be positive, samples nonempty, utilization in
0..1000, and all metrics nonnegative. Arithmetic bounds protect the historical
Int-based benchmark summary. Comparisons require exact profile/model/runtime/
hardware/kind/workload/unit equality and a common origin. Synthetic and local
observations require separate packets.

File controls decode UTF-8 strictly, with a 16 MiB byte bound before reading and
the existing 4 Mi-character format bound after decoding. This accommodates
Unicode packet text without allowing unbounded file reads. No upload occurs.

## Inspect samples and export spreadsheets

Choose **Inspect samples** on any captured comparison run. The local sample
explorer shows all eight recorded metrics, the original one-based sample number,
and an explicit synthetic/local-observation label. Filter to failed samples or
sort by slowest latency / longest queue. Ties retain original order. Previous
and Next show 25 rows at a time, with matching and complete-run counts.

The explorer does not change selected evidence, packet identity, full-run
statistics, or objective outcomes. A zero-match filter is an empty view, not
evidence that the full run was successful. No outlier is removed from a plan.

Choose **Prepare matching samples CSV**, then **Download all matching samples
CSV**. The download includes every matching row across all pages, in the chosen
order. Each row retains run ID, declared origin, canonical observation SHA-256,
output unit, original sample index and all raw metrics. Changing run, filter,
order or captured evidence clears the prepared sample export. Paging does not.

After preparing a comparison, **Download comparison summary CSV** exports one
row per selected run, including complete identity/context, source reference,
observation hash, actual failure count, rounded legacy failure rate, measured
latencies/throughput/memory, declared objectives and exact-count results. Tested
concurrency and the untested suggested concurrency have distinct columns.

Both CSVs are UTF-8 with CRLF records and quoted text cells. Formula-like text is
prefixed with an apostrophe for spreadsheet viewing. Embedded commas, quotes,
newlines and Unicode are preserved with CSV quoting. CSV is a report projection;
use the unchanged JSON packet for exact strings, reopening and recomputation.
The raw-observation CSV importer below is a separate workflow; summary CSVs are
not raw observations. Neither workflow authenticates physical measurements.

## Import ordinary raw benchmark CSV

Use **Import raw benchmark CSV observations** when a measurement tool produces
one record per observation but does not emit LunaNexa evidence JSON.

1. Choose a UTF-8 CSV file or paste CSV and choose **Preview CSV columns**.
   Inspect the record count and first five records. This stages the data locally;
   it does not change your current comparison or its exported packet.
2. Map all eight metric selectors to the CSV header names. Exact standard names
   are preselected; other headers need an explicit mapping. Each metric must use
   a distinct column. Check units before proceeding: latency, queue, load, first
   output and duration are integer milliseconds; output units are integer counts;
   utilization is integer per mille (0–1000). The failure flag accepts
   `true`/`false`, `TRUE`/`FALSE`, or `1`/`0`; **1 means failed**, not successful.
   Missing metrics are not filled with zeros. Decimal seconds, percentages,
   scientific notation and status-code conventions need an explicit conversion
   by the producing tool before import. No numeric rounding is performed.
3. Enter the run ID, profile, exact model/runtime identities, hardware/driver/
   topology profile, kind and tested concurrency. Declare the origin, source
   record reference, workload revision, output unit and measured total/peak
   memory from this same run and pool. Provenance starts blank. Use
   `SyntheticFixture` for invented data; `LocalObservation` is an operator
   declaration, not measurement authentication.
4. Choose **Add / replace CSV run**. Every record is validated, then the new run
   joins and is selected in the existing comparison. The same ID explicitly
   replaces only that run. Other sources and the captured change-analysis
   baseline remain. Up to eight comparison sources are supported. Invalid
   data leaves the current sources and packet intact, with a record/column
   diagnostic for malformed metrics. A successful add invalidates the old
   packet so the objective must be evaluated again.
5. Set or review the ordinary objective, prepare a packet, inspect samples,
   download summary/sample CSVs, or compare against a captured baseline using
   the existing controls. The resulting JSON packet retains the exact converted
   samples and declared context and reopens with the unchanged v1 verifier.
6. **Download CSV import mapping JSON** saves the validated context and mappings
   for repeatable offline CLI import. This is a mapping file, not a saved packet
   and not a copy of the CSV. Keep the original CSV alongside it. Editing CSV
   staging clears this download until another successful add. **Clear CSV
   staging** removes only the intake fields; **Clear local draft** resets the
   whole workbench. Neither staging nor packet persists across a tab reload.

For the single-run browser form and `import-csv` command, one file is one run:
rows are never grouped, filtered, dropped or pooled. To ingest interleaved runs
from one CSV without splitting it, use the separate offline
[grouped CSV import](BENCHMARK_GROUPED_CSV_QUICKSTART.md) command. The
parser accepts comma delimiters, optional UTF-8 BOM, LF/CRLF/CR records, quoted
commas/newlines and doubled quotes. Header whitespace is trimmed and names must
be unique and nonempty. Numeric surrounding whitespace is trimmed. A final line
ending is allowed; blank data records, ragged rows, malformed quotes, duplicate
headers and invalid metrics reject the whole import. Bounds are 4 Mi characters,
16 MiB file bytes, 128 columns and 1–10000 samples. Existing run arithmetic,
identity and memory bounds still apply. Only five rows are shown in the preview,
but all rows must pass import validation.

Unmapped columns are displayed in the preview but do not enter the evidence or
packet. The source reference is explicitly supplied; the importer does not
invent a telemetry snapshot identity or retain raw CSV bytes/mappings in the v1
packet. Save the CSV and mapping separately if you need to reconstruct the
conversion. CSV summary reports and aggregate percentile rows are not a valid
substitute for raw observations. This is a local file workflow with no upload,
telemetry mutation, provider call or benchmark execution.

Native import uses the identical portable core:

```text
lunanexa-capacity-plan import-csv tests/fixtures/benchmark-observations.synthetic.csv tests/fixtures/benchmark-csv-mapping.v1.json > imported-evidence.json
```

Open `imported-evidence.json` through **Benchmark evidence file**, then use the
normal editable objective and packet controls. For batch tooling, the output is
the existing evidence array accepted in planning-input JSON. The command emits
no stdout on failure and exits nonzero with a diagnostic on stderr. Mapping JSON
uses schema version 1 and rejects unknown fields, including nested fields;
its limit is 64 Ki characters. The browser can create this mapping without JSON
authoring. Reuse requires that the new file represents the declared run context;
update the run ID and context when those change.

The committed CSV fixture contains 12 explicitly invented observations, including
one failure, nonstandard headers and a quoted Unicode note. The supplied mapping
declares synthetic runtime v3, 32 GiB total and 22 GiB peak memory. Its p95 is
330 ms, throughput is 366 tokens/s, and failure rate is 1/12 (83‰ rounded down).
It fails a zero-failure objective. These numbers are fixture outputs, never
hardware performance evidence.

## Explore repeated concurrency sweeps

For one selected run's latency, queue, first-output, load or duration histogram,
use [editable benchmark distributions](BENCHMARK_DISTRIBUTION_QUICKSTART.md).
The offline CLI exports exact success/failure and cumulative bucket counts to
JSON or CSV while preserving the original packet and its provenance.

Use the offline [sweep explorer](BENCHMARK_SWEEP_QUICKSTART.md) to group a saved
packet by tested concurrency and total memory, inspect per-run latency/queue
ranges and exact failures, and optionally compare observed counts with intended
repeat coverage. Missing levels remain unmeasured and failed repeats stay visible.
The optional plan never executes a benchmark or changes the original packet.

## Compare a baseline with a candidate

Use **Compare a baseline with a candidate** to review a runtime, model,
hardware or concurrency change from two saved planning packets. Unlike the
same-configuration capacity table, this workflow deliberately permits those
configuration differences and lists every changed value.

1. Prepare or reopen the baseline packet with the existing controls. Select
   the baseline run and choose **Capture selected run as baseline**.
2. Reopen the candidate packet, or edit/import evidence and prepare it normally.
   The captured baseline and its objective remain unchanged in this tab.
3. Select the candidate run, then choose **Analyze selected candidate against
   baseline**. Review p50/p95/p99 latency, p95 queue and first output, throughput,
   peak memory and memory headroom. Values, absolute deltas and relative deltas
   are shown together. Exact failed/total fractions determine failure-rate
   direction, including cases where both legacy rounded rates are zero.
4. Read both outcomes against the **fixed baseline objective and minimum
   concurrency**. A relaxed candidate packet objective never silently improves
   its outcome. Lower latency may accompany lower throughput or more failures;
   the workbench does not choose an overall winner.
5. Download the reproducible change-analysis JSON and readable text report.
   The JSON contains both complete selected observations, their source context,
   the fixed objective, deterministic results and a content identity. Use the
   native `review` or `reopen-analysis` commands below to verify it again.

The two runs must share origin, profile, benchmark kind, exact workload/dataset
revision and output unit. Model/runtime/hardware, tested concurrency and total
memory may differ; the report names all five changed configuration fields.
Different sample counts are shown separately. These are independent unpaired
observations, not a statistical test: no significance, confidence interval,
causal attribution or output-quality equivalence is established. Throughput
keeps the existing sum(output units)/sum(sample durations) meaning. A lower
memory peak is not necessarily better performance or lower cost.

Every delta is candidate minus baseline. Relative deltas are signed per mille
of the baseline, truncated toward zero: -500 means -50%. A zero baseline gives
an unavailable relative delta while retaining the absolute change. Exact
failure-rate direction uses integer cross-products, not rounded percentages.

Selecting another run, replacing/preparing a packet or editing its inputs
clears the current analysis export. The captured baseline survives those actions,
ordinary route navigation and telemetry refresh in the same tab. Invalid packet
imports retain the current inputs and report. **Clear baseline and analysis**
removes only the comparison; **Clear local draft** removes everything. Neither
draft nor baseline survives reload/logout/tab closure. No extra server write,
benchmark execution, upload or deployment occurs.

The new analysis has a separate versioned format and 8 Mi-character limit;
the original planning-packet format and identity are unchanged. It hashes its
canonical input and revalidates both complete selected runs, but it is still
operator-declared evidence, not a measurement signature. The readable report
is a projection; save JSON for exact strings, samples and recomputation.

## Evidence semantics and limits

`SyntheticFixture` means invented deterministic test measurements, never physical
observations. `LocalObservation` means operator-declared measurements with a
source reference; import does not independently authenticate them. Neither origin
is a production qualification, deployment approval or SLA. The hardware profile
should carry its driver and topology revision; a changed serving configuration
requires a new benchmark.

The workbench calls the existing pure `summarize`, `build_recommendation` and
`recommend_capacity` implementation. These functions now live in the portable
`telemetry/benchmark` package and remain re-exported from the historical native
`telemetry` API. No controller or node source acquires UI dependencies.

The existing throughput statistic is sum(output units) / sum(sample durations),
using integer units/second. It is **not aggregate fleet throughput**. The existing
concurrency recommendation retains tested concurrency when its integer failure
rate is zero and otherwise suggests one lower, with a minimum of one. The legacy
rate is floor(failed samples × 1000 / total samples): one failure among 1001
samples therefore reports 0‰ and retains tested concurrency. Its historical
`recommendation.objective_met` also uses that rounded rate and remains unchanged
in the packet. A displayed 0‰ does not mean zero observed failures.

The new workbench shows actual failed/total sample counts alongside that rounded
rate. Its displayed objective status and packet `meets_declared_envelope` use
the exact-count comparison failed × 1000 ≤ allowed per mille × total, alongside
the existing latency/throughput checks. Consequently any observed failure fails
a declared 0‰ objective, even when the legacy recommendation field is true.
That distinction preserves historical telemetry semantics without overstating
the new planner's result. Suggested concurrency is still an untested heuristic;
tested and suggested concurrency are shown separately. Every objective status
describes only the original samples. No price, savings, future availability,
fleet size or guaranteed SLA is inferred.

Packet identity is SHA-256 over the typed canonical input JSON, including all raw
samples, selected-run order, provenance, measured memory, objective and workload.
This is content identity and accidental-tamper detection, not a signature or proof
that measurements are genuine. Imports reject unknown fields, including nested
ones, so future semantic inputs cannot silently disappear. A new schema version
is required for new semantic fields. Whitespace and object-key ordering are not
part of typed input identity.

## Native offline CLI

`cmd/benchmark-evidence` exports one exact run from a saved production telemetry
response or durable telemetry snapshot. It does not execute a benchmark or
contact a provider. Declare the genuinely missing metadata using normal command
arguments; no evidence JSON authoring is required:

```
moon run cmd/benchmark-evidence --target native -- telemetry.json RUN_ID SyntheticFixture SOURCE_REF WORKLOAD_REF tokens 16000 12000
```

Use `LocalObservation` only for an actual operator-declared local observation;
these example numbers are synthetic. The command reads at most 32 MiB, rejects
unknown raw-run fields and duplicate IDs, and invokes the same recorded-evidence
constructor and strict validator as the UI. Save stdout as a JSON file, then
choose it in **Benchmark evidence file**. Model/runtime/hardware/concurrency and
every sample come from the selected recorded run. No memory or origin defaults
are supplied. The exporter and UI preserve the same snapshot/run identities.

`cmd/capacity-plan` shares exactly the browser core and has no HTTP/client import:

```
moon run cmd/capacity-plan --target native -- prepare tests/fixtures/capacity-input.v1.json
moon run cmd/capacity-plan --target native -- reopen saved-capacity-plan.json
moon run cmd/capacity-plan --target native -- summary saved-capacity-plan.json > comparison.csv
moon run cmd/capacity-plan --target native -- samples saved-capacity-plan.json synthetic-concurrency-4 all latency > samples.csv
moon run cmd/capacity-plan --target native -- samples saved-capacity-plan.json synthetic-concurrency-4 failed queue > failures.csv
moon run cmd/capacity-plan --target native -- analyze baseline.json BASELINE_RUN candidate.json CANDIDATE_RUN > change.json
moon run cmd/capacity-plan --target native -- review change.json > change.txt
moon run cmd/capacity-plan --target native -- reopen-analysis change.json > verified-change.json
```

`prepare` and `reopen` print the verified packet to stdout. Save that output as JSON using
the host's normal output redirection. `tests/fixtures/capacity-evidence.v1.json`
is a directly importable console example; `capacity-input.v1.json` is its explicit
objective/workload input. Both are clearly synthetic, use fictitious fixture
hardware and pinned fixture digests, and must not be treated as capacity evidence
for a real cluster.

`summary` and `samples` reopen and recompute the packet before exporting CSV;
they reject altered recommendations. `samples` requires an exact run ID and
accepts `all` (default) or `failed`, then `recorded` (default), `latency` or
`queue`. It exports all matching rows, with no CLI pagination. An empty failed
filter produces a header-only CSV. Every command bounds the file to 16 MiB
before reading, decodes strict UTF-8 and applies the existing 4 Mi-character
packet limit. There are no network/client imports or controller writes.
Invalid commands, missing runs and changed packets exit nonzero with diagnostics
on stderr, leaving redirected CSV stdout empty.

`analyze` verifies both packets and selects exact run IDs independently; IDs may
be the same across two snapshots. `review` and `reopen-analysis` recompute every
result and content identity from the analysis JSON before producing output.
Change-analysis files have a 32 MiB byte / 8 Mi-character limit to accommodate
two selected runs; original packet limits stay unchanged. Invalid analyses,
missing runs and incompatible workloads leave stdout empty and exit nonzero.

For a complete invented runtime-review example, prepare
`tests/fixtures/benchmark-change-baseline.v1.json` and
`tests/fixtures/benchmark-change-candidate.v1.json`, then analyze run IDs
`synthetic-runtime-v1` and `synthetic-runtime-v2`. Each contains 24 synthetic
samples. The candidate's p95 improves from 310 to 245 ms and peak memory falls
by 4096 MiB, while throughput falls from 400 to 320 tokens/s. It therefore fails
the fixed baseline 350 tokens/s objective even though its own relaxed
300 tokens/s objective passed. These are fictitious measurements, not evidence
of actual GPU/runtime performance.

## Verification boundary

Core native/JS fixture tests, Rabbita reducer/render tests and console host source
tests cover the workflow. A native fixture records observations using production
FileTelemetry, reopens its store, serializes the exact payload expression used
by GET /v1/telemetry, and passes that wire through the production console decoder,
selection, missing-metadata form, packet preparation and reopening. An actual
native producer export is imported through the same UI file reducer and yields
the identical packet, including the one-failure-in-1001 zero-target failure.
These are not execution of the full API server/auth middleware, live-browser,
accessibility, live-provider,
physical-cluster or commercial qualification. The download control's actual
browser file-save behavior remains a browser-acceptance gate.
