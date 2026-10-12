# Reconcile external references with saved usage and costs

A billing viewer can import an editable list of expected usage events, assign
several events to one opaque invoice/project/task reference, inspect each
reference's recorded costs, and find expected events that have no selected row.
`cmd/usage-report` adds `correlate-json`, `correlate-rows` and
`correlate-summary`. It only reads local files and writes stdout.

This fills the saved-record exploration part of PRD LUNANEXA-R03's external
cost-correlation direction. An association is supplied by the analyst. It is
not a verified provider receipt, an accepted invoice, a payment instruction,
proof of model delivery, or production MoonGate integration. No application
schema, source dependency, placement authority or remote call is introduced.

## Run the retained synthetic example

Build with the delivered BUILD.md and use its private environment:

```sh
. /workspace/scratch/665adc5202cf/.moonsuite-background/r386-390/work/r389-lunanexa/environment.sh
flock "$MOON_NATIVE_LOCK" "$USAGE_REPORT_EXE" correlate-json \
  "$USAGE_REPORT_FIXTURES/usage-snapshot.synthetic.json" \
  "$USAGE_REPORT_FIXTURES/usage-query.synthetic.json" \
  "$USAGE_REPORT_FIXTURES/usage-correlation.synthetic.json"
flock "$MOON_NATIVE_LOCK" "$USAGE_REPORT_EXE" correlate-rows \
  "$USAGE_REPORT_FIXTURES/usage-snapshot.synthetic.json" \
  "$USAGE_REPORT_FIXTURES/usage-query.synthetic.json" \
  "$USAGE_REPORT_FIXTURES/usage-correlation.synthetic.json"
flock "$MOON_NATIVE_LOCK" "$USAGE_REPORT_EXE" correlate-summary \
  "$USAGE_REPORT_FIXTURES/usage-snapshot.synthetic.json" \
  "$USAGE_REPORT_FIXTURES/usage-query.synthetic.json" \
  "$USAGE_REPORT_FIXTURES/usage-correlation.synthetic.json"
```

Redirect stdout only to a new export filename. Redirecting onto an input would
truncate it before the executable can read it. Keep inputs and exports in your
authorized private storage. The supplied data is invented, not a customer bill.

The fixture maps two original events to `invoice:2026-10-research`. That
reference receives the 12,000 CNY-minor-unit charge and its -2,000 credit under
project-inference, and a 6,000 charge under project-batch. The query groups by
project, so those are two groups; use `group_by: "cost-center"` in a copied
query to see their combined 16,000 minor units. Currency and scale remain CNY/2.
`task:eval-42` has 300 units of unpriced usage, with unknown money.
`task:eval-43` has an expected event but no selected row, and no numeric total.
The genuine zero-price charge remains unassigned until you add its event to a
reference. One repeated identical link is reported as a duplicate and adds no
rows or money. JSON `duplicate_link_count` is 1.

## Prepare and edit the manifest

Use the already authorized commercial snapshot and query described in
[the usage explorer](USAGE_EXPLORER_QUICKSTART.md). No login or snapshot fetching
is performed. Copy the manifest fixture and edit only these fields:

```json
{
  "schema_version": "lunanexa.usage-correlation-manifest.v1",
  "organization_id": "org-example",
  "links": [
    {"external_ref":"invoice:2026-10-research","project_id":"project-inference","event_id":"usage-one"},
    {"external_ref":"invoice:2026-10-research","project_id":"project-batch","event_id":"usage-two"},
    {"external_ref":"task:eval-43","project_id":"project-batch","event_id":"usage-awaiting-capture"}
  ]
}
```

Use exact original usage event IDs, available as `event_id` for a charge or
unpriced row in the existing explorer; these are `source_event_id` on source
ledger charges. Do not use a workload ID, ledger entry ID or adjustment event.
The project must exist in the selected organization. An event already found in
that organization must agree with its recorded project. A future/absent event
can be listed, but no evidence is synthesized for it.

External references are opaque labels: 1–160 ASCII letters/digits or `- _ : . @`.
Event IDs use the same bound. Put no credentials, personal details or domain
payloads in labels. Many distinct events may share a reference; one event may
have only one reference. Repeating the same exact link is harmless and counted;
a conflicting assignment fails the entire command. Other fields are rejected,
including authority claims. A manifest conveys no permission or placement.

Save a new copy, rerun, and compare the outputs. For example, add
`{"external_ref":"invoice:free-trial","project_id":"project-inference","event_id":"usage-zero-not-in-export"}`
to assign the actual zero-price charge. The retained native CLI test performs
this edit, reopens it twice, and verifies identical output and untouched inputs.

## Interpret the outputs

- JSON has one `references` element per distinct label, sorted lexically.
  Each has per-event link status, selected row count, stable `source_row_ids`
  (`ledger:<entry_id>` or `usage:<event_id>`), and the existing full report with
  grouped totals and traceable rows. `unassigned` is another full report.
- Every selected original row appears in exactly one reference report or in
  `unassigned`. A charge and observation remain one row. A credit/debit/adjustment
  follows its linked original charge's event even if that charge lies outside
  this query window. Its original adjustment event, linked charge ID, timestamps
  and amount remain intact. Quantities are not duplicated from the charge.
- `not_observed_in_selection` means no selected row was found. The source may be
  incomplete, the event may be absent, or query project/meter/time filters may
  exclude it. It does not prove zero cost, non-execution, invalidity or nonpayment.
  Such references have no groups or fabricated amount. A reference can contain
  both matched and unresolved links; inspect the links as well as the totals.
- `correlate-rows` includes assigned and unassigned rows plus blank evidence
  rows for every unresolved link. Assigned CSV rows include the correlation
  event ID and the original source event ID so linked adjustments are traceable.
- `correlate-summary` preserves the query's project/cost-center/meter grouping.
  It includes a separate unresolved row for each reference with missing links.
  `missing_link_count` is a reference count repeated on each of that reference's
  summary rows: do not sum it across groups. Use JSON links or drilldown CSV for
  the individual missing event identities.
- Unit, meter, currency, scale and unpriced status remain separate groups. Money
  uses exact signed 64-bit minor units. Unknown money is JSON null/blank CSV;
  a recorded numeric zero stays zero. No conversion, repricing or proration.
- Service-interval overlap selects complete rows, with crossing-window flags.
  Do not sum overlapping queries without event/entry deduplication. Recorded
  times, pricing basis, project labels and missing-observation counts are kept.
- CSV quotes and escapes text, including spreadsheet formula-prefix protection.
  Spreadsheet apps may round integers longer than 15 digits: import these
  columns as text or use JSON for exact precision.

## Limits and failures

Manifest limits: 1 MiB file bytes, 512 Ki UTF-16 characters, 2000 input links
(including duplicates). Snapshot/query limits and validation remain unchanged:
16 MiB snapshot bytes/8 Mi characters, 16 KiB query bytes, at most 20,000 rows per
commercial collection. Empty links are allowed and leave all rows unassigned.

All validation and calculation precede stdout. Invalid JSON, unsupported fields,
conflicting links, wrong organization/project, adjustment event references,
invalid snapshot/window, arithmetic overflow and missing files exit nonzero
with empty stdout. Diagnostics go to stderr and may include local paths.

Exports omit node/actor identities and legal profiles but include organization,
project, workload/event IDs and your external labels. They remain private.
This workflow does not change a ledger, confirm a commercial event, rate usage,
create an invoice, grant access or satisfy physical/provider acceptance gates.
