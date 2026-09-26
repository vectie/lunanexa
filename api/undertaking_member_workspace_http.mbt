///|
fn undertaking_member_workspace_path(path : String) -> Bool {
  path == "/v1/portal/self/undertaking-workspace"
}

///|
fn undertaking_member_has_gpu_workspace(
  snapshot : @workspace.WorkspaceDirectorySnapshot,
  subject_ref : String,
  tenant_ref : String,
  now : Int64,
) -> Bool {
  let required : Array[@workspace.WorkspaceCapability] = [
    TextGenerate,
    EmbeddingCreate,
    ImageGenerate,
    VideoGenerate,
    AudioGenerate,
  ]
  guard snapshot.users
    .iter()
    .find_first(user => {
      user.subject_ref == subject_ref && user.state == UserActive
    })
    is Some(user) &&
    snapshot.access_grants.any(grant => {
      grant.user_id == user.user_id &&
      grant.tenant_ref == tenant_ref &&
      grant.access == Developer &&
      grant.state == GrantActive &&
      grant.starts_unix_ms <= now &&
      grant.expires_unix_ms > now
    }) else {
    return false
  }
  snapshot.leases.any(lease => {
    lease.subject_ref == subject_ref &&
    lease.tenant_ref == tenant_ref &&
    lease.access == Developer &&
    lease.state == Active &&
    lease.starts_unix_ms <= now &&
    lease.expires_unix_ms > now &&
    required.all(capability => {
      lease.limits.capabilities.any(limit => limit.capability == capability)
    })
  })
}

///|
/// Each colleague activates their own bounded WebIDE/model capability lease.
/// The machine allocation is still the company's single signed authority.
async fn ApiService::handle_undertaking_member_workspace(
  self : ApiService,
  verb : ApiMethod,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.portal_store is Some(portal) &&
    self.portal_subject(headers, allow_asserted_subject) is Some(subject_ref) &&
    self.scheduler is Some(scheduler) &&
    self.workspace_directory is Some(directory) else {
    return api_error(
      401, "Unauthenticated", "enterprise identity is required", false,
    )
  }
  let view = try portal_view_for_request(portal, subject_ref, headers) catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  guard view.membership.active &&
    @portal.role_allows(view.membership.roles, Developer) else {
    return api_error(
      403, "DeveloperRequired", "company developer membership is required", false,
    )
  }
  if verb != Get && verb != Post {
    return api_error(405, "MethodNotAllowed", "use GET or POST", false)
  }
  let now = @async.now()
  let mut allocation : @scheduler.NodeReservation? = None
  for candidate in scheduler.snapshot().node_reservations.unwrap_or([]) {
    if candidate.request.tenant_ref == view.membership.tenant_ref &&
      candidate.request.organization_id == view.membership.organization_id &&
      candidate.request.reservation_id.has_prefix("undertaking-resource-") &&
      self.undertaking_reservation_allowed(candidate, now) {
      allocation = Some(candidate)
      break
    }
  }
  let ready = undertaking_member_has_gpu_workspace(
    directory.snapshot(now),
    subject_ref,
    view.membership.tenant_ref,
    now,
  )
  if verb == Get {
    return json_reply(200, {
      "status": if allocation is None {
        "NoCompanyMachines"
      } else if ready {
        "Ready"
      } else {
        "NeedsActivation"
      },
      "expires_unix_ms": allocation
      .map(value => value.request.expires_unix_ms)
      .to_json(),
    })
  }
  guard allocation is Some(reservation) else {
    return api_error(
      409, "CompanyMachinesRequired", "approved company machines are required", false,
    )
  }
  if ready {
    return json_reply(200, {
      "status": "Ready",
      "expires_unix_ms": reservation.request.expires_unix_ms.to_json(),
    })
  }
  guard self.account_store is Some(accounts) &&
    self.access_onboarding_store is Some(journal) &&
    accounts.snapshot().accounts
    .iter()
    .find_first(account => {
      account.subject_ref == subject_ref &&
      account.state == Active &&
      @account.role_allows(account.roles, EnterpriseUser)
    })
    is Some(account) else {
    return api_error(
      409, "AccountRequired", "active enterprise account is required", false,
    )
  }
  let fingerprint = @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode(
        reservation.request.reservation_id + ":" + account.account_id,
      ),
    ),
  )
  let operation_id = "undertaking-member-access-\{fingerprint}"
  let intent : @onboarding.AccessOnboardingIntent = {
    operation_id,
    fingerprint,
    requested_by: subject_ref,
    account_id: account.account_id,
    subject_ref,
    identity_issuer: account.identity_issuer,
    identity_subject_sha256: account.identity_subject_sha256,
    display_name: account.display_name,
    email: account.email,
    organization_id: view.membership.organization_id,
    tenant_ref: view.membership.tenant_ref,
    membership_id: view.membership.membership_id,
    user_id: "undertaking-member-user-\{fingerprint}",
    grant_id: "undertaking-member-grant-\{fingerprint}",
    lease_id: "undertaking-member-lease-\{fingerprint}",
    identity_receipt: account.identity_receipt,
    expires_unix_ms: reservation.request.expires_unix_ms,
    enterprise_gpu_capabilities: Some(true),
  }
  let record = match journal.record(operation_id) {
    Some(existing) => existing
    None =>
      try journal.begin(intent, now) catch {
        _ =>
          return api_error(
            503, "WorkspaceActivationUnavailable", "workspace activation could not be saved",
            true,
          )
      } noraise {
        value => value
      }
  }
  if record.intent != intent || record.status == Conflicted {
    return api_error(
      409, "WorkspaceActivationConflict", "previous activation conflicts with the current company allocation",
      false,
    )
  }
  if record.status == RecoverableFailure {
    ignore(journal.retry(operation_id, now)) catch {
      _ =>
        return api_error(
          503, "WorkspaceActivationUnavailable", "workspace activation retry could not be saved",
          true,
        )
    }
  }
  let prepared = self.execute_webide_access_package(intent, now)
  if prepared.status >= 400 {
    return prepared
  }
  if !self.undertaking_reservation_allowed(reservation, @async.now()) {
    return api_error(
      409, "CompanyMachinesRequired", "company allocation ended during activation",
      false,
    )
  }
  let lease = directory.snapshot(now).leases
    .iter()
    .find_first(value => {
      value.lease_id == intent.lease_id && value.subject_ref == subject_ref
    })
  guard lease is Some(existing_lease) else {
    return api_error(
      503, "WorkspaceActivationUnavailable", "personal lease is not ready", true,
    )
  }
  if existing_lease.state == Requested {
    ignore(directory.activate_lease(intent.lease_id, @async.now())) catch {
      _ =>
        return api_error(
          503, "WorkspaceActivationUnavailable", "personal lease could not be activated",
          true,
        )
    }
  }
  ignore(journal.advance(operation_id, Enabled, @async.now())) catch {
    _ =>
      return api_error(
        503, "WorkspaceActivationUnavailable", "activation checkpoint could not be saved",
        true,
      )
  }
  self.operator_audit_as(
    subject_ref,
    "undertaking.member-workspace.enabled",
    operation_id,
    reservation.request.reservation_id,
  )
  json_reply(200, {
    "status": "Ready",
    "expires_unix_ms": reservation.request.expires_unix_ms.to_json(),
  })
}
