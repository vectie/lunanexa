///|
enum AccessPersistence {
  AccessFile(String)
  AccessPostgres(@database.PostgresDatabase)
}

///|
pub struct AccessStore {
  persistence : AccessPersistence
  issuer_secret : String
  mut credentials : Map[String, ApiCredential]
  mutex : @async.Mutex
}

///|
fn digest_secret(secret : String) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(secret)))}"
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn valid_text(value : String, maximum : Int) -> Bool {
  value.length() > 0 &&
  value.length() <= maximum &&
  value.all(character => {
    character.is_printable() && character != '<' && character != '>'
  })
}

///|
fn valid_billing_attribution(
  organization_id : String?,
  project_id : String?,
) -> Bool {
  match (organization_id, project_id) {
    (None, None) => true
    (Some(organization), Some(project)) =>
      @contracts.valid_identifier(organization) &&
      @contracts.valid_identifier(project)
    _ => false
  }
}

///|
pub fn validate_api_key_intent(
  intent : ApiKeyIssueIntent,
  now_unix_ms : Int64,
) -> Unit raise AccessError {
  if !@contracts.valid_identifier(intent.key_id) ||
    !@contracts.valid_identifier(intent.tenant_ref) ||
    !@contracts.valid_identifier(intent.subject_ref) ||
    !@contracts.valid_identifier(intent.organization_id) ||
    !@contracts.valid_identifier(intent.project_id) ||
    !valid_text(intent.display_name, 128) ||
    intent.scopes.length() == 0 ||
    intent.scopes.length() > 2 ||
    intent.scopes.any(scope => intent.scopes.count(scope) != 1) ||
    intent.allowed_models.length() > 128 ||
    intent.allowed_models.any(model => !@contracts.valid_identifier(model)) ||
    intent.allowed_models.any(model => intent.allowed_models.count(model) != 1) ||
    intent.expires_unix_ms <= now_unix_ms ||
    intent.expires_unix_ms - now_unix_ms > 31536000000L ||
    intent.maximum_requests <= 0L ||
    intent.maximum_requests > 1000000000L {
    raise InvalidInput("invalid API key intent")
  }
}

///|
fn sorted_credentials(
  values : Map[String, ApiCredential],
) -> Array[ApiCredential] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.key_id)
  result
}

///|
fn AccessStore::snapshot_unlocked(self : AccessStore) -> AccessSnapshot {
  {
    schema_version: snapshot_schema_version,
    credentials: sorted_credentials(self.credentials),
  }
}

///|
async fn write_file(path : String, snapshot : AccessSnapshot) -> Unit {
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
fn AccessStore::restore(
  self : AccessStore,
  snapshot : AccessSnapshot,
) -> Unit raise AccessError {
  if snapshot.schema_version != snapshot_schema_version {
    raise InvalidSnapshot("unsupported access snapshot")
  }
  for credential in snapshot.credentials {
    if self.credentials.contains(credential.key_id) ||
      !@contracts.valid_identifier(credential.key_id) ||
      !@contracts.valid_identifier(credential.tenant_ref) ||
      !@contracts.valid_identifier(credential.subject_ref) ||
      !valid_billing_attribution(
        credential.organization_id,
        credential.project_id,
      ) ||
      credential.secret_sha256.length() != 71 ||
      !credential.secret_sha256.has_prefix("sha256:") ||
      credential.issued_unix_ms <= 0L ||
      credential.expires_unix_ms <= credential.issued_unix_ms ||
      credential.maximum_requests <= 0L ||
      credential.consumed_requests < 0L ||
      credential.consumed_requests > credential.maximum_requests {
      raise InvalidSnapshot("invalid API credential")
    }
    self.credentials[credential.key_id] = credential
  }
}

///|
pub async fn AccessStore::open(
  path : String,
  issuer_secret : String,
) -> AccessStore {
  if path.trim() == "" || issuer_secret.length() < 32 {
    raise InvalidInput("access store path is empty")
  }
  let store : AccessStore = {
    persistence: AccessFile(path),
    issuer_secret,
    credentials: Map([]),
    mutex: Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : AccessSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error => raise InvalidSnapshot("\{Repr(error)}")
    }
    store.restore(snapshot)
  } else {
    write_file(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn AccessStore::open_postgres(
  database : @database.PostgresDatabase,
  issuer_secret : String,
) -> AccessStore {
  if issuer_secret.length() < 32 {
    raise InvalidInput("API key issuer authority is too short")
  }
  let store : AccessStore = {
    persistence: AccessPostgres(database),
    issuer_secret,
    credentials: Map([]),
    mutex: Mutex(),
  }
  match database.load_snapshot("access_keys", snapshot_schema_version) {
    Some(payload) => {
      let snapshot : AccessSnapshot = @json.from_json(@json.parse(payload)) catch {
        error => raise InvalidSnapshot("\{Repr(error)}")
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "access_keys",
        snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn AccessStore::persist(self : AccessStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    AccessFile(path) => write_file(path, snapshot)
    AccessPostgres(database) =>
      database.save_opaque_snapshot(
        "access_keys",
        snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn AccessStore::issue_secret(
  self : AccessStore,
  intent : ApiKeyIssueIntent,
  now_unix_ms : Int64,
) -> String {
  let key = @utf8.encode(self.issuer_secret)
  let material = @utf8.encode(
    "lunanexa.api-key.v2|\{intent.key_id}|\{intent.tenant_ref}|\{intent.subject_ref}|\{intent.organization_id}|\{intent.project_id}|\{now_unix_ms}",
  )
  "lnx_\{@crypto.bytes_to_hex_string(@crypto.hmac(@crypto.SHA256::new(), key.view(), material.view()))}"
}

///|
pub async fn AccessStore::issue(
  self : AccessStore,
  intent : ApiKeyIssueIntent,
  now_unix_ms : Int64,
) -> IssuedApiKey {
  validate_api_key_intent(intent, now_unix_ms)
  let secret = self.issue_secret(intent, now_unix_ms)
  self.mutex.acquire()
  let previous = self.credentials.copy()
  try {
    if self.credentials.contains(intent.key_id) {
      raise AlreadyExists(intent.key_id)
    }
    let credential : ApiCredential = {
      key_id: intent.key_id,
      tenant_ref: intent.tenant_ref,
      subject_ref: intent.subject_ref,
      organization_id: Some(intent.organization_id),
      project_id: Some(intent.project_id),
      display_name: intent.display_name,
      secret_sha256: digest_secret(secret),
      scopes: intent.scopes,
      allowed_models: intent.allowed_models,
      issued_unix_ms: now_unix_ms,
      expires_unix_ms: intent.expires_unix_ms,
      maximum_requests: intent.maximum_requests,
      consumed_requests: 0L,
      revoked_unix_ms: None,
    }
    self.credentials[intent.key_id] = credential
    self.persist()
    self.mutex.release()
    { credential, secret }
  } catch {
    error => {
      self.credentials = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccessStore::revoke(
  self : AccessStore,
  key_id : String,
  now_unix_ms : Int64,
) -> ApiCredential {
  self.mutex.acquire()
  let previous = self.credentials.copy()
  try {
    guard self.credentials.get(key_id) is Some(current) else {
      raise NotFound(key_id)
    }
    let revoked = { ..current, revoked_unix_ms: Some(now_unix_ms) }
    self.credentials[key_id] = revoked
    self.persist()
    self.mutex.release()
    revoked
  } catch {
    error => {
      self.credentials = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
/// Revokes every active personal API credential owned by one durable subject.
/// This is intentionally one-way: reactivating an account never resurrects a
/// credential that was invalidated by an account suspension or revocation.
pub async fn AccessStore::revoke_subject(
  self : AccessStore,
  subject_ref : String,
  now_unix_ms : Int64,
) -> Int {
  if !@contracts.valid_identifier(subject_ref) || now_unix_ms <= 0L {
    raise InvalidInput("invalid API-key subject revocation")
  }
  self.mutex.acquire()
  let previous = self.credentials.copy()
  try {
    let mut revoked_count = 0
    for key_id, credential in self.credentials {
      if credential.subject_ref == subject_ref &&
        credential.revoked_unix_ms is None {
        self.credentials[key_id] = {
          ..credential,
          revoked_unix_ms: Some(now_unix_ms),
        }
        revoked_count += 1
      }
    }
    if revoked_count > 0 {
      self.persist()
    }
    self.mutex.release()
    revoked_count
  } catch {
    error => {
      self.credentials = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccessStore::authorize(
  self : AccessStore,
  secret : String,
  scope : ApiKeyScope,
  tenant_ref? : String,
  model? : String,
  now_unix_ms : Int64,
  consume : Bool,
) -> ApiAuthorization {
  if secret.length() != 68 || !secret.has_prefix("lnx_") {
    raise Unauthorized
  }
  let digest = digest_secret(secret)
  self.mutex.acquire()
  let previous = self.credentials.copy()
  try {
    let mut matched : ApiCredential? = None
    for value in self.credentials.values() {
      if constant_time_equal(value.secret_sha256, digest) {
        matched = Some(value)
      }
    }
    guard matched is Some(current) else { raise Unauthorized }
    guard current.organization_id is Some(organization_id) &&
      current.project_id is Some(project_id) else {
      raise Unauthorized
    }
    if current.revoked_unix_ms is Some(_) ||
      current.expires_unix_ms <= now_unix_ms ||
      !current.scopes.contains(scope) ||
      tenant_ref.map(value => value != current.tenant_ref).unwrap_or(false) ||
      model
      .map(value => {
        current.allowed_models.length() > 0 &&
        !current.allowed_models.contains(value)
      })
      .unwrap_or(false) {
      raise Unauthorized
    }
    if consume && current.consumed_requests >= current.maximum_requests {
      raise QuotaExceeded
    }
    if consume {
      self.credentials[current.key_id] = {
        ..current,
        consumed_requests: current.consumed_requests + 1L,
      }
      self.persist()
    }
    self.mutex.release()
    {
      key_id: current.key_id,
      tenant_ref: current.tenant_ref,
      subject_ref: current.subject_ref,
      organization_id,
      project_id,
    }
  } catch {
    error => {
      self.credentials = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccessStore::snapshot(self : AccessStore) -> AccessSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}

///|
pub async fn AccessStore::views(self : AccessStore) -> Array[ApiCredentialView] {
  let snapshot = self.snapshot()
  snapshot.credentials.map(value => {
    key_id: value.key_id,
    tenant_ref: value.tenant_ref,
    subject_ref: value.subject_ref,
    organization_id: value.organization_id,
    project_id: value.project_id,
    display_name: value.display_name,
    scopes: value.scopes,
    allowed_models: value.allowed_models,
    issued_unix_ms: value.issued_unix_ms,
    expires_unix_ms: value.expires_unix_ms,
    maximum_requests: value.maximum_requests,
    consumed_requests: value.consumed_requests,
    revoked_unix_ms: value.revoked_unix_ms,
  })
}

///|
pub fn IssuedApiKey::public_view(self : IssuedApiKey) -> IssuedApiKeyView {
  {
    credential: {
      key_id: self.credential.key_id,
      tenant_ref: self.credential.tenant_ref,
      subject_ref: self.credential.subject_ref,
      organization_id: self.credential.organization_id,
      project_id: self.credential.project_id,
      display_name: self.credential.display_name,
      scopes: self.credential.scopes,
      allowed_models: self.credential.allowed_models,
      issued_unix_ms: self.credential.issued_unix_ms,
      expires_unix_ms: self.credential.expires_unix_ms,
      maximum_requests: self.credential.maximum_requests,
      consumed_requests: self.credential.consumed_requests,
      revoked_unix_ms: self.credential.revoked_unix_ms,
    },
    secret: self.secret,
  }
}

///|
pub async fn AccessStore::views_for_subject(
  self : AccessStore,
  tenant_ref : String,
  subject_ref : String,
) -> Array[ApiCredentialView] {
  self
  .views()
  .filter(value => {
    value.tenant_ref == tenant_ref && value.subject_ref == subject_ref
  })
}

///|
pub async fn AccessStore::revoke_for_subject(
  self : AccessStore,
  key_id : String,
  tenant_ref : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> ApiCredential {
  self.mutex.acquire()
  guard self.credentials.get(key_id) is Some(current) &&
    current.tenant_ref == tenant_ref &&
    current.subject_ref == subject_ref else {
    self.mutex.release()
    raise NotFound(key_id)
  }
  self.mutex.release()
  self.revoke(key_id, now_unix_ms)
}
