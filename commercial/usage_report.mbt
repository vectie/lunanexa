///|
pub fn import_usage_query(text : String) -> UsageQuery raise CommercialError {
  @json.from_json(@json.parse(text)) catch {
    error =>
      raise InvalidInput(
        "invalid usage query (64-bit values use decimal strings): \{error}",
      )
  }
}

///|
pub fn import_usage_snapshot(
  text : String,
) -> CommercialSnapshot raise CommercialError {
  if text.length() > 8388608 {
    raise InvalidInput("commercial snapshot exceeds 8 Mi characters")
  }
  @json.from_json(@json.parse(text)) catch {
    error => raise InvalidInput("invalid commercial snapshot: \{error}")
  }
}

///|
fn usage_query_selects(
  query : UsageQuery,
  project : String,
  meter : String,
  start : Int64,
  end : Int64,
) -> Bool {
  (query.project_id == "" || query.project_id == project) &&
  (query.meter == "" || query.meter == meter) &&
  start < query.ended_unix_ms &&
  end > query.started_unix_ms
}

///|
fn usage_crosses_window(query : UsageQuery, start : Int64, end : Int64) -> Bool {
  start < query.started_unix_ms || end > query.ended_unix_ms
}

///|
fn usage_group_id(query : UsageQuery, row : UsageReportRow) -> String {
  match query.group_by {
    "project" => row.project_id
    "cost-center" => row.cost_center_id
    _ => row.meter
  }
}

///|
fn usage_group_key(
  group_id : String,
  meter : String,
  unit : String,
  amount : FixedMoney?,
) -> String {
  let (currency, scale) = match amount {
    Some(value) => (value.currency, value.scale.to_string())
    None => ("", "")
  }
  [group_id, meter, unit, currency, scale].to_json().stringify()
}

///|
/// Explore a previously obtained snapshot. This function neither authorizes
/// access nor rates usage, creates invoices, or mutates a commercial store.
pub fn explore_usage(
  snapshot : CommercialSnapshot,
  query : UsageQuery,
) -> UsageReport raise CommercialError {
  if snapshot.schema_version != snapshot_schema_version {
    raise InvalidInput("unsupported commercial snapshot schema")
  }
  if !safe_identifier(query.organization_id) ||
    query.started_unix_ms < 0L ||
    query.ended_unix_ms <= query.started_unix_ms ||
    (query.project_id != "" && !safe_identifier(query.project_id)) ||
    (query.meter != "" && !safe_identifier(query.meter)) ||
    !(query.group_by == "project" ||
    query.group_by == "cost-center" ||
    query.group_by == "meter") {
    raise InvalidInput(
      "query requires an organization, increasing nonnegative window, optional project/meter, and project|cost-center|meter grouping",
    )
  }
  if snapshot.usage_observations.length() > 20000 ||
    snapshot.ledger_entries.length() > 20000 ||
    snapshot.projects.length() > 20000 ||
    snapshot.cost_centers.length() > 20000 {
    raise InvalidInput(
      "usage exploration supports at most 20000 records per collection",
    )
  }
  if snapshot.organizations
    .filter(org => org.organization_id == query.organization_id)
    .length() !=
    1 {
    raise InvalidInput(
      "query organization must occur exactly once in the snapshot",
    )
  }
  let centers : Map[String, CostCenter] = Map([])
  for center in snapshot.cost_centers {
    if center.organization_id != query.organization_id {
      continue
    }
    if centers.contains(center.cost_center_id) ||
      !safe_identifier(center.cost_center_id) {
      raise InvalidInput("duplicate or invalid cost center")
    }
    centers[center.cost_center_id] = center
  }
  let projects : Map[String, Project] = Map([])
  for project in snapshot.projects {
    if project.organization_id != query.organization_id {
      continue
    }
    if projects.contains(project.project_id) ||
      !safe_identifier(project.project_id) ||
      !centers.contains(project.cost_center_id) {
      raise InvalidInput(
        "duplicate project or missing organization cost center",
      )
    }
    projects[project.project_id] = project
  }
  if query.project_id != "" && !projects.contains(query.project_id) {
    raise InvalidInput("selected project is absent from the organization")
  }
  let observations : Map[String, UsageObservation] = Map([])
  for observation in snapshot.usage_observations {
    if observation.organization_id != query.organization_id {
      continue
    }
    if observations.contains(observation.event_id) ||
      !safe_identifier(observation.event_id) ||
      !projects.contains(observation.project_id) ||
      !safe_identifier(observation.meter) ||
      !safe_identifier(observation.unit) ||
      observation.quantity <= 0L ||
      observation.started_unix_ms < 0L ||
      observation.ended_unix_ms <= observation.started_unix_ms {
      raise InvalidInput("duplicate or invalid usage observation")
    }
    observations[observation.event_id] = observation
  }
  let entries : Map[String, LedgerEntry] = Map([])
  let charges : Map[String, LedgerEntry] = Map([])
  for entry in snapshot.ledger_entries {
    if entry.organization_id != query.organization_id {
      continue
    }
    if entries.contains(entry.entry_id) ||
      !safe_identifier(entry.entry_id) ||
      !safe_identifier(entry.source_event_id) ||
      !projects.contains(entry.project_id) ||
      !centers.contains(entry.cost_center_id) ||
      !safe_identifier(entry.meter) ||
      !safe_identifier(entry.unit) ||
      entry.quantity < 0L ||
      entry.service_started_unix_ms < 0L ||
      entry.service_ended_unix_ms <= entry.service_started_unix_ms {
      raise InvalidInput("duplicate or invalid ledger entry")
    }
    ignore(
      money(entry.amount.minor_units, entry.amount.currency, entry.amount.scale),
    )
    entries[entry.entry_id] = entry
    if entry.kind == Charge {
      if charges.contains(entry.source_event_id) ||
        entry.linked_entry_id is Some(_) ||
        entry.quantity <= 0L ||
        entry.amount.minor_units < 0L {
        raise InvalidInput("ambiguous charge for usage event")
      }
      charges[entry.source_event_id] = entry
      if observations.get(entry.source_event_id) is Some(observation) {
        if observation.project_id != entry.project_id ||
          observation.meter != entry.meter ||
          observation.unit != entry.unit ||
          observation.quantity != entry.quantity ||
          observation.started_unix_ms != entry.service_started_unix_ms ||
          observation.ended_unix_ms != entry.service_ended_unix_ms {
          raise InvalidInput("charge does not match its usage observation")
        }
      }
    }
  }
  let rows : Array[UsageReportRow] = []
  for entry in entries.values() {
    if entry.kind != Charge {
      guard entry.linked_entry_id is Some(linked_id) &&
        entries.get(linked_id) is Some(linked) &&
        linked.kind == Charge &&
        linked.project_id == entry.project_id &&
        linked.cost_center_id == entry.cost_center_id &&
        linked.meter == entry.meter &&
        linked.unit == entry.unit &&
        linked.amount.currency == entry.amount.currency &&
        linked.amount.scale == entry.amount.scale &&
        entry.quantity == 0L else {
        raise InvalidInput(
          "adjustment requires a same-project, same-unit original charge",
        )
      }
    }
    if !usage_query_selects(
        query,
        entry.project_id,
        entry.meter,
        entry.service_started_unix_ms,
        entry.service_ended_unix_ms,
      ) {
      continue
    }
    let observation = if entry.kind == Charge {
      observations.get(entry.source_event_id)
    } else {
      None
    }
    rows.push({
      cost_center_id: entry.cost_center_id,
      cost_center_name: entry.cost_center_name_snapshot,
      project_id: entry.project_id,
      project_name: entry.project_name_snapshot,
      event_id: entry.source_event_id,
      workload_id: observation.map(o => o.workload_id).unwrap_or(""),
      entry_id: entry.entry_id,
      linked_entry_id: entry.linked_entry_id.unwrap_or(""),
      kind: match entry.kind {
        Charge => "charge"
        Credit => "credit"
        Debit => "debit"
        Adjustment => "adjustment"
      },
      rate_card_id: entry.rate_card_id,
      rate_card_version: entry.rate_card_version,
      reason: entry.reason,
      meter: entry.meter,
      unit: entry.unit,
      quantity: entry.quantity,
      amount: Some(entry.amount),
      started_unix_ms: entry.service_started_unix_ms,
      ended_unix_ms: entry.service_ended_unix_ms,
      recorded_unix_ms: entry.recorded_unix_ms,
      observation_available: observation is Some(_),
      crosses_window: usage_crosses_window(
        query,
        entry.service_started_unix_ms,
        entry.service_ended_unix_ms,
      ),
    })
  }
  for observation in observations.values() {
    if charges.contains(observation.event_id) ||
      !usage_query_selects(
        query,
        observation.project_id,
        observation.meter,
        observation.started_unix_ms,
        observation.ended_unix_ms,
      ) {
      continue
    }
    let project = projects[observation.project_id]
    let center = centers[project.cost_center_id]
    rows.push({
      cost_center_id: center.cost_center_id,
      cost_center_name: center.display_name,
      project_id: project.project_id,
      project_name: project.display_name,
      event_id: observation.event_id,
      workload_id: observation.workload_id,
      entry_id: "",
      linked_entry_id: "",
      kind: "unpriced_usage",
      rate_card_id: "",
      rate_card_version: "",
      reason: "",
      meter: observation.meter,
      unit: observation.unit,
      quantity: observation.quantity,
      amount: None,
      started_unix_ms: observation.started_unix_ms,
      ended_unix_ms: observation.ended_unix_ms,
      recorded_unix_ms: observation.observed_unix_ms,
      observation_available: true,
      crosses_window: usage_crosses_window(
        query,
        observation.started_unix_ms,
        observation.ended_unix_ms,
      ),
    })
  }
  rows.sort_by((a, b) => {
    let by_time = a.started_unix_ms.compare(b.started_unix_ms)
    if by_time != 0 {
      by_time
    } else {
      let by_event = a.event_id.compare(b.event_id)
      if by_event != 0 {
        by_event
      } else {
        a.entry_id.compare(b.entry_id)
      }
    }
  })
  { query, rows, groups: usage_group_rows(query, rows), }
}

///|
fn usage_group_rows(
  query : UsageQuery,
  rows : Array[UsageReportRow],
) -> Array[UsageReportGroup] raise CommercialError {
  let grouped : Map[String, UsageReportGroup] = Map([])
  for row in rows {
    let group_id = usage_group_id(query, row)
    let key = usage_group_key(group_id, row.meter, row.unit, row.amount)
    let group = grouped
      .get(key)
      .unwrap_or({
        group_id,
        meter: row.meter,
        unit: row.unit,
        quantity: 0L,
        amount: row.amount.map(zero_like),
        row_count: 0,
        ledger_entry_count: 0,
        unpriced_usage_count: 0,
        missing_observation_count: 0,
        crossing_window_count: 0,
      })
    let amount = match (group.amount, row.amount) {
      (Some(total), Some(value)) => Some(total.add(value))
      _ => None
    }
    grouped[key] = {
      ..group,
      quantity: checked_add_int64(group.quantity, row.quantity),
      amount,
      row_count: group.row_count + 1,
      ledger_entry_count: group.ledger_entry_count +
      (if row.entry_id != "" { 1 } else { 0 }),
      unpriced_usage_count: group.unpriced_usage_count +
      (if row.amount is None { 1 } else { 0 }),
      missing_observation_count: group.missing_observation_count +
      (if row.kind == "charge" && !row.observation_available { 1 } else { 0 }),
      crossing_window_count: group.crossing_window_count +
      (if row.crosses_window { 1 } else { 0 }),
    }
  }
  let groups = grouped.values().to_array()
  groups.sort_by_key(group => {
    usage_group_key(group.group_id, group.meter, group.unit, group.amount)
  })
  groups
}
