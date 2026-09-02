///|
priv struct ImportSnapshot {
  schema_version : Int
  operations : Array[ImportOperation]
} derive(FromJson, ToJson)

///|
extend ImportSnapshot with ToJson::{to_json}

///|
pub struct FileImportStore {
  path : String
  operations : Map[String, ImportOperation]
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
  let snapshot : ImportSnapshot = { schema_version: 1, operations: records }
  let next = "\{path}.next"
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
      let snapshot : ImportSnapshot = @json.from_json(
        @json.parse(@fs.read_file(path).text()),
      )
      if snapshot.schema_version != 1 {
        raise Failure("unsupported model-source snapshot")
      }
      for operation in snapshot.operations {
        let restored = if operation.state == Downloading {
          { ..operation, state: Queued, error_code: "recovered-after-restart" }
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
  let store : FileImportStore = { path, operations, mutex: Mutex() }
  write_snapshot(path, operations)
  store
}

///|
async fn FileImportStore::persist(self : FileImportStore) -> Unit {
  write_snapshot(self.path, self.operations)
}

///|
pub async fn FileImportStore::create(
  self : FileImportStore,
  request : ImportRequest,
  license : String,
  now_unix_ms : Int64,
) -> ImportOperation {
  let id = import_id(request.model_id, request.revision)
  self.mutex.acquire()
  try {
    if self.operations.contains(id) {
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
      error_code: "",
      cancel_requested: false,
      created_unix_ms: now_unix_ms,
      updated_unix_ms: now_unix_ms,
    }
    self.operations[id] = record
    self.persist()
    record
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    value => {
      self.mutex.release()
      value
    }
  }
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
  try {
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
          state: Downloading,
          error_code: "",
          updated_unix_ms: @async.now(),
        }
        self.operations[record.import_id] = next
        self.persist()
        Some(next)
      }
      None => None
    }
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    value => {
      self.mutex.release()
      value
    }
  }
}

///|
pub async fn FileImportStore::replace(
  self : FileImportStore,
  record : ImportOperation,
) -> ImportOperation {
  self.mutex.acquire()
  try {
    if !self.operations.contains(record.import_id) {
      raise ImportNotFound
    }
    self.operations[record.import_id] = record
    self.persist()
    record
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    value => {
      self.mutex.release()
      value
    }
  }
}

///|
pub async fn FileImportStore::cancel(
  self : FileImportStore,
  id : String,
  now_unix_ms : Int64,
) -> ImportOperation {
  self.mutex.acquire()
  try {
    guard self.operations.get(id) is Some(record) else { raise ImportNotFound }
    let next = match record.state {
      Queued => { ..record, state: Cancelled, updated_unix_ms: now_unix_ms }
      Downloading =>
        { ..record, cancel_requested: true, updated_unix_ms: now_unix_ms }
      _ => raise ImportNotCancelable
    }
    self.operations[id] = next
    self.persist()
    next
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    value => {
      self.mutex.release()
      value
    }
  }
}

///|
pub async fn FileImportStore::retry(
  self : FileImportStore,
  id : String,
  now_unix_ms : Int64,
) -> ImportOperation {
  self.mutex.acquire()
  try {
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
  } catch {
    error => {
      self.mutex.release()
      raise error
    }
  } noraise {
    value => {
      self.mutex.release()
      value
    }
  }
}
