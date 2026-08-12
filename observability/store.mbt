///|
enum ObservabilityPersistence {
  ObservabilityFile(String)
  ObservabilityPostgres(@database.PostgresDatabase)
}

///|
pub struct ObservabilityStore {
  persistence : ObservabilityPersistence
  event_history_limit : Int
  emit_json_lines : Bool
  mut events : Array[OperationalEvent]
  mut counters : Map[String, OperationalCounter]
  mutex : @async.Mutex
}

///|
fn safe_identifier(value : String, maximum? : Int = 256) -> Bool {
  @contracts.valid_identifier(value, maximum_length=maximum)
}

///|
pub fn validate_event(
  event : OperationalEvent,
) -> Unit raise ObservabilityError {
  if event.version != contract_version ||
    !safe_identifier(event.event_id) ||
    event.timestamp_unix_ms <= 0L ||
    !safe_identifier(event.component, maximum=64) ||
    !safe_identifier(event.event_code, maximum=96) ||
    !safe_identifier(event.correlation_id) ||
    event.tenant_hash.map_or(false, digest => {
      !@contracts.valid_sha256_digest(digest)
    }) ||
    !safe_identifier(event.target_type, maximum=96) ||
    !safe_identifier(event.outcome, maximum=64) ||
    event.status_code < 0 ||
    event.status_code > 599 ||
    event.duration_ms < 0L ||
    event.duration_ms > 86400000L {
    raise InvalidEvent("operational event is invalid or unbounded")
  }
}

///|
fn status_class(status : Int) -> String {
  if status >= 500 {
    "5xx"
  } else if status >= 400 {
    "4xx"
  } else if status >= 300 {
    "3xx"
  } else if status >= 200 {
    "2xx"
  } else {
    "other"
  }
}

///|
fn counter_key(event : OperationalEvent) -> String {
  "\{event.event_code}|\{event.target_type}|\{event.outcome}|\{status_class(event.status_code)}"
}

///|
fn sorted_counters(
  values : Map[String, OperationalCounter],
) -> Array[OperationalCounter] {
  let result = values.values().to_array()
  result.sort_by((left, right) => {
    let left_key = "\{left.event_code}|\{left.target_type}|\{left.outcome}|\{left.status_class}"
    let right_key = "\{right.event_code}|\{right.target_type}|\{right.outcome}|\{right.status_class}"
    left_key.compare(right_key)
  })
  result
}

///|
fn ObservabilityStore::snapshot_unlocked(
  self : ObservabilityStore,
) -> ObservabilitySnapshot {
  {
    schema_version: snapshot_schema_version,
    events: self.events.copy(),
    counters: sorted_counters(self.counters),
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : ObservabilitySnapshot,
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
fn ObservabilityStore::empty(
  persistence : ObservabilityPersistence,
  event_history_limit : Int,
  emit_json_lines : Bool,
) -> ObservabilityStore raise ObservabilityError {
  if event_history_limit <= 0 || event_history_limit > 1000000 {
    raise InvalidSnapshot("event history limit is invalid")
  }
  {
    persistence,
    event_history_limit,
    emit_json_lines,
    events: [],
    counters: Map([]),
    mutex: Mutex(),
  }
}

///|
fn ObservabilityStore::restore(
  self : ObservabilityStore,
  snapshot : ObservabilitySnapshot,
) -> Unit raise ObservabilityError {
  if snapshot.schema_version != snapshot_schema_version {
    raise InvalidSnapshot("unsupported observability snapshot")
  }
  for event in snapshot.events {
    validate_event(event)
    self.events.push(event)
  }
  while self.events.length() > self.event_history_limit {
    ignore(self.events.remove(0))
  }
  for counter in snapshot.counters {
    if !safe_identifier(counter.event_code, maximum=96) ||
      !safe_identifier(counter.target_type, maximum=96) ||
      !safe_identifier(counter.outcome, maximum=64) ||
      !["2xx", "3xx", "4xx", "5xx", "other"].contains(counter.status_class) ||
      counter.value < 0L {
      raise InvalidSnapshot("invalid operational counter")
    }
    let key = "\{counter.event_code}|\{counter.target_type}|\{counter.outcome}|\{counter.status_class}"
    if self.counters.contains(key) {
      raise InvalidSnapshot("duplicate operational counter")
    }
    self.counters[key] = counter
  }
}

///|
pub async fn ObservabilityStore::open(
  path : String,
  event_history_limit? : Int = 10000,
  emit_json_lines? : Bool = false,
) -> ObservabilityStore {
  if path.trim() == "" {
    raise InvalidSnapshot("observability path is empty")
  }
  let store = ObservabilityStore::empty(
    ObservabilityFile(path),
    event_history_limit,
    emit_json_lines,
  )
  if @fs.exists(path) {
    let snapshot : ObservabilitySnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error =>
        raise InvalidSnapshot("invalid observability snapshot: \{Repr(error)}")
    }
    store.restore(snapshot)
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn ObservabilityStore::open_postgres(
  database : @database.PostgresDatabase,
  event_history_limit? : Int = 10000,
  emit_json_lines? : Bool = false,
) -> ObservabilityStore {
  let store = ObservabilityStore::empty(
    ObservabilityPostgres(database),
    event_history_limit,
    emit_json_lines,
  )
  match database.load_snapshot("observability", snapshot_schema_version) {
    Some(payload) => {
      let snapshot : ObservabilitySnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
        error =>
          raise InvalidSnapshot(
            "invalid observability snapshot: \{Repr(error)}",
          )
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "observability",
        snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn ObservabilityStore::persist(self : ObservabilityStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    ObservabilityFile(path) => write_snapshot(path, snapshot)
    ObservabilityPostgres(database) =>
      database.save_opaque_snapshot(
        "observability",
        snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
pub async fn ObservabilityStore::record(
  self : ObservabilityStore,
  event : OperationalEvent,
) -> Unit {
  validate_event(event)
  self.mutex.acquire()
  let previous_events = self.events.copy()
  let previous_counters = self.counters.copy()
  try {
    self.events.push(event)
    while self.events.length() > self.event_history_limit {
      ignore(self.events.remove(0))
    }
    let key = counter_key(event)
    let class = status_class(event.status_code)
    let current = self.counters.get(key).map_or(0L, counter => counter.value)
    self.counters[key] = {
      event_code: event.event_code,
      target_type: event.target_type,
      outcome: event.outcome,
      status_class: class,
      value: current + 1L,
    }
    self.persist()
    self.mutex.release()
    if self.emit_json_lines {
      println(event.to_json().stringify())
    }
  } catch {
    error => {
      self.events = previous_events
      self.counters = previous_counters
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn ObservabilityStore::snapshot(
  self : ObservabilityStore,
) -> ObservabilitySnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}

///|
pub async fn ObservabilityStore::recent_count(
  self : ObservabilityStore,
  event_code : String,
  target_type : String,
  since_unix_ms : Int64,
) -> Int {
  if !safe_identifier(event_code, maximum=96) ||
    !safe_identifier(target_type, maximum=96) ||
    since_unix_ms <= 0L {
    raise InvalidEvent("recent event query is invalid")
  }
  self.mutex.acquire()
  let count = self.events.count_if(event => {
    event.event_code == event_code &&
    event.target_type == target_type &&
    event.timestamp_unix_ms >= since_unix_ms
  })
  self.mutex.release()
  count
}
