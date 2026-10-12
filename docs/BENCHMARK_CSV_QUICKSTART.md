# Raw benchmark CSV quick start

## Try the invented sample

From the repository root, build/run the offline capacity CLI:

```text
moon run cmd/capacity-plan --target native -- import-csv tests/fixtures/benchmark-observations.synthetic.csv tests/fixtures/benchmark-csv-mapping.v1.json > imported-evidence.json
```

Open **Benchmarks → Capacity-plan workbench → Or import a complete producer
evidence file** and choose `imported-evidence.json`. Set minimum tested
concurrency **4**, maximum p95 **350 ms**, minimum throughput **350 tokens/s**
and maximum failures **0‰**. Prepare the packet. The 12 synthetic samples have
p95 **330 ms**, throughput **366 tokens/s** and **one failure**: the zero-failure
objective is not met. Inspect the failed sample, save the packet and reopen it.
These are invented numbers, not measurements of hardware.

## Import your own CSV without JSON authoring

1. Expand **Import raw benchmark CSV observations** and choose the file.
2. Inspect the preview. Map all eight metrics and check whole-millisecond,
   whole-output-unit and utilization-per-mille units. `1` means failed.
3. Fill in the run identity, explicit provenance, source/workload references,
   output unit, tested concurrency and measured total/peak memory.
4. Choose **Add / replace CSV run**, then review the objective and prepare a
   packet. A repeated run ID replaces only that run; failures retain your work.
5. Save the packet. Optionally download the mapping JSON for repeatable native
   `import-csv` use, keeping the original CSV with it.

No records are skipped or rounded. Missing metrics, decimals, malformed records
and invalid context reject the import. Bounds: one run, 1–10000 samples, 128
columns, 4 Mi characters / 16 MiB file bytes. Everything stays local to the tab
until you download it. See [the full guide](CAPACITY_PLANNING.md#import-ordinary-raw-benchmark-csv)
for quoted CSV behavior, provenance semantics and verification limits.
