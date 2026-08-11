///|
fn csv_cell(value : String) -> String {
  let guarded = if value.has_prefix("=") ||
    value.has_prefix("+") ||
    value.has_prefix("-") ||
    value.has_prefix("@") ||
    value.has_prefix("\t") ||
    value.has_prefix("\r") ||
    value.has_prefix("\n") {
    "'\{value}"
  } else {
    value
  }
  let escaped = guarded.replace_all(old="\"", new="\"\"")
  "\"\{escaped}\""
}

///|
fn entry_compare(left : LedgerEntry, right : LedgerEntry) -> Int {
  let by_time = left.service_started_unix_ms.compare(
    right.service_started_unix_ms,
  )
  if by_time == 0 {
    left.entry_id.compare(right.entry_id)
  } else {
    by_time
  }
}

///|
pub fn CommercialStore::export_ledger_csv(
  self : CommercialStore,
  organization_id : String,
  actor_user_id : String,
  filter_project_id : String?,
  generated_unix_ms : Int64,
) -> CommercialExport raise CommercialError {
  ignore(self.require_organization(organization_id))
  if !self.has_permission(
      organization_id,
      actor_user_id,
      ExportFinance,
      generated_unix_ms,
    ) {
    raise PermissionDenied("finance export permission required")
  }
  match filter_project_id {
    Some(project_id) =>
      ignore(self.require_project(organization_id, project_id))
    None => ()
  }
  let entries = self.entries
    .values()
    .filter(entry => {
      entry.organization_id == organization_id &&
      (filter_project_id is None || filter_project_id == Some(entry.project_id))
    })
    .to_array()
  entries.sort_by(entry_compare)
  let builder = StringBuilder()
  builder.write_string(
    "schema_version,entry_id,cost_center_id,project_id,organization_name,cost_center_name,project_name,kind,meter,quantity,unit,minor_units,currency,scale,service_started_unix_ms,service_ended_unix_ms,linked_entry_id,reason\n",
  )
  for entry in entries {
    let cells = [
      export_schema_version,
      entry.entry_id,
      entry.cost_center_id,
      entry.project_id,
      entry.organization_name_snapshot,
      entry.cost_center_name_snapshot,
      entry.project_name_snapshot,
      "\{Repr(entry.kind)}",
      entry.meter,
      entry.quantity.to_string(),
      entry.unit,
      entry.amount.minor_units.to_string(),
      entry.amount.currency,
      entry.amount.scale.to_string(),
      entry.service_started_unix_ms.to_string(),
      entry.service_ended_unix_ms.to_string(),
      entry.linked_entry_id.unwrap_or(""),
      entry.reason,
    ]
    builder.write_string(cells.map(csv_cell).join(","))
    builder.write_char('\n')
  }
  let content = builder.to_string()
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(content)),
  )
  {
    schema_version: export_schema_version,
    organization_id,
    generated_unix_ms,
    filter_project_id,
    csv_content: content,
    content_sha256: "sha256:\{digest}",
    row_count: entries.length(),
  }
}

///|
pub fn CommercialStore::snapshot(
  self : CommercialStore,
  organization_id : String,
) -> CommercialSnapshot raise CommercialError {
  ignore(self.require_organization(organization_id))
  let organizations = self.organizations
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let cost_centers = self.cost_centers
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let projects = self.projects
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let usage_observations = self.observations
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let ledger_entries = self.entries
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let finalized_periods = self.periods
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let budgets = self.budgets
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let quotas = self.quotas
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let commitments = self.commitments
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let consumptions = self.consumptions
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let agreement_templates = self.templates
    .values()
    .filter(template => {
      self.acceptances
      .values()
      .any(acceptance => {
        acceptance.organization_id == organization_id &&
        acceptance.template_id == template.template_id &&
        acceptance.template_version == template.version
      }) ||
      self.agreements
      .values()
      .any(agreement => {
        agreement.organization_id == organization_id &&
        agreement.template_id == template.template_id &&
        agreement.template_version == template.version
      })
    })
    .to_array()
  let clickwrap_acceptances = self.acceptances
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let agreements = self.agreements
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  let role_grants = self.grants
    .values()
    .filter(value => value.organization_id == organization_id)
    .to_array()
  organizations.sort_by_key(value => value.organization_id)
  cost_centers.sort_by_key(value => value.cost_center_id)
  projects.sort_by_key(value => value.project_id)
  usage_observations.sort_by_key(value => value.event_id)
  ledger_entries.sort_by(entry_compare)
  finalized_periods.sort_by_key(value => value.period_id)
  budgets.sort_by_key(value => value.budget_id)
  quotas.sort_by_key(value => value.quota_id)
  commitments.sort_by_key(value => value.commitment_id)
  consumptions.sort_by_key(value => value.consumption_id)
  agreement_templates.sort_by((left, right) => {
    template_key(left.template_id, left.version).compare(
      template_key(right.template_id, right.version),
    )
  })
  clickwrap_acceptances.sort_by_key(value => value.acceptance_id)
  agreements.sort_by_key(value => value.agreement_id)
  role_grants.sort_by_key(value => value.grant_id)
  {
    schema_version: snapshot_schema_version,
    organizations,
    cost_centers,
    projects,
    usage_observations,
    ledger_entries,
    finalized_periods,
    budgets,
    quotas,
    commitments,
    consumptions,
    agreement_templates,
    clickwrap_acceptances,
    agreements,
    role_grants,
  }
}

///|
pub fn CommercialStore::summary(
  self : CommercialStore,
  organization_id : String,
  currency : String,
  scale : Int,
  now_unix_ms : Int64,
) -> CommercialSummary raise CommercialError {
  let snapshot = self.snapshot(organization_id)
  let mut provisional_total = money(0L, currency, scale)
  for entry in snapshot.ledger_entries {
    provisional_total = provisional_total.add(entry.amount)
  }
  let active_budget_count = snapshot.budgets
    .filter(budget => {
      now_unix_ms >= budget.effective_from_unix_ms &&
      now_unix_ms < budget.effective_until_unix_ms
    })
    .length()
  let active_commitment_count = snapshot.commitments
    .filter(commitment => {
      (commitment.state == Approved || commitment.state == ActiveCommitment) &&
      now_unix_ms >= commitment.effective_from_unix_ms &&
      now_unix_ms < commitment.effective_until_unix_ms
    })
    .length()
  let pending_agreement_count = snapshot.agreements
    .filter(agreement => {
      agreement.state != Executed &&
      agreement.state != Declined &&
      agreement.state != ExpiredAgreement &&
      agreement.state != Voided &&
      agreement.state != SupersededAgreement
    })
    .length()
  let executed_agreement_count = snapshot.agreements
    .filter(agreement => agreement.state == Executed)
    .length()
  {
    organization_id,
    organization_count: snapshot.organizations.length(),
    cost_center_count: snapshot.cost_centers.length(),
    project_count: snapshot.projects.length(),
    usage_event_count: snapshot.usage_observations.length(),
    ledger_entry_count: snapshot.ledger_entries.length(),
    finalized_period_count: snapshot.finalized_periods.length(),
    active_budget_count,
    active_commitment_count,
    pending_agreement_count,
    executed_agreement_count,
    provisional_total,
  }
}
