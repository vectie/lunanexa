///|
pub fn role_allows(
  role : OrganizationRole,
  permission : CommercialPermission,
) -> Bool {
  match (role, permission) {
    (OrganizationOwner, _) => true
    (
      BillingAdministrator,
      ManageCostCenters
      | ManageBudgets
      | ViewFinance
      | ExportFinance,
    ) => true
    (FinanceViewer, ViewFinance | ExportFinance) => true
    (ProcurementApprover, ApproveCommitment | ViewFinance) => true
    (LegalSigner, SignAgreement) => true
    (Deployer, DeployWorkload) => true
    (LeaseAdministrator, AdministerLease) => true
    (Auditor, ViewFinance | ExportFinance) => true
    (PlatformOperator, OperatePlatform) => true
    _ => false
  }
}

///|
pub fn CommercialStore::has_permission(
  self : CommercialStore,
  organization_id : String,
  user_id : String,
  permission : CommercialPermission,
  now_unix_ms : Int64,
) -> Bool {
  self.grants
  .values()
  .any(grant => {
    grant.organization_id == organization_id &&
    grant.user_id == user_id &&
    (
      grant.expires_unix_ms is None ||
      grant.expires_unix_ms.unwrap_or(0L) > now_unix_ms
    ) &&
    role_allows(grant.role, permission)
  })
}

///|
fn high_risk_role(role : OrganizationRole) -> Bool {
  match role {
    OrganizationOwner
    | BillingAdministrator
    | ProcurementApprover
    | LegalSigner => true
    FinanceViewer
    | Deployer
    | LeaseAdministrator
    | Auditor
    | PlatformOperator => false
  }
}

///|
pub fn CommercialStore::grant_role(
  self : CommercialStore,
  grant : RoleGrant,
) -> Unit raise CommercialError {
  ignore(self.require_organization(grant.organization_id))
  if !safe_identifier(grant.grant_id) ||
    !safe_identifier(grant.user_id) ||
    !safe_identifier(grant.granted_by) ||
    grant.granted_unix_ms <= 0L ||
    grant.expires_unix_ms
    .map(expiry => expiry <= grant.granted_unix_ms)
    .unwrap_or(false) {
    raise InvalidInput("invalid role grant")
  }
  if self.grants.contains(grant.grant_id) {
    raise AlreadyExists("role grant")
  }
  let has_any_grant = self.grants
    .values()
    .any(existing => existing.organization_id == grant.organization_id)
  let bootstrap = !has_any_grant &&
    grant.role == OrganizationOwner &&
    grant.user_id == grant.granted_by
  if !bootstrap {
    if !self.has_permission(
        grant.organization_id,
        grant.granted_by,
        ManageOrganization,
        grant.granted_unix_ms,
      ) {
      raise PermissionDenied("organization owner permission required")
    }
    if high_risk_role(grant.role) && grant.user_id == grant.granted_by {
      raise SeparationOfDuties("a user cannot grant their own elevated role")
    }
  }
  self.grants[grant.grant_id] = grant
}
