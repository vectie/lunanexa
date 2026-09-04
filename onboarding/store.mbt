///|
enum AccessOnboardingPersistence {
  JournalFile(String)
  JournalPostgres(@database.PostgresDatabase)
}

///|
pub struct AccessOnboardingStore {
  persistence : AccessOnboardingPersistence
  mut operations : Map[String, AccessOnboardingRecord]
  mutex : @async.Mutex
}

///|
fn step_rank(step : AccessOnboardingStep) -> Int {
  match step {
    IntentRecorded => 0
    AccountReady => 1
    MembershipReady => 2
    WorkspaceUserReady => 3
    GrantReady => 4
    LeaseReady => 5
    Prepared => 6
    Enabled => 7
  }
}

///|
fn valid_identifier(value : String) -> Bool {
  @contracts.valid_identifier(value)
}

///|
fn validate_intent(
  intent : AccessOnboardingIntent,
) -> Unit raise AccessOnboardingError {
  let identifiers = [
    intent.operation_id,
    intent.fingerprint,
    intent.requested_by,
    intent.account_id,
    intent.subject_ref,
    intent.organization_id,
    intent.tenant_ref,
    intent.membership_id,
    intent.user_id,
    intent.grant_id,
    intent.lease_id,
    intent.identity_receipt,
  ]
  if identifiers.any(value => !valid_identifier(value)) ||
    intent.identity_issuer.trim() == "" ||
    intent.identity_issuer.length() > 512 ||
    intent.identity_subject_sha256.length() != 71 ||
    !intent.identity_subject_sha256.has_prefix("sha256:") ||
    intent.display_name.trim() == "" ||
    intent.display_name.length() > 128 ||
    intent.email.trim() == "" ||
    intent.email.length() > 320 ||
    intent.expires_unix_ms <= 0L {
    raise InvalidIntent("access onboarding intent is invalid")
  }
}

///|
fn sorted_operations(
  values : Map[String, AccessOnboardingRecord],
) -> Array[AccessOnboardingRecord] {
  let result = values.values().to_array()
  result.sort_by_key(record => record.intent.operation_id)
  result
}

///|
fn AccessOnboardingStore::snapshot_unlocked(
  self : AccessOnboardingStore,
) -> AccessOnboardingSnapshot {
  {
    schema_version: snapshot_schema_version,
    operations: sorted_operations(self.operations),
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : AccessOnboardingSnapshot,
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
fn AccessOnboardingStore::restore(
  self : AccessOnboardingStore,
  snapshot : AccessOnboardingSnapshot,
) -> Unit raise AccessOnboardingError {
  if snapshot.schema_version != snapshot_schema_version {
    raise InvalidSnapshot("unsupported access onboarding snapshot")
  }
  for record in snapshot.operations {
    validate_intent(record.intent)
    if self.operations.contains(record.intent.operation_id) ||
      record.attempts <= 0 ||
      record.created_unix_ms <= 0L ||
      record.updated_unix_ms < record.created_unix_ms ||
      (record.status == PreparedForEnablement && record.step != Prepared) ||
      (record.status == Completed && record.step != Enabled) {
      raise InvalidSnapshot("invalid access onboarding operation")
    }
    self.operations[record.intent.operation_id] = record
  }
}

///|
pub async fn AccessOnboardingStore::open(
  path : String,
) -> AccessOnboardingStore {
  if path.trim() == "" {
    raise InvalidSnapshot("access onboarding journal path is empty")
  }
  let store : AccessOnboardingStore = {
    persistence: JournalFile(path),
    operations: Map([]),
    mutex: Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : AccessOnboardingSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      _ => raise InvalidSnapshot("invalid access onboarding journal JSON")
    }
    store.restore(snapshot)
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn AccessOnboardingStore::open_postgres(
  database : @database.PostgresDatabase,
) -> AccessOnboardingStore {
  let store : AccessOnboardingStore = {
    persistence: JournalPostgres(database),
    operations: Map([]),
    mutex: Mutex(),
  }
  match database.load_snapshot("access_onboarding", snapshot_schema_version) {
    Some(payload) => {
      let snapshot : AccessOnboardingSnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
        _ => raise InvalidSnapshot("invalid database access onboarding journal")
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "access_onboarding",
        snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn AccessOnboardingStore::persist(self : AccessOnboardingStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    JournalFile(path) => write_snapshot(path, snapshot)
    JournalPostgres(database) =>
      database.save_opaque_snapshot(
        "access_onboarding",
        snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
pub async fn AccessOnboardingStore::begin(
  self : AccessOnboardingStore,
  intent : AccessOnboardingIntent,
  now_unix_ms : Int64,
) -> AccessOnboardingRecord {
  validate_intent(intent)
  if now_unix_ms <= 0L || intent.expires_unix_ms <= now_unix_ms {
    raise InvalidIntent("access onboarding time window is invalid")
  }
  self.mutex.acquire()
  let previous = self.operations.copy()
  try {
    match self.operations.get(intent.operation_id) {
      Some(record) if record.intent == intent => {
        self.mutex.release()
        return record
      }
      Some(_) => raise IdempotencyConflict(intent.operation_id)
      None => ()
    }
    let record : AccessOnboardingRecord = {
      intent,
      step: IntentRecorded,
      status: Running,
      attempts: 1,
      last_error_code: None,
      last_error_message: None,
      created_unix_ms: now_unix_ms,
      updated_unix_ms: now_unix_ms,
    }
    self.operations[intent.operation_id] = record
    self.persist()
    self.mutex.release()
    record
  } catch {
    error => {
      self.operations = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccessOnboardingStore::record(
  self : AccessOnboardingStore,
  operation_id : String,
) -> AccessOnboardingRecord? {
  self.mutex.acquire()
  let result = self.operations.get(operation_id)
  self.mutex.release()
  result
}

///|
pub async fn AccessOnboardingStore::snapshot(
  self : AccessOnboardingStore,
) -> AccessOnboardingSnapshot {
  self.mutex.acquire()
  let result = self.snapshot_unlocked()
  self.mutex.release()
  result
}

///|
pub async fn AccessOnboardingStore::pending(
  self : AccessOnboardingStore,
) -> Array[AccessOnboardingRecord] {
  self.mutex.acquire()
  let result = sorted_operations(self.operations).filter(record => {
    record.status == Running || record.status == RecoverableFailure
  })
  self.mutex.release()
  result
}

///|
pub async fn AccessOnboardingStore::retry(
  self : AccessOnboardingStore,
  operation_id : String,
  now_unix_ms : Int64,
) -> AccessOnboardingRecord {
  self.mutex.acquire()
  let previous = self.operations.copy()
  try {
    guard self.operations.get(operation_id) is Some(record) else {
      raise OperationNotFound(operation_id)
    }
    if record.status == Conflicted || record.status == Completed {
      self.mutex.release()
      return record
    }
    let resumed = {
      ..record,
      status: Running,
      attempts: record.attempts + 1,
      last_error_code: None,
      last_error_message: None,
      updated_unix_ms: now_unix_ms,
    }
    self.operations[operation_id] = resumed
    self.persist()
    self.mutex.release()
    resumed
  } catch {
    error => {
      self.operations = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccessOnboardingStore::advance(
  self : AccessOnboardingStore,
  operation_id : String,
  step : AccessOnboardingStep,
  now_unix_ms : Int64,
) -> AccessOnboardingRecord {
  self.mutex.acquire()
  let previous = self.operations.copy()
  try {
    guard self.operations.get(operation_id) is Some(record) else {
      raise OperationNotFound(operation_id)
    }
    if record.status == Conflicted {
      raise InvalidTransition("a conflicted onboarding cannot advance")
    }
    let current_rank = step_rank(record.step)
    let next_rank = step_rank(step)
    if next_rank < current_rank {
      self.mutex.release()
      return record
    }
    if next_rank > current_rank + 1 {
      raise InvalidTransition("access onboarding step was skipped")
    }
    let status = match step {
      Prepared => PreparedForEnablement
      Enabled => Completed
      _ => Running
    }
    let advanced = {
      ..record,
      step,
      status,
      last_error_code: None,
      last_error_message: None,
      updated_unix_ms: now_unix_ms,
    }
    self.operations[operation_id] = advanced
    self.persist()
    self.mutex.release()
    advanced
  } catch {
    error => {
      self.operations = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
fn bounded_message(message : String) -> String {
  if message.length() <= 240 {
    message
  } else {
    message[:240].to_owned()
  }
}

///|
pub async fn AccessOnboardingStore::fail(
  self : AccessOnboardingStore,
  operation_id : String,
  code : String,
  message : String,
  terminal : Bool,
  now_unix_ms : Int64,
) -> AccessOnboardingRecord {
  if !valid_identifier(code) {
    raise InvalidTransition("invalid onboarding failure code")
  }
  self.mutex.acquire()
  let previous = self.operations.copy()
  try {
    guard self.operations.get(operation_id) is Some(record) else {
      raise OperationNotFound(operation_id)
    }
    let failed = {
      ..record,
      status: if terminal {
        Conflicted
      } else {
        RecoverableFailure
      },
      last_error_code: Some(code),
      last_error_message: Some(bounded_message(message)),
      updated_unix_ms: now_unix_ms,
    }
    self.operations[operation_id] = failed
    self.persist()
    self.mutex.release()
    failed
  } catch {
    error => {
      self.operations = previous
      self.mutex.release()
      raise error
    }
  }
}
