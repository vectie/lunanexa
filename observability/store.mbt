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
  mut last_external_export_unix_ms : Int64?
  mut appended_since_prune : Int
  mutex : @async.Mutex
}

///|
priv struct LegacyObservabilitySnapshot {
  schema_version : String
  events : Array[OperationalEvent]
  counters : Array[OperationalCounter]
} derive(FromJson)

///|
fn decode_snapshot(payload : String) -> ObservabilitySnapshot raise {
  let value = @json.parse(payload)
  @json.from_json(value) catch {
    _ => {
      let legacy : LegacyObservabilitySnapshot = @json.from_json(value)
      {
        schema_version: legacy.schema_version,
        events: legacy.events,
        counters: legacy.counters,
        last_external_export_unix_ms: None,
      }
    }
  }
}

///|
fn safe_identifier(value : String, maximum? : Int = 256) -> Bool {
  let normalized = value.to_lower()
  @contracts.valid_identifier(value, maximum_length=maximum) &&
  ![
    "bearer-", "authorization-", "password-", "private-key", "ssh-rsa", "raw-prompt",
    "model-output", "callback-body", "document-bytes",
  ].any(marker => normalized.contains(marker))
}

///|
fn safe_target_type(value : String) -> Bool {
  [
    "api", "health", "metrics", "workload", "node", "notification", "notification_delivery",
    "enterprise_portal", "exclusive_lease", "commercial", "contract_document", "workspace",
    "deployment", "telemetry", "artifact", "database", "guide", "reconciliation",
    "runtime", "scheduler",
  ].contains(value)
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
    !safe_target_type(event.target_type) ||
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
fn checked_nonnegative_add(left : Int64, right : Int64) -> Int64? {
  if left < 0L || right < 0L || left > @int64.MAX_VALUE - right {
    None
  } else {
    Some(left + right)
  }
}

///|
fn generated_sequence(event_id : String) -> Int64? {
  guard event_id.has_prefix("event-operational-") else { return None }
  guard event_id.rev_find("-") is Some(separator) else { return None }
  Some(@string.parse_int64(event_id[separator + 1:])) catch {
    _ => None
  }
}

///|
fn checked_counter_total(counters : Map[String, OperationalCounter]) -> Int64? {
  let mut total = 0L
  for _, counter in counters {
    guard checked_nonnegative_add(total, counter.value) is Some(next) else {
      return None
    }
    total = next
  }
  Some(total)
}

///|
fn ensure_counter_capacity(
  counters : Map[String, OperationalCounter],
  key : String,
) -> Unit raise ObservabilityError {
  if !counters.contains(key) &&
    counters.length() >= maximum_operational_counter_series {
    raise InvalidEvent("operational counter cardinality limit reached")
  }
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
    last_external_export_unix_ms: self.last_external_export_unix_ms,
  }
}

///|
/// The durable projection for the PostgreSQL backend: counters and external
/// export freshness only. Operational events live in their own append-only
/// relation, so the per-domain snapshot no longer carries the recent window.
fn ObservabilityStore::counter_snapshot_unlocked(
  self : ObservabilityStore,
) -> ObservabilitySnapshot {
  {
    schema_version: snapshot_schema_version,
    events: [],
    counters: sorted_counters(self.counters),
    last_external_export_unix_ms: self.last_external_export_unix_ms,
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
    ToJson::to_json(snapshot).stringify(),
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
    last_external_export_unix_ms: None,
    appended_since_prune: 0,
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
  if snapshot.events.length() > self.event_history_limit {
    raise InvalidSnapshot(
      "observability event history exceeds configured limit",
    )
  }
  if snapshot.counters.length() > maximum_operational_counter_series {
    raise InvalidSnapshot("operational counter cardinality limit exceeded")
  }
  let event_ids : Map[String, Unit] = Map([])
  let generated_sequences : Map[Int64, Unit] = Map([])
  let retained_counts : Map[String, Int64] = Map([])
  for event in snapshot.events {
    validate_event(event) catch {
      InvalidEvent(reason) =>
        raise InvalidSnapshot("invalid operational event: \{reason}")
      error => raise error
    }
    if event_ids.contains(event.event_id) {
      raise InvalidSnapshot("duplicate operational event identifier")
    }
    event_ids[event.event_id] = ()
    let key = counter_key(event)
    let current = retained_counts.get(key).unwrap_or(0L)
    retained_counts[key] = checked_nonnegative_add(current, 1L).unwrap()
    self.events.push(event)
  }
  for counter in snapshot.counters {
    if !safe_identifier(counter.event_code, maximum=96) ||
      !safe_target_type(counter.target_type) ||
      !safe_identifier(counter.outcome, maximum=64) ||
      !["2xx", "3xx", "4xx", "5xx", "other"].contains(counter.status_class) ||
      counter.value <= 0L {
      raise InvalidSnapshot("invalid operational counter")
    }
    let key = "\{counter.event_code}|\{counter.target_type}|\{counter.outcome}|\{counter.status_class}"
    if self.counters.contains(key) {
      raise InvalidSnapshot("duplicate operational counter")
    }
    self.counters[key] = counter
  }
  guard checked_counter_total(self.counters) is Some(total) else {
    raise InvalidSnapshot("operational counter total overflow")
  }
  for key, retained in retained_counts {
    guard self.counters.get(key) is Some(counter) && counter.value >= retained else {
      raise InvalidSnapshot(
        "event history is inconsistent with operational counters",
      )
    }
  }
  for event in self.events {
    if event.event_id.has_prefix("event-operational-") {
      guard generated_sequence(event.event_id) is Some(sequence) &&
        sequence > 0L &&
        sequence <= total &&
        event.event_id ==
        "event-operational-\{event.timestamp_unix_ms}-\{sequence}" &&
        !generated_sequences.contains(sequence) else {
        raise InvalidSnapshot("invalid generated operational event sequence")
      }
      generated_sequences[sequence] = ()
    }
  }
  if snapshot.last_external_export_unix_ms.map_or(false, value => value <= 0L) {
    raise InvalidSnapshot("invalid external export timestamp")
  }
  self.last_external_export_unix_ms = snapshot.last_external_export_unix_ms
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
    let snapshot = decode_snapshot(@fs.read_file(path).text()) catch {
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
/// Loads and validates the recent event window from the append-only event
/// relation. Each row is validated on its own; the counter cross-checks that
/// `restore` applies to a self-contained snapshot deliberately do not apply
/// here, because the counters snapshot and the event relation are written by
/// separate statements and may legitimately differ by the events of the
/// request that was in flight when a writer stopped.
async fn ObservabilityStore::load_event_window(
  self : ObservabilityStore,
  database : @database.PostgresDatabase,
) -> Array[OperationalEvent] {
  let payloads = database.load_recent_operational_events(
    self.event_history_limit,
  )
  let events : Array[OperationalEvent] = []
  let identifiers : Map[String, Unit] = Map([])
  for payload in payloads {
    let value = @json.parse(payload) catch {
      _ => raise InvalidSnapshot("invalid operational event payload")
    }
    let event : OperationalEvent = @json.from_json(value) catch {
      _ => raise InvalidSnapshot("invalid operational event payload")
    }
    validate_event(event) catch {
      InvalidEvent(reason) =>
        raise InvalidSnapshot("invalid operational event: \{reason}")
      error => raise error
    }
    if identifiers.contains(event.event_id) {
      raise InvalidSnapshot("duplicate operational event identifier")
    }
    identifiers[event.event_id] = ()
    events.push(event)
  }
  events
}

///|
/// Opens the PostgreSQL-backed store. Operational events are restored from
/// the append-only event relation; the `observability` snapshot supplies the
/// counters and the external export freshness.
///
/// Backwards compatibility: a snapshot written before events moved out of it
/// still carries the recent window inside its `events` array. Those events are
/// migrated into the event relation once per stored row — the insert is
/// idempotent on `event_id` — and the snapshot is then rewritten without them,
/// so the relation is the only source of truth afterwards and a retried
/// migration cannot duplicate an event. Old snapshot windows are therefore
/// preserved across the upgrade rather than dropped.
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
      let snapshot = decode_snapshot(payload) catch {
        error =>
          raise InvalidSnapshot(
            "invalid observability snapshot: \{Repr(error)}",
          )
      }
      store.restore(snapshot)
      if store.events.length() > 0 {
        for event in store.events {
          database.append_operational_event(
            event.event_id,
            event.timestamp_unix_ms,
            ToJson::to_json(event).stringify(),
          )
        }
        store.events = []
        store.persist()
      }
    }
    None =>
      database.save_opaque_snapshot(
        "observability",
        snapshot_schema_version,
        ToJson::to_json(store.counter_snapshot_unlocked()).stringify(),
      )
  }
  store.events = store.load_event_window(database)
  store.appended_since_prune = 0
  database.prune_operational_events(store.event_history_limit)
  store
}

///|
/// Writes the durable projection the backend keeps for the store. The file
/// backend owns one JSON document and therefore still rewrites the whole
/// document; the PostgreSQL backend stores events separately and only has to
/// keep counters and external export freshness in `lunanexa.snapshots`.
async fn ObservabilityStore::persist(self : ObservabilityStore) -> Unit {
  match self.persistence {
    ObservabilityFile(path) => write_snapshot(path, self.snapshot_unlocked())
    ObservabilityPostgres(database) =>
      database.save_opaque_snapshot(
        "observability",
        snapshot_schema_version,
        ToJson::to_json(self.counter_snapshot_unlocked()).stringify(),
      )
  }
}

///|
/// Durably records one appended event. The file backend rewrites its single
/// document, because a local file has no append-only relation.
///
/// The PostgreSQL backend writes the counters projection first and the event
/// row second. That order means every stored event is already covered by the
/// durable counters, so a crash between the two statements can only leave the
/// counters ahead of the event window, never behind it.
///
/// Pruning runs at most once per `event_history_limit` appends — matching how
/// the in-memory window itself only discards events once it is full — so the
/// relation stays bounded near twice the configured window without adding a
/// DELETE to every request.
async fn ObservabilityStore::persist_recorded_event(
  self : ObservabilityStore,
  event : OperationalEvent,
) -> Unit {
  match self.persistence {
    ObservabilityFile(_) => self.persist()
    ObservabilityPostgres(database) => {
      self.persist()
      database.append_operational_event(
        event.event_id,
        event.timestamp_unix_ms,
        ToJson::to_json(event).stringify(),
      )
      self.appended_since_prune = self.appended_since_prune + 1
      if self.appended_since_prune >= self.event_history_limit {
        database.prune_operational_events(self.event_history_limit)
        self.appended_since_prune = 0
      }
    }
  }
}

///|
pub async fn ObservabilityStore::record(
  self : ObservabilityStore,
  event : OperationalEvent,
) -> Unit {
  validate_event(event)
  if event.event_id.has_prefix("event-operational-") {
    raise InvalidEvent("generated operational event identifier is reserved")
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let previous_events = self.events.copy()
  let previous_counters = self.counters.copy()
  errdefer {
    self.events = previous_events
    self.counters = previous_counters
  }
  for existing in self.events {
    if existing.event_id == event.event_id {
      if existing == event {
        return
      }
      raise EventConflict(event.event_id)
    }
  }
  self.events.push(event)
  while self.events.length() > self.event_history_limit {
    ignore(self.events.remove(0))
  }
  let key = counter_key(event)
  let class = status_class(event.status_code)
  ensure_counter_capacity(self.counters, key)
  let current = self.counters.get(key).map_or(0L, counter => counter.value)
  guard checked_nonnegative_add(current, 1L) is Some(next) else {
    raise InvalidEvent("operational counter exhausted")
  }
  self.counters[key] = {
    event_code: event.event_code,
    target_type: event.target_type,
    outcome: event.outcome,
    status_class: class,
    value: next,
  }
  self.persist_recorded_event(event)
  if self.emit_json_lines {
    println(ToJson::to_json(event).stringify())
  }
}

///| Atomically allocates a monotonically increasing operational event ID from

///| durable counter totals. This is used for concurrent request events whose

///|
/// timestamps and caller correlations may legitimately be identical.
pub async fn ObservabilityStore::record_generated(
  self : ObservabilityStore,
  event : OperationalEvent,
) -> OperationalEvent {
  self.mutex.acquire()
  defer self.mutex.release()
  let previous_events = self.events.copy()
  let previous_counters = self.counters.copy()
  errdefer {
    self.events = previous_events
    self.counters = previous_counters
  }
  guard checked_counter_total(self.counters) is Some(total) &&
    checked_nonnegative_add(total, 1L) is Some(sequence) else {
    raise InvalidEvent("operational event sequence exhausted")
  }
  let generated = {
    ..event,
    event_id: "event-operational-\{event.timestamp_unix_ms}-\{sequence}",
  }
  validate_event(generated)
  if self.events.any(event => event.event_id == generated.event_id) {
    raise EventConflict(generated.event_id)
  }
  let key = counter_key(generated)
  ensure_counter_capacity(self.counters, key)
  let current = self.counters.get(key).map_or(0L, counter => counter.value)
  guard checked_nonnegative_add(current, 1L) is Some(next) else {
    raise InvalidEvent("operational counter exhausted")
  }
  self.events.push(generated)
  while self.events.length() > self.event_history_limit {
    ignore(self.events.remove(0))
  }
  let class = status_class(generated.status_code)
  self.counters[key] = {
    event_code: generated.event_code,
    target_type: generated.target_type,
    outcome: generated.outcome,
    status_class: class,
    value: next,
  }
  self.persist_recorded_event(generated)
  if self.emit_json_lines {
    println(ToJson::to_json(generated).stringify())
  }
  generated
}

///| Records a bounded component lifecycle event using the same durable event

///|
/// and low-cardinality counter path as HTTP outcomes.
pub async fn ObservabilityStore::record_component_event(
  self : ObservabilityStore,
  event_id : String,
  timestamp_unix_ms : Int64,
  severity : OperationalSeverity,
  component : String,
  event_code : String,
  correlation_id : String,
  target_type : String,
  outcome : String,
  status_code : Int,
  duration_ms : Int64,
) -> Unit {
  self.record({
    version: contract_version,
    event_id,
    timestamp_unix_ms,
    severity,
    component,
    event_code,
    correlation_id,
    actor_class: Controller,
    tenant_hash: None,
    target_type,
    outcome,
    status_code,
    duration_ms,
  })
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

///| Lightweight scrape projection; avoids copying the recent event history for

///|
/// every Prometheus request.
pub async fn ObservabilityStore::metrics_snapshot(
  self : ObservabilityStore,
) -> (Array[OperationalCounter], Int) {
  self.mutex.acquire()
  let counters = sorted_counters(self.counters)
  let event_count = self.events.length()
  self.mutex.release()
  (counters, event_count)
}

///|
pub async fn ObservabilityStore::recent_count(
  self : ObservabilityStore,
  event_code : String,
  target_type : String,
  since_unix_ms : Int64,
) -> Int {
  if !safe_identifier(event_code, maximum=96) ||
    !safe_target_type(target_type) ||
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

///| Bounded rule query over the durable recent window. All dimensions are

///|
/// validated low-cardinality values already used by counters.
pub async fn ObservabilityStore::recent_outcome_count(
  self : ObservabilityStore,
  event_code : String,
  target_type : String,
  outcome : String,
  since_unix_ms : Int64,
) -> Int {
  if !safe_identifier(event_code, maximum=96) ||
    !safe_target_type(target_type) ||
    !safe_identifier(outcome, maximum=64) ||
    since_unix_ms <= 0L {
    raise InvalidEvent("recent outcome query is invalid")
  }
  self.mutex.acquire()
  let count = self.events.count_if(event => {
    event.event_code == event_code &&
    event.target_type == target_type &&
    event.outcome == outcome &&
    event.timestamp_unix_ms >= since_unix_ms
  })
  self.mutex.release()
  count
}

///| Fixed low-cardinality latency buckets computed from the bounded recent

///| event window. Target type is allowlisted by event validation; request,

///|
/// tenant, user, workload and lease identifiers never become labels.
pub async fn ObservabilityStore::latency_buckets(
  self : ObservabilityStore,
) -> Array[OperationalLatencyBucket] {
  self.mutex.acquire()
  let targets : Map[String, Unit] = Map([])
  for event in self.events {
    targets[event.target_type] = ()
  }
  let result : Array[OperationalLatencyBucket] = []
  for target, _ in targets {
    for upper_bound in [10L, 50L, 100L, 250L, 500L, 1000L, 2500L, 5000L, 10000L] {
      result.push({
        target_type: target,
        upper_bound_ms: Some(upper_bound),
        count: self.events
        .count_if(event => {
          event.target_type == target && event.duration_ms <= upper_bound
        })
        .to_int64(),
      })
    }
  }
  for target, _ in targets {
    result.push({
      target_type: target,
      upper_bound_ms: None,
      count: self.events
      .count_if(event => event.target_type == target)
      .to_int64(),
    })
  }
  result.sort_by((left, right) => {
    let target = left.target_type.compare(right.target_type)
    if target == 0 {
      left.upper_bound_ms
      .unwrap_or(9223372036854775807L)
      .compare(right.upper_bound_ms.unwrap_or(9223372036854775807L))
    } else {
      target
    }
  })
  self.mutex.release()
  result
}

///|
pub async fn ObservabilityStore::latency_summaries(
  self : ObservabilityStore,
) -> Array[OperationalLatencySummary] {
  self.mutex.acquire()
  let targets : Map[String, Unit] = Map([])
  for event in self.events {
    targets[event.target_type] = ()
  }
  let result : Array[OperationalLatencySummary] = []
  for target, _ in targets {
    let matching = self.events.filter(event => event.target_type == target)
    result.push({
      target_type: target,
      count: matching.length().to_int64(),
      sum_ms: matching.fold(init=0L, (total, event) => total + event.duration_ms),
    })
  }
  result.sort_by_key(summary => summary.target_type)
  self.mutex.release()
  result
}

///| Renders the bounded recent window as gauges. The values may decrease when

///| old events leave the window, so they deliberately are not advertised as a

///| Prometheus histogram/counter family.

///|
/// have already passed the target-type allowlist.
pub async fn ObservabilityStore::prometheus_latency_fragment(
  self : ObservabilityStore,
) -> String {
  let buckets = self.latency_buckets()
  let summaries = self.latency_summaries()
  let builder = StringBuilder()
  builder.write_string(
    "# HELP lunanexa_operational_request_duration_ms_recent_window Recent bounded operational latency window.\n",
  )
  builder.write_string(
    "# TYPE lunanexa_operational_request_duration_ms_recent_window_bucket gauge\n",
  )
  builder.write_string(
    "# TYPE lunanexa_operational_request_duration_ms_recent_window_sum gauge\n",
  )
  builder.write_string(
    "# TYPE lunanexa_operational_request_duration_ms_recent_window_count gauge\n",
  )
  for bucket in buckets {
    let bound = bucket.upper_bound_ms
      .map(value => value.to_string())
      .unwrap_or("+Inf")
    builder.write_string(
      "lunanexa_operational_request_duration_ms_recent_window_bucket{target_type=\"\{bucket.target_type}\",le=\"\{bound}\"} \{bucket.count}\n",
    )
  }
  for summary in summaries {
    builder.write_string(
      "lunanexa_operational_request_duration_ms_recent_window_sum{target_type=\"\{summary.target_type}\"} \{summary.sum_ms}\n",
    )
    builder.write_string(
      "lunanexa_operational_request_duration_ms_recent_window_count{target_type=\"\{summary.target_type}\"} \{summary.count}\n",
    )
  }
  builder.to_string()
}

///|
pub async fn ObservabilityStore::readiness(
  self : ObservabilityStore,
  external_collector_configured? : Bool = false,
  now_unix_ms? : Int64 = 0L,
  external_export_freshness_ms? : Int64 = 300000L,
) -> ObservabilityReadiness {
  let now = if now_unix_ms > 0L { now_unix_ms } else { @async.now() }
  self.mutex.acquire()
  let last_external_export = self.last_external_export_unix_ms
  let external_export_verified = last_external_export.map_or(false, value => {
    value <= now && now - value <= external_export_freshness_ms
  })
  let result : ObservabilityReadiness = {
    version: contract_version,
    state: if !self.emit_json_lines {
      ObservabilityDegraded
    } else if !external_collector_configured || !external_export_verified {
      ExternalCollectorPending
    } else {
      LocalJsonReady
    },
    persistence_available: true,
    json_lines_enabled: self.emit_json_lines,
    external_collector_configured,
    external_export_verified,
    last_external_export_unix_ms: last_external_export,
    event_history_count: self.events.length(),
    event_history_limit: self.event_history_limit,
    oldest_event_unix_ms: self.events
    .get(0)
    .map(event => event.timestamp_unix_ms),
    newest_event_unix_ms: self.events
    .last()
    .map(event => event.timestamp_unix_ms),
  }
  self.mutex.release()
  result
}

///| Persists a collector-to-sink success proof. The caller is authenticated at

///|
/// the HTTP boundary; this store accepts only a bounded opaque receipt.
pub async fn ObservabilityStore::record_external_export_proof(
  self : ObservabilityStore,
  proof : ExternalExportProof,
) -> OperationalEvent {
  if !safe_identifier(proof.proof_receipt) || proof.exported_unix_ms <= 0L {
    raise InvalidEvent("external export proof is invalid")
  }
  let event = self.record_generated({
    version: contract_version,
    event_id: "event-pending",
    timestamp_unix_ms: proof.exported_unix_ms,
    severity: Information,
    component: "external-collector",
    event_code: "ExternalCollectorExportVerified",
    correlation_id: proof.proof_receipt,
    actor_class: Provider,
    tenant_hash: None,
    target_type: "telemetry",
    outcome: "exported",
    status_code: 200,
    duration_ms: 0L,
  })
  self.mutex.acquire()
  defer self.mutex.release()
  let previous = self.last_external_export_unix_ms
  errdefer {
    self.last_external_export_unix_ms = previous
  }
  self.last_external_export_unix_ms = Some(
    previous.map_or(proof.exported_unix_ms, value => {
      value.max(proof.exported_unix_ms)
    }),
  )
  self.persist()
  event
}
