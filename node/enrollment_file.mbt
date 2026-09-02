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
  defer self.mutex.release()
  let token = self.service.issue_token(token_id, secret, expires_unix_ms)
  write_enrollment(self.path, self.service.snapshot())
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
  defer self.mutex.release()
  let certificate = self.service.enroll(
    node_id,
    token_id,
    secret,
    node_auth_secret,
    public_key_ref,
    now_unix_ms,
    certificate_lifetime_ms~,
  )
  write_enrollment(self.path, self.service.snapshot())
  certificate
}

///|
pub async fn FileEnrollmentService::authorized(
  self : FileEnrollmentService,
  node_id : String,
  secret : String,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  let authorized = self.service.authorized(node_id, secret, now_unix_ms)
  authorized
}

///|
pub async fn FileEnrollmentService::renew(
  self : FileEnrollmentService,
  node_id : String,
  secret : String,
  public_key_ref : String,
  current_serial : Int64,
  now_unix_ms : Int64,
  certificate_lifetime_ms? : Int64 = 3600000L,
  renewal_grace_ms? : Int64 = 86400000L,
) -> NodeCertificate {
  self.mutex.acquire()
  defer self.mutex.release()
  let certificate = self.service.renew(
    node_id,
    secret,
    public_key_ref,
    current_serial,
    now_unix_ms,
    certificate_lifetime_ms~,
    renewal_grace_ms~,
  )
  write_enrollment(self.path, self.service.snapshot())
  certificate
}

///|
pub async fn FileEnrollmentService::active_node_ids(
  self : FileEnrollmentService,
  now_unix_ms : Int64,
) -> Array[String] {
  self.mutex.acquire()
  defer self.mutex.release()
  let result = self.service.active_node_ids(now_unix_ms)
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
  defer self.mutex.release()
  let certificate = self.service.rotate(
    node_id,
    public_key_ref,
    now_unix_ms,
    certificate_lifetime_ms~,
  )
  write_enrollment(self.path, self.service.snapshot())
  certificate
}
