///|
/// Event identity joins an unpriced observation to its later charge. Adjustments
/// have independent ledger identities and never replace their original charge.
pub(all) struct UsageChange {
  identity_kind : String
  identity : String
  status : String
  before : UsageReportRow?
  after : UsageReportRow?
} derive(ToJson)

///|
pub extend UsageChange with ToJson::{to_json}

///|
pub(all) struct UsageChanges {
  query : UsageQuery
  baseline_row_count : Int
  candidate_row_count : Int
  unchanged_count : Int
  changes : Array[UsageChange]
}

///|
fn usage_change_identity(row : UsageReportRow) -> (String, String) {
  if row.kind == "charge" || row.kind == "unpriced_usage" {
    ("event", row.event_id)
  } else {
    ("ledger", row.entry_id)
  }
}

///|
fn usage_change_key(row : UsageReportRow) -> String {
  let (kind, identity) = usage_change_identity(row)
  [kind, identity].to_json().stringify()
}

///|
/// Compare two saved snapshots under exactly the same query. This reports view
/// differences, not deletion, settlement, approval or authenticity evidence.
pub fn compare_usage_snapshots(
  baseline : CommercialSnapshot,
  candidate : CommercialSnapshot,
  query : UsageQuery,
) -> UsageChanges raise CommercialError {
  let before = explore_usage(baseline, query)
  let after = explore_usage(candidate, query)
  let previous : Map[String, UsageReportRow] = Map([])
  let current : Map[String, UsageReportRow] = Map([])
  for row in before.rows {
    previous[usage_change_key(row)] = row
  }
  for row in after.rows {
    current[usage_change_key(row)] = row
  }
  let changes : Array[UsageChange] = []
  let mut unchanged_count = 0
  for key, row in previous {
    let next = current.get(key)
    if next == Some(row) {
      unchanged_count += 1
      continue
    }
    let (identity_kind, identity) = usage_change_identity(row)
    changes.push({
      identity_kind,
      identity,
      status: if next is Some(_) {
        "changed"
      } else {
        "removed"
      },
      before: Some(row),
      after: next,
    })
  }
  for key, row in current {
    if previous.contains(key) {
      continue
    }
    let (identity_kind, identity) = usage_change_identity(row)
    changes.push({
      identity_kind,
      identity,
      status: "added",
      before: None,
      after: Some(row),
    })
  }
  changes.sort_by((a, b) => {
    let by_kind = a.identity_kind.compare(b.identity_kind)
    if by_kind != 0 {
      by_kind
    } else {
      a.identity.compare(b.identity)
    }
  })
  {
    query,
    baseline_row_count: before.rows.length(),
    candidate_row_count: after.rows.length(),
    unchanged_count,
    changes,
  }
}

///|
fn usage_change_row_json(row : UsageReportRow?) -> Json {
  match row {
    None => Json::null()
    Some(row) => {
      let json = row.to_json()
      if json is Object(fields) {
        fields["amount"] = row.amount
          .map(value => value.to_json())
          .unwrap_or(Json::null())
      }
      json
    }
  }
}

///|
pub fn UsageChanges::json_text(self : UsageChanges) -> String {
  let changes = self.changes.map(change => {
    let json = ToJson::to_json(change)
    if json is Object(fields) {
      fields["before"] = usage_change_row_json(change.before)
      fields["after"] = usage_change_row_json(change.after)
    }
    json
  })
  let json : Json = {
    "schema_version": "lunanexa.usage-changes.v1",
    "window_policy": "intersecting records in full; no proration",
    "query": self.query.to_json(),
    "baseline_row_count": self.baseline_row_count.to_json(),
    "candidate_row_count": self.candidate_row_count.to_json(),
    "unchanged_count": self.unchanged_count.to_json(),
    "changes": changes.to_json(),
  }
  json.stringify(indent=2)
}

///|
/// One record per present side, including the complete joined row as JSON.
/// Unknown money remains empty; it is never converted into numeric zero.
pub fn UsageChanges::rows_csv(self : UsageChanges) -> String {
  let output = StringBuilder()
  output.write_string(
    "organization_id,window_start_unix_ms,window_end_unix_ms,identity_kind,identity,status,side,kind,entry_id,minor_units,currency,scale,row_json\n",
  )
  for change in self.changes {
    for (side, row) in [("before", change.before), ("after", change.after)] {
      if row is Some(row) {
        let cells = usage_query_cells(self.query)
        cells.append(
          [
            change.identity_kind,
            change.identity,
            change.status,
            side,
            row.kind,
            row.entry_id,
          ].map(csv_cell),
        )
        cells.append(usage_amount_cells(row.amount))
        cells.push(csv_cell(usage_change_row_json(Some(row)).stringify()))
        output.write_string(cells.join(","))
        output.write_char('\n')
      }
    }
  }
  output.to_string()
}
