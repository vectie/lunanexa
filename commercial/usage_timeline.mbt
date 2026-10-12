///|
/// Fixed-width intervals anchored to the selected window, not calendar periods.
pub(all) struct UsageTimeBucket {
  started_unix_ms : Int64
  ended_unix_ms : Int64
  crossing_bucket_count : Int
  report : UsageReport
}

///|
pub(all) struct UsageTimeline {
  query : UsageQuery
  bucket_milliseconds : Int64
  buckets : Array[UsageTimeBucket]
}

///|
/// Assign each intersecting record once, by service start, clamped to the first
/// bucket when it begins before the selected window. Never prorate or duplicate
/// long intervals. Empty buckets contain no evidence, not an asserted zero bill.
pub fn explore_usage_timeline(
  snapshot : CommercialSnapshot,
  query : UsageQuery,
  bucket_milliseconds : Int64,
) -> UsageTimeline raise CommercialError {
  if bucket_milliseconds <= 0L {
    raise InvalidInput("bucket milliseconds must be positive")
  }
  let report = explore_usage(snapshot, query)
  let duration = query.ended_unix_ms - query.started_unix_ms
  let count = (duration - 1L) / bucket_milliseconds + 1L
  if count > 1000L {
    raise InvalidInput(
      "timeline supports at most 1000 buckets; increase bucket milliseconds",
    )
  }
  let rows : Array[Array[UsageReportRow]] = Array::makei(count.to_int(), _ => [])
  for row in report.rows {
    let index = if row.started_unix_ms < query.started_unix_ms {
      0
    } else {
      ((row.started_unix_ms - query.started_unix_ms) / bucket_milliseconds).to_int()
    }
    rows[index].push(row)
  }
  let buckets : Array[UsageTimeBucket] = []
  for index, selected in rows {
    let start = query.started_unix_ms + index.to_int64() * bucket_milliseconds
    let remaining = query.ended_unix_ms - start
    let end = start +
      (if remaining < bucket_milliseconds {
        remaining
      } else {
        bucket_milliseconds
      })
    buckets.push({
      started_unix_ms: start,
      ended_unix_ms: end,
      crossing_bucket_count: selected
      .filter(row => row.started_unix_ms < start || row.ended_unix_ms > end)
      .length(),
      report: {
        query,
        rows: selected,
        groups: usage_group_rows(query, selected),
      },
    })
  }
  { query, bucket_milliseconds, buckets, }
}

///|
pub fn UsageTimeline::json_text(self : UsageTimeline) -> String {
  let buckets = self.buckets.map(bucket => {
    let value : Json = {
      "started_unix_ms": bucket.started_unix_ms.to_json(),
      "ended_unix_ms": bucket.ended_unix_ms.to_json(),
      "crossing_bucket_count": bucket.crossing_bucket_count.to_json(),
      "report": bucket.report.usage_report_json(),
    }
    value
  })
  let result : Json = {
    "schema_version": "lunanexa.usage-timeline.v1",
    "assignment_policy": "service start, clamped to window start; each record once in full; no proration",
    "empty_bucket_policy": "no selected records in this saved snapshot; not proof of zero usage or cost",
    "query": self.query.to_json(),
    "bucket_milliseconds": self.bucket_milliseconds.to_json(),
    "buckets": buckets.to_json(),
  }
  result.stringify(indent=2)
}

///|
/// One row per bucket and existing accounting group. Empty buckets have an
/// explicit empty status and blank quantity/money cells. JSON includes drilldown.
pub fn UsageTimeline::summary_csv(self : UsageTimeline) -> String {
  let output = StringBuilder()
  output.write_string(
    "organization_id,assignment_policy,bucket_start_unix_ms,bucket_end_unix_ms,bucket_status,bucket_crossing_count,group_by,group_id,meter,unit,quantity,minor_units,currency,scale,row_count,ledger_entry_count,unpriced_usage_count,missing_observation_count,crossing_window_count\n",
  )
  for bucket in self.buckets {
    let prefix = [
      csv_cell(self.query.organization_id),
      "service_start_clamped_once_no_proration",
      bucket.started_unix_ms.to_string(),
      bucket.ended_unix_ms.to_string(),
    ]
    if bucket.report.groups.is_empty() {
      prefix.append(["empty", "0", csv_cell(self.query.group_by)])
      prefix.append(["", "", "", "", "", "", "", "0", "0", "0", "0", "0"])
      output.write_string(prefix.join(",") + "\n")
    } else {
      for group in bucket.report.groups {
        let cells = prefix.copy()
        cells.append([
          "observed",
          bucket.crossing_bucket_count.to_string(),
          csv_cell(self.query.group_by),
          csv_cell(group.group_id),
          csv_cell(group.meter),
          csv_cell(group.unit),
          group.quantity.to_string(),
        ])
        cells.append(usage_amount_cells(group.amount))
        cells.append([
          group.row_count.to_string(),
          group.ledger_entry_count.to_string(),
          group.unpriced_usage_count.to_string(),
          group.missing_observation_count.to_string(),
          group.crossing_window_count.to_string(),
        ])
        output.write_string(cells.join(",") + "\n")
      }
    }
  }
  output.to_string()
}
