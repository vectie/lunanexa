///|
pub struct FileEnrollmentService {
  path : String
  service : EnrollmentService
  mutex : @async.Mutex
}

///|
async fn write_enrollment(path : String, snapshot : String) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    snapshot,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
pub async fn FileEnrollmentService::open(
  path : String,
) -> FileEnrollmentService {
  let service = if @fs.exists(path) {
    EnrollmentService::restore(@fs.read_file(path).text())
  } else {
    EnrollmentService::new()
  }
  let durable = { path, service, mutex: Mutex() }
  if !@fs.exists(path) {
    write_enrollment(path, service.snapshot())
  }
  durable
}

///|
pub async fn FileEnrollmentService::issue_token(
  self : FileEnrollmentService,
  token_id : String,
  secret : String,
  expires_unix_ms : Int64,
) -> BootstrapToken {
  self.mutex.acquire()
  let token = self.service.issue_token(token_id, secret, expires_unix_ms)
  self.persist_and_release()
  token
}

///|
pub async fn FileEnrollmentService::enroll(
  self : FileEnrollmentService,
  node_id : String,
  token_id : String,
  secret : String,
  node_auth_secret : String,
  public_key_ref : String,
  now_unix_ms : Int64,
  certificate_lifetime_ms? : Int64 = 3600000L,
) -> NodeCertificate {
  self.mutex.acquire()
  try {
    let certificate = self.service.enroll(
      node_id,
      token_id,
      secret,
      node_auth_secret,
      public_key_ref,
      now_unix_ms,
      certificate_lifetime_ms~,
    )
    self.persist_and_release()
    certificate
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn FileEnrollmentService::authorized(
  self : FileEnrollmentService,
  node_id : String,
  secret : String,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  let authorized = self.service.authorized(node_id, secret, now_unix_ms)
  self.mutex.release()
  authorized
}

///|
pub async fn FileEnrollmentService::active_node_ids(
  self : FileEnrollmentService,
  now_unix_ms : Int64,
) -> Array[String] {
  self.mutex.acquire()
  let result = self.service.active_node_ids(now_unix_ms)
  self.mutex.release()
  result
}

///|
pub async fn FileEnrollmentService::rotate(
  self : FileEnrollmentService,
  node_id : String,
  public_key_ref : String,
  now_unix_ms : Int64,
  certificate_lifetime_ms? : Int64 = 3600000L,
) -> NodeCertificate {
  self.mutex.acquire()
  try {
    let certificate = self.service.rotate(
      node_id,
      public_key_ref,
      now_unix_ms,
      certificate_lifetime_ms~,
    )
    self.persist_and_release()
    certificate
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
}

///|
async fn FileEnrollmentService::persist_and_release(
  self : FileEnrollmentService,
) -> Unit {
  try write_enrollment(self.path, self.service.snapshot()) catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    _ => self.mutex.release()
  }
}
