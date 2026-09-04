///|
enum EnrollmentPersistence {
  EnrollmentFile(String)
  EnrollmentPostgres(@database.PostgresDatabase)
}

///|
pub struct FileEnrollmentService {
  persistence : EnrollmentPersistence
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
  let durable = { persistence: EnrollmentFile(path), service, mutex: Mutex() }
  if !@fs.exists(path) {
    write_enrollment(path, service.snapshot())
  }
  durable
}

///|
pub async fn FileEnrollmentService::open_postgres(
  database : @database.PostgresDatabase,
) -> FileEnrollmentService {
  let payload = database.load_snapshot(
    "node_enrollment", "lunanexa.enrollment.v2",
  )
  let service = match payload {
    Some(snapshot) => EnrollmentService::restore(snapshot)
    None => EnrollmentService::new()
  }
  let durable = {
    persistence: EnrollmentPostgres(database),
    service,
    mutex: Mutex(),
  }
  if payload is None {
    database.save_opaque_snapshot(
      "node_enrollment",
      "lunanexa.enrollment.v2",
      service.snapshot(),
    )
  }
  durable
}

///|
async fn FileEnrollmentService::persist(self : FileEnrollmentService) -> Unit {
  match self.persistence {
    EnrollmentFile(path) => write_enrollment(path, self.service.snapshot())
    EnrollmentPostgres(database) =>
      database.save_opaque_snapshot(
        "node_enrollment",
        "lunanexa.enrollment.v2",
        self.service.snapshot(),
      )
  }
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
  self.persist()
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
  self.persist()
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
  self.persist()
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
pub async fn FileEnrollmentService::snapshot(
  self : FileEnrollmentService,
) -> String {
  self.mutex.acquire()
  let snapshot = self.service.snapshot()
  self.mutex.release()
  snapshot
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
  self.persist()
  certificate
}
