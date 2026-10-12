# Reproducible capacity planning

`import_evidence` validates complete benchmark records. `prepare` validates an
explicit objective/workload and returns an input-addressed packet whose choices
use the existing benchmark algorithms. `Packet::export_json` and `reopen` retain
and recheck the exact typed inputs and computed results. These APIs are pure and
portable across native and JavaScript; they never allocate infrastructure.

`preview_csv` exposes bounded headers and the first five records of ordinary
comma-separated observation data. `import_csv` maps all eight raw metrics using
an explicit `CsvImportSpec`, validates every row and returns the same `Evidence`
used above. `import_csv_spec` strictly reopens the versioned mapping/context JSON.
No missing value, unit, origin or run identity is inferred; extra columns are
omitted. This intake complements the existing CSV report exports, which are not
a general raw-data interchange format. See `docs/CAPACITY_PLANNING.md` for the
file workflow, integer units, bounds and reproducibility limits.

`explore_samples(evidence, failed_only, order)` returns independent indexed rows
in `RecordedOrder`, `SlowestLatency`, or `LongestQueue` order. Original one-based
indices survive filtering and ties. `samples_csv` exports that full filtered
view, while `Packet::summary_csv` verifies the packet and exports one comparison
row per run. Neither changes the raw samples or full-run objective. CSV is a
spreadsheet projection; JSON remains the exact reopenable representation.

`compare_packet_runs` verifies two saved packets, selects one run from each and
compares them using the baseline packet's objective and minimum concurrency.
`analyze_change` accepts the equivalent explicit `ChangeInput`. Runtime, model,
hardware and concurrency may change while workload, profile, kind, unit and
origin remain equal. `ChangeReport::export_json` retains both complete runs;
`reopen_change` recomputes every result, and `summary_text` renders a readable
projection. Metrics expose absolute and relative deltas; exact failure fractions
and a fixed objective keep tradeoffs visible without choosing a winner.

Empty evidence is an error, rather than an invented capacity estimate:

```mbt check
///|
test "empty evidence does not become a capacity estimate" {
  let rejected = try {
    let _ = @planning.import_evidence("[]")
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
```

The complete synthetic input and console-import examples are in
`tests/fixtures/capacity-input.v1.json` and
`tests/fixtures/capacity-evidence.v1.json`; see
`docs/CAPACITY_PLANNING.md` for authoring, the CLI and the interpretation limits.
