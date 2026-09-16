///|
pub struct CommercialStore {
  mut organizations : Map[String, Organization]
  mut cost_centers : Map[String, CostCenter]
  mut projects : Map[String, Project]
  mut observations : Map[String, UsageObservation]
  mut entries : Map[String, LedgerEntry]
  mut rated_events : Map[String, String]
  mut periods : Map[String, FinalizedPeriod]
  mut budgets : Map[String, Budget]
  mut quotas : Map[String, Quota]
  mut commitments : Map[String, CapacityCommitment]
  mut consumptions : Map[String, EntitlementConsumption]
  mut templates : Map[String, AgreementTemplate]
  mut acceptances : Map[String, ClickwrapAcceptance]
  mut acceptance_keys : Map[String, String]
  mut agreements : Map[String, Agreement]
  mut signature_callbacks : Map[String, SignatureCallback]
  mut grants : Map[String, RoleGrant]
}

///|
pub fn CommercialStore::new() -> CommercialStore {
  {
    organizations: Map([]),
    cost_centers: Map([]),
    projects: Map([]),
    observations: Map([]),
    entries: Map([]),
    rated_events: Map([]),
    periods: Map([]),
    budgets: Map([]),
    quotas: Map([]),
    commitments: Map([]),
    consumptions: Map([]),
    templates: Map([]),
    acceptances: Map([]),
    acceptance_keys: Map([]),
    agreements: Map([]),
    signature_callbacks: Map([]),
    grants: Map([]),
  }
}

///|
pub fn CommercialStore::from_durable_snapshot(
  durable : CommercialDurableSnapshot,
) -> CommercialStore raise CommercialError {
  if durable.schema_version != snapshot_schema_version ||
    durable.commercial.schema_version != snapshot_schema_version {
    raise InvalidInput("unsupported commercial snapshot")
  }
  let store = CommercialStore::new()
  for value in durable.commercial.organizations {
    validate_organization(value)
    if store.organizations.contains(value.organization_id) {
      raise InvalidInput("duplicate organization")
    }
    store.organizations[value.organization_id] = value
  }
  for value in durable.commercial.cost_centers {
    if store.cost_centers.contains(value.cost_center_id) ||
      !store.organizations.contains(value.organization_id) {
      raise InvalidInput("invalid cost center snapshot")
    }
    store.cost_centers[value.cost_center_id] = value
  }
  for value in durable.commercial.projects {
    if store.projects.contains(value.project_id) ||
      !store.organizations.contains(value.organization_id) ||
      !store.cost_centers.contains(value.cost_center_id) {
      raise InvalidInput("invalid project snapshot")
    }
    store.projects[value.project_id] = value
  }
  for value in durable.commercial.usage_observations {
    if store.observations.contains(value.event_id) ||
      !store.projects.contains(value.project_id) {
      raise InvalidInput("invalid usage snapshot")
    }
    store.observations[value.event_id] = value
  }
  for value in durable.commercial.ledger_entries {
    if store.entries.contains(value.entry_id) ||
      !store.observations.contains(value.source_event_id) {
      raise InvalidInput("invalid ledger snapshot")
    }
    store.entries[value.entry_id] = value
    store.rated_events[value.source_event_id] = value.entry_id
  }
  for value in durable.commercial.finalized_periods {
    let key = period_key(value.organization_id, value.period_id)
    if store.periods.contains(key) {
      raise InvalidInput("duplicate period")
    }
    store.periods[key] = value
  }
  for value in durable.commercial.budgets {
    if store.budgets.contains(value.budget_id) {
      raise InvalidInput("duplicate budget")
    }
    store.budgets[value.budget_id] = value
  }
  for value in durable.commercial.quotas {
    if store.quotas.contains(value.quota_id) {
      raise InvalidInput("duplicate quota")
    }
    store.quotas[value.quota_id] = value
  }
  for value in durable.commercial.commitments {
    if store.commitments.contains(value.commitment_id) {
      raise InvalidInput("duplicate commitment")
    }
    store.commitments[value.commitment_id] = value
  }
  for value in durable.commercial.consumptions {
    if store.consumptions.contains(value.consumption_id) {
      raise InvalidInput("duplicate consumption")
    }
    store.consumptions[value.consumption_id] = value
  }
  for value in durable.commercial.agreement_templates {
    let key = template_key(value.template_id, value.version)
    if store.templates.contains(key) {
      raise InvalidInput("duplicate agreement template")
    }
    store.templates[key] = value
  }
  for value in durable.commercial.clickwrap_acceptances {
    if store.acceptances.contains(value.acceptance_id) ||
      store.acceptance_keys.contains(value.idempotency_key) {
      raise InvalidInput("duplicate clickwrap acceptance")
    }
    store.acceptances[value.acceptance_id] = value
    store.acceptance_keys[value.idempotency_key] = value.acceptance_id
  }
  for value in durable.commercial.agreements {
    if store.agreements.contains(value.agreement_id) {
      raise InvalidInput("duplicate agreement")
    }
    store.agreements[value.agreement_id] = value
  }
  for value in durable.signature_callbacks {
    if store.signature_callbacks.contains(value.callback_id) ||
      !store.agreements.contains(value.agreement_id) {
      raise InvalidInput("invalid signature callback snapshot")
    }
    store.signature_callbacks[value.callback_id] = value
  }
  for value in durable.commercial.role_grants {
    if store.grants.contains(value.grant_id) {
      raise InvalidInput("duplicate role grant")
    }
    store.grants[value.grant_id] = value
  }
  store
}

///|
pub fn CommercialStore::replace_from_durable_snapshot(
  self : CommercialStore,
  durable : CommercialDurableSnapshot,
) -> Unit raise CommercialError {
  let restored = CommercialStore::from_durable_snapshot(durable)
  self.organizations = restored.organizations
  self.cost_centers = restored.cost_centers
  self.projects = restored.projects
  self.observations = restored.observations
  self.entries = restored.entries
  self.rated_events = restored.rated_events
  self.periods = restored.periods
  self.budgets = restored.budgets
  self.quotas = restored.quotas
  self.commitments = restored.commitments
  self.consumptions = restored.consumptions
  self.templates = restored.templates
  self.acceptances = restored.acceptances
  self.acceptance_keys = restored.acceptance_keys
  self.agreements = restored.agreements
  self.signature_callbacks = restored.signature_callbacks
  self.grants = restored.grants
}

///|
fn safe_identifier(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 160 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == ':' ||
    character == '.' ||
    character == '@'
  })
}

///|
fn safe_display_name(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 200 &&
  value.all(character => {
    character.is_printable() && character != '<' && character != '>'
  })
}

///|
fn safe_legal_text(value : String, maximum_length : Int) -> Bool {
  let trimmed = value.trim()
  trimmed != "" &&
  value.length() <= maximum_length &&
  value.all(character => {
    character.is_printable() &&
    character != '\u0000' &&
    character != '\n' &&
    character != '\r'
  })
}

///|
fn valid_country_code(value : String) -> Bool {
  value.length() == 2 &&
  value.all(character => character >= 'A' && character <= 'Z')
}

///|
fn valid_optional_legal_identifier(value : String?) -> Bool {
  match value {
    Some(identifier) => safe_legal_text(identifier, 160)
    None => true
  }
}

///|
fn validate_organization(value : Organization) -> Unit raise CommercialError {
  if !safe_identifier(value.organization_id) ||
    !safe_display_name(value.display_name) ||
    value.created_unix_ms <= 0L {
    raise InvalidInput("invalid organization")
  }
  match value.legal_profile {
    Some(profile) => {
      if !safe_legal_text(profile.legal_name, 240) ||
        !valid_country_code(profile.country_code) ||
        !valid_optional_legal_identifier(profile.registration_number) ||
        !valid_optional_legal_identifier(profile.tax_identifier) ||
        !safe_legal_text(profile.registered_address, 500) ||
        !safe_legal_text(profile.billing_contact.display_name, 160) ||
        !safe_legal_text(profile.billing_contact.email, 320) ||
        !profile.billing_contact.email.contains("@") ||
        !profile.billing_contact.phone
        .map(phone => safe_legal_text(phone, 64))
        .unwrap_or(true) {
        raise InvalidInput("invalid organization legal profile")
      }
      if profile.subject_kind == Company &&
        profile.registration_number is None &&
        profile.tax_identifier is None {
        raise InvalidInput(
          "a company requires a registration number or tax identifier",
        )
      }
    }
    None => ()
  }
}

///|
fn valid_sha256(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    false
  } else {
    let suffix = value[7:]
    suffix.all(character => character.is_ascii_hexdigit())
  }
}

///|
fn template_key(template_id : String, version : String) -> String {
  "\{template_id}@\{version}"
}

///|
fn period_key(organization_id : String, period_id : String) -> String {
  "\{organization_id}:\{period_id}"
}

///|
fn CommercialStore::require_organization(
  self : CommercialStore,
  organization_id : String,
) -> Organization raise CommercialError {
  match self.organizations.get(organization_id) {
    Some(value) => value
    None => raise NotFound("organization")
  }
}

///|
fn CommercialStore::require_project(
  self : CommercialStore,
  organization_id : String,
  project_id : String,
) -> Project raise CommercialError {
  match self.projects.get(project_id) {
    Some(value) =>
      if value.organization_id == organization_id {
        value
      } else {
        raise TenantMismatch
      }
    None => raise NotFound("project")
  }
}

///|
/// Returns a project only when it belongs to the supplied organization. This
/// is the tenant-safe attribution check used before issuing billable access.
pub fn CommercialStore::project_for_organization(
  self : CommercialStore,
  organization_id : String,
  project_id : String,
) -> Project? {
  match self.projects.get(project_id) {
    Some(value) if value.organization_id == organization_id => Some(value)
    _ => None
  }
}

///|
pub fn CommercialStore::add_organization(
  self : CommercialStore,
  value : Organization,
) -> Unit raise CommercialError {
  validate_organization(value)
  if self.organizations.contains(value.organization_id) {
    raise AlreadyExists("organization")
  }
  self.organizations[value.organization_id] = value
}

///| Promote a pending organization only from authenticated external identity

///| evidence. Replays with the same evidence are idempotent; suspended or

///|
/// closed organizations cannot be reactivated by a provider callback.
pub fn CommercialStore::record_identity_verification(
  self : CommercialStore,
  organization_id : String,
  verification_ref : String,
) -> Organization raise CommercialError {
  let organization = self.require_organization(organization_id)
  if !safe_identifier(verification_ref) {
    raise InvalidInput("invalid organization verification evidence")
  }
  if organization.state == Active &&
    organization.verification_ref == Some(verification_ref) {
    return organization
  }
  if organization.state != PendingVerification {
    raise InvalidTransition(
      "only a pending organization can complete identity verification",
    )
  }
  let verified = {
    ..organization,
    state: Active,
    verification_ref: Some(verification_ref),
  }
  self.organizations[organization_id] = verified
  verified
}

///|
pub fn CommercialStore::add_cost_center(
  self : CommercialStore,
  value : CostCenter,
) -> Unit raise CommercialError {
  ignore(self.require_organization(value.organization_id))
  if !safe_identifier(value.cost_center_id) ||
    !safe_display_name(value.display_name) ||
    value.created_unix_ms <= 0L {
    raise InvalidInput("invalid cost center")
  }
  if self.cost_centers.contains(value.cost_center_id) {
    raise AlreadyExists("cost center")
  }
  match value.parent_cost_center_id {
    Some(parent_id) =>
      match self.cost_centers.get(parent_id) {
        Some(parent) =>
          if parent.organization_id != value.organization_id {
            raise TenantMismatch
          }
        None => raise NotFound("parent cost center")
      }
    None => ()
  }
  self.cost_centers[value.cost_center_id] = value
}

///|
pub fn CommercialStore::add_project(
  self : CommercialStore,
  value : Project,
) -> Unit raise CommercialError {
  ignore(self.require_organization(value.organization_id))
  if !safe_identifier(value.project_id) ||
    !safe_display_name(value.display_name) ||
    value.created_unix_ms <= 0L {
    raise InvalidInput("invalid project")
  }
  if self.projects.contains(value.project_id) {
    raise AlreadyExists("project")
  }
  match self.cost_centers.get(value.cost_center_id) {
    Some(cost_center) =>
      if cost_center.organization_id != value.organization_id {
        raise TenantMismatch
      }
    None => raise NotFound("cost center")
  }
  self.projects[value.project_id] = value
}

///|
pub fn CommercialStore::organization(
  self : CommercialStore,
  organization_id : String,
) -> Organization? {
  self.organizations.get(organization_id)
}
