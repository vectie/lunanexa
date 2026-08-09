///|
pub struct FileWorkspaceDirectory {
  path : String
  admission_path : String
  users : Map[String, @workspace.WorkspaceUser]
  mut access_grants : Map[String, @workspace.WorkspaceAccessGrant]
  mut leases : Map[String, @workspace.WorkspaceLease]
  mut workload_reservations : Map[String, WorkloadReservation]
  mutex : @async.Mutex
}

///|
fn sorted_users(
  users : Map[String, @workspace.WorkspaceUser],
) -> Array[@workspace.WorkspaceUser] {
  let values = [ for _, user in users => user ]
  values.sort_by((left, right) => left.user_id.compare(right.user_id))
  values
}

///|
fn sorted_grants(
  grants : Map[String, @workspace.WorkspaceAccessGrant],
) -> Array[@workspace.WorkspaceAccessGrant] {
  let values = [ for _, grant in grants => grant ]
  values.sort_by((left, right) => left.grant_id.compare(right.grant_id))
  values
}

///|
fn sorted_leases(
  leases : Map[String, @workspace.WorkspaceLease],
) -> Array[@workspace.WorkspaceLease] {
  let values = [ for _, lease in leases => lease ]
  values.sort_by((left, right) => left.lease_id.compare(right.lease_id))
  values
}

///|
fn FileWorkspaceDirectory::snapshot_unlocked(
  self : FileWorkspaceDirectory,
) -> @workspace.WorkspaceDirectorySnapshot {
  {
    schema_version: @workspace.directory_schema_version,
    users: sorted_users(self.users),
    access_grants: sorted_grants(self.access_grants),
    leases: sorted_leases(self.leases),
  }
}

///|
async fn write_directory(
  path : String,
  snapshot : @workspace.WorkspaceDirectorySnapshot,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
fn FileWorkspaceDirectory::restore_snapshot(
  self : FileWorkspaceDirectory,
  snapshot : @workspace.WorkspaceDirectorySnapshot,
) -> Unit raise {
  if snapshot.schema_version != @workspace.directory_schema_version {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "unsupported workspace directory schema",
    )
  }
  let subjects : Map[String, String] = Map([])
  for user in snapshot.users {
    @workspace.validate_workspace_user(user)
    if self.users.contains(user.user_id) {
      raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
        "user:\{user.user_id}",
      )
    }
    if subjects.contains(user.subject_ref) {
      raise @workspace.WorkspaceDirectoryError::SubjectConflict(
        user.subject_ref,
      )
    }
    self.users[user.user_id] = user
    subjects[user.subject_ref] = user.user_id
  }
  for grant in snapshot.access_grants {
    @workspace.validate_workspace_access_grant(grant)
    if self.access_grants.contains(grant.grant_id) {
      raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
        "access_grant:\{grant.grant_id}",
      )
    }
    if !self.users.contains(grant.user_id) {
      raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
        "access grant references an unknown user",
      )
    }
    self.access_grants[grant.grant_id] = grant
  }
  for lease in snapshot.leases {
    @workspace.validate_workspace_lease(lease)
    if self.leases.contains(lease.lease_id) {
      raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
        "lease:\{lease.lease_id}",
      )
    }
    if !subjects.contains(lease.subject_ref) {
      raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
        "lease references an unknown subject",
      )
    }
    self.leases[lease.lease_id] = lease
  }
}

///|
fn FileWorkspaceDirectory::reconcile_expiry_unlocked(
  self : FileWorkspaceDirectory,
  now_unix_ms : Int64,
) -> Bool raise {
  let expired_grants = [
    for grant_id, grant in self.access_grants if grant.state == GrantActive &&
    now_unix_ms >= grant.expires_unix_ms => grant_id
  ]
  let expired_leases = [
    for lease_id, lease in self.leases if (
      lease.state == Requested ||
      lease.state == Active ||
      lease.state == Suspended
    ) &&
    now_unix_ms >= lease.expires_unix_ms => lease_id
  ]
  for grant_id in expired_grants {
    guard self.access_grants.get(grant_id) is Some(grant) else { continue }
    self.access_grants[grant_id] = grant.transition(GrantExpired, now_unix_ms)
  }
  for lease_id in expired_leases {
    guard self.leases.get(lease_id) is Some(lease) else { continue }
    self.leases[lease_id] = lease.transition(Expired, now_unix_ms)
  }
  expired_grants.length() > 0 || expired_leases.length() > 0
}

///|
pub async fn FileWorkspaceDirectory::open(
  path : String,
  now_unix_ms? : Int64,
) -> FileWorkspaceDirectory {
  if path.trim() == "" {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "workspace directory path is empty",
    )
  }
  let directory : FileWorkspaceDirectory = {
    path,
    admission_path: "\{path}.admissions",
    users: Map([]),
    access_grants: Map([]),
    leases: Map([]),
    workload_reservations: Map([]),
    mutex: Mutex(),
  }
  let now = now_unix_ms.unwrap_or(@async.now())
  if @fs.exists(path) {
    let snapshot : @workspace.WorkspaceDirectorySnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error =>
        raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
          "invalid workspace directory JSON: \{Repr(error)}",
        )
    }
    directory.restore_snapshot(snapshot)
    if directory.reconcile_expiry_unlocked(now) {
      write_directory(path, directory.snapshot_unlocked())
    }
  } else {
    write_directory(path, directory.snapshot_unlocked())
  }
  directory.open_admissions(now)
  directory
}

///|
async fn FileWorkspaceDirectory::persist(self : FileWorkspaceDirectory) -> Unit {
  write_directory(self.path, self.snapshot_unlocked())
}

///|
pub async fn FileWorkspaceDirectory::snapshot(
  self : FileWorkspaceDirectory,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceDirectorySnapshot {
  self.mutex.acquire()
  let previous_grants = self.access_grants.copy()
  let previous_leases = self.leases.copy()
  try {
    if self.reconcile_expiry_unlocked(now_unix_ms) {
      self.persist()
    }
    let snapshot = self.snapshot_unlocked()
    self.mutex.release()
    snapshot
  } catch {
    error => {
      self.access_grants = previous_grants
      self.leases = previous_leases
      self.mutex.release()
      raise error
    }
  }
}

///|
fn user_can_be_created(state : @workspace.WorkspaceUserState) -> Bool {
  state == UserInvited || state == UserActive
}

///|
pub async fn FileWorkspaceDirectory::create_user(
  self : FileWorkspaceDirectory,
  user : @workspace.WorkspaceUser,
) -> @workspace.WorkspaceUser {
  @workspace.validate_workspace_user(user)
  if !user_can_be_created(user.state) {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "a new user must be invited or active",
    )
  }
  self.mutex.acquire()
  if self.users.contains(user.user_id) {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
      "user:\{user.user_id}",
    )
  }
  if self.users.values().any(current => current.subject_ref == user.subject_ref) {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::SubjectConflict(user.subject_ref)
  }
  self.users[user.user_id] = user
  try self.persist() catch {
    error => {
      ignore(self.users.remove(user.user_id))
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  user
}

///|
pub async fn FileWorkspaceDirectory::invite_user(
  self : FileWorkspaceDirectory,
  user : @workspace.WorkspaceUser,
) -> @workspace.WorkspaceUser {
  if user.state != UserInvited {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "an invitation must use UserInvited state",
    )
  }
  self.create_user(user)
}

///|
fn user_for_subject(
  users : Map[String, @workspace.WorkspaceUser],
  subject_ref : String,
) -> @workspace.WorkspaceUser? {
  users.values().find_first(user => user.subject_ref == subject_ref)
}

///|
fn current_grant(
  grant : @workspace.WorkspaceAccessGrant,
  required_access : @workspace.WorkspaceAccess,
  now_unix_ms : Int64,
) -> Bool {
  grant.state == GrantActive &&
  now_unix_ms >= grant.starts_unix_ms &&
  now_unix_ms < grant.expires_unix_ms &&
  @workspace.workspace_access_satisfies(grant.access, required_access)
}

///|
fn FileWorkspaceDirectory::has_grant_for_lease_unlocked(
  self : FileWorkspaceDirectory,
  user : @workspace.WorkspaceUser,
  lease : @workspace.WorkspaceLease,
  now_unix_ms : Int64,
) -> Bool {
  user.state == UserActive &&
  self.access_grants
  .values()
  .any(grant => {
    grant.user_id == user.user_id &&
    grant.tenant_ref == lease.tenant_ref &&
    current_grant(grant, lease.access, now_unix_ms)
  })
}

///|
pub async fn FileWorkspaceDirectory::issue_access_grant(
  self : FileWorkspaceDirectory,
  grant : @workspace.WorkspaceAccessGrant,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceAccessGrant {
  @workspace.validate_workspace_access_grant(grant)
  if grant.state != GrantActive ||
    now_unix_ms < grant.starts_unix_ms ||
    now_unix_ms >= grant.expires_unix_ms {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "a new access grant must be active at issuance",
    )
  }
  self.mutex.acquire()
  if self.access_grants.contains(grant.grant_id) {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
      "access_grant:\{grant.grant_id}",
    )
  }
  if !self.users.contains(grant.user_id) {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::RecordNotFound(
      "user:\{grant.user_id}",
    )
  }
  self.access_grants[grant.grant_id] = grant
  try self.persist() catch {
    error => {
      ignore(self.access_grants.remove(grant.grant_id))
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  grant
}

///|
pub async fn FileWorkspaceDirectory::issue_lease(
  self : FileWorkspaceDirectory,
  lease : @workspace.WorkspaceLease,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceLease {
  @workspace.validate_workspace_lease(lease)
  if lease.state != Requested && lease.state != Active {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "a new lease must be requested or active",
    )
  }
  if now_unix_ms >= lease.expires_unix_ms ||
    (lease.state == Active && now_unix_ms < lease.starts_unix_ms) {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "a new lease must have a usable time window",
    )
  }
  self.mutex.acquire()
  if self.leases.contains(lease.lease_id) {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::DuplicateRecord(
      "lease:\{lease.lease_id}",
    )
  }
  guard user_for_subject(self.users, lease.subject_ref) is Some(user) else {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::RecordNotFound(
      "subject:\{lease.subject_ref}",
    )
  }
  if lease.state == Active &&
    !self.has_grant_for_lease_unlocked(user, lease, now_unix_ms) {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::AccessDenied(AccessUnavailable)
  }
  self.leases[lease.lease_id] = lease
  try self.persist() catch {
    error => {
      ignore(self.leases.remove(lease.lease_id))
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
  lease
}

///|
pub async fn FileWorkspaceDirectory::activate_lease_with_prior(
  self : FileWorkspaceDirectory,
  lease_id : String,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceLease, @workspace.WorkspaceLease) {
  self.mutex.acquire()
  let previous_grants = self.access_grants.copy()
  let previous_leases = self.leases.copy()
  try {
    ignore(self.reconcile_expiry_unlocked(now_unix_ms))
    guard self.leases.get(lease_id) is Some(lease) else {
      raise @workspace.WorkspaceDirectoryError::RecordNotFound(
        "lease:\{lease_id}",
      )
    }
    guard user_for_subject(self.users, lease.subject_ref) is Some(user) else {
      raise @workspace.WorkspaceDirectoryError::RecordNotFound(
        "subject:\{lease.subject_ref}",
      )
    }
    if !self.has_grant_for_lease_unlocked(user, lease, now_unix_ms) {
      raise @workspace.WorkspaceDirectoryError::AccessDenied(AccessUnavailable)
    }
    let active = lease.transition(Active, now_unix_ms)
    self.leases[lease_id] = active
    self.persist()
    self.mutex.release()
    (lease, active)
  } catch {
    error => {
      self.access_grants = previous_grants
      self.leases = previous_leases
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileWorkspaceDirectory::activate_lease(
  self : FileWorkspaceDirectory,
  lease_id : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceLease {
  let (_, active) = self.activate_lease_with_prior(lease_id, now_unix_ms)
  active
}

///|
pub async fn FileWorkspaceDirectory::revoke_access_grant(
  self : FileWorkspaceDirectory,
  grant_id : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceAccessGrant {
  self.mutex.acquire()
  let previous_grants = self.access_grants.copy()
  let previous_leases = self.leases.copy()
  try {
    ignore(self.reconcile_expiry_unlocked(now_unix_ms))
    guard self.access_grants.get(grant_id) is Some(grant) else {
      raise @workspace.WorkspaceDirectoryError::RecordNotFound(
        "access_grant:\{grant_id}",
      )
    }
    let revoked = grant.transition(GrantRevoked, now_unix_ms)
    self.access_grants[grant_id] = revoked
    self.persist()
    self.mutex.release()
    revoked
  } catch {
    error => {
      self.access_grants = previous_grants
      self.leases = previous_leases
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileWorkspaceDirectory::revoke_lease(
  self : FileWorkspaceDirectory,
  lease_id : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceLease {
  self.mutex.acquire()
  let previous_grants = self.access_grants.copy()
  let previous_leases = self.leases.copy()
  try {
    ignore(self.reconcile_expiry_unlocked(now_unix_ms))
    guard self.leases.get(lease_id) is Some(lease) else {
      raise @workspace.WorkspaceDirectoryError::RecordNotFound(
        "lease:\{lease_id}",
      )
    }
    let revoked = lease.transition(Revoked, now_unix_ms)
    self.leases[lease_id] = revoked
    self.persist()
    self.mutex.release()
    revoked
  } catch {
    error => {
      self.access_grants = previous_grants
      self.leases = previous_leases
      self.mutex.release()
      raise error
    }
  }
}
