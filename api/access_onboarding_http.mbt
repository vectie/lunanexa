///|
fn access_onboarding_path(path : String) -> Bool {
  path == "/v1/onboarding/access-packages" ||
  (
    path.has_prefix("/v1/onboarding/access-packages/") &&
    path.has_suffix(":enable")
  )
}

///|
priv struct WebIdeAccessPackageIntent {
  identity_issuer : String
  identity_subject : String
  display_name : String
  email : String
  organization_id : String
  tenant_ref : String
  template_id : String
  lifetime_days : Int
  identity_verified : Bool
} derive(FromJson)

///|
fn decode_webide_access_package(body : String) -> WebIdeAccessPackageIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn webide_access_package_fingerprint(
  issuer : String,
  subject : String,
) -> String {
  let digest = @account.identity_subject_digest(issuer, subject)
  digest[7:31].to_owned()
}

///|
async fn access_package_approved_aliases(
  registry : @registry.FileRegistry?,
) -> Array[String] {
  guard registry is Some(registry) else { return [] }
  let snapshot = registry.snapshot()
  [
    for model_alias in snapshot.aliases if snapshot.models.any(model => {
      model.model_id == model_alias.model_id &&
      model.version == model_alias.version &&
      model.state == Approved
    }) => model_alias.name
  ]
}

///|
fn access_package_state(
  account_active : Bool,
  membership_ready : Bool,
  contract_ready : Bool,
  workspace_user_ready : Bool,
  grant_ready : Bool,
  lease_state : @workspace.WorkspaceLeaseState?,
  models_ready : Bool,
) -> String {
  if !account_active ||
    !membership_ready ||
    !workspace_user_ready ||
    !grant_ready {
    "AttentionRequired"
  } else if !contract_ready {
    "ContractRequired"
  } else if !models_ready {
    "ModelRequired"
  } else {
    match lease_state {
      Some(Active) => "Ready"
      Some(Requested) => "ReadyToEnable"
      _ => "AttentionRequired"
    }
  }
}

///|
async fn ApiService::access_package_view_for_membership(
  self : ApiService,
  account : @account.AccountView,
  membership : @portal.EnterpriseMembership,
  workspace : @workspace.WorkspaceDirectorySnapshot,
  now : Int64,
) -> Json {
  let user = workspace.users
    .iter()
    .find_first(value => value.subject_ref == account.subject_ref)
  let grant = match user {
    Some(user) =>
      workspace.access_grants
      .iter()
      .find_first(value => {
        value.user_id == user.user_id &&
        value.tenant_ref == membership.tenant_ref &&
        value.access == Developer &&
        value.state == GrantActive &&
        value.starts_unix_ms <= now &&
        value.expires_unix_ms > now
      })
    None => None
  }
  let lease = workspace.leases
    .iter()
    .find_first(value => {
      value.subject_ref == account.subject_ref &&
      value.tenant_ref == membership.tenant_ref &&
      value.access == Developer &&
      value.starts_unix_ms <= now &&
      value.expires_unix_ms > now &&
      (value.state == Requested || value.state == Active)
    })
  let contract_ready = match self.contract_document_store {
    Some(contracts) =>
      contracts.has_effective_master_lease(
        membership.tenant_ref,
        account.subject_ref,
        now,
      )
    None => false
  }
  let aliases = access_package_approved_aliases(self.registry)
  let account_active = account.state == Active &&
    @account.role_allows(account.roles, EnterpriseUser)
  let membership_ready = membership.active &&
    @portal.role_allows(membership.roles, Developer)
  let workspace_user_ready = user.map_or(false, value => {
    value.state == UserActive
  })
  let grant_ready = grant is Some(_)
  let lease_state = lease.map(value => value.state)
  let models_ready = aliases.length() > 0
  {
    "package_id": "access-\{account.account_id}",
    "account_id": account.account_id,
    "subject_ref": account.subject_ref,
    "display_name": account.display_name,
    "email": account.email,
    "organization_id": membership.organization_id,
    "tenant_ref": membership.tenant_ref,
    "user_id": user.map(value => value.user_id),
    "membership_id": membership.membership_id,
    "grant_id": grant.map(value => value.grant_id),
    "lease_id": lease.map(value => value.lease_id),
    "lease_state": lease_state,
    "expires_unix_ms": lease.map(value => value.expires_unix_ms),
    "approved_model_aliases": aliases.to_json(),
    "account_ready": account_active,
    "membership_ready": membership_ready,
    "contract_ready": contract_ready,
    "workspace_ready": workspace_user_ready && grant_ready,
    "models_ready": models_ready,
    "ready": access_package_state(
      account_active, membership_ready, contract_ready, workspace_user_ready, grant_ready,
      lease_state, models_ready,
    ) ==
    "Ready",
    "can_enable": access_package_state(
      account_active, membership_ready, contract_ready, workspace_user_ready, grant_ready,
      lease_state, models_ready,
    ) ==
    "ReadyToEnable",
    "state": access_package_state(
      account_active, membership_ready, contract_ready, workspace_user_ready, grant_ready,
      lease_state, models_ready,
    ),
  }
}

///|
async fn ApiService::access_package_views(self : ApiService) -> Array[Json] {
  guard self.account_store is Some(accounts) &&
    self.portal_store is Some(portal) &&
    self.workspace_directory is Some(directory) else {
    return []
  }
  let now = @async.now()
  let account_views = accounts.views()
  let portal_snapshot = portal.snapshot()
  let workspace = directory.snapshot(now)
  let output : Array[Json] = []
  for membership in portal_snapshot.memberships {
    match
      account_views
      .iter()
      .find_first(account => account.subject_ref == membership.subject_ref) {
      Some(account) if @account.role_allows(account.roles, EnterpriseUser) =>
        output.push(
          self.access_package_view_for_membership(
            account, membership, workspace, now,
          ),
        )
      _ => ()
    }
  }
  output
}

///|
async fn ApiService::create_webide_access_package(
  self : ApiService,
  operator_id : String,
  intent : WebIdeAccessPackageIntent,
) -> HttpReply {
  if !intent.identity_verified ||
    intent.template_id != "webide-developer" ||
    intent.lifetime_days <= 0 ||
    intent.lifetime_days > 365 ||
    !safe_identity_value(intent.identity_issuer, 512) ||
    !safe_identity_value(intent.identity_subject, 1024) ||
    !safe_identity_value(intent.display_name, 128) ||
    !safe_identity_value(intent.email, 320) ||
    !@contracts.valid_identifier(intent.organization_id) ||
    !@contracts.valid_identifier(intent.tenant_ref) {
    return api_error(
      400, "InvalidRequest", "verified identity, organization, tenant, template and access period are required",
      false,
    )
  }
  guard self.account_store is Some(accounts) &&
    self.portal_store is Some(portal) &&
    self.workspace_directory is Some(directory) else {
    return api_error(
      503, "AccessOnboardingUnavailable", "account, portal and workspace authorities are required",
      true,
    )
  }
  let now = @async.now()
  let fingerprint = webide_access_package_fingerprint(
    intent.identity_issuer,
    intent.identity_subject,
  )
  let account_id = "account-\{fingerprint}"
  let subject_ref = "subject-\{fingerprint}"
  let membership_id = "membership-\{fingerprint}"
  let user_id = "user-\{fingerprint}"
  let grant_id = "grant-\{fingerprint}"
  let lease_id = "lease-\{fingerprint}"
  let identity_receipt = "oidc-verified-\{fingerprint}"
  let expires = now + intent.lifetime_days.to_int64() * 86400000L
  self.operator_audit_as(
    operator_id,
    "access-package.begin",
    account_id,
    "access-package:\{fingerprint}:begin",
  )
  match
    accounts.views().iter().find_first(value => value.account_id == account_id) {
    Some(existing) => {
      if existing.subject_ref != subject_ref ||
        existing.identity_issuer != intent.identity_issuer ||
        existing.email != intent.email ||
        !@account.role_allows(existing.roles, EnterpriseUser) {
        return api_error(
          409, "AccessPackageConflict", "the derived account identity is already bound to different access",
          false,
        )
      }
      if existing.state == Invited {
        ignore(accounts.set_state(account_id, Active, now)) catch {
          _ =>
            return api_error(
              409, "AccessPackageConflict", "the existing account cannot be activated",
              false,
            )
        }
      } else if existing.state != Active {
        return api_error(
          409, "AccessPackageConflict", "a suspended or revoked account requires explicit operator recovery",
          false,
        )
      }
    }
    None => {
      ignore(
        accounts.create({
          version: @account.contract_version,
          account_id,
          subject_ref,
          identity_issuer: intent.identity_issuer,
          identity_subject_sha256: @account.identity_subject_digest(
            intent.identity_issuer,
            intent.identity_subject,
          ),
          display_name: intent.display_name,
          email: intent.email,
          identity_receipt,
          roles: [EnterpriseUser],
          state: Active,
          created_unix_ms: now,
          updated_unix_ms: now,
        }),
      ) catch {
        _ =>
          return api_error(
            409, "AccessPackageConflict", "the identity is already registered under another account",
            false,
          )
      }
      self.operator_audit_as(
        operator_id, "access-package.account.created", account_id, identity_receipt,
      )
    }
  }
  let portal_snapshot = portal.snapshot()
  match
    portal_snapshot.memberships
    .iter()
    .find_first(value => value.membership_id == membership_id) {
    Some(existing) =>
      if existing.subject_ref != subject_ref ||
        existing.tenant_ref != intent.tenant_ref ||
        existing.organization_id != intent.organization_id ||
        !existing.active ||
        !@portal.role_allows(existing.roles, Developer) {
        return api_error(
          409, "AccessPackageConflict", "the derived membership is already bound to different access",
          false,
        )
      }
    None => {
      ignore(
        portal.put_membership({
          membership_id,
          tenant_ref: intent.tenant_ref,
          organization_id: intent.organization_id,
          subject_ref,
          roles: [Developer],
          active: true,
          created_unix_ms: now,
        }),
      ) catch {
        _ =>
          return api_error(
            409, "AccessPackageConflict", "enterprise membership creation was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id,
        "access-package.membership.created",
        membership_id,
        "access-package:\{fingerprint}:membership",
      )
    }
  }
  let initial_workspace = directory.snapshot(now)
  match
    initial_workspace.users.iter().find_first(value => value.user_id == user_id) {
    Some(existing) => {
      if existing.subject_ref != subject_ref || existing.email != intent.email {
        return api_error(
          409, "AccessPackageConflict", "the derived workspace user is already bound to another identity",
          false,
        )
      }
      if existing.state == UserInvited {
        ignore(directory.activate_user(user_id, now)) catch {
          _ =>
            return api_error(
              409, "AccessPackageConflict", "the existing workspace user cannot be activated",
              false,
            )
        }
      } else if existing.state != UserActive {
        return api_error(
          409, "AccessPackageConflict", "a suspended or revoked workspace user requires explicit operator recovery",
          false,
        )
      }
    }
    None => {
      ignore(
        directory.create_user({
          version: @workspace.contract_version,
          user_id,
          subject_ref,
          display_name: intent.display_name,
          email: intent.email,
          state: UserActive,
          created_unix_ms: now,
          last_active_unix_ms: None,
          identity_receipt,
        }),
      ) catch {
        _ =>
          return api_error(
            409, "AccessPackageConflict", "workspace user creation was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id, "access-package.workspace-user.created", user_id, identity_receipt,
      )
    }
  }
  let workspace_after_user = directory.snapshot(now)
  match
    workspace_after_user.access_grants
    .iter()
    .find_first(value => value.grant_id == grant_id) {
    Some(existing) =>
      if existing.user_id != user_id ||
        existing.tenant_ref != intent.tenant_ref ||
        existing.access != Developer ||
        existing.state != GrantActive ||
        existing.expires_unix_ms <= now {
        return api_error(
          409, "AccessPackageConflict", "the derived Developer grant is unavailable",
          false,
        )
      }
    None => {
      ignore(
        directory.issue_access_grant(
          {
            version: @workspace.contract_version,
            grant_id,
            user_id,
            tenant_ref: intent.tenant_ref,
            access: Developer,
            starts_unix_ms: now - 1000L,
            expires_unix_ms: expires,
            state: GrantActive,
            policy_receipt: "access-package-\{fingerprint}",
          },
          now,
        ),
      ) catch {
        _ =>
          return api_error(
            409, "AccessPackageConflict", "Developer access grant creation was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id,
        "access-package.grant.created",
        grant_id,
        "access-package:\{fingerprint}:grant",
      )
    }
  }
  let workspace_after_grant = directory.snapshot(now)
  match
    workspace_after_grant.leases
    .iter()
    .find_first(value => value.lease_id == lease_id) {
    Some(existing) =>
      if existing.subject_ref != subject_ref ||
        existing.tenant_ref != intent.tenant_ref ||
        existing.access != Developer ||
        existing.expires_unix_ms <= now ||
        (existing.state != Requested && existing.state != Active) {
        return api_error(
          409, "AccessPackageConflict", "the derived workspace lease is unavailable",
          false,
        )
      }
    None => {
      ignore(
        directory.issue_lease(
          {
            version: @workspace.contract_version,
            lease_id,
            tenant_ref: intent.tenant_ref,
            subject_ref,
            access: Developer,
            limits: {
              max_active_sessions: 2,
              max_session_duration_ms: 3600000L,
              capabilities: [
                {
                  capability: TextGenerate,
                  max_concurrent_requests: 2,
                  max_requests_per_hour: 100,
                  max_input_units_per_request: 65536,
                  max_output_units_per_request: 8192,
                },
              ],
            },
            starts_unix_ms: now - 1000L,
            expires_unix_ms: expires,
            state: Requested,
            policy_receipt: "access-package-\{fingerprint}",
          },
          now,
        ),
      ) catch {
        _ =>
          return api_error(
            409, "AccessPackageConflict", "workspace lease creation was rejected",
            false,
          )
      }
      self.operator_audit_as(
        operator_id,
        "access-package.lease.requested",
        lease_id,
        "access-package:\{fingerprint}:lease",
      )
    }
  }
  self.operator_audit_as(
    operator_id,
    "access-package.prepared",
    account_id,
    "access-package:\{fingerprint}:prepared",
  )
  let membership = portal.snapshot().memberships
    .iter()
    .find_first(value => value.membership_id == membership_id)
    .unwrap()
  let account = accounts
    .views()
    .iter()
    .find_first(value => value.account_id == account_id)
    .unwrap()
  json_reply(
    201,
    self.access_package_view_for_membership(
      account,
      membership,
      directory.snapshot(now),
      now,
    ),
  )
}

///|
async fn ApiService::enable_webide_access_package(
  self : ApiService,
  operator_id : String,
  account_id : String,
) -> HttpReply {
  guard self.account_store is Some(accounts) &&
    self.portal_store is Some(portal) &&
    self.workspace_directory is Some(directory) else {
    return api_error(
      503, "AccessOnboardingUnavailable", "account, portal and workspace authorities are required",
      true,
    )
  }
  guard accounts
    .views()
    .iter()
    .find_first(value => value.account_id == account_id)
    is Some(account) else {
    return api_error(404, "NotFound", "access package was not found", false)
  }
  let membership = try portal.self_view(account.subject_ref).membership catch {
    _ =>
      return api_error(
        409, "AccessPackageNotReady", "an active Developer membership is required",
        false,
      )
  } noraise {
    value => value
  }
  let now = @async.now()
  guard account.state == Active &&
    @account.role_allows(account.roles, EnterpriseUser) &&
    membership.active &&
    @portal.role_allows(membership.roles, Developer) else {
    return api_error(
      409, "AccessPackageNotReady", "account and Developer membership must be active",
      false,
    )
  }
  guard self.contract_document_store is Some(contracts) &&
    contracts.has_effective_master_lease(
      membership.tenant_ref,
      account.subject_ref,
      now,
    ) else {
    return api_error(
      409, "MasterLeaseRequired", "complete the MasterLease before enabling WebIDE access",
      false,
    )
  }
  if access_package_approved_aliases(self.registry).length() == 0 {
    return api_error(
      409, "ApprovedModelRequired", "at least one approved model alias is required",
      false,
    )
  }
  let workspace = directory.snapshot(now)
  guard workspace.users
    .iter()
    .any(user => {
      user.subject_ref == account.subject_ref && user.state == UserActive
    }) &&
    workspace.access_grants
    .iter()
    .any(grant => {
      grant.tenant_ref == membership.tenant_ref &&
      grant.access == Developer &&
      grant.state == GrantActive &&
      grant.starts_unix_ms <= now &&
      grant.expires_unix_ms > now &&
      workspace.users
      .iter()
      .any(user => {
        user.user_id == grant.user_id && user.subject_ref == account.subject_ref
      })
    }) else {
    return api_error(
      409, "AccessPackageNotReady", "an active workspace user and Developer grant are required",
      false,
    )
  }
  guard workspace.leases
    .iter()
    .find_first(lease => {
      lease.subject_ref == account.subject_ref &&
      lease.tenant_ref == membership.tenant_ref &&
      lease.access == Developer &&
      lease.starts_unix_ms <= now &&
      lease.expires_unix_ms > now &&
      (lease.state == Requested || lease.state == Active)
    })
    is Some(lease) else {
    return api_error(
      409, "AccessPackageNotReady", "a requested workspace lease is required", false,
    )
  }
  if lease.state == Requested {
    ignore(directory.activate_lease(lease.lease_id, now)) catch {
      _ =>
        return api_error(
          409, "AccessPackageNotReady", "the workspace lease could not be activated",
          false,
        )
    }
    self.operator_audit_as(
      operator_id,
      "access-package.enabled",
      account_id,
      "access-package:\{account_id}:lease:\{lease.lease_id}",
    )
  }
  json_reply(
    200,
    self.access_package_view_for_membership(
      account,
      membership,
      directory.snapshot(now),
      now,
    ),
  )
}

///|
async fn ApiService::handle_access_onboarding(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.operator_identity(headers) is Some(operator_id) else {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  guard self.account_store is Some(_) &&
    self.portal_store is Some(_) &&
    self.workspace_directory is Some(_) else {
    return api_error(
      503, "AccessOnboardingUnavailable", "account, portal and workspace authorities are required",
      true,
    )
  }
  match (verb, path) {
    (Get, "/v1/onboarding/access-packages") =>
      json_reply(200, self.access_package_views().to_json())
    (Post, "/v1/onboarding/access-packages") => {
      guard decode_webide_access_package(body) is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid WebIDE access package", false,
        )
      }
      self.create_webide_access_package(operator_id, intent)
    }
    (Post, _) => {
      guard path_identifier(path, "/v1/onboarding/access-packages/", ":enable")
        is Some(account_id) else {
        return api_error(404, "NotFound", "route was not found", false)
      }
      self.enable_webide_access_package(operator_id, account_id)
    }
    _ => api_error(405, "MethodNotAllowed", "method is not allowed", false)
  }
}
