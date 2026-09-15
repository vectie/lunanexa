///|
async fn FileWorkspaceDirectory::transition_user(
  self : FileWorkspaceDirectory,
  user_id : String,
  to : @workspace.WorkspaceUserState,
  now_unix_ms : Int64,
) -> (@workspace.WorkspaceUser, @workspace.WorkspaceUser) {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.users.get(user_id) is Some(previous) else {
    raise @workspace.WorkspaceDirectoryError::RecordNotFound("user:\{user_id}")
  }
  let mut committed = false
  defer (if !committed { self.users[user_id] = previous })
  let updated = previous.transition(to, now_unix_ms)
  self.users[user_id] = updated
  self.persist()
  committed = true
  (previous, updated)
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
