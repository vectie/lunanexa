///|
enum CredentialPersistence {
  CredentialFile(String)
  CredentialPostgres(@database.PostgresDatabase)
}

///|
fn issuer_readiness_material(
  evidence : @credential.CredentialIssuerReadinessEvidence,
) -> String {
  { ..evidence, signature: "" }.to_json().stringify()
}

///|
/// Creates the signature used by the deployment evidence producer. This does
/// not perform a network probe; production evidence must be emitted only after
/// the deployment-owned issuer check succeeds.
pub fn issuer_readiness_signature(
  evidence : @credential.CredentialIssuerReadinessEvidence,
  secret : String,
) -> String {
  if secret.length() < 32 || secret.length() > 4096 {
    return ""
  }
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode(issuer_readiness_material(evidence)).view(),
    ),
  )
}

///|
/// Loads a bounded signed issuer health document. Kubernetes projected Secret
/// symlinks are accepted only when their resolved regular-file target stays
/// beneath the configured mount. Missing configuration is an intentional
/// pending state; partial or invalid configuration fails startup.
pub async fn load_issuer_readiness_evidence(
  path : String?,
  secret : String?,
  now_unix_ms : Int64,
) -> @credential.CredentialIssuerReadinessEvidence? {
  match (path, secret) {
    (None, None) | (Some(""), None) | (None, Some("")) => None
    (Some(path), Some(secret)) => {
      if !path.has_prefix("/") || secret.length() < 32 || secret.length() > 4096 {
        raise @credential.CredentialHandoffError::InvalidInput(
          "credential issuer readiness configuration is invalid",
        )
      }
      let resolved = @fs.realpath(path)
      guard path.rev_find("/") is Some(separator) && separator > 0 else {
        raise @credential.CredentialHandoffError::InvalidInput(
          "credential issuer readiness path is invalid",
        )
      }
      let configured_directory = @fs.realpath(path[:separator])
      if !resolved.has_prefix("\{configured_directory}/") ||
        @fs.kind(resolved, follow_symlink=true) != Regular {
        raise @credential.CredentialHandoffError::InvalidInput(
          "credential issuer readiness must resolve inside its configured directory",
        )
      }
      let bytes = @fs.read_file(resolved).binary()
      if bytes.length() == 0 || bytes.length() > 16384 {
        raise @credential.CredentialHandoffError::InvalidInput(
          "credential issuer readiness document size is invalid",
        )
      }
      let evidence : @credential.CredentialIssuerReadinessEvidence = @json.from_json(
        @json.parse(@utf8.decode(bytes)),
      ) catch {
        _ =>
          raise @credential.CredentialHandoffError::InvalidInput(
            "credential issuer readiness document is malformed",
          )
      }
      let expected = issuer_readiness_signature(evidence, secret)
      if !@credential.credential_issuer_evidence_ready(evidence, now_unix_ms) ||
        expected.length() != evidence.signature.length() {
        raise @credential.CredentialHandoffError::InvalidInput(
          "credential issuer readiness evidence is invalid or expired",
        )
      }
      let mut difference = 0
      for index in 0..<expected.length() {
        difference = difference |
          (expected[index].to_int() ^ evidence.signature[index].to_int())
      }
      if difference != 0 {
        raise @credential.CredentialHandoffError::InvalidInput(
          "credential issuer readiness signature is invalid",
        )
      }
      Some(evidence)
    }
    _ =>
      raise @credential.CredentialHandoffError::InvalidInput(
        "credential issuer readiness path and secret must be configured together",
      )
  }
}

///|
pub struct CredentialHandoffStore {
  persistence : CredentialPersistence
  issuer_secret : String
  issuer_readiness : @credential.CredentialIssuerReadinessEvidence?
  mut records : Map[String, @credential.CredentialHandoffRecord]
  mutex : @async.Mutex
}

///|
fn sorted_records(
  records : Map[String, @credential.CredentialHandoffRecord],
) -> Array[@credential.CredentialHandoffRecord] {
  let values = records.values().to_array()
  values.sort_by_key(value => value.handoff_ref)
  values
}

///|
fn CredentialHandoffStore::snapshot_unlocked(
  self : CredentialHandoffStore,
) -> @credential.CredentialHandoffSnapshot {
  {
    schema_version: @credential.snapshot_schema_version,
    records: sorted_records(self.records),
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @credential.CredentialHandoffSnapshot,
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
fn CredentialHandoffStore::restore(
  self : CredentialHandoffStore,
  snapshot : @credential.CredentialHandoffSnapshot,
) -> Unit raise @credential.CredentialHandoffError {
  if snapshot.schema_version != @credential.snapshot_schema_version {
    raise InvalidSnapshot("unsupported credential handoff snapshot")
  }
  let request_ids : Map[String, String] = Map([])
  let lease_generations : Map[String, String] = Map([])
  for record in snapshot.records {
    @credential.validate_issue_intent({
      request_id: record.request_id,
      lease_id: record.lease_id,
      expected_generation: record.generation,
      host_alias: record.host_alias,
      ssh_port: record.ssh_port,
      host_key_fingerprint: record.host_key_fingerprint,
      issuer_redirect_url: record.issuer_redirect_url,
    })
    if record.version != @credential.contract_version ||
      !@contracts.valid_identifier(record.handoff_ref) ||
      !@contracts.valid_identifier(record.node_id, maximum_length=128) ||
      !@contracts.valid_identifier(record.subject_ref) ||
      !@nodelease.valid_unix_username(record.username) ||
      record.created_unix_ms <= 0L ||
      record.expires_unix_ms <= record.created_unix_ms ||
      record.redeemed_unix_ms.map_or(false, value => {
        value < record.created_unix_ms || value >= record.expires_unix_ms
      }) ||
      record.revoked_unix_ms.map_or(false, value => {
        value < record.created_unix_ms
      }) ||
      self.records.contains(record.handoff_ref) ||
      request_ids.contains(record.request_id) ||
      lease_generations.contains("\{record.lease_id}:\{record.generation}") {
      raise InvalidSnapshot("invalid credential handoff record")
    }
    self.records[record.handoff_ref] = record
    request_ids[record.request_id] = record.handoff_ref
    lease_generations["\{record.lease_id}:\{record.generation}"] = record.handoff_ref
  }
}

///|
fn CredentialHandoffStore::empty(
  persistence : CredentialPersistence,
  issuer_secret : String,
) -> CredentialHandoffStore raise @credential.CredentialHandoffError {
  if issuer_secret.length() < 32 {
    raise InvalidInput("credential handoff issuer secret is too short")
  }
  {
    persistence,
    issuer_secret,
    issuer_readiness: None,
    records: Map([]),
    mutex: Mutex(),
  }
}

///|
/// Installs bounded deployment-owned health evidence for the external issuer.
/// The evidence is intentionally not persisted with customer handoff records.
pub fn CredentialHandoffStore::with_issuer_readiness(
  self : CredentialHandoffStore,
  evidence : @credential.CredentialIssuerReadinessEvidence,
) -> CredentialHandoffStore raise @credential.CredentialHandoffError {
  if !@credential.credential_issuer_evidence_ready(
      evidence,
      evidence.checked_unix_ms,
    ) {
    raise InvalidInput("credential issuer readiness evidence is invalid")
  }
  { ..self, issuer_readiness: Some(evidence) }
}

///|
pub fn CredentialHandoffStore::issuer_adapter_ready(
  self : CredentialHandoffStore,
  now_unix_ms : Int64,
) -> Bool {
  match self.issuer_readiness {
    Some(evidence) =>
      @credential.credential_issuer_evidence_ready(evidence, now_unix_ms)
    None => false
  }
}

///|
pub fn CredentialHandoffStore::issuer_redirect_ready(
  self : CredentialHandoffStore,
  redirect_url : String,
  now_unix_ms : Int64,
) -> Bool {
  match self.issuer_readiness {
    Some(evidence) =>
      @credential.credential_issuer_evidence_ready(evidence, now_unix_ms) &&
      @credential.credential_issuer_origin_matches(evidence, redirect_url)
    None => false
  }
}

///|
pub async fn CredentialHandoffStore::open(
  path : String,
  issuer_secret : String,
) -> CredentialHandoffStore {
  if path.trim() == "" {
    raise @credential.CredentialHandoffError::InvalidInput(
      "credential handoff path is empty",
    )
  }
  let store = CredentialHandoffStore::empty(CredentialFile(path), issuer_secret)
  if @fs.exists(path) {
    let snapshot : @credential.CredentialHandoffSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      _ =>
        raise @credential.CredentialHandoffError::InvalidSnapshot(
          "credential handoff snapshot is malformed",
        )
    }
    store.restore(snapshot)
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn CredentialHandoffStore::open_postgres(
  database : @database.PostgresDatabase,
  issuer_secret : String,
) -> CredentialHandoffStore {
  let store = CredentialHandoffStore::empty(
    CredentialPostgres(database),
    issuer_secret,
  )
  match
    database.load_snapshot(
      "credential_handoffs", @credential.snapshot_schema_version,
    ) {
    Some(payload) => {
      let snapshot : @credential.CredentialHandoffSnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
        _ =>
          raise @credential.CredentialHandoffError::InvalidSnapshot(
            "credential handoff snapshot is malformed",
          )
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "credential_handoffs",
        @credential.snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn CredentialHandoffStore::persist(self : CredentialHandoffStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    CredentialFile(path) => write_snapshot(path, snapshot)
    CredentialPostgres(database) =>
      database.save_opaque_snapshot(
        "credential_handoffs",
        @credential.snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn CredentialHandoffStore::handoff_ref(
  self : CredentialHandoffStore,
  intent : @credential.CredentialHandoffIssueIntent,
  lease : @nodelease.ExclusiveNodeLease,
  now_unix_ms : Int64,
) -> String {
  let payload = "lunanexa.credential-handoff.v1|\{intent.request_id}|\{lease.intent.lease_id}|\{lease.intent.subject_ref}|\{lease.intent.node_id}|\{lease.generation}|\{now_unix_ms}"
  "lnxh_\{@crypto.bytes_to_hex_string(@crypto.hmac(@crypto.SHA256::new(), @utf8.encode(self.issuer_secret).view(), @utf8.encode(payload).view()))}"
}

///|
fn CredentialHandoffStore::by_request(
  self : CredentialHandoffStore,
  request_id : String,
) -> @credential.CredentialHandoffRecord? {
  self.records.values().find_first(record => record.request_id == request_id)
}

///|
pub async fn CredentialHandoffStore::issue(
  self : CredentialHandoffStore,
  intent : @credential.CredentialHandoffIssueIntent,
  lease : @nodelease.ExclusiveNodeLease,
  now_unix_ms : Int64,
) -> @credential.CredentialHandoffRecord {
  @credential.validate_issue_intent(intent)
  if !self.issuer_redirect_ready(intent.issuer_redirect_url, now_unix_ms) {
    raise @credential.CredentialHandoffError::InvalidInput(
      "credential redirect is not authorized by current issuer evidence",
    )
  }
  if intent.lease_id != lease.intent.lease_id ||
    intent.expected_generation != lease.generation {
    raise @credential.CredentialHandoffError::StaleGeneration
  }
  if lease.state != Active ||
    now_unix_ms < lease.intent.starts_unix_ms ||
    now_unix_ms >= lease.intent.expires_unix_ms {
    raise @credential.CredentialHandoffError::InvalidInput(
      "credential handoff requires an active lease",
    )
  }
  self.mutex.acquire()
  let previous = self.records.copy()
  try {
    match self.by_request(intent.request_id) {
      Some(existing) if existing.lease_id == lease.intent.lease_id &&
        existing.generation == lease.generation &&
        existing.host_alias == intent.host_alias &&
        existing.ssh_port == intent.ssh_port &&
        existing.host_key_fingerprint == intent.host_key_fingerprint &&
        existing.issuer_redirect_url == intent.issuer_redirect_url => {
        self.mutex.release()
        return existing
      }
      Some(_) => raise @credential.CredentialHandoffError::IdempotencyConflict
      None => ()
    }
    if self.records
      .values()
      .any(record => {
        record.lease_id == lease.intent.lease_id &&
        record.generation == lease.generation
      }) {
      raise @credential.CredentialHandoffError::IdempotencyConflict
    }
    let handoff_ref = self.handoff_ref(intent, lease, now_unix_ms)
    let record : @credential.CredentialHandoffRecord = {
      version: @credential.contract_version,
      handoff_ref,
      request_id: intent.request_id,
      lease_id: lease.intent.lease_id,
      node_id: lease.intent.node_id,
      subject_ref: lease.intent.subject_ref,
      generation: lease.generation,
      username: lease.intent.unix_username,
      host_alias: intent.host_alias,
      ssh_port: intent.ssh_port,
      host_key_fingerprint: intent.host_key_fingerprint,
      issuer_redirect_url: intent.issuer_redirect_url,
      created_unix_ms: now_unix_ms,
      expires_unix_ms: lease.intent.expires_unix_ms,
      redeemed_unix_ms: None,
      revoked_unix_ms: None,
    }
    self.records[handoff_ref] = record
    self.persist()
    self.mutex.release()
    record
  } catch {
    error => {
      self.records = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn CredentialHandoffStore::view_for_lease(
  self : CredentialHandoffStore,
  lease : @nodelease.ExclusiveNodeLease,
  subject_ref : String,
  now_unix_ms : Int64,
) -> @credential.CustomerCredentialHandoffView? {
  self.mutex.acquire()
  let record = self.records
    .values()
    .find_first(value => {
      value.lease_id == lease.intent.lease_id &&
      value.generation == lease.generation &&
      value.subject_ref == subject_ref
    })
  self.mutex.release()
  match record {
    Some(value) =>
      Some(@credential.customer_view(value, subject_ref, now_unix_ms))
    None => None
  }
}

///|
fn CredentialHandoffStore::redemption(
  self : CredentialHandoffStore,
  record : @credential.CredentialHandoffRecord,
) -> @credential.CredentialHandoffRedemption raise @credential.CredentialHandoffError {
  let redeemed_unix_ms = record.redeemed_unix_ms.unwrap()
  let payload = "lunanexa.credential-redemption.v1|\{record.handoff_ref}|\{record.lease_id}|\{record.subject_ref}|\{record.generation}|\{redeemed_unix_ms}"
  let receipt = "lnxr_\{@crypto.bytes_to_hex_string(@crypto.hmac(@crypto.SHA256::new(), @utf8.encode(self.issuer_secret).view(), @utf8.encode(payload).view()))}"
  {
    version: @credential.contract_version,
    handoff_ref: record.handoff_ref,
    lease_ref: record.lease_id,
    generation: record.generation,
    issuer_redirect_url: record.issuer_redirect_url,
    host_alias: record.host_alias,
    ssh_port: record.ssh_port,
    host_key_fingerprint: record.host_key_fingerprint,
    connection_command: @credential.connection_command(
      record.username,
      record.host_alias,
      record.ssh_port,
    ),
    valid_until_unix_ms: record.expires_unix_ms,
    redemption_receipt: receipt,
    one_time: true,
    raw_secret_included: false,
  }
}

///| Redeeming records the single issuer capability issuance exactly once.
/// Repeating the same subject- and generation-bound request only recovers the
/// identical safe metadata and receipt; it never creates another handoff.

///|
pub async fn CredentialHandoffStore::redeem(
  self : CredentialHandoffStore,
  handoff_ref : String,
  lease : @nodelease.ExclusiveNodeLease,
  subject_ref : String,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> @credential.CredentialHandoffRedemption {
  self.mutex.acquire()
  let previous = self.records.copy()
  try {
    guard self.records.get(handoff_ref) is Some(record) else {
      raise @credential.CredentialHandoffError::NotFound
    }
    if record.subject_ref != subject_ref ||
      record.lease_id != lease.intent.lease_id ||
      record.node_id != lease.intent.node_id {
      raise @credential.CredentialHandoffError::NotFound
    }
    if record.generation != expected_generation ||
      lease.generation != expected_generation ||
      lease.state != Active {
      raise @credential.CredentialHandoffError::StaleGeneration
    }
    if record.revoked_unix_ms is Some(_) {
      raise @credential.CredentialHandoffError::Revoked
    }
    if now_unix_ms >= record.expires_unix_ms ||
      now_unix_ms >= lease.intent.expires_unix_ms {
      raise @credential.CredentialHandoffError::Expired
    }
    if record.redeemed_unix_ms is Some(_) {
      let recovered = self.redemption(record)
      self.mutex.release()
      return recovered
    }
    let redeemed = { ..record, redeemed_unix_ms: Some(now_unix_ms) }
    self.records[handoff_ref] = { ..redeemed }
    self.persist()
    self.mutex.release()
    self.redemption(redeemed)
  } catch {
    error => {
      self.records = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn CredentialHandoffStore::revoke_for_lease(
  self : CredentialHandoffStore,
  lease_id : String,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  let previous = self.records.copy()
  let mut changed = false
  try {
    for handoff_ref, record in self.records.copy() {
      if record.lease_id == lease_id && record.revoked_unix_ms is None {
        self.records[handoff_ref] = {
          ..record,
          revoked_unix_ms: Some(now_unix_ms),
        }
        changed = true
      }
    }
    if changed {
      self.persist()
    }
    self.mutex.release()
    changed
  } catch {
    error => {
      self.records = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn CredentialHandoffStore::snapshot(
  self : CredentialHandoffStore,
) -> @credential.CredentialHandoffSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}
