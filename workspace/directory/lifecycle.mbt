///|
async fn FileWorkspaceDirectory::transition_user(
  self : FileWorkspaceDirectory,
  user_id : String,
  to : @workspace.WorkspaceUserState,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceUser, @workspace.WorkspaceUser) {
  self.mutex.acquire()
  guard self.users.get(user_id) is Some(previous) else {
    self.mutex.release()
    raise @workspace.WorkspaceDirectoryError::RecordNotFound("user:\{user_id}")
  }
  try {
    let updated = previous.transition(to, now_unix_ms)
    self.users[user_id] = updated
    self.persist()
    self.mutex.release()
    (previous, updated)
  } catch {
    error => {
      self.users[user_id] = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileWorkspaceDirectory::activate_user(
  self : FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceUser {
  let (_, updated) = self.activate_user_with_prior(user_id, now_unix_ms)
  updated
}

///|
pub async fn FileWorkspaceDirectory::activate_user_with_prior(
  self : FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceUser, @workspace.WorkspaceUser) {
  self.transition_user(user_id, UserActive, now_unix_ms)
}

///|
pub async fn FileWorkspaceDirectory::suspend_user(
  self : FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceUser {
  let (_, updated) = self.suspend_user_with_prior(user_id, now_unix_ms)
  updated
}

///|
pub async fn FileWorkspaceDirectory::suspend_user_with_prior(
  self : FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceUser, @workspace.WorkspaceUser) {
  self.transition_user(user_id, UserSuspended, now_unix_ms)
}

///|
pub async fn FileWorkspaceDirectory::revoke_user(
  self : FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> @workspace.WorkspaceUser {
  let (_, updated) = self.revoke_user_with_prior(user_id, now_unix_ms)
  updated
}

///|
pub async fn FileWorkspaceDirectory::revoke_user_with_prior(
  self : FileWorkspaceDirectory,
  user_id : String,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceUser, @workspace.WorkspaceUser) {
  self.transition_user(user_id, UserRevoked, now_unix_ms)
}
