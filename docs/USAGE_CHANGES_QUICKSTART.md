# Compare saved usage snapshots

Billing viewers can compare two already-authorized saved commercial snapshots
under the same organization, service window and project/meter filters. This
answers what changed in the visible usage records: a newly rated observation,
an added credit, a changed source binding, or a record absent from the later view.
The existing single-snapshot report and hypothetical candidate pricing remain
available. This command does not call a service, rate usage, alter a ledger,
approve a payment, or infer a paid model response.

Build `cmd/usage-report` with the pinned toolchain and Leaf R58 companion using
an absolute external target. Set `REPORT` to the native usage-report executable:

```sh
$REPORT changes-json baseline.json candidate.json query.json > changes.json
$REPORT changes-rows baseline.json candidate.json query.json > changes.csv
```

The query is identical to `usage-report json`: organization_id, decimal-string
started_unix_ms and ended_unix_ms, project_id and meter (empty means all), and
group_by (project, cost-center or meter). A selected organization and selected
project must be present in both snapshots. Both snapshots must independently
pass the existing usage validation before any output is written. Records
intersecting the half-open service window are included in full without proration.
Use new output filenames: shell redirection may truncate an existing file before
the program starts. Keep inputs stable while reading.

## Matching and meaning

- Charges and unpriced observations match by exact case-sensitive event_id in
  the selected organization. Rating an observation becomes one `changed` item,
  from unpriced_usage to charge. Changing the charge entry_id remains visible
  in that pair. No fuzzy matching by label, amount, workload or time occurs.
- Credits, debits and adjustments match by exact entry_id in an independent
  `ledger` identity namespace. A new credit appears separately from its charge.
  Changing a charge's event binding can produce an added event and a changed or
  removed old event, rather than concealing the binding change.
- Equality compares every field of the joined UsageReportRow, including money,
  labels, rate-card version, reason, workload, entry links, time and observation
  availability. Hidden node/actor/legal metadata is not part of this view.
- `added` and `removed` mean present in only one filtered view. They do not prove
  creation or deletion in a canonical store. A record can move outside the query
  window or filter, and different snapshot access scopes can hide observations.
  A changed money value is a discrepancy to inspect, not an approved ledger edit.
- Baseline/candidate ordering is chosen by you; no capture time is inferred.
  The output is an inspection export, not a signed or reopen-verified packet.
  Retain both source snapshots and the query alongside it for reproduction.

JSON schema `lunanexa.usage-changes.v1` includes the query, both row counts,
unchanged_count, and sorted changes. Each change has identity_kind, identity,
status, before and after. An absent side is null; an unknown amount inside a
present row is null. Known zero stays an exact money object. No difference is
calculated from an unknown amount, and currencies/scales are never converted.
Identities sort by namespace then exact ID, independent of source array order.

CSV emits one record per present before/after side, exact money columns, and the
complete joined row as quoted JSON. Embedded punctuation is escaped and cells
use the existing spreadsheet formula protection. Unchanged rows are omitted;
identical or empty views yield a header-only CSV (JSON carries the counts).

Inputs retain the existing limits: each snapshot file at most 16 MiB and 8 Mi
UTF-16 characters, query file at most 16 KiB, and at most 20000 items per usage,
ledger, project and cost-center collection. The two snapshots are validated
separately; aggregate overflow still rejects either input. Failure returns
nonzero, a diagnostic on stderr and empty stdout. No browser, physical hardware,
provider, database or production qualification is implied by this offline tool.

## Try synthetic files

Copy `tests/fixtures/usage-snapshot.synthetic.json` to baseline.json and
candidate.json. In candidate.json change the first charge's minor_units from
`12000` to `13000`, then use `tests/fixtures/usage-query.synthetic.json` as query.
The result has one changed event (`usage-one`), four unchanged rows, and both
exact amounts. These invented values are not actual usage or billing evidence.
