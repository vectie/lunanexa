# Explore when saved usage and cost occurred

R369 adds `timeline-json` and `timeline-summary` to LunaNexa's native
`cmd/usage-report`. A billing viewer can turn an already authorized commercial
snapshot into time buckets, inspect daily or hourly cost patterns, and drill down
from a bucket to the existing charge, credit, and unpriced usage records.

The prior explorer only grouped across the whole window. Snapshot comparison,
capture consolidation and candidate-rate pricing remain separate existing tools.
This workflow does not need live API, payment, model, node or GPU access.

## Run the complete synthetic example

Build as described in BUILD.md, then run:

```sh
. /workspace/scratch/665adc5202cf/.moonsuite-background/r366-370/work/r369-lunanexa/environment.sh
flock "$MOON_NATIVE_LOCK" "$USAGE_REPORT_EXE" timeline-json \
  "$R/source/tests/fixtures/usage-snapshot.synthetic.json" \
  "$R/source/tests/fixtures/usage-query.synthetic.json" 86400000
flock "$MOON_NATIVE_LOCK" "$USAGE_REPORT_EXE" timeline-summary \
  "$R/source/tests/fixtures/usage-snapshot.synthetic.json" \
  "$R/source/tests/fixtures/usage-query.synthetic.json" 86400000
```

Use a new output filename to save stdout; shell redirection can truncate an
existing input before the executable opens it. The program never writes inputs.
The retained outputs are evidence/cli/timeline.json and timeline.csv. Fixtures
are invented local data, not an observed customer bill or actual model response.

For another saved snapshot, reuse the existing query format: organization_id,
started_unix_ms, ended_unix_ms, project_id, meter, group_by. Int64 timestamps
are decimal JSON strings. Empty project_id/meter selects all. group_by is
project, cost-center or meter. A query must name one existing organization and
an increasing, nonnegative half-open service window. Existing tenant selection,
record validation, exact arithmetic and privacy-minimized rows are reused.

The final CLI argument is a positive integer bucket width in milliseconds:
3600000 for hours or 86400000 for fixed 24-hour periods. At most 1000 buckets
are allowed; choose a larger width or narrower window otherwise. Widths are
fixed durations anchored to the exact query start. They are not local calendar
periods, a billing timezone, or daylight-saving-aware days. Choose the window
start explicitly; the last bucket is shortened to the window end.

## Interpret the timeline correctly

- First select records intersecting the full query window, using the existing
  explorer. Then assign each selected record exactly once to the bucket of its
  service start. A start before the window is clamped to the first bucket.
- Quantities and recorded amounts are included in full, never prorated across
  time buckets. A long-running record appears in one bucket, not every bucket
  it overlaps. This is service-start attribution, not instantaneous utilization.
- crossing_bucket_count counts rows extending outside their assigned bucket;
  it is a bucket total repeated on each of that bucket's CSV group rows. Do not
  add the repeated count across groups. Existing crossing_window_count remains
  the group's count against the original full query window.
- Credits and adjustments use their own stored service intervals, not the date
  of the original charge and not necessarily their recording timestamp. The
  JSON drilldown retains original timestamps, links and event/entry identities.
- Groups keep meter, unit, currency, money scale and unpriced status separate.
  Money is exact minor units; never combine unlike units or currencies.
  Unpriced money is JSON null or blank CSV cells. A recorded numeric zero remains
  zero. Missing observations remain explicitly counted.
- All intervals appear, including empty ones. An empty bucket means this saved
  snapshot contains no selected records assigned there. It is not proof of zero
  usage, zero cost, complete collection or an inactive service. Empty CSV rows
  have bucket_status=empty and blank quantity and money, not fabricated zeros.
- JSON includes the original query, assignment policy, bucket bounds, grouped
  totals and full existing drilldown rows. CSV labels every row with service_start_clamped_once_no_proration and includes bucket bounds and group
  totals, suitable for a spreadsheet or chart. No chart or calendar labels are
  silently guessed.

In the supplied seven-day example, the first charge starts before the window
and appears once on day one (12000 CNY minor units). Day two separates a 6000
charge and a genuine zero-price charge. Day three has 300 units of unpriced
usage; day four has a -2000 credit. The remaining three days are empty.

## Limits and failures

The input file limits are unchanged: snapshot 16 MiB bytes and 8 Mi characters,
query 16 KiB bytes; up to 20000 records per commercial collection. All validation
and aggregation finish before stdout is written. Invalid width, too many buckets,
unknown organization, invalid records, overflow, malformed JSON or missing files
exit nonzero with empty stdout and a diagnostic on stderr. Error paths may name
local files. Keep input and exports in authorized private storage.

No registration, payment, invoice, ledger mutation, rating, provisioning or
network call occurs. These are saved-record analyses, not a production billing
statement, live service health report or physical-cluster qualification.
