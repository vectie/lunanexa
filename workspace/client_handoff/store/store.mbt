///|
enum ClientHandoffPersistence {
  ClientHandoffFile(String)
  ClientHandoffPostgres(@database.PostgresDatabase)
}

///|
pub struct ClientHandoffStore {
  persistence : ClientHandoffPersistence
  issuer_secret : String
  mut handoffs : Map[String, @handoff.ClientHandoffRecord]
  mut credentials : Map[String, @handoff.ClientCredential]
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
fn sorted_handoffs(
  values : Map[String, @handoff.ClientHandoffRecord],
) -> Array[@handoff.ClientHandoffRecord] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.handoff_id)
  result
}

///|
fn sorted_credentials(
  values : Map[String, @handoff.ClientCredential],
) -> Array[@handoff.ClientCredential] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.key_id)
  result
}

///|
fn ClientHandoffStore::snapshot_unlocked(
  self : ClientHandoffStore,
) -> @handoff.ClientHandoffSnapshot {
  {
    schema_version: @handoff.snapshot_schema_version,
    handoffs: sorted_handoffs(self.handoffs),
    credentials: sorted_credentials(self.credentials),
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @handoff.ClientHandoffSnapshot,
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
fn ClientHandoffStore::empty(
  persistence : ClientHandoffPersistence,
  issuer_secret : String,
) -> ClientHandoffStore raise @handoff.ClientHandoffError {
  if issuer_secret.length() < 32 || issuer_secret.length() > 4096 {
    raise InvalidInput("client handoff issuer secret is invalid")
  }
  {
    persistence,
    issuer_secret,
    handoffs: Map([]),
    credentials: Map([]),
    mutex: Mutex(),
  }
}

///|
fn ClientHandoffStore::restore(
  self : ClientHandoffStore,
  snapshot : @handoff.ClientHandoffSnapshot,
) -> Unit raise @handoff.ClientHandoffError {
  if snapshot.schema_version != @handoff.snapshot_schema_version {
    raise InvalidSnapshot("unsupported client handoff snapshot")
  }
  for record in snapshot.handoffs {
    if record.version != @handoff.contract_version ||
      !@contracts.valid_identifier(record.handoff_id) ||
      !@contracts.valid_identifier(record.request_id) ||
      !@contracts.valid_identifier(record.client_id) ||
      !@contracts.valid_identifier(record.tenant_ref) ||
      !@contracts.valid_identifier(record.subject_ref) ||
      !@contracts.valid_identifier(record.api_key_id) ||
      !@contracts.valid_sha256_digest(record.code_sha256) ||
      record.created_unix_ms <= 0L ||
      record.handoff_expires_unix_ms <= record.created_unix_ms ||
      record.credential_expires_unix_ms <= record.handoff_expires_unix_ms ||
      record.redeemed_unix_ms.map_or(false, value => {
        value < record.created_unix_ms ||
        value >= record.handoff_expires_unix_ms
      }) ||
      record.revoked_unix_ms.map_or(false, value => {
        value < record.created_unix_ms
      }) ||
      self.handoffs.contains(record.handoff_id) ||
      self.handoffs.values().any(value => value.request_id == record.request_id) {
      raise InvalidSnapshot("invalid client handoff record")
    }
    self.handoffs[record.handoff_id] = record
  }
  for credential in snapshot.credentials {
    if !@contracts.valid_identifier(credential.key_id) ||
      !@contracts.valid_identifier(credential.handoff_id) ||
      !@contracts.valid_identifier(credential.client_id) ||
      !@contracts.valid_identifier(credential.tenant_ref) ||
      !@contracts.valid_identifier(credential.subject_ref) ||
      !@contracts.valid_sha256_digest(credential.secret_sha256) ||
      credential.issued_unix_ms <= 0L ||
      credential.expires_unix_ms <= credential.issued_unix_ms ||
      credential.maximum_requests <= 0L ||
      credential.consumed_requests < 0L ||
      credential.consumed_requests > credential.maximum_requests ||
      self.credentials.contains(credential.key_id) ||
      !self.handoffs.contains(credential.handoff_id) {
      raise InvalidSnapshot("invalid client credential")
    }
    guard self.handoffs.get(credential.handoff_id) is Some(record) &&
      record.api_key_id == credential.key_id &&
      record.client_id == credential.client_id &&
      record.tenant_ref == credential.tenant_ref &&
      record.subject_ref == credential.subject_ref else {
      raise InvalidSnapshot("client credential does not match its handoff")
    }
    self.credentials[credential.key_id] = credential
  }
  if self.handoffs
    .values()
    .any(record => !self.credentials.contains(record.api_key_id)) {
    raise InvalidSnapshot("client handoff credential is missing")
  }
}

///|
pub async fn ClientHandoffStore::open(
  path : String,
  issuer_secret : String,
) -> ClientHandoffStore {
  if path.trim() == "" {
    raise @handoff.ClientHandoffError::InvalidInput(
      "client handoff path is empty",
    )
  }
  let store = ClientHandoffStore::empty(ClientHandoffFile(path), issuer_secret)
  if @fs.exists(path) {
    let snapshot : @handoff.ClientHandoffSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      _ =>
        raise @handoff.ClientHandoffError::InvalidSnapshot(
          "client handoff snapshot is malformed",
        )
    }
    store.restore(snapshot)
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn ClientHandoffStore::open_postgres(
  database : @database.PostgresDatabase,
  issuer_secret : String,
) -> ClientHandoffStore {
  let store = ClientHandoffStore::empty(
    ClientHandoffPostgres(database),
    issuer_secret,
  )
  match
    database.load_snapshot("client_handoffs", @handoff.snapshot_schema_version) {
    Some(payload) => {
      let snapshot : @handoff.ClientHandoffSnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
        _ =>
          raise @handoff.ClientHandoffError::InvalidSnapshot(
            "client handoff snapshot is malformed",
          )
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "client_handoffs",
        @handoff.snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn ClientHandoffStore::persist(self : ClientHandoffStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    ClientHandoffFile(path) => write_snapshot(path, snapshot)
    ClientHandoffPostgres(database) =>
      database.save_opaque_snapshot(
        "client_handoffs",
        @handoff.snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn ClientHandoffStore::hmac_hex(
  self : ClientHandoffStore,
  material : String,
) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(self.issuer_secret).view(),
      @utf8.encode(material).view(),
    ),
  )
}

///|
fn ClientHandoffStore::handoff_code(
  self : ClientHandoffStore,
  intent : @handoff.ClientHandoffIssueIntent,
  created_unix_ms : Int64,
) -> String {
  "lnxc_\{self.hmac_hex("lunanexa.client-handoff.code.v1|\{intent.request_id}|\{intent.client_id}|\{intent.tenant_ref}|\{intent.subject_ref}|\{created_unix_ms}")}"
}

///|
fn ClientHandoffStore::api_secret(
  self : ClientHandoffStore,
  record : @handoff.ClientHandoffRecord,
) -> String {
  "lnx_\{self.hmac_hex("lunanexa.client-handoff.api.v1|\{record.api_key_id}|\{record.handoff_id}|\{record.tenant_ref}|\{record.subject_ref}|\{record.created_unix_ms}")}"
}

///|
fn ClientHandoffStore::by_request(
  self : ClientHandoffStore,
  request_id : String,
) -> @handoff.ClientHandoffRecord? {
  self.handoffs.values().find_first(record => record.request_id == request_id)
}

///|
fn ClientHandoffStore::issued_view(
  self : ClientHandoffStore,
  record : @handoff.ClientHandoffRecord,
) -> @handoff.IssuedClientHandoff {
  let intent : @handoff.ClientHandoffIssueIntent = {
    request_id: record.request_id,
    client_id: record.client_id,
    tenant_ref: record.tenant_ref,
    subject_ref: record.subject_ref,
    display_name: record.display_name,
    allowed_models: record.allowed_models,
    handoff_expires_unix_ms: record.handoff_expires_unix_ms,
    credential_expires_unix_ms: record.credential_expires_unix_ms,
    maximum_requests: record.maximum_requests,
  }
  {
    handoff_id: record.handoff_id,
    client_id: record.client_id,
    handoff_code: self.handoff_code(intent, record.created_unix_ms),
    handoff_expires_unix_ms: record.handoff_expires_unix_ms,
    credential_expires_unix_ms: record.credential_expires_unix_ms,
    redemption_path: "/v1/client-handoffs:redeem",
    one_time: true,
  }
}

///|
pub async fn ClientHandoffStore::issue(
  self : ClientHandoffStore,
  intent : @handoff.ClientHandoffIssueIntent,
  now_unix_ms : Int64,
) -> @handoff.IssuedClientHandoff {
  @handoff.validate_issue_intent(intent, now_unix_ms)
  self.mutex.acquire()
  let previous_handoffs = self.handoffs.copy()
  let previous_credentials = self.credentials.copy()
  try {
    match self.by_request(intent.request_id) {
      Some(existing) if existing.client_id == intent.client_id &&
        existing.tenant_ref == intent.tenant_ref &&
        existing.subject_ref == intent.subject_ref &&
        existing.display_name == intent.display_name &&
        existing.allowed_models == intent.allowed_models &&
        existing.handoff_expires_unix_ms == intent.handoff_expires_unix_ms &&
        existing.credential_expires_unix_ms == intent.credential_expires_unix_ms &&
        existing.maximum_requests == intent.maximum_requests => {
        let issued = self.issued_view(existing)
        self.mutex.release()
        return issued
      }
      Some(_) => raise @handoff.ClientHandoffError::IdempotencyConflict
      None => ()
    }
    let digest = self.hmac_hex(
      "lunanexa.client-handoff.id.v1|\{intent.request_id}|\{intent.client_id}|\{intent.subject_ref}|\{now_unix_ms}",
    )
    let handoff_id = "client-handoff-\{digest[:32]}"
    let api_key_id = "client-key-\{digest[32:]}"
    let code = self.handoff_code(intent, now_unix_ms)
    let record : @handoff.ClientHandoffRecord = {
      version: @handoff.contract_version,
      handoff_id,
      request_id: intent.request_id,
      client_id: intent.client_id,
      tenant_ref: intent.tenant_ref,
      subject_ref: intent.subject_ref,
      api_key_id,
      code_sha256: digest_secret(code),
      display_name: intent.display_name,
      allowed_models: intent.allowed_models.copy(),
      created_unix_ms: now_unix_ms,
      handoff_expires_unix_ms: intent.handoff_expires_unix_ms,
      credential_expires_unix_ms: intent.credential_expires_unix_ms,
      maximum_requests: intent.maximum_requests,
      redeemed_unix_ms: None,
      revoked_unix_ms: None,
    }
    let secret = self.api_secret(record)
    let credential : @handoff.ClientCredential = {
      key_id: api_key_id,
      handoff_id,
      client_id: intent.client_id,
      tenant_ref: intent.tenant_ref,
      subject_ref: intent.subject_ref,
      secret_sha256: digest_secret(secret),
      allowed_models: intent.allowed_models.copy(),
      issued_unix_ms: now_unix_ms,
      expires_unix_ms: intent.credential_expires_unix_ms,
      maximum_requests: intent.maximum_requests,
      consumed_requests: 0L,
      revoked_unix_ms: None,
    }
    self.handoffs[handoff_id] = record
    self.credentials[api_key_id] = credential
    self.persist()
    let issued = self.issued_view(record)
    self.mutex.release()
    issued
  } catch {
    error => {
      self.handoffs = previous_handoffs
      self.credentials = previous_credentials
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ClientHandoffStore::redeem(
  self : ClientHandoffStore,
  handoff_code : String,
  client_id : String,
  now_unix_ms : Int64,
) -> @handoff.ClientHandoffRedemption {
  if handoff_code.length() != 69 ||
    !handoff_code.has_prefix("lnxc_") ||
    !@contracts.valid_identifier(client_id) {
    raise @handoff.ClientHandoffError::Unauthorized
  }
  let code_digest = digest_secret(handoff_code)
  self.mutex.acquire()
  let previous = self.handoffs.copy()
  try {
    let mut matched : @handoff.ClientHandoffRecord? = None
    for record in self.handoffs.values() {
      if constant_time_equal(record.code_sha256, code_digest) {
        matched = Some(record)
      }
    }
    guard matched is Some(record) else {
      raise @handoff.ClientHandoffError::Unauthorized
    }
    if record.client_id != client_id {
      raise @handoff.ClientHandoffError::ClientMismatch
    }
    if record.revoked_unix_ms is Some(_) {
      raise @handoff.ClientHandoffError::Revoked
    }
    if record.redeemed_unix_ms is Some(_) {
      raise @handoff.ClientHandoffError::AlreadyRedeemed
    }
    if now_unix_ms >= record.handoff_expires_unix_ms {
      raise @handoff.ClientHandoffError::Expired
    }
    guard self.credentials.get(record.api_key_id) is Some(credential) else {
      raise @handoff.ClientHandoffError::NotFound
    }
    // Verify the deterministic secret before consuming the one-time record.
    // A corrupted credential snapshot must fail closed without persisting an
    // irreversible redeemed state.
    let secret = self.api_secret(record)
    if !constant_time_equal(digest_secret(secret), credential.secret_sha256) {
      raise @handoff.ClientHandoffError::Unauthorized
    }
    let redeemed = { ..record, redeemed_unix_ms: Some(now_unix_ms) }
    self.handoffs[record.handoff_id] = redeemed
    self.persist()
    self.mutex.release()
    {
      handoff_id: record.handoff_id,
      client_id: record.client_id,
      api_key_id: credential.key_id,
      api_secret: secret,
      tenant_ref: record.tenant_ref,
      subject_ref: record.subject_ref,
      allowed_models: record.allowed_models.copy(),
      expires_unix_ms: credential.expires_unix_ms,
      maximum_requests: credential.maximum_requests,
      one_time: true,
    }
  } catch {
    error => {
      self.handoffs = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ClientHandoffStore::authorize(
  self : ClientHandoffStore,
  secret : String,
  scope : @access.ApiKeyScope,
  model? : String,
  now_unix_ms : Int64,
  consume : Bool,
) -> @handoff.ClientAuthorization {
  if secret.length() != 68 || !secret.has_prefix("lnx_") {
    raise @handoff.ClientHandoffError::Unauthorized
  }
  // ApiKeyScope is intentionally accepted as a closed two-case authority:
  // every desktop handoff grants both model discovery and inference.
  ignore(scope)
  let secret_digest = digest_secret(secret)
  self.mutex.acquire()
  let previous = self.credentials.copy()
  try {
    let mut matched : @handoff.ClientCredential? = None
    for credential in self.credentials.values() {
      if constant_time_equal(credential.secret_sha256, secret_digest) {
        matched = Some(credential)
      }
    }
    guard matched is Some(current) else {
      raise @handoff.ClientHandoffError::Unauthorized
    }
    guard self.handoffs.get(current.handoff_id) is Some(record) &&
      record.redeemed_unix_ms is Some(_) &&
      record.revoked_unix_ms is None else {
      raise @handoff.ClientHandoffError::Unauthorized
    }
    if current.revoked_unix_ms is Some(_) ||
      current.expires_unix_ms <= now_unix_ms ||
      model
      .map(value => !current.allowed_models.contains(value))
      .unwrap_or(false) {
      raise @handoff.ClientHandoffError::Unauthorized
    }
    if consume && current.consumed_requests >= current.maximum_requests {
      raise @handoff.ClientHandoffError::QuotaExceeded
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
pub async fn ClientHandoffStore::revoke_for_subject(
  self : ClientHandoffStore,
  handoff_id : String,
  tenant_ref : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> @handoff.ClientHandoffView {
  self.mutex.acquire()
  let previous_handoffs = self.handoffs.copy()
  let previous_credentials = self.credentials.copy()
  try {
    guard self.handoffs.get(handoff_id) is Some(record) &&
      record.tenant_ref == tenant_ref &&
      record.subject_ref == subject_ref &&
      self.credentials.get(record.api_key_id) is Some(credential) else {
      raise @handoff.ClientHandoffError::NotFound
    }
    let revoked_at = record.revoked_unix_ms.unwrap_or(now_unix_ms)
    let revoked = { ..record, revoked_unix_ms: Some(revoked_at) }
    let revoked_credential = {
      ..credential,
      revoked_unix_ms: Some(credential.revoked_unix_ms.unwrap_or(revoked_at)),
    }
    self.handoffs[handoff_id] = revoked
    self.credentials[credential.key_id] = revoked_credential
    self.persist()
    let view = handoff_view(revoked, revoked_credential)
    self.mutex.release()
    view
  } catch {
    error => {
      self.handoffs = previous_handoffs
      self.credentials = previous_credentials
      self.mutex.release()
      raise error
    }
  }
}

///|
fn handoff_view(
  record : @handoff.ClientHandoffRecord,
  credential : @handoff.ClientCredential,
) -> @handoff.ClientHandoffView {
  {
    handoff_id: record.handoff_id,
    request_id: record.request_id,
    client_id: record.client_id,
    api_key_id: record.api_key_id,
    display_name: record.display_name,
    allowed_models: record.allowed_models.copy(),
    created_unix_ms: record.created_unix_ms,
    handoff_expires_unix_ms: record.handoff_expires_unix_ms,
    credential_expires_unix_ms: record.credential_expires_unix_ms,
    maximum_requests: credential.maximum_requests,
    consumed_requests: credential.consumed_requests,
    redeemed_unix_ms: record.redeemed_unix_ms,
    revoked_unix_ms: record.revoked_unix_ms,
  }
}

///|
pub async fn ClientHandoffStore::views_for_subject(
  self : ClientHandoffStore,
  tenant_ref : String,
  subject_ref : String,
) -> Array[@handoff.ClientHandoffView] {
  self.mutex.acquire()
  let result : Array[@handoff.ClientHandoffView] = []
  for record in sorted_handoffs(self.handoffs) {
    if record.tenant_ref == tenant_ref && record.subject_ref == subject_ref {
      match self.credentials.get(record.api_key_id) {
        Some(credential) => result.push(handoff_view(record, credential))
        None => ()
      }
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn ClientHandoffStore::snapshot(
  self : ClientHandoffStore,
) -> @handoff.ClientHandoffSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}
