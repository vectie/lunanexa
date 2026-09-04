///|
priv struct SelfServiceOrganizationIntent {
  idempotency_key : String
  display_name : String
  legal_profile : @commercial.OrganizationLegalProfile
} derive(FromJson)

///|
priv struct SelfServiceOrganizationView {
  organization : SelfServiceOrganizationSummary
  membership : @portal.EnterpriseMembership
  default_project_id : String?
  verification : SelfServiceOrganizationVerificationView?
} derive(ToJson)

///|
priv struct SelfServiceOrganizationSummary {
  organization_id : String
  display_name : String
  state : @commercial.OrganizationState
  verification_ref : String?
  legal_profile : @commercial.OrganizationLegalProfile?
} derive(ToJson)

///|
priv struct SelfServiceOrganizationVerificationView {
  required : Bool
  record : @commercial_integrations.ExternalRecordView?
  blocker_code : String?
} derive(ToJson)

///|
priv struct SelfServiceOrganizationsView {
  version : String
  organizations : Array[SelfServiceOrganizationView]
} derive(ToJson)

///|
priv struct SelfServiceInvitationAcceptanceIntent {
  invitation_secret : String
} derive(FromJson)

///|
priv struct SelfServiceInvitationAcceptanceView {
  invitation : @account.AccountInvitationView
  membership : @portal.EnterpriseMembership
} derive(ToJson)

///|
fn self_service_organization_path(path : String) -> Bool {
  path == "/v1/portal/self/organizations"
}

///|
fn self_service_invitation_accept_path(path : String) -> Bool {
  path == "/v1/portal/self/invitations:accept"
}

///|
fn self_service_portal_account_path(path : String) -> Bool {
  self_service_organization_path(path) ||
  self_service_invitation_accept_path(path)
}

///|
fn self_organization_forbidden_field(value : Json) -> Bool {
  match value {
    Object(fields) => {
      for key, child in fields {
        let normalized = key.to_lower()
        if normalized == "organization_id" ||
          normalized == "tenant_ref" ||
          normalized == "membership_id" ||
          normalized == "project_id" ||
          normalized == "cost_center_id" ||
          normalized == "grant_id" ||
          normalized == "state" ||
          normalized == "verification_ref" ||
          normalized == "role" ||
          normalized == "roles" ||
          self_organization_forbidden_field(child) {
          return true
        }
      }
      false
    }
    Array(values) => values.any(self_organization_forbidden_field)
    _ => false
  }
}

///|
fn decode_self_service_organization(
  body : String,
) -> SelfServiceOrganizationIntent? {
  try {
    let value = @json.parse(body)
    if self_organization_forbidden_field(value) {
      None
    } else {
      Some(@json.from_json(value))
    }
  } catch {
    _ => None
  }
}

///|
fn decode_self_service_invitation_acceptance(
  body : String,
) -> SelfServiceInvitationAcceptanceIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn normalized_optional_organization_text(value : String?) -> String? {
  value.map(text => text.trim().to_owned())
}

///|
fn normalized_legal_profile(
  value : @commercial.OrganizationLegalProfile,
) -> @commercial.OrganizationLegalProfile {
  {
    subject_kind: value.subject_kind,
    legal_name: value.legal_name.trim().to_owned(),
    country_code: value.country_code.trim().to_owned().to_upper(),
    registration_number: normalized_optional_organization_text(
      value.registration_number,
    ),
    tax_identifier: normalized_optional_organization_text(value.tax_identifier),
    registered_address: value.registered_address.trim().to_owned(),
    billing_contact: {
      display_name: value.billing_contact.display_name.trim().to_owned(),
      email: value.billing_contact.email.trim().to_owned().to_lower(),
      phone: normalized_optional_organization_text(value.billing_contact.phone),
    },
  }
}

///|
fn organization_registration_conflict() -> HttpReply {
  api_error(
    409, "OrganizationRegistrationConflict", "the idempotency key identifies different organization registration data",
    false,
  )
}

///|
fn self_service_verification_record_id(organization_id : String) -> String {
  "identity-\{provider_request_digest(organization_id, "self-service-identity-verification-v1")}"
}

///|
fn ApiService::self_service_verification_view(
  self : ApiService,
  organization : @commercial.Organization,
) -> SelfServiceOrganizationVerificationView {
  let record_id = self_service_verification_record_id(
    organization.organization_id,
  )
  let record = self.commercial_integrations.snapshot(
      organization.organization_id,
    ).records
    .iter()
    .find_first(value => value.record_id == record_id)
  let required = organization.state == PendingVerification
  {
    required,
    record,
    blocker_code: if !required || record is Some(_) {
      None
    } else if self.commercial_provider_adapter_ready() {
      Some("IdentityVerificationQueueRetryRequired")
    } else {
      Some("CommercialProviderUnavailable")
    },
  }
}

///|
fn organization_view_from_snapshot(
  service : ApiService,
  organization : @commercial.Organization,
  membership : @portal.EnterpriseMembership,
  commercial : @commercial.CommercialSnapshot,
) -> SelfServiceOrganizationView {
  let can_view_legal = @portal.role_allows(membership.roles, BillingViewer) ||
    @portal.role_allows(membership.roles, LegalSigner)
  let can_verify = @portal.role_allows(membership.roles, LegalSigner)
  {
    organization: {
      organization_id: organization.organization_id,
      display_name: organization.display_name,
      state: organization.state,
      verification_ref: if can_verify {
        organization.verification_ref
      } else {
        None
      },
      legal_profile: if can_view_legal {
        organization.legal_profile
      } else {
        None
      },
    },
    membership,
    default_project_id: commercial.projects
    .iter()
    .find_first(project => {
      project.organization_id == organization.organization_id
    })
    .map(project => project.project_id),
    verification: if can_verify {
      Some(service.self_service_verification_view(organization))
    } else {
      None
    },
  }
}

///|
async fn ApiService::list_self_service_organizations(
  self : ApiService,
  portal : @portal_store.FilePortalStore,
  subject_ref : String,
) -> HttpReply {
  let memberships = portal.memberships_for_subject(subject_ref)
  self.commercial_mutex.acquire()
  let commercial = self.commercial_store.durable_snapshot().commercial
  let organizations : Array[SelfServiceOrganizationView] = []
  for membership in memberships {
    match
      commercial.organizations
      .iter()
      .find_first(organization => {
        organization.organization_id == membership.organization_id
      }) {
      Some(organization) =>
        organizations.push(
          organization_view_from_snapshot(
            self, organization, membership, commercial,
          ),
        )
      None => ()
    }
  }
  self.commercial_mutex.release()
  json_reply(
    200,
    ToJson::to_json(SelfServiceOrganizationsView::{
      version: @portal.contract_version,
      organizations,
    }),
  )
}

///|
async fn ApiService::create_self_service_organization(
  self : ApiService,
  portal : @portal_store.FilePortalStore,
  account : @account.AccountView,
  intent : SelfServiceOrganizationIntent,
) -> HttpReply {
  if !@contracts.valid_identifier(intent.idempotency_key) {
    return api_error(
      400, "InvalidRequest", "invalid organization idempotency key", false,
    )
  }
  let fingerprint = digest_hex(
    "lunanexa.self-service-organization.v1\n\{account.subject_ref}\n\{intent.idempotency_key}",
  )[:32].to_owned()
  let organization_id = "organization-\{fingerprint}"
  let tenant_ref = "tenant-\{fingerprint}"
  let cost_center_id = "cost-center-\{fingerprint}"
  let project_id = "project-\{fingerprint}"
  let membership_id = "membership-\{fingerprint}"
  let grant_id = "role-grant-\{fingerprint}"
  let profile = normalized_legal_profile(intent.legal_profile)
  let display_name = intent.display_name.trim().to_owned()
  let portal_snapshot = portal.snapshot()
  let existing_membership = portal_snapshot.memberships
    .iter()
    .find_first(value => value.membership_id == membership_id)
  self.commercial_mutex.acquire()
  defer self.commercial_mutex.release()
  let before = self.commercial_store.durable_snapshot()
  let existing_organization = self.commercial_store.organization(
    organization_id,
  )
  let created_unix_ms = match existing_organization {
    Some(value) => value.created_unix_ms
    None =>
      existing_membership
      .map(value => value.created_unix_ms)
      .unwrap_or(@async.now())
  }
  let expected_organization : @commercial.Organization = {
    organization_id,
    display_name,
    state: PendingVerification,
    verification_ref: None,
    legal_profile: Some(profile),
    created_unix_ms,
  }
  let expected_cost_center : @commercial.CostCenter = {
    cost_center_id,
    organization_id,
    parent_cost_center_id: None,
    display_name: "Default",
    created_unix_ms,
  }
  let expected_project : @commercial.Project = {
    project_id,
    organization_id,
    cost_center_id,
    display_name: "Default project",
    created_unix_ms,
  }
  let expected_grant : @commercial.RoleGrant = {
    grant_id,
    organization_id,
    user_id: account.subject_ref,
    role: OrganizationOwner,
    granted_by: account.subject_ref,
    granted_unix_ms: created_unix_ms,
    expires_unix_ms: None,
  }
  let expected_membership : @portal.EnterpriseMembership = {
    membership_id,
    tenant_ref,
    organization_id,
    subject_ref: account.subject_ref,
    roles: [
      OrganizationAdministrator,
      LegalSigner,
      LeaseRequester,
      BillingViewer,
      Developer,
    ],
    active: true,
    created_unix_ms,
  }
  match existing_organization {
    Some(value) if value.organization_id == organization_id &&
      value.display_name == display_name &&
      value.legal_profile == Some(profile) => ()
    Some(_) => return organization_registration_conflict()
    None =>
      self.commercial_store.add_organization(expected_organization) catch {
        _ =>
          return api_error(
            400, "OrganizationRejected", "organization details were rejected", false,
          )
      }
  }
  let commercial = self.commercial_store.durable_snapshot().commercial
  match
    commercial.cost_centers
    .iter()
    .find_first(value => value.cost_center_id == cost_center_id) {
    Some(value) if value == expected_cost_center => ()
    Some(_) => {
      ignore(self.commercial_store.replace_from_durable_snapshot(before))
      return organization_registration_conflict()
    }
    None => self.commercial_store.add_cost_center(expected_cost_center)
  }
  match
    commercial.projects
    .iter()
    .find_first(value => value.project_id == project_id) {
    Some(value) if value == expected_project => ()
    Some(_) => {
      ignore(self.commercial_store.replace_from_durable_snapshot(before))
      return organization_registration_conflict()
    }
    None => self.commercial_store.add_project(expected_project)
  }
  match
    commercial.role_grants
    .iter()
    .find_first(value => value.grant_id == grant_id) {
    Some(value) if value == expected_grant => ()
    Some(_) => {
      ignore(self.commercial_store.replace_from_durable_snapshot(before))
      return organization_registration_conflict()
    }
    None => self.commercial_store.grant_role(expected_grant)
  }
  match existing_membership {
    Some(value) if value == expected_membership => ()
    Some(_) => {
      ignore(self.commercial_store.replace_from_durable_snapshot(before))
      return organization_registration_conflict()
    }
    None => ()
  }
  let replayed = existing_organization is Some(_) &&
    existing_membership is Some(_) &&
    commercial.cost_centers.contains(expected_cost_center) &&
    commercial.projects.contains(expected_project) &&
    commercial.role_grants.contains(expected_grant)
  self.persist_commercial_state() catch {
    _ => {
      ignore(self.commercial_store.replace_from_durable_snapshot(before))
      return api_error(
        503, "OrganizationPersistenceFailed", "organization registration was not committed",
        true,
      )
    }
  }
  let membership = match existing_membership {
    Some(value) => value
    None =>
      portal.put_membership(expected_membership) catch {
        _ => {
          ignore(self.commercial_store.replace_from_durable_snapshot(before))
          ignore(self.persist_commercial_state()) catch {
            _ => ()
          }
          return api_error(
            503, "OrganizationPersistenceFailed", "organization membership was not committed",
            true,
          )
        }
      }
  }
  let organization = self.commercial_store
    .organization(organization_id)
    .unwrap()
  if organization.state == PendingVerification &&
    self.commercial_integrations.record_by_id(
      self_service_verification_record_id(organization_id),
    )
    is None &&
    self.commercial_provider_adapter_ready() {
    let verification_digest = provider_request_digest(
      organization_id, "self-service-identity-verification-v1",
    )
    ignore(
      self.queue_provider_record(
        {
          record_id: "identity-\{verification_digest}",
          organization_id,
          kind: IdentityVerification,
          provider: self.commercial_provider_name.unwrap_or(""),
          environment: self.commercial_provider_environment.unwrap_or(""),
          external_ref: "identity-\{verification_digest}",
          state: Pending,
          expected_amount_minor: None,
          currency: None,
          money_scale: None,
          expected_document_hash: None,
          entitlement_transaction_ref: Some(
            "self-service-organization:\{organization_id}",
          ),
          created_unix_ms: organization.created_unix_ms,
          updated_unix_ms: organization.created_unix_ms,
        },
        commercial_lock_held=true,
      ),
    ) catch {
      // The organization remains durably PendingVerification. Replaying the
      // same registration repairs an interrupted or temporarily unavailable
      // provider-outbox commit without duplicating the organization.
      _ => ()
    }
  }
  let after = self.commercial_store.durable_snapshot().commercial
  self.operator_audit_as(
    account.subject_ref,
    "organization.self-service.create",
    organization_id,
    "organization-registration:\{fingerprint}",
  )
  json_reply(
    if replayed {
      200
    } else {
      201
    },
    ToJson::to_json(
      organization_view_from_snapshot(self, organization, membership, after),
    ),
  )
}

///|
async fn ApiService::accept_self_service_invitation(
  self : ApiService,
  portal : @portal_store.FilePortalStore,
  account : @account.AccountView,
  intent : SelfServiceInvitationAcceptanceIntent,
) -> HttpReply {
  guard self.account_store is Some(accounts) else {
    return api_error(
      503, "AccountStoreUnavailable", "durable human-account authority is unavailable",
      true,
    )
  }
  let invitation = try
    accounts.accept_invitation(
      intent.invitation_secret,
      account.account_id,
      @async.now(),
    )
  catch {
    error => return account_error(error)
  } noraise {
    value => value
  }
  self.commercial_mutex.acquire()
  let target_exists = self.commercial_store
    .organization(invitation.organization_id)
    .map(organization => organization.state == Active)
    .unwrap_or(false) &&
    self.commercial_store.project_for_organization(
      invitation.organization_id,
      invitation.project_id,
    )
    is Some(_)
  self.commercial_mutex.release()
  if !target_exists {
    return api_error(
      409, "InvitationTargetUnavailable", "the invited organization or project is not active",
      false,
    )
  }
  let fingerprint = digest_hex(
    "lunanexa.existing-account-invitation.v1\n\{account.account_id}\n\{invitation.invitation_id}",
  )[:32].to_owned()
  let created_unix_ms = invitation.consumed_unix_ms.unwrap_or(@async.now())
  let expected : @portal.EnterpriseMembership = {
    membership_id: "membership-\{fingerprint}",
    tenant_ref: invitation.tenant_ref,
    organization_id: invitation.organization_id,
    subject_ref: account.subject_ref,
    roles: [Developer],
    active: true,
    created_unix_ms,
  }
  let existing = portal.snapshot().memberships
    .iter()
    .find_first(membership => membership.membership_id == expected.membership_id)
  let membership = match existing {
    Some(value) if value == expected => value
    Some(_) => return organization_registration_conflict()
    None =>
      try portal.put_membership(expected) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
  }
  self.operator_audit_as(
    account.subject_ref,
    "organization.invitation.accept",
    membership.membership_id,
    "invitation:\{invitation.invitation_id}",
  )
  json_reply(
    if existing is Some(_) {
      200
    } else {
      201
    },
    ToJson::to_json(SelfServiceInvitationAcceptanceView::{
      invitation,
      membership,
    }),
  )
}

///|
async fn ApiService::handle_self_service_organizations(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  portal : @portal_store.FilePortalStore,
) -> HttpReply {
  if !self_service_portal_account_path(path) {
    return api_error(404, "NotFound", "route was not found", false)
  }
  guard self.account_session_authorization(headers, EnterpriseUser)
    is Some(authorization) else {
    return api_error(
      401, "Unauthenticated", "a valid enterprise account session is required", false,
    )
  }
  match (verb, path) {
    (Get, "/v1/portal/self/organizations") =>
      self.list_self_service_organizations(
        portal,
        authorization.account.subject_ref,
      )
    (Post, "/v1/portal/self/organizations") => {
      guard decode_self_service_organization(body) is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid self-service organization registration",
          false,
        )
      }
      self.create_self_service_organization(
        portal,
        authorization.account,
        intent,
      )
    }
    (Post, "/v1/portal/self/invitations:accept") => {
      guard decode_self_service_invitation_acceptance(body) is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid invitation acceptance", false,
        )
      }
      self.accept_self_service_invitation(portal, authorization.account, intent)
    }
    _ => api_error(405, "MethodNotAllowed", "method is not allowed", false)
  }
}

///|
async fn portal_view_for_request(
  portal : @portal_store.FilePortalStore,
  subject_ref : String,
  headers : Map[String, String],
) -> @portal.EnterpriseSelfView {
  match header(headers, "X-LunaNexa-Organization") {
    Some(organization_id) =>
      portal.self_view_for_organization(subject_ref, organization_id)
    None => portal.self_view(subject_ref)
  }
}
