///|
/// One-based position in the supplied capture list. The digest identifies the
/// typed canonical snapshot, not its original whitespace or a trusted signature.
pub(all) struct UsageCaptureSource {
  source_index : Int
  snapshot_sha256 : String
  selected_row_count : Int
  usage_count : Int
  ledger_count : Int
} derive(ToJson)

///|
pub extend UsageCaptureSource with ToJson::{to_json}

///|
pub(all) struct UsageRowSources {
  event_id : String
  entry_id : String
  observation_sources : Array[Int]
  ledger_sources : Array[Int]
} derive(ToJson)

///|
pub extend UsageRowSources with ToJson::{to_json}

///|
pub(all) struct UsageConsolidation {
  report : UsageReport
  sources : Array[UsageCaptureSource]
  row_sources : Array[UsageRowSources]
  unique_usage_count : Int
  unique_ledger_count : Int
  duplicate_usage_count : Int
  duplicate_ledger_count : Int
}

///|
fn[T : Eq] consolidate_record(
  records : Map[String, T],
  key : String,
  value : T,
  kind : String,
  source_index : Int,
) -> Unit raise CommercialError {
  match records.get(key) {
    Some(previous) =>
      if previous != value {
        raise InvalidInput(
          "conflicting \{kind} identity \{key} in source \{source_index}; compare the captures before combining",
        )
      }
    None => {
      if records.length() >= 20000 {
        raise InvalidInput("combined \{kind} collection exceeds 20000 records")
      }
      records[key] = value
    }
  }
}

///|
fn record_source(
  sources : Map[String, Array[Int]],
  identity : String,
  index : Int,
) -> Unit {
  match sources.get(identity) {
    Some(indices) => indices.push(index)
    None => sources[identity] = [index]
  }
}

///|
/// Combine compatible partial captures before joining observations to charges.
/// Equal identities count once; conflicting identities fail without choosing a
/// newest capture. Sources must independently satisfy ordinary usage validation.
/// This creates a report only, never a restorable commercial snapshot.
pub fn consolidate_usage(
  snapshots : Array[CommercialSnapshot],
  query : UsageQuery,
) -> UsageConsolidation raise CommercialError {
  if snapshots.is_empty() || snapshots.length() > 8 {
    raise InvalidInput("usage consolidation requires 1 to 8 snapshots")
  }
  let centers : Map[String, CostCenter] = Map([])
  let projects : Map[String, Project] = Map([])
  let observations : Map[String, UsageObservation] = Map([])
  let entries : Map[String, LedgerEntry] = Map([])
  let observation_sources : Map[String, Array[Int]] = Map([])
  let ledger_sources : Map[String, Array[Int]] = Map([])
  let sources : Array[UsageCaptureSource] = []
  let mut total_usage = 0
  let mut total_ledger = 0
  for index, snapshot in snapshots {
    let source_index = index + 1
    let selected = explore_usage(snapshot, query) catch {
      InvalidInput(message) =>
        raise InvalidInput("source \{source_index}: \{message}")
      error => raise error
    }
    for center in snapshot.cost_centers {
      if center.organization_id == query.organization_id {
        consolidate_record(
          centers,
          center.cost_center_id,
          center,
          "cost center",
          source_index,
        )
      }
    }
    for project in snapshot.projects {
      if project.organization_id == query.organization_id {
        consolidate_record(
          projects,
          project.project_id,
          project,
          "project",
          source_index,
        )
      }
    }
    let mut usage_count = 0
    let mut ledger_count = 0
    for observation in snapshot.usage_observations {
      if observation.organization_id == query.organization_id {
        consolidate_record(
          observations,
          observation.event_id,
          observation,
          "usage event",
          source_index,
        )
        record_source(observation_sources, observation.event_id, source_index)
        usage_count += 1
      }
    }
    for entry in snapshot.ledger_entries {
      if entry.organization_id == query.organization_id {
        consolidate_record(
          entries,
          entry.entry_id,
          entry,
          "ledger entry",
          source_index,
        )
        record_source(ledger_sources, entry.entry_id, source_index)
        ledger_count += 1
      }
    }
    total_usage += usage_count
    total_ledger += ledger_count
    sources.push({
      source_index,
      snapshot_sha256: "sha256:" +
      @crypto.bytes_to_hex_string(
        @crypto.sha256(@utf8.encode(snapshot.to_json().stringify())),
      ),
      selected_row_count: selected.rows.length(),
      usage_count,
      ledger_count,
    })
  }
  // The existing join revalidates cross-capture associations, charge uniqueness,
  // exact arithmetic, window selection and money dimensions after deduplication.
  let combined = {
    ..snapshots[0],
    cost_centers: centers.values().to_array(),
    projects: projects.values().to_array(),
    usage_observations: observations.values().to_array(),
    ledger_entries: entries.values().to_array(),
  }
  let report = explore_usage(combined, query)
  let row_sources = report.rows.map(row => UsageRowSources::{
    event_id: row.event_id,
    entry_id: row.entry_id,
    observation_sources: if row.kind == "charge" || row.kind == "unpriced_usage" {
      observation_sources.get(row.event_id).unwrap_or([]).copy()
    } else {
      []
    },
    ledger_sources: ledger_sources.get(row.entry_id).unwrap_or([]).copy(),
  })
  {
    report,
    sources,
    row_sources,
    unique_usage_count: observations.length(),
    unique_ledger_count: entries.length(),
    duplicate_usage_count: total_usage - observations.length(),
    duplicate_ledger_count: total_ledger - entries.length(),
  }
}

///|
pub fn UsageConsolidation::json_text(self : UsageConsolidation) -> String {
  // Reuse the ordinary export's explicit null representation for unknown money.
  let report = try! @json.parse(self.report.json_text())
  let result : Json = {
    "schema_version": "lunanexa.usage-consolidation.v1",
    "interpretation": "union of supplied records, not latest state, invoice or completeness evidence",
    "sources": self.sources.to_json(),
    "unique_usage_count": self.unique_usage_count.to_json(),
    "unique_ledger_count": self.unique_ledger_count.to_json(),
    "duplicate_usage_count": self.duplicate_usage_count.to_json(),
    "duplicate_ledger_count": self.duplicate_ledger_count.to_json(),
    "row_sources": self.row_sources.to_json(),
    "report": report,
  }
  result.stringify(indent=2)
}

///|
pub fn UsageConsolidation::summary_csv(self : UsageConsolidation) -> String {
  self.report.summary_csv()
}

///|
/// One joined row plus separate observation/ledger capture indices. These are
/// positions in sources, not claims that every capture contained the full row.
pub fn UsageConsolidation::rows_csv(self : UsageConsolidation) -> String {
  let output = StringBuilder()
  output.write_string(
    "organization_id,window_start_unix_ms,window_end_unix_ms,event_id,entry_id,kind,quantity,minor_units,currency,scale,observation_sources,ledger_sources,row_json\n",
  )
  for index, row in self.report.rows {
    let provenance = self.row_sources[index]
    let cells = usage_query_cells(self.report.query)
    cells.append([row.event_id, row.entry_id, row.kind].map(csv_cell))
    cells.push(row.quantity.to_string())
    cells.append(usage_amount_cells(row.amount))
    cells.append([
      csv_cell(provenance.observation_sources.to_json().stringify()),
      csv_cell(provenance.ledger_sources.to_json().stringify()),
      csv_cell(usage_change_row_json(Some(row)).stringify()),
    ])
    output.write_string(cells.join(","))
    output.write_char('\n')
  }
  output.to_string()
}
