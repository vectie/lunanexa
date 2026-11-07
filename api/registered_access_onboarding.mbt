///|
priv struct RegisteredAccessRequest {
  account_id : String
  organization_id : String
  lifetime_days : Int32
  lifetime_minutes : Int32?
} derive(FromJson)

///|
async fn ApiService::access_organization_options(self : ApiService) -> Json {
  guard self.portal_store is Some(portal) else { return [] }
  let memberships = portal.snapshot().memberships
  let options : Array[Json] = []
  for
    organization in self.commercial_store.durable_snapshot().commercial.organizations {
    if organization.state != Active {
      continue
    }
    let tenants : Array[String] = []
    for member in memberships {
      if member.organization_id == organization.organization_id &&
        member.active &&
        !tenants.contains(member.tenant_ref) {
        tenants.push(member.tenant_ref)
      }
    }
    // Ambiguous mappings require operator repair, never an arbitrary choice.
    if tenants.length() == 1 {
      options.push({
        "organization_id": organization.organization_id,
        "display_name": organization.display_name,
        "tenant_ref": tenants[0],
      })
    }
  }
  Json(options)
}

///|
async fn ApiService::prepare_registered_access(
  self : ApiService,
  operator_id : String,
  body : String,
) -> HttpReply {
  let request : RegisteredAccessRequest = @json.from_json(@json.parse(body)) catch {
    _ =>
      return api_error(
        400, "InvalidRequest", "account, organization and duration are required",
        false,
      )
  }
  let duration : Int64 = match
    (request.lifetime_days, request.lifetime_minutes) {
    (0, Some(60)) => 3600000L
    (days, None) if days > 0 && days <= 365 => days.to_int64() * 86400000L
    _ =>
      return api_error(400, "InvalidRequest", "invalid access duration", false)
  }
  guard self.account_store is Some(accounts) &&
    self.access_onboarding_store is Some(journal) else {
    return api_error(
      503, "AccessOnboardingUnavailable", "onboarding authorities unavailable", true,
    )
  }
  guard accounts.snapshot().accounts
    .iter()
    .find_first(account => account.account_id == request.account_id)
    is Some(account) &&
    account.state == Active &&
    @account.role_allows(account.roles, EnterpriseUser) else {
    return api_error(
      409, "AccountNotReady", "an active registered enterprise account is required",
      false,
    )
  }
  guard self.access_organization_options() is Array(options) &&
    options
    .iter()
    .find_first(option => {
      option is { "organization_id": String(id), .. } &&
      id == request.organization_id
    })
    is Some({ "tenant_ref": String(tenant), .. }) else {
    return api_error(
      409, "OrganizationNotReady", "an approved organization with an unambiguous tenant is required",
      false,
    )
  }
  let now = @async.now()
  let operation_id = "access-" + account.account_id
  let record = match journal.record(operation_id) {
    Some(existing) => {
      guard existing.intent.account_id == account.account_id &&
        existing.intent.subject_ref == account.subject_ref &&
        existing.intent.identity_subject_sha256 ==
        account.identity_subject_sha256 &&
        existing.intent.organization_id == request.organization_id &&
        existing.intent.tenant_ref == tenant &&
        existing.intent.expires_unix_ms - existing.created_unix_ms == duration else {
        return api_error(
          409, "AccessPackageConflict", "existing access terms cannot be rebound or extended",
          false,
        )
      }
      existing
    }
    None => {
      let fingerprint = @identity.subject_fingerprint(
        account.identity_issuer,
        account.identity_subject_sha256,
      )
      journal.begin(
        {
          operation_id,
          fingerprint,
          requested_by: operator_id,
          account_id: account.account_id,
          subject_ref: account.subject_ref,
          identity_issuer: account.identity_issuer,
          identity_subject_sha256: account.identity_subject_sha256,
          display_name: account.display_name,
          email: account.email,
          organization_id: request.organization_id,
          tenant_ref: tenant,
          membership_id: "membership-" + fingerprint,
          user_id: "user-" + fingerprint,
          grant_id: "grant-" + fingerprint,
          lease_id: "lease-" + fingerprint,
          identity_receipt: account.identity_receipt,
          expires_unix_ms: now + duration,
          enterprise_gpu_capabilities: None,
        },
        now,
      ) catch {
        _ =>
          return api_error(
            503, "AccessOnboardingJournalUnavailable", "could not save onboarding approval",
            true,
          )
      }
    }
  }
  let reply = self.resume_access_package(record)
  if reply.status >= 200 &&
    reply.status < 300 &&
    (@json.parse(reply.body) catch { _ => Json::null() })
    is { "can_enable": true, .. } {
    // This explicit operator action approves opening access; all existing
    // contract, model and workspace gates still run in enablement.
    self.enable_webide_access_package(operator_id, account.account_id)
  } else {
    reply
  }
}
