///|
/// An analyst-supplied association, not verified receipt or payment evidence.
/// Multiple distinct usage events can share an opaque external reference.
pub(all) struct UsageCorrelationLink {
  external_ref : String
  project_id : String
  event_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UsageCorrelationManifest {
  schema_version : String
  organization_id : String
  links : Array[UsageCorrelationLink]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UsageCorrelationMatch {
  link : UsageCorrelationLink
  status : String
  row_count : Int
  source_row_ids : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct UsageCorrelationGroup {
  external_ref : String
  links : Array[UsageCorrelationMatch]
  report : UsageReport
} derive(Debug, Eq)

///|
pub(all) struct UsageCorrelationReport {
  query : UsageQuery
  duplicate_link_count : Int
  references : Array[UsageCorrelationGroup]
  unassigned : UsageReport
} derive(Debug, Eq)

///|
pub fn import_usage_correlation_manifest(
  text : String,
) -> UsageCorrelationManifest raise CommercialError {
  if text.length() > 524288 {
    raise InvalidInput("correlation manifest exceeds 512 Ki characters")
  }
  let json = @json.parse(text) catch {
    _ => raise InvalidInput("invalid correlation manifest JSON")
  }
  let manifest : UsageCorrelationManifest = @json.from_json(json) catch {
    _ => raise InvalidInput("invalid correlation manifest fields")
  }
  if manifest.to_json() != json {
    raise InvalidInput("correlation manifest contains unsupported fields")
  }
  manifest
}

///|
fn correlation_key(project_id : String, event_id : String) -> String {
  [project_id, event_id].to_json().stringify()
}

///|
fn correlation_row_id(row : UsageReportRow) -> String {
  if row.entry_id == "" {
    "usage:" + row.event_id
  } else {
    "ledger:" + row.entry_id
  }
}

///|
fn correlation_event(
  row : UsageReportRow,
  entries : Map[String, LedgerEntry],
) -> String {
  if row.linked_entry_id == "" {
    row.event_id
  } else {
    // explore_usage has already validated this same-project original charge.
    entries[row.linked_entry_id].source_event_id
  }
}

///|
fn correlation_subset(
  query : UsageQuery,
  rows : Array[UsageReportRow],
) -> UsageReport raise CommercialError {
  { query, rows, groups: usage_group_rows(query, rows), }
}

///|
/// Associate each selected row once. Adjustments follow their original charge's
/// usage event, even when that charge is outside the selected service window.
pub fn correlate_usage(
  snapshot : CommercialSnapshot,
  query : UsageQuery,
  manifest : UsageCorrelationManifest,
) -> UsageCorrelationReport raise CommercialError {
  let selected = explore_usage(snapshot, query)
  if manifest.schema_version != "lunanexa.usage-correlation-manifest.v1" ||
    manifest.organization_id != query.organization_id ||
    manifest.links.length() > 2000 {
    raise InvalidInput(
      "correlation manifest requires v1, the query organization, and at most 2000 links",
    )
  }
  let projects : Map[String, Bool] = Map([])
  for project in snapshot.projects {
    if project.organization_id == query.organization_id {
      projects[project.project_id] = true
    }
  }
  let event_projects : Map[String, String] = Map([])
  let adjustment_events : Map[String, Bool] = Map([])
  let entries : Map[String, LedgerEntry] = Map([])
  for observation in snapshot.usage_observations {
    if observation.organization_id == query.organization_id {
      event_projects[observation.event_id] = observation.project_id
    }
  }
  for entry in snapshot.ledger_entries {
    if entry.organization_id != query.organization_id {
      continue
    }
    entries[entry.entry_id] = entry
    if entry.kind == Charge {
      event_projects[entry.source_event_id] = entry.project_id
    } else {
      adjustment_events[entry.source_event_id] = true
    }
  }
  let links : Map[String, UsageCorrelationLink] = Map([])
  let mut duplicate_link_count = 0
  for link in manifest.links {
    if !safe_identifier(link.external_ref) ||
      !safe_identifier(link.event_id) ||
      !projects.contains(link.project_id) {
      raise InvalidInput(
        "correlation links require bounded opaque references, event IDs and an existing organization project",
      )
    }
    if adjustment_events.contains(link.event_id) {
      raise InvalidInput(
        "correlation links name original usage events, not adjustment events",
      )
    }
    if event_projects.get(link.event_id) is Some(project_id) &&
      project_id != link.project_id {
      raise InvalidInput("correlation event belongs to another project")
    }
    let key = correlation_key(link.project_id, link.event_id)
    if links.get(key) is Some(prior) {
      if prior != link {
        raise InvalidInput(
          "one usage event cannot belong to multiple external references",
        )
      }
      duplicate_link_count += 1
    } else {
      links[key] = link
    }
  }
  let rows_by_reference : Map[String, Array[UsageReportRow]] = Map([])
  let source_rows : Map[String, Array[String]] = Map([])
  let unassigned : Array[UsageReportRow] = []
  for row in selected.rows {
    let key = correlation_key(row.project_id, correlation_event(row, entries))
    if links.get(key) is Some(link) {
      let rows = rows_by_reference.get_or_default(link.external_ref, [])
      rows.push(row)
      rows_by_reference[link.external_ref] = rows
      let ids = source_rows.get_or_default(key, [])
      ids.push(correlation_row_id(row))
      source_rows[key] = ids
    } else {
      unassigned.push(row)
    }
  }
  let matches : Map[String, Array[UsageCorrelationMatch]] = Map([])
  let sorted_links = links.values().to_array()
  sorted_links.sort_by_key(link => {
    [link.external_ref, link.project_id, link.event_id].to_json().stringify()
  })
  for link in sorted_links {
    let source_row_ids = source_rows.get_or_default(
      correlation_key(link.project_id, link.event_id),
      [],
    )
    let row_count = source_row_ids.length()
    let values = matches.get_or_default(link.external_ref, [])
    values.push({
      link,
      row_count,
      source_row_ids,
      status: if row_count == 0 {
        "not_observed_in_selection"
      } else {
        "selected_rows"
      },
    })
    matches[link.external_ref] = values
  }
  let references : Array[UsageCorrelationGroup] = []
  for external_ref, links in matches {
    references.push({
      external_ref,
      links,
      report: correlation_subset(
        query,
        rows_by_reference.get_or_default(external_ref, []),
      ),
    })
  }
  references.sort_by((a, b) => a.external_ref.lexical_compare(b.external_ref))
  {
    query,
    duplicate_link_count,
    references,
    unassigned: correlation_subset(query, unassigned),
  }
}

///|
pub extend UsageCorrelationLink with Debug::{to_repr}

///|
pub extend UsageCorrelationLink with Eq::{not_equal, equal}

///|
pub extend UsageCorrelationLink with ToJson::{to_json}

///|
pub extend UsageCorrelationLink with FromJson::{from_json}

///|
pub extend UsageCorrelationManifest with Debug::{to_repr}

///|
pub extend UsageCorrelationManifest with Eq::{not_equal, equal}

///|
pub extend UsageCorrelationManifest with ToJson::{to_json}

///|
pub extend UsageCorrelationManifest with FromJson::{from_json}

///|
pub extend UsageCorrelationMatch with Debug::{to_repr}

///|
pub extend UsageCorrelationMatch with Eq::{not_equal, equal}

///|
pub extend UsageCorrelationMatch with ToJson::{to_json}

///|
pub extend UsageCorrelationGroup with Debug::{to_repr}

///|
pub extend UsageCorrelationGroup with Eq::{not_equal, equal}

///|
pub extend UsageCorrelationReport with Debug::{to_repr}

///|
pub extend UsageCorrelationReport with Eq::{not_equal, equal}
