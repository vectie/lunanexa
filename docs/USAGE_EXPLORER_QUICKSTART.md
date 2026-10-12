# Explore usage and allocate recorded costs

`cmd/usage-report` turns an already obtained commercial snapshot into a filtered
cost allocation and a usage/ledger drill-down. It is an offline MoonBit tool:
it reads two files and writes CSV or JSON to stdout. It does not contact a
controller, rate usage, create an invoice, or change a payment or lease.

For overlapping or complementary saved captures, use the
[consolidation workflow](USAGE_CONSOLIDATION_QUICKSTART.md) to join observations
and charges across files without counting repeated records twice.

For a separate hypothetical comparison against analyst-authored rate cards, use
the [candidate-rate workflow](USAGE_PRICE_QUICKSTART.md). It preserves recorded
charges and adjustments and labels proposed amounts and unresolved coverage.

## Try the synthetic example

From the LunaNexa module, with the repository's dependencies available:

```text
moon run cmd/usage-report --target native -- summary tests/fixtures/usage-snapshot.synthetic.json tests/fixtures/usage-query.synthetic.json > summary.csv
moon run cmd/usage-report --target native -- rows tests/fixtures/usage-snapshot.synthetic.json tests/fixtures/usage-query.synthetic.json > rows.csv
moon run cmd/usage-report --target native -- json tests/fixtures/usage-snapshot.synthetic.json tests/fixtures/usage-query.synthetic.json > report.json
```

These invented records produce three project groups:

- `project-inference`: 170 recorded accelerator-seconds and 10,000 CNY minor
  units, scale 2 (CNY 100.00), including a 2,000-minor-unit credit.
- `project-batch`: 200 recorded accelerator-seconds and 6,000 CNY minor units,
  scale 2 (CNY 60.00).
- `project-batch`, unpriced: 300 accelerator-seconds with empty money cells.

There are five drill-down rows. One charge crosses the window start, and one
zero-price charge lacks its source observation in the export. The output counts
both conditions. These are synthetic accounting examples, not real purchases,
payments, consumption measurements, or evidence of delivered service.

## Use an existing source and edit the query

Save the JSON body of a commercial snapshot you are already authorized to read:

- Operator source: `GET /v1/commercial/organizations/{organization_id}/snapshot`.
- Billing-viewer source: `GET /v1/portal/self/commercial` with the existing
  authenticated, selected-organization context. This endpoint intentionally
  removes usage observations; the report can allocate the remaining ledger and
  identifies charges whose observations are absent.

Use the existing authenticated client/session to obtain the file. The offline
tool does not grant access to either endpoint. Never copy authentication
headers or credentials into the snapshot/query. A snapshot can include private
organization and agreement details: keep the original in your approved storage.
Exports omit legal profiles, role grants, node IDs and actor references, but
retain project, event and workload identifiers, so still treat them as private.

Copy `tests/fixtures/usage-query.synthetic.json` and edit these six fields:

```json
{
  "organization_id": "org-example",
  "started_unix_ms": "1790812800000",
  "ended_unix_ms": "1791417600000",
  "project_id": "",
  "meter": "",
  "group_by": "cost-center"
}
```

This window is 2026-10-01 00:00 UTC through 2026-10-08 00:00 UTC, end exclusive.
Keep timestamps in quoted decimal strings, as in the existing MoonBit snapshot
format, so 64-bit values retain exact precision. JSON output uses this same
string representation for timestamps, quantities and money minor units.
Use `project`, `cost-center`, or `meter` grouping. Empty `project_id` and `meter`
mean all values; otherwise each is an exact identifier filter. For example,
`project_id: "project-batch"` selects that project's priced and unpriced rows.
Run `rows` with the same query to inspect any group back to its source events.
The portable functions `commercial.import_usage_snapshot`, `import_usage_query`
and `explore_usage` expose the same workflow to native and JS callers.

## Read the result correctly

- Selection uses service-interval overlap: `start < query_end` and
  `end > query_start`. Intersecting records contribute their entire recorded
  quantity and amount; there is no inferred prorating. `crosses_window` and
  `crossing_window_count` identify boundary-spanning records. Adjacent reports
  can therefore both include such a record: do not sum them without deduping
  by entry/event identity or selecting boundaries aligned to your source.
- A charge and its matching usage observation become one row. Credits, debits
  and adjustments remain separate rows at their own service intervals and
  retain `linked_entry_id`. Their quantity is zero. An original charge outside
  the query window still supports a linked adjustment inside it.
  Drill-down rows also retain the recorded time, rate-card identity/version and
  entry reason so differently priced usage can be traced to its pricing basis.
- `unpriced_usage` means no charge appears in this snapshot. It could be
  prepaid usage or incomplete rating evidence; this tool does not infer which.
  Its money is blank in CSV and `null` in JSON, never an invented zero.
- A real zero-priced ledger entry exports numeric `0`. Recorded amounts use
  exact signed 64-bit minor units and their original currency/scale. No exchange
  rates or rounding are applied. CSV money and quantity columns are numeric;
  text fields are quoted and spreadsheet formula prefixes are escaped.
  Spreadsheet applications may round integers longer than 15 digits; import
  those columns as text or use the JSON output when that precision matters.
- Groups never combine different meters, units, currencies or scales. Unpriced
  quantities have their own group. `quantity` is a sum of recorded meter units,
  not elapsed wall-clock time. It is not request/token count unless the meter
  and unit say so.
- Ledger rows retain historical project/cost-center labels. Unpriced usage
  uses the current project hierarchy in the source. Group IDs remain stable
  when display names change. Sort order is deterministic.
- This is an allocation of available records, not an invoice, a completeness
  certificate, payment reconciliation, or a recalculation of rate cards. A
  snapshot with omitted observations cannot reveal unseen unpriced usage.

The supported input is the existing `lunanexa.commercial.snapshot.v1` shape,
not a durable-snapshot wrapper or ledger CSV. The CLI accepts a 16 MiB snapshot
(8 Mi UTF-16 characters) and a 16 KiB query, with at most 20,000 observations,
entries, projects and cost centers per collection. Duplicate identities,
ambiguous joins, inconsistent source associations and arithmetic overflow fail
with a diagnostic, nonzero exit and no partial report on stdout. Other snapshot
domains are not revalidated; this tool is not a snapshot-recovery validator.
