///|
async fn owner_nonce() -> String {
  // Use the OS-backed OpenSSL RNG without a shell or inherited environment.
  // Async file event registration does not support /dev/urandom on all hosts.
  @async.with_timeout(5000, () => {
    let (status, output, _) = @process.collect_output(
      "/usr/bin/openssl",
      ["rand", "-hex", "32"],
      inherit_env=false,
    )
    let nonce = output.text().trim().to_owned()
    if status != 0 || !@contracts.valid_sha256_digest("sha256:" + nonce) {
      raise LifecycleError::InvalidResource
    }
    nonce
  })
}

///|
/// A process-held exclusive lock prevents two node agents from racing the same
/// journal. Commit flushes the snapshot, atomically renames it, then flushes the
/// containing directory. The directory must be deployment-owned and private.
pub async fn RuntimeSupervisor::open_file(
  settings : RuntimeSettings,
  transport : Transport,
  path : String,
) -> RuntimeSupervisor {
  if !safe_path(path) {
    raise LifecycleError::InvalidResource
  }
  let parent = path[:path.rev_find("/").unwrap()].to_owned()
  if parent == "" {
    raise LifecycleError::InvalidResource
  }
  if @fs.realpath(parent) != parent {
    raise LifecycleError::InvalidResource
  }
  for target in [path, path + ".lock", path + ".next"] {
    let kind = try @fs.kind(target, follow_symlink=false) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => None
      error => raise error
    } noraise {
      value => Some(value)
    }
    if kind is Some(value) && value != Regular {
      raise LifecycleError::InvalidResource
    }
  }
  let lock = @fs.open(
    path + ".lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  let mut keep_lock = false
  defer (if !keep_lock { lock.close() })
  if !lock.try_lock(Exclusive) {
    raise LifecycleError::OwnershipConflict
  }
  let snapshot = if @fs.exists(path) {
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    Some(@utf8.decode(limited(file, 4194304)))
  } else {
    None
  }
  let commit : JournalCommit = contents => {
    if @utf8.encode(contents).length() > 4194304 {
      raise LifecycleError::InvalidResource
    }
    @fs.write_file(
      path + ".next",
      contents,
      create_mode=CreateOrTruncate,
      permission=0o600,
      sync=Full,
    )
    @fs.rename(path + ".next", path, replace=true)
    let directory = @fs.open(parent, mode=ReadOnly)
    defer directory.close()
    directory.sync()
  }
  let fresh_owner = if snapshot is None { owner_nonce() } else { "" }
  let supervisor = RuntimeSupervisor::restore(
    settings, transport, commit, snapshot, fresh_owner,
  )
  supervisor.persist()
  keep_lock = true
  { ..supervisor, file_lock: Some(lock), }
}

///|
/// Call after stopping the supervisor's tasks. Closing releases only the local
/// journal lock; it never deletes workloads, model files or persistent storage.
pub fn RuntimeSupervisor::close(self : RuntimeSupervisor) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  if self.file_lock is Some(lock) {
    lock.close()
  }
}
