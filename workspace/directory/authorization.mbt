///|
fn grant_is_current_for(
  grant : @workspace.WorkspaceAccessGrant,
  tenant_ref : String,
  required_access : @workspace.WorkspaceAccess,
  now_unix_ms : Int64,
) -> Bool {
  grant.tenant_ref == tenant_ref &&
  grant.state == GrantActive &&
  now_unix_ms >= grant.starts_unix_ms &&
  now_unix_ms < grant.expires_unix_ms &&
  @workspace.workspace_access_satisfies(grant.access, required_access)
}

///|
fn lease_is_current_for(
  lease : @workspace.WorkspaceLease,
  required_access : @workspace.WorkspaceAccess,
  now_unix_ms : Int64,
) -> Bool {
  lease.state == Active &&
  now_unix_ms >= lease.starts_unix_ms &&
  now_unix_ms < lease.expires_unix_ms &&
  @workspace.workspace_access_satisfies(lease.access, required_access)
}

///|
fn find_subject_user(
  snapshot : @workspace.WorkspaceDirectorySnapshot,
  subject_ref : String,
) -> @workspace.WorkspaceUser raise {
  guard snapshot.users
    .iter()
    .find_first(user => user.subject_ref == subject_ref)
    is Some(user) else {
    raise @workspace.WorkspaceDirectoryError::RecordNotFound(
      "subject:\{subject_ref}",
    )
  }
  user
}

///|
fn select_authorization(
  user : @workspace.WorkspaceUser,
  grants : Array[@workspace.WorkspaceAccessGrant],
  leases : Array[@workspace.WorkspaceLease],
  required_access : @workspace.WorkspaceAccess,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceAuthorization? {
  if user.state != UserActive {
    return None
  }
  for lease in leases {
    if lease_is_current_for(lease, required_access, now_unix_ms) {
      for grant in grants {
        if grant_is_current_for(
            grant,
            lease.tenant_ref,
            required_access,
            now_unix_ms,
          ) {
          return Some({
            subject_ref: user.subject_ref,
            user_id: user.user_id,
            access_grant: grant,
            lease,
          })
        }
      }
    }
  }
  None
}

///|
fn subject_self_contract(
  snapshot : @workspace.WorkspaceDirectorySnapshot,
  subject_ref : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceSelfContract raise {
  let user = find_subject_user(snapshot, subject_ref)
  let grants = snapshot.access_grants.filter(grant => {
    grant.user_id == user.user_id
  })
  let leases = snapshot.leases.filter(lease => lease.subject_ref == subject_ref)
  if user.state != UserActive {
    return {
      version: @workspace.contract_version,
      subject_ref,
      user,
      access_grants: grants,
      leases,
      active_lease: None,
      authorized: false,
      readiness: UserUnavailable,
    }
  }
  let current_grants = grants.filter(grant => {
    current_grant(grant, Developer, now_unix_ms)
  })
  if current_grants.length() == 0 {
    return {
      version: @workspace.contract_version,
      subject_ref,
      user,
      access_grants: grants,
      leases,
      active_lease: None,
      authorized: false,
      readiness: AccessUnavailable,
    }
  }
  match
    select_authorization(user, current_grants, leases, Developer, now_unix_ms) {
    Some(authorization) =>
      {
        version: @workspace.contract_version,
        subject_ref,
        user,
        access_grants: grants,
        leases,
        active_lease: Some(authorization.lease),
        authorized: true,
        readiness: WorkspaceReady,
      }
    None =>
      {
        version: @workspace.contract_version,
        subject_ref,
        user,
        access_grants: grants,
        leases,
        active_lease: None,
        authorized: false,
        readiness: LeaseUnavailable,
      }
  }
}

///|
pub async fn FileWorkspaceDirectory::self_view(
  self : FileWorkspaceDirectory,
  subject_ref : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceSelfContract {
  if !@workspace.valid_identifier(subject_ref) {
    raise @workspace.WorkspaceDirectoryError::RecordNotFound(
      "subject:\{subject_ref}",
    )
  }
  subject_self_contract(self.snapshot(now_unix_ms), subject_ref, now_unix_ms)
}

///|
pub async fn FileWorkspaceDirectory::authorize_subject(
  self : FileWorkspaceDirectory,
  subject_ref : String,
  required_access : @workspace.WorkspaceAccess,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceAuthorization {
  let snapshot = self.snapshot(now_unix_ms)
  let user = find_subject_user(snapshot, subject_ref)
  if user.state != UserActive {
    raise @workspace.WorkspaceDirectoryError::AccessDenied(UserUnavailable)
  }
  let grants = snapshot.access_grants.filter(grant => {
    grant.user_id == user.user_id
  })
  if !grants.any(grant => current_grant(grant, required_access, now_unix_ms)) {
    raise @workspace.WorkspaceDirectoryError::AccessDenied(AccessUnavailable)
  }
  let leases = snapshot.leases.filter(lease => lease.subject_ref == subject_ref)
  match
    select_authorization(user, grants, leases, required_access, now_unix_ms) {
    Some(authorization) => authorization
    None =>
      raise @workspace.WorkspaceDirectoryError::AccessDenied(LeaseUnavailable)
  }
}

///|
/// Authorizes one subject for an exact opaque tenant scope. This avoids
/// accidentally selecting a different active lease when a subject has more
/// than one tenant entitlement.
pub async fn FileWorkspaceDirectory::authorize_subject_for_tenant(
  self : FileWorkspaceDirectory,
  subject_ref : String,
  tenant_ref : String,
  required_access : @workspace.WorkspaceAccess,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceAuthorization {
  let snapshot = self.snapshot(now_unix_ms)
  let user = find_subject_user(snapshot, subject_ref)
  if user.state != UserActive {
    raise @workspace.WorkspaceDirectoryError::AccessDenied(UserUnavailable)
  }
  let grants = snapshot.access_grants.filter(grant => {
    grant.user_id == user.user_id && grant.tenant_ref == tenant_ref
  })
  if !grants.any(grant => current_grant(grant, required_access, now_unix_ms)) {
    raise @workspace.WorkspaceDirectoryError::AccessDenied(AccessUnavailable)
  }
  let leases = snapshot.leases.filter(lease => {
    lease.subject_ref == subject_ref && lease.tenant_ref == tenant_ref
  })
  match
    select_authorization(user, grants, leases, required_access, now_unix_ms) {
    Some(authorization) => authorization
    None =>
      raise @workspace.WorkspaceDirectoryError::AccessDenied(LeaseUnavailable)
  }
}
