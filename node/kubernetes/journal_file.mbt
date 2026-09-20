///|
#borrow(output)
extern "c" fn fill_secure_random(output : Bytes) -> Int = "lunanexa_node_secure_random"

///|
fn owner_nonce() -> String raise LifecycleError {
  // The nonce identifies this process as the journal's owner, so it has to be
  // unique and it must not come from anything an operator could predict. It
  // used to be read from the `openssl rand` binary, which meant the whole
  // Kubernetes adapter could not start on an agent image that does not ship
  // OpenSSL -- and an agent image has no reason to. getentropy reads the same
  // kernel entropy source without spawning anything or inheriting an
  // environment; the C stub is the one already used elsewhere in this
  // repository for the same reason.
  let bytes = Bytes::make(32, 0)
  if fill_secure_random(bytes) != 0 {
    raise LifecycleError::InvalidResource
  }
  let nonce = @crypto.bytes_to_hex_string(bytes)
  if !@contracts.valid_sha256_digest("sha256:" + nonce) {
    raise LifecycleError::InvalidResource
  }
  nonce
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
