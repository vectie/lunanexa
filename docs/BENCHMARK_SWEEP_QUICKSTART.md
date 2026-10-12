# Explore repeated benchmark concurrency sweeps

Use the offline `capacity-plan` executable to answer: which tested concurrency
levels have observations, how much did their repeated runs vary, and which
repeats missed the declared objective? Start with any existing verified planning
packet. No extra plan is required just to explore it.

```sh
$CAPACITY_PLAN sweep saved-packet.json > observed-sweep.json
$CAPACITY_PLAN sweep-csv saved-packet.json > observed-sweep.csv
```

`CAPACITY_PLAN` is the native `cmd/capacity-plan` executable built under your
external target directory with the pinned graph. These commands read local
files and write stdout only. They do not run measurements, contact a controller
or provider, allocate capacity, change telemetry, or issue an approval.

## Complete input-to-output example

The committed example is entirely invented. Its values are software fixtures,
not GPU, runtime or provider performance measurements.

```sh
$CAPACITY_PLAN prepare tests/fixtures/benchmark-sweep-input.synthetic.json > sweep-packet.json
$CAPACITY_PLAN sweep sweep-packet.json tests/fixtures/benchmark-sweep-plan.v1.json > sweep.json
$CAPACITY_PLAN sweep-csv sweep-packet.json tests/fixtures/benchmark-sweep-plan.v1.json > sweep.csv
$CAPACITY_PLAN samples sweep-packet.json synthetic-repeat-b failed queue > failed-samples.csv
```

The example includes two repeats at concurrency 4 / 16000 MiB, one observed
repeat at concurrency 2 / 16000 MiB, and a separate concurrency 4 / 32000 MiB
observation. Its optional plan expects two repeats each at 2, 4 and 8 / 16000 MiB.
The resulting rows, sorted by concurrency then total memory, show:

- 2 / 16000 MiB: incomplete, one observed repeat and one missing
- 4 / 16000 MiB: complete coverage, but only one of two repeats meets the objective;
  the failed repeat remains present, and per-run p95 latency ranges from 30 to 90 ms
- 4 / 32000 MiB: unplanned, retained as its own environment group
- 8 / 16000 MiB: missing, with no observations or metric ranges

The failed repeat is visible in `groups[].runs`, including its exact failed count,
summary, source reference and raw-observation hash. Use the existing `samples`
command with that run ID to inspect every failed observation. The sweep never
filters failed samples or removes an unsuccessful repeat.

## Optional coverage targets

A version-1 plan contains only `schema_version` and `targets`. Each target has
`tested_concurrency`, `memory_total_mib`, and `expected_repeats`. For example:

```json
{
  "schema_version": 1,
  "targets": [
    { "tested_concurrency": 4, "memory_total_mib": 16000, "expected_repeats": 2 },
    { "tested_concurrency": 8, "memory_total_mib": 16000, "expected_repeats": 2 }
  ]
}
```

Omit the plan, or use an empty targets array, to inspect all observed groups
with `coverage: "unspecified"`. The tool does not invent intended levels or
expected repetitions. With a nonempty plan:

- `missing`: a planned group has no observed run
- `incomplete`: the observed count is below its expected count
- `complete`: the count is at least the declared target, including extra repeats
- `unplanned`: observations exist at a concurrency/memory pair absent from the plan

Coverage is separate from objective success. “Complete” does not mean all runs
passed, the workload completed successfully, or the measurements establish safe
production capacity. A failed observed run still counts as an observed repeat.
An interrupted capture with no valid raw observations cannot be reconstructed;
its planned group stays missing/incomplete. This format does not identify which
absent repeat failed to start, ended early or was simply not selected.

Plans accept up to eight unique concurrency/total-memory targets. Concurrency
must be 1–1024, total memory positive, and expected repeats 1–8. Unknown fields,
invalid values and duplicate target pairs fail the command. Plan text is limited
to 64 Ki characters, within the existing bounded file reader. Existing packets
remain limited to eight selected runs, 10000 samples per run, 16 MiB file bytes
and 4 Mi characters. Coverage describes only the supplied selection. Keep the
source captures to determine whether any runs were omitted.

## Comparability and interpretation

The command reopens the saved packet and recomputes its identity and choices.
The existing packet contract requires exact profile, model digest, runtime
digest, hardware profile, benchmark kind, workload/dataset revision and output
unit, with a common declared origin. Use separate packets for changed runtime,
hardware or workload configurations; the existing two-run `analyze` workflow
can compare such changes explicitly. The hardware profile must identify its
actual driver/topology/environment revision; a matching label cannot prove that
the external environment was unchanged.

Within one packet, total-memory values may differ. A different measured total
memory gets a separate group, even at the same concurrency. No group silently
combines these environments. The JSON repeats the common context/objective and
retains the complete per-run summaries and source identities. Each range is the
minimum/maximum of independently computed per-run statistics, never a pooled
percentile, an average of percentiles, confidence interval, or statistical test.
Different sample counts remain visible. Failed/total counts are exact; the
legacy rounded per-mille summary is not used to disguise small failure rates.

Throughput retains the existing sum(output units) / sum(sample durations)
meaning within each run, in integer output units/second. It is not aggregate
wall-clock or fleet throughput. The output makes no causal claim, chooses no
winner or recommended production capacity, and does not extrapolate to untested
levels. No model-output quality, SLA or independent measurement authentication
is established. `SyntheticFixture` and `LocalObservation` keep their existing
operator-declared meanings; importing local observations does not certify them.

## Files, traceability and errors

The JSON is a projection with schema `lunanexa.benchmark-sweep.v1`, the exact
source `packet_id`, the supplied plan, common context and sorted groups. Save
the original packet and plan to preserve raw samples and reproduce the report;
the projection itself is not a reopenable capacity packet. CSV is one row per
group with context, objectives, coverage, counts and per-run-statistic ranges.
Its final three columns are quoted JSON arrays of ordered run IDs, source
references and observation hashes. Their positions correspond to one another.

Missing groups have zero observed/sample counts but no measured statistics:
CSV metric cells are empty and JSON `ranges`/`runs` are empty arrays. An omitted
repeat target has null expected/missing counts in JSON and blank CSV cells.
Do not treat an empty metric cell as zero or a zero observed failure count with
zero samples as success. CSV uses UTF-8, CRLF and the existing quoting/formula
protection. Use JSON for exact metadata; import spreadsheet text columns as text.

Every command validates all inputs before writing output. Changed packet
identity/results, invalid plans, unreadable files or invalid UTF-8 exit nonzero,
write a diagnostic to stderr and leave stdout empty. The source files are never
rewritten. Repeating a command with identical packet and plan bytes produces
identical output. Editing a plan changes only the report; it never edits the
packet or executes a benchmark.
