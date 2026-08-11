///|
pub struct CommercialStore {
  organizations : Map[String, Organization]
  cost_centers : Map[String, CostCenter]
  projects : Map[String, Project]
  observations : Map[String, UsageObservation]
  entries : Map[String, LedgerEntry]
  rated_events : Map[String, String]
  periods : Map[String, FinalizedPeriod]
  budgets : Map[String, Budget]
  quotas : Map[String, Quota]
  commitments : Map[String, CapacityCommitment]
  consumptions : Map[String, EntitlementConsumption]
  templates : Map[String, AgreementTemplate]
  acceptances : Map[String, ClickwrapAcceptance]
  acceptance_keys : Map[String, String]
  agreements : Map[String, Agreement]
  signature_callbacks : Map[String, SignatureCallback]
  grants : Map[String, RoleGrant]
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
pub fn CommercialStore::add_organization(
  self : CommercialStore,
  value : Organization,
) -> Unit raise CommercialError {
  if !safe_identifier(value.organization_id) ||
    !safe_display_name(value.display_name) ||
    value.created_unix_ms <= 0L {
    raise InvalidInput("invalid organization")
  }
  if self.organizations.contains(value.organization_id) {
    raise AlreadyExists("organization")
  }
  self.organizations[value.organization_id] = value
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
