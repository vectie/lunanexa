# Combine saved usage captures without counting overlap twice

Use `cmd/usage-report` to allocate costs across compatible partial or overlapping
commercial snapshots that you already have permission to read. For example,
one export can contain observations while another contains their charges and
credits. The combined report joins them and counts repeated records once.

This is a union of supplied evidence, not a latest-state reconstruction. Records
absent from a later capture remain in the union. Use the existing
[change review](USAGE_CHANGES_QUICKSTART.md) to inspect changed or missing records.
The commands read local files and write stdout; they never contact a service,
restore a store, rate usage, issue an invoice, or change payment/access state.

## Run the complete synthetic example

Build `cmd/usage-report` with the pinned graph and Leaf R58 companion, using an
absolute external target directory. Set `REPORT` to that native executable.
From the source directory:

```sh
$REPORT combine-json tests/fixtures/usage-query.synthetic.json \
  tests/fixtures/usage-capture-observations.synthetic.json \
  tests/fixtures/usage-capture-ledger.synthetic.json \
  tests/fixtures/usage-capture-ledger.synthetic.json > combined.json
$REPORT combine-summary tests/fixtures/usage-query.synthetic.json \
  tests/fixtures/usage-capture-observations.synthetic.json \
  tests/fixtures/usage-capture-ledger.synthetic.json > allocation.csv
$REPORT combine-rows tests/fixtures/usage-query.synthetic.json \
  tests/fixtures/usage-capture-observations.synthetic.json \
  tests/fixtures/usage-capture-ledger.synthetic.json > rows.csv
```

The first command intentionally supplies the ledger capture twice. It reports
three unique observations, four unique ledger entries, and four duplicate ledger
occurrences. The resulting five joined rows and three allocation groups are the
same as the existing complete synthetic snapshot:

- `project-inference`: 170 accelerator-seconds and 10000 CNY minor units, scale 2,
  including a 2000-minor-unit credit
- `project-batch`: 200 accelerator-seconds and 6000 CNY minor units, scale 2
- `project-batch`, unpriced: 300 accelerator-seconds, with unknown money

One zero-price charge still lacks an observation. Combining captures cannot
recover records that none of them contains. All example values are invented,
not real consumption, payment, model-response or hardware evidence.

## Choose captures and a query

Pass the query first, followed by one to eight snapshot files. No manifest or
handwritten combined snapshot is needed. Use the same query format as the
[single-capture explorer](USAGE_EXPLORER_QUICKSTART.md): selected organization,
half-open service window, optional project/meter filters, and project,
cost-center or meter grouping. Each capture must independently pass the existing
usage validation, including the selected organization/project and linked-charge
checks. A fragment containing only a credit and no original charge is not a
valid standalone snapshot for this workflow.

Only records in the selected organization are combined. Within that organization:

- Observation identity is the exact, case-sensitive `event_id`.
- Ledger identity is the exact, case-sensitive `entry_id`, in a separate namespace.
- Equal records with the same identity count once, even in repeated files.
- Every field of a repeated typed observation or ledger entry must agree,
  including timing, amount, workload, hidden actor/node attribution and links.
- Repeated project/cost-center identities must also agree in every field. A
  renamed label or moved project is a conflict; the tool never chooses an older
  or newer hierarchy automatically.
- Organization legal/status records and unrelated snapshot domains are not
  merged or exported. This report cannot be restored as a commercial snapshot.

After deduplication the ordinary usage join runs again. An observation and its
charge from different captures must agree in project, meter, unit, quantity and
service interval. Two different charge IDs for the same event fail rather than
double-count. Credits/debits/adjustments keep independent identities and are
included once. The same observation seen before rating and alongside its later
charge becomes one charged row, with both sources traceable.

All selected-organization records participate in conflict checks, including
records outside the query window or filters. A narrower query cannot hide a
conflict in the supplied evidence. Select compatible exports, or inspect the
discrepancy with `changes-json` before combining. Conflicts do not prove a store
was corrupted; captures can have different scopes, labels or revisions.

## Trace the result

JSON schema `lunanexa.usage-consolidation.v1` contains:

- `report`: the ordinary `lunanexa.usage-report.v1` query, joined rows and groups
- `sources`: one-based source positions in command-line order, typed snapshot
  SHA-256, independently selected row count, and organization usage/ledger counts
- `row_sources`: one item aligned with each report row, carrying event/entry IDs
  and separate `observation_sources` and `ledger_sources` index arrays
- Unique and duplicate counts for observations and ledger entries across the
  selected organization, before window filtering

The hash identifies all known typed snapshot fields, preserving array order;
formatting and unknown JSON fields discarded by the existing importer are not
part of it. It is content identity, not authentication, capture time or authority.
Input paths, organization legal profiles and actor/node fields are not exported.
Keep the original files and their command-line order with the report. Files and
reports still contain private business identifiers; use approved storage.

`combine-summary` uses the existing allocation CSV columns. `combine-rows` emits
one row per joined record, exact quantity/money, observation and ledger source
index arrays, and the complete joined row as quoted JSON. Save JSON alongside
CSV for the source table and hashes. Empty source arrays mean that component is
absent; an adjustment does not falsely claim its linked charge's observation.

Repeating the same invocation produces identical output. Reordering compatible
captures changes source positions but leaves allocation and joined rows unchanged.
Unknown money remains JSON null/blank CSV; actual zero stays numeric zero.
Currencies, scales, meters and units are never combined or converted. Existing
signed 64-bit arithmetic rejects overflow. Interval-overlap selection includes
whole records without proration; boundary-crossing counts remain visible.
Do not sum overlapping reports again without identity-based deduplication.

## Limits and failures

Each file retains the existing 16 MiB byte and 8 Mi-character snapshot bounds;
the query is at most 16 KiB. There are at most eight captures and 20000 records
per usage, ledger, project and cost-center collection, both per capture and after
the selected-organization union. One capture is supported for a provenance-rich
report. An empty selected window produces headers and empty row/group arrays.

Invalid UTF-8/JSON, missing files, conflicts, invalid associations and overflow
exit nonzero with stderr and no partial stdout. Every capture is processed before
output starts; original files are never modified. Use fresh output filenames:
shell redirection can truncate an existing file before the executable runs.

This workflow does not establish completeness, deletion, settlement, live provider
qualification, a paid response or current access. Missing usage and money remain
unresolved. The portable `commercial.consolidate_usage` function exposes the same
core to native and JS callers; this round adds the native offline CLI workflow.
