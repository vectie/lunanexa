///|
priv struct ImportSnapshot {
  schema_version : Int
  operations : Array[ImportOperation]
} derive(FromJson, ToJson)

///|
extend ImportSnapshot with ToJson::{to_json}

///|
const ImportSnapshotSchemaVersion : Int = 2

///|
fn snapshot_schema_version(value : Json) -> Double? {
  guard value is Object(fields) &&
    fields.get("schema_version") is Some(Number(version, ..)) else {
    return None
  }
  Some(version)
}

///|
/// Snapshot v1 predates `local_directory`. Normalize the decoded document
/// instead of failing the read, so an upgrade keeps every existing import.
fn migrate_snapshot(value : Json) -> Json {
  guard value is Object(fields) &&
    fields.get("operations") is Some(Array(items)) else {
    return value
  }
  let migrated : Array[Json] = []
  for item in items {
    match item {
      Object(entry) if !entry.contains("local_directory") => {
        let entry = entry.copy()
        entry["local_directory"] = Json::string("")
        migrated.push(Json::object(entry))
      }
      _ => migrated.push(item)
    }
  }
  let normalized = fields.copy()
  normalized["operations"] = Json::array(migrated)
  normalized["schema_version"] = Json::number(
    ImportSnapshotSchemaVersion.to_double(),
  )
  Json::object(normalized)
}

///|
pub struct FileImportStore {
  path : String
  mut operations : Map[String, ImportOperation]
  mutex : @async.Mutex
}

///|
async fn write_snapshot(
  path : String,
  operations : Map[String, ImportOperation],
) -> Unit {
  let records = operations.values().to_array()
  records.sort_by((left, right) => {
    let created = left.created_unix_ms.compare(right.created_unix_ms)
    if created == 0 {
      left.import_id.compare(right.import_id)
    } else {
      created
    }
  })
  let snapshot : ImportSnapshot = {
    schema_version: ImportSnapshotSchemaVersion,
    operations: records,
  }
  let next = "\{path}.next"
  errdefer (@fs.remove(next) catch { _ => () })
  @fs.write_file(
    next,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(next, path, replace=true)
}

///|
pub async fn FileImportStore::open(path : String) -> FileImportStore {
  let operations : Map[String, ImportOperation] = Map([])
  if @fs.exists(path) {
    try {
      let document = @json.parse(@fs.read_file(path).text())
      guard snapshot_schema_version(document) is Some(version) &&
        version >= 1.0 &&
        version <= ImportSnapshotSchemaVersion.to_double() else {
        raise Failure("unsupported model-source snapshot")
      }
      let snapshot : ImportSnapshot = @json.from_json(
        migrate_snapshot(document),
      )
      for operation in snapshot.operations {
        let restored = if operation.state == Downloading ||
          operation.state == Verifying {
          { ..operation, state: Queued, error_code: "recovered-after-restart", }
        } else {
          operation
        }
        operations[operation.import_id] = restored
      }
    } catch {
      error => raise Failure("invalid model-source snapshot: \{Repr(error)}")
    } noraise {
      _ => ()
    }
  }
  let store : FileImportStore = { path, operations, mutex: Mutex(), }
  write_snapshot(path, operations)
  store
}

///|
async fn FileImportStore::persist(self : FileImportStore) -> Unit {
  write_snapshot(self.path, self.operations)
}

///|
async fn FileImportStore::create_record(
  self : FileImportStore,
  request : ImportRequest,
  license : String,
  local_directory : String,
  now_unix_ms : Int64,
  supersede? : Bool = false,
) -> ImportOperation {
  let id = import_id(request.model_id, request.revision)
  self.mutex.acquire()
  defer self.mutex.release()
  let before = self.operations.copy()
  errdefer {
    self.operations = before
  }
  if !supersede && self.operations.contains(id) {
    raise ImportAlreadyExists
  }
  let record : ImportOperation = {
    import_id: id,
    source: "modelscope",
    model_id: request.model_id,
    revision: request.revision,
    state: Queued,
    files_total: 0,
    files_completed: 0,
    bytes_total: 0L,
    bytes_completed: 0L,
    manifest_digest: "",
    artifact_uri: "",
    license,
    local_directory,
    error_code: "",
    cancel_requested: false,
    created_unix_ms: now_unix_ms,
    updated_unix_ms: now_unix_ms,
  }
  self.operations[id] = record
  self.persist()
  record
}

///|
pub async fn FileImportStore::create(
  self : FileImportStore,
  request : ImportRequest,
  license : String,
  now_unix_ms : Int64,
) -> ImportOperation {
  self.create_record(request, license, "", now_unix_ms)
}

///|
/// Register a revision the operator already placed inside the managed model
/// store. The worker still has to prove every file against ModelScope before
/// the import becomes `Verified`; nothing here is trusted on assertion.
///
/// The same upstream revision may be registered again when the directory the
/// old record pointed at no longer exists: moving or renaming a directory is a
/// layout change, not a different revision, and the stale record could not
/// serve anything anyway. The record is replaced, never duplicated.
pub async fn FileImportStore::create_local(
  self : FileImportStore,
  request : ImportRequest,
  license : String,
  local_directory : String,
  model_root : String,
  now_unix_ms : Int64,
) -> ImportOperation {
  if !valid_local_directory(local_directory) {
    raise InvalidRepositoryPath
  }
  let id = import_id(request.model_id, request.revision)
  self.mutex.acquire()
  let previous = self.operations.get(id)
  self.mutex.release()
  let supersede = match previous {
    Some(record) =>
      record.local_directory != "" &&
      !@fs.exists("\{model_root}/\{record.local_directory}")
    None => false
  }
  self.create_record(request, license, local_directory, now_unix_ms, supersede~)
}

///|
pub async fn FileImportStore::list(
  self : FileImportStore,
) -> Array[ImportOperation] {
  self.mutex.acquire()
  let records = self.operations.values().to_array()
  self.mutex.release()
  records.sort_by((left, right) => {
    let created = right.created_unix_ms.compare(left.created_unix_ms)
    if created == 0 {
      left.import_id.compare(right.import_id)
    } else {
      created
    }
  })
  records
}

///|
pub async fn FileImportStore::get(
  self : FileImportStore,
  id : String,
) -> ImportOperation? {
  self.mutex.acquire()
  let record = self.operations.get(id)
  self.mutex.release()
  record
}

///|
pub async fn FileImportStore::next_queued(
  self : FileImportStore,
) -> ImportOperation? {
  self.mutex.acquire()
  defer self.mutex.release()
  let before = self.operations.copy()
  errdefer {
    self.operations = before
  }
  let mut queued : ImportOperation? = None
  for record in self.operations.values() {
    if queued is None && record.state == Queued {
      queued = Some(record)
    }
  }
  match queued {
    Some(record) => {
      let next = {
        ..record,
        state: if record.local_directory == "" {
          Downloading
        } else {
          Verifying
        },
        error_code: "",
        updated_unix_ms: @async.now(),
      }
      self.operations[record.import_id] = next
      self.persist()
      Some(next)
    }
    None => None
  }
}

///|
pub async fn FileImportStore::replace(
  self : FileImportStore,
  record : ImportOperation,
) -> ImportOperation {
  self.mutex.acquire()
  defer self.mutex.release()
  let before = self.operations.copy()
  errdefer {
    self.operations = before
  }
  if !self.operations.contains(record.import_id) {
    raise ImportNotFound
  }
  self.operations[record.import_id] = record
  self.persist()
  record
}

///|
pub async fn FileImportStore::cancel(
  self : FileImportStore,
  id : String,
  now_unix_ms : Int64,
) -> ImportOperation {
  self.mutex.acquire()
  defer self.mutex.release()
  let before = self.operations.copy()
  errdefer {
    self.operations = before
  }
  guard self.operations.get(id) is Some(record) else { raise ImportNotFound }
  let next = match record.state {
    Queued => { ..record, state: Cancelled, updated_unix_ms: now_unix_ms, }
    // Both in-flight states have to accept a cancellation request, otherwise a
    // revision being re-derived can never be withdrawn.
    Downloading | Verifying =>
      { ..record, cancel_requested: true, updated_unix_ms: now_unix_ms, }
    _ => raise ImportNotCancelable
  }
  self.operations[id] = next
  self.persist()
  next
}

///|
pub async fn FileImportStore::retry(
  self : FileImportStore,
  id : String,
  now_unix_ms : Int64,
) -> ImportOperation {
  self.mutex.acquire()
  defer self.mutex.release()
  let before = self.operations.copy()
  errdefer {
    self.operations = before
  }
  guard self.operations.get(id) is Some(record) else { raise ImportNotFound }
  let next = match record.state {
    Failed | Cancelled =>
      {
        ..record,
        state: Queued,
        error_code: "",
        cancel_requested: false,
        updated_unix_ms: now_unix_ms,
      }
    _ => raise ImportNotRetryable
  }
  self.operations[id] = next
  self.persist()
  next
}
