///|
enum NotificationPersistence {
  NotificationFile(String)
  NotificationPostgres(@database.PostgresDatabase)
}

///|
pub struct NotificationStore {
  persistence : NotificationPersistence
  mut records : Map[String, @notifications.NotificationRecord]
  mut deliveries : Map[String, @notifications.NotificationDelivery]
  mut preferences : Map[String, @notifications.NotificationPreference]
  mut worker_health : @notifications.NotificationWorkerHealth
  redrive_audit : Array[@notifications.NotificationDeliveryRedriveReceipt]
  history_limit : Int
  maximum_delivery_attempts : Int
  mutex : @async.Mutex
}

///| Backward-compatible reader for snapshots written before worker health and

///|
/// redrive receipts became durable readiness evidence.
priv struct LegacyNotificationSnapshot {
  schema_version : String
  records : Array[@notifications.NotificationRecord]
  deliveries : Array[@notifications.NotificationDelivery]
  preferences : Array[@notifications.NotificationPreference]
} derive(FromJson)

///|
fn empty_worker_health() -> @notifications.NotificationWorkerHealth {
  {
    generation: 0L,
    last_heartbeat_unix_ms: None,
    last_attempt_unix_ms: None,
    last_success_unix_ms: None,
    last_failure_unix_ms: None,
    consecutive_failures: 0,
    last_error_code: None,
  }
}

///|
fn sorted_records(
  values : Map[String, @notifications.NotificationRecord],
) -> Array[@notifications.NotificationRecord] {
  let result = values.values().to_array()
  result.sort_by((left, right) => {
    if left.event.created_unix_ms == right.event.created_unix_ms {
      left.event.notification_id.compare(right.event.notification_id)
    } else {
      left.event.created_unix_ms.compare(right.event.created_unix_ms)
    }
  })
  result
}

///|
fn sorted_deliveries(
  values : Map[String, @notifications.NotificationDelivery],
) -> Array[@notifications.NotificationDelivery] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.delivery_id)
  result
}

///|
fn sorted_preferences(
  values : Map[String, @notifications.NotificationPreference],
) -> Array[@notifications.NotificationPreference] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.preference_id)
  result
}

///|
fn NotificationStore::snapshot_unlocked(
  self : NotificationStore,
) -> @notifications.NotificationSnapshot {
  {
    schema_version: @notifications.snapshot_schema_version,
    records: sorted_records(self.records),
    deliveries: sorted_deliveries(self.deliveries),
    preferences: sorted_preferences(self.preferences),
    worker_health: self.worker_health,
    redrive_audit: self.redrive_audit.copy(),
  }
}

///|
fn decode_snapshot(
  payload : String,
) -> @notifications.NotificationSnapshot raise {
  let value = @json.parse(payload)
  @json.from_json(value) catch {
    _ => {
      let legacy : LegacyNotificationSnapshot = @json.from_json(value)
      {
        schema_version: legacy.schema_version,
        records: legacy.records,
        deliveries: legacy.deliveries,
        preferences: legacy.preferences,
        worker_health: empty_worker_health(),
        redrive_audit: [],
      }
    }
  }
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @notifications.NotificationSnapshot,
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
fn NotificationStore::restore(
  self : NotificationStore,
  snapshot : @notifications.NotificationSnapshot,
) -> Unit raise @notifications.NotificationError {
  if snapshot.schema_version != @notifications.snapshot_schema_version {
    raise InvalidInput("unsupported notification snapshot")
  }
  if snapshot.records.length() > self.history_limit {
    raise InvalidInput(
      "notification snapshot exceeds the configured history bound",
    )
  }
  for record in snapshot.records {
    @notifications.validate_event(record.event)
    if record.generation <= 0L ||
      record.updated_unix_ms < record.event.created_unix_ms ||
      self.records.contains(record.event.notification_id) {
      raise InvalidInput("invalid notification record")
    }
    self.records[record.event.notification_id] = record
  }
  for delivery in snapshot.deliveries {
    if !@contracts.valid_identifier(delivery.delivery_id) ||
      !self.records.contains(delivery.notification_id) ||
      delivery.attempt_count < 0 ||
      delivery.attempt_count > self.maximum_delivery_attempts ||
      self.deliveries.contains(delivery.delivery_id) {
      raise InvalidInput("invalid notification delivery")
    }
    self.deliveries[delivery.delivery_id] = delivery
  }
  for preference in snapshot.preferences {
    @notifications.validate_preference(preference)
    if self.preferences.contains(preference.preference_id) {
      raise InvalidInput("duplicate notification preference")
    }
    self.preferences[preference.preference_id] = preference
  }
  let health = snapshot.worker_health
  if health.generation < 0L ||
    health.consecutive_failures < 0 ||
    health.last_error_code.map_or(false, code => {
      !@contracts.valid_identifier(code)
    }) {
    raise InvalidInput("invalid notification worker health")
  }
  self.worker_health = health
  if snapshot.redrive_audit.length() > 1000 {
    raise InvalidInput("notification redrive audit is unbounded")
  }
  for receipt in snapshot.redrive_audit {
    if !@contracts.valid_identifier(receipt.receipt_id) ||
      !@contracts.valid_identifier(receipt.delivery_id) ||
      !@contracts.valid_identifier(receipt.actor_ref) ||
      receipt.previous_attempt_count <= 0 ||
      receipt.accepted_unix_ms <= 0L {
      raise InvalidInput("invalid notification redrive audit")
    }
    self.redrive_audit.push(receipt)
  }
}

///|
fn NotificationStore::empty(
  persistence : NotificationPersistence,
  history_limit : Int,
  maximum_delivery_attempts : Int,
) -> NotificationStore raise @notifications.NotificationError {
  if history_limit <= 0 ||
    history_limit > 1000000 ||
    maximum_delivery_attempts <= 0 ||
    maximum_delivery_attempts > 32 {
    raise InvalidInput("notification store limits are invalid")
  }
  {
    persistence,
    records: Map([]),
    deliveries: Map([]),
    preferences: Map([]),
    worker_health: empty_worker_health(),
    redrive_audit: [],
    history_limit,
    maximum_delivery_attempts,
    mutex: Mutex(),
  }
}

///|
pub async fn NotificationStore::open(
  path : String,
  history_limit? : Int = 100000,
  maximum_delivery_attempts? : Int = 5,
) -> NotificationStore {
  if path.trim() == "" {
    raise @notifications.NotificationError::InvalidInput(
      "notification store path is empty",
    )
  }
  let store = NotificationStore::empty(
    NotificationFile(path),
    history_limit,
    maximum_delivery_attempts,
  )
  if @fs.exists(path) {
    let snapshot = decode_snapshot(@fs.read_file(path).text()) catch {
      error =>
        raise @notifications.NotificationError::InvalidInput(
          "invalid notification snapshot: \{Repr(error)}",
        )
    }
    store.restore(snapshot)
  } else {
    write_snapshot(path, store.snapshot_unlocked())
  }
  store
}

///|
pub async fn NotificationStore::open_postgres(
  database : @database.PostgresDatabase,
  history_limit? : Int = 100000,
  maximum_delivery_attempts? : Int = 5,
) -> NotificationStore {
  let store = NotificationStore::empty(
    NotificationPostgres(database),
    history_limit,
    maximum_delivery_attempts,
  )
  match
    database.load_snapshot(
      "notifications", @notifications.snapshot_schema_version,
    ) {
    Some(payload) => {
      let snapshot = decode_snapshot(payload) catch {
        error =>
          raise @notifications.NotificationError::InvalidInput(
            "invalid notification snapshot: \{Repr(error)}",
          )
      }
      store.restore(snapshot)
    }
    None =>
      database.save_opaque_snapshot(
        "notifications",
        @notifications.snapshot_schema_version,
        store.snapshot_unlocked().to_json().stringify(),
      )
  }
  store
}

///|
async fn NotificationStore::persist(self : NotificationStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    NotificationFile(path) => write_snapshot(path, snapshot)
    NotificationPostgres(database) =>
      database.save_opaque_snapshot(
        "notifications",
        @notifications.snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn channel_name(channel : @notifications.NotificationChannel) -> String {
  match channel {
    InApp => "in-app"
    Email => "email"
    Sms => "sms"
    Webhook => "webhook"
  }
}

///|
fn NotificationStore::channels_for_event_unlocked(
  self : NotificationStore,
  event : @notifications.NotificationEvent,
) -> Array[@notifications.NotificationChannel] {
  match event.audience {
    Subject(tenant_ref~, subject_ref~) => {
      for _, preference in self.preferences {
        if preference.tenant_ref == tenant_ref &&
          preference.subject_ref == subject_ref &&
          preference.topic == event.topic {
          return preference.channels.filter(channel => {
            @notifications.preference_allows(preference, event, channel)
          })
        }
      }
      [InApp]
    }
    PlatformOperators if event.severity == Critical => [InApp, Webhook]
    PlatformOperators | TenantUsers(_) => [InApp]
  }
}

///|
fn same_source(
  left : @notifications.NotificationEvent,
  right : @notifications.NotificationEvent,
) -> Bool {
  left.source_receipt == right.source_receipt &&
  left.topic == right.topic &&
  left.audience == right.audience
}

///|
fn NotificationStore::prune_unlocked(self : NotificationStore) -> Unit {
  if self.records.length() <= self.history_limit {
    return
  }
  let candidates = sorted_records(self.records).filter(record => {
    record.lifecycle == Resolved
  })
  for record in candidates {
    if self.records.length() <= self.history_limit {
      break
    }
    self.records.remove(record.event.notification_id)
    let delivery_ids = [
      for id, delivery in self.deliveries if delivery.notification_id ==
      record.event.notification_id => id
    ]
    for id in delivery_ids {
      self.deliveries.remove(id)
    }
  }
}

///| Makes one slot without discarding an active record. If the durable active

///| set itself reaches the configured bound, admission fails closed rather than

///|
/// silently losing an alert.
fn NotificationStore::make_capacity_unlocked(
  self : NotificationStore,
) -> Unit raise @notifications.NotificationError {
  if self.records.length() < self.history_limit {
    return
  }
  for record in sorted_records(self.records) {
    if record.lifecycle == Resolved {
      self.records.remove(record.event.notification_id)
      let delivery_ids = [
        for id, delivery in self.deliveries if delivery.notification_id ==
        record.event.notification_id => id
      ]
      for id in delivery_ids {
        self.deliveries.remove(id)
      }
      if self.records.length() < self.history_limit {
        return
      }
    }
  }
  raise InvalidInput("notification active history capacity is exhausted")
}

///|
pub async fn NotificationStore::enqueue(
  self : NotificationStore,
  event : @notifications.NotificationEvent,
) -> @notifications.NotificationRecord {
  @notifications.validate_event(event)
  self.mutex.acquire()
  let previous_records = self.records.copy()
  let previous_deliveries = self.deliveries.copy()
  try {
    match self.records.get(event.notification_id) {
      Some(existing) if existing.event == event => {
        self.mutex.release()
        return existing
      }
      Some(_) =>
        raise @notifications.NotificationError::AlreadyExists(
          event.notification_id,
        )
      None => ()
    }
    for _, existing in self.records {
      if same_source(existing.event, event) {
        if existing.event == event {
          self.mutex.release()
          return existing
        }
        raise @notifications.NotificationError::IdempotencyConflict(
          event.source_receipt,
        )
      }
      if existing.lifecycle != Resolved &&
        existing.event.deduplication_key == event.deduplication_key &&
        existing.event.audience == event.audience {
        if existing.event.topic == event.topic &&
          existing.event.code == event.code {
          self.mutex.release()
          return existing
        }
        raise @notifications.NotificationError::IdempotencyConflict(
          event.deduplication_key,
        )
      }
    }
    self.make_capacity_unlocked()
    let record : @notifications.NotificationRecord = {
      event,
      lifecycle: Unread,
      generation: 1L,
      assigned_to: None,
      acknowledged_by: None,
      acknowledged_unix_ms: None,
      silenced_until_unix_ms: None,
      resolved_by: None,
      resolved_unix_ms: None,
      updated_unix_ms: event.created_unix_ms,
    }
    self.records[event.notification_id] = record
    for channel in self.channels_for_event_unlocked(event) {
      let delivery_id = "delivery-\{event.notification_id}-\{channel_name(channel)}"
      self.deliveries[delivery_id] = {
        delivery_id,
        notification_id: event.notification_id,
        channel,
        state: if channel == InApp {
          Delivered
        } else {
          PendingDelivery
        },
        attempt_count: 0,
        next_attempt_unix_ms: if channel == InApp {
          None
        } else {
          Some(event.created_unix_ms)
        },
        provider_receipt: if channel == InApp {
          Some("in-app:\{event.notification_id}")
        } else {
          None
        },
        last_error_code: None,
        updated_unix_ms: event.created_unix_ms,
      }
    }
    self.prune_unlocked()
    self.persist()
    self.mutex.release()
    record
  } catch {
    error => {
      self.records = previous_records
      self.deliveries = previous_deliveries
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn NotificationStore::set_preference(
  self : NotificationStore,
  preference : @notifications.NotificationPreference,
) -> @notifications.NotificationPreference {
  @notifications.validate_preference(preference)
  self.mutex.acquire()
  let previous = self.preferences.copy()
  try {
    match self.preferences.get(preference.preference_id) {
      Some(existing) if existing.tenant_ref != preference.tenant_ref ||
        existing.subject_ref != preference.subject_ref ||
        existing.topic != preference.topic =>
        raise @notifications.NotificationError::IdempotencyConflict(
          preference.preference_id,
        )
      _ => ()
    }
    self.preferences[preference.preference_id] = preference
    self.persist()
    self.mutex.release()
    preference
  } catch {
    error => {
      self.preferences = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
fn visible_to_subject(
  record : @notifications.NotificationRecord,
  tenant_ref : String,
  subject_ref : String,
) -> Bool {
  match record.event.audience {
    Subject(tenant_ref=tenant, subject_ref=subject) =>
      tenant == tenant_ref && subject == subject_ref
    TenantUsers(tenant_ref=tenant) => tenant == tenant_ref
    PlatformOperators => false
  }
}

///|
pub async fn NotificationStore::records_for_subject(
  self : NotificationStore,
  tenant_ref : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> Array[@notifications.NotificationRecord] {
  if !@contracts.valid_identifier(tenant_ref) ||
    !@contracts.valid_identifier(subject_ref) ||
    now_unix_ms <= 0L {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification subject",
    )
  }
  self.mutex.acquire()
  let records = sorted_records(self.records).filter(record => {
    visible_to_subject(record, tenant_ref, subject_ref) &&
    record.event.expires_unix_ms.map_or(true, expiry => expiry > now_unix_ms)
  })
  self.mutex.release()
  records
}

///|
pub async fn NotificationStore::preferences_for_subject(
  self : NotificationStore,
  tenant_ref : String,
  subject_ref : String,
) -> Array[@notifications.NotificationPreference] {
  if !@contracts.valid_identifier(tenant_ref) ||
    !@contracts.valid_identifier(subject_ref) {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification subject",
    )
  }
  self.mutex.acquire()
  let preferences = sorted_preferences(self.preferences).filter(preference => {
    preference.tenant_ref == tenant_ref && preference.subject_ref == subject_ref
  })
  self.mutex.release()
  preferences
}

///|
pub async fn NotificationStore::records_for_operators(
  self : NotificationStore,
  now_unix_ms : Int64,
) -> Array[@notifications.NotificationRecord] {
  if now_unix_ms <= 0L {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification time",
    )
  }
  self.mutex.acquire()
  let records = sorted_records(self.records).filter(record => {
    record.event.audience == PlatformOperators &&
    record.event.expires_unix_ms.map_or(true, expiry => expiry > now_unix_ms)
  })
  self.mutex.release()
  records
}

///|
pub async fn NotificationStore::record(
  self : NotificationStore,
  notification_id : String,
) -> @notifications.NotificationRecord? {
  if !@contracts.valid_identifier(notification_id) {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification identity",
    )
  }
  self.mutex.acquire()
  let result = self.records.get(notification_id)
  self.mutex.release()
  result
}

///| Clears elapsed silence windows as a durable generation-fenced state

///| transition. This makes silence expiry independent of whether an operator

///|
/// currently has the alert page open.
pub async fn NotificationStore::expire_silences(
  self : NotificationStore,
  now_unix_ms : Int64,
) -> Int {
  if now_unix_ms <= 0L {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification time",
    )
  }
  self.mutex.acquire()
  let previous = self.records.copy()
  try {
    let mut expired = 0
    for notification_id, record in self.records {
      if record.lifecycle != Resolved &&
        record.silenced_until_unix_ms.map_or(false, expiry => {
          expiry <= now_unix_ms
        }) {
        self.records[notification_id] = {
          ..record,
          generation: record.generation + 1L,
          silenced_until_unix_ms: None,
          updated_unix_ms: now_unix_ms,
        }
        expired += 1
      }
    }
    if expired > 0 {
      self.persist()
    }
    self.mutex.release()
    expired
  } catch {
    error => {
      self.records = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn NotificationStore::delivery_readiness(
  self : NotificationStore,
  adapter_configured : Bool,
  now_unix_ms? : Int64 = 0L,
  worker_freshness_ms? : Int64 = 300000L,
) -> @notifications.NotificationDeliveryReadiness {
  let now = if now_unix_ms > 0L { now_unix_ms } else { @async.now() }
  self.mutex.acquire()
  let pending = self.deliveries
    .values()
    .count_if(delivery => {
      delivery.channel != InApp &&
      (delivery.state == PendingDelivery || delivery.state == RetryScheduled)
    })
  let delivering = self.deliveries
    .values()
    .count_if(delivery => {
      delivery.channel != InApp && delivery.state == Delivering
    })
  let dead_letters = self.deliveries
    .values()
    .count_if(delivery => {
      delivery.channel != InApp && delivery.state == DeadLetter
    })
  let capacity_exhausted = self.records.length() >= self.history_limit &&
    !self.records.values().any(record => record.lifecycle == Resolved)
  let health = self.worker_health
  self.mutex.release()
  let heartbeat_fresh = health.last_heartbeat_unix_ms.map_or(false, value => {
    value <= now && now - value <= worker_freshness_ms
  })
  let attempt_fresh = health.last_attempt_unix_ms.map_or(false, value => {
    value <= now && now - value <= worker_freshness_ms
  })
  let success_fresh = health.last_success_unix_ms.map_or(false, value => {
    value <= now && now - value <= worker_freshness_ms
  })
  {
    version: @notifications.contract_version,
    state: if dead_letters > 0 ||
      capacity_exhausted ||
      health.consecutive_failures > 0 ||
      (health.last_heartbeat_unix_ms is Some(_) && !heartbeat_fresh) {
      DeliveryDegraded
    } else if !adapter_configured {
      AdaptersPending
    } else if !heartbeat_fresh || !attempt_fresh || !success_fresh {
      AdaptersPending
    } else {
      DeliveryReady
    },
    adapter_configured,
    pending_count: pending,
    delivering_count: delivering,
    dead_letter_count: dead_letters,
    capacity_exhausted,
    worker_health: health,
    supported_channels: if adapter_configured {
      [InApp, Email, Sms, Webhook]
    } else {
      [InApp]
    },
  }
}

///| Persists one completed worker pass. A success timestamp is proof of a real

///|
/// adapter exchange, not merely an idle loop or configured endpoint.
pub async fn NotificationStore::record_worker_pass(
  self : NotificationStore,
  now_unix_ms : Int64,
  attempted : Int,
  delivered : Int,
  retry_scheduled : Int,
  dead_lettered : Int,
) -> @notifications.NotificationWorkerHealth {
  if now_unix_ms <= 0L ||
    attempted < 0 ||
    delivered < 0 ||
    retry_scheduled < 0 ||
    dead_lettered < 0 ||
    delivered + retry_scheduled + dead_lettered > attempted {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification worker pass",
    )
  }
  self.mutex.acquire()
  let previous = self.worker_health
  try {
    let failed = retry_scheduled > 0 || dead_lettered > 0
    self.worker_health = {
      generation: previous.generation + 1L,
      last_heartbeat_unix_ms: Some(now_unix_ms),
      last_attempt_unix_ms: if attempted > 0 {
        Some(now_unix_ms)
      } else {
        previous.last_attempt_unix_ms
      },
      last_success_unix_ms: if attempted > 0 && delivered == attempted {
        Some(now_unix_ms)
      } else {
        previous.last_success_unix_ms
      },
      last_failure_unix_ms: if failed {
        Some(now_unix_ms)
      } else {
        previous.last_failure_unix_ms
      },
      consecutive_failures: if failed {
        previous.consecutive_failures + 1
      } else if attempted > 0 && delivered == attempted {
        0
      } else {
        previous.consecutive_failures
      },
      last_error_code: if dead_lettered > 0 {
        Some("DeliveryDeadLettered")
      } else if retry_scheduled > 0 {
        Some("DeliveryRetryScheduled")
      } else if attempted > 0 && delivered == attempted {
        None
      } else {
        previous.last_error_code
      },
    }
    self.persist()
    self.mutex.release()
    self.worker_health
  } catch {
    error => {
      self.worker_health = previous
      self.mutex.release()
      raise error
    }
  }
}

///| Records an unexpected worker-loop failure before the controller task fails

///|
/// closed and is restarted by its supervisor.
pub async fn NotificationStore::record_worker_failure(
  self : NotificationStore,
  now_unix_ms : Int64,
  error_code : String,
) -> @notifications.NotificationWorkerHealth {
  if now_unix_ms <= 0L || !@contracts.valid_identifier(error_code) {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification worker failure",
    )
  }
  self.mutex.acquire()
  let previous = self.worker_health
  try {
    self.worker_health = {
      ..previous,
      generation: previous.generation + 1L,
      last_heartbeat_unix_ms: Some(now_unix_ms),
      last_failure_unix_ms: Some(now_unix_ms),
      consecutive_failures: previous.consecutive_failures + 1,
      last_error_code: Some(error_code),
    }
    self.persist()
    self.mutex.release()
    self.worker_health
  } catch {
    error => {
      self.worker_health = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn NotificationStore::record_by_deduplication_key(
  self : NotificationStore,
  deduplication_key : String,
  audience : @notifications.NotificationAudience,
) -> @notifications.NotificationRecord? {
  if !@contracts.valid_identifier(deduplication_key) {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification deduplication key",
    )
  }
  self.mutex.acquire()
  let matching = sorted_records(self.records).filter(record => {
    record.event.deduplication_key == deduplication_key &&
    record.event.audience == audience
  })
  let mut found : @notifications.NotificationRecord? = None
  for record in matching {
    if record.lifecycle != Resolved {
      found = Some(record)
    } else if found is None {
      found = Some(record)
    }
  }
  self.mutex.release()
  found
}

///|
async fn NotificationStore::replace_record(
  self : NotificationStore,
  notification_id : String,
  update : (@notifications.NotificationRecord) -> @notifications.NotificationRecord raise,
) -> @notifications.NotificationRecord {
  self.mutex.acquire()
  let previous = self.records.copy()
  try {
    guard self.records.get(notification_id) is Some(record) else {
      raise @notifications.NotificationError::NotFound(notification_id)
    }
    let updated = update(record)
    self.records[notification_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.records = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn NotificationStore::mark_read_for_subject(
  self : NotificationStore,
  tenant_ref : String,
  subject_ref : String,
  action : @notifications.NotificationAction,
) -> @notifications.NotificationRecord {
  self.replace_record(action.notification_id, record => {
    let visible = match record.event.audience {
      Subject(tenant_ref=tenant, subject_ref=subject) =>
        tenant == tenant_ref && subject == subject_ref
      TenantUsers(tenant_ref=tenant) => tenant == tenant_ref
      PlatformOperators => false
    }
    guard visible && action.actor_ref == subject_ref else {
      raise @notifications.NotificationError::Unauthorized
    }
    record.mark_read(action)
  })
}

///|
fn operator_record(
  record : @notifications.NotificationRecord,
) -> Unit raise @notifications.NotificationError {
  if record.event.audience != PlatformOperators {
    raise Unauthorized
  }
}

///|
pub async fn NotificationStore::acknowledge_operator(
  self : NotificationStore,
  action : @notifications.NotificationAction,
) -> @notifications.NotificationRecord {
  self.replace_record(action.notification_id, record => {
    operator_record(record)
    record.acknowledge(action)
  })
}

///|
pub async fn NotificationStore::resolve_operator(
  self : NotificationStore,
  action : @notifications.NotificationAction,
) -> @notifications.NotificationRecord {
  self.replace_record(action.notification_id, record => {
    operator_record(record)
    record.resolve(action)
  })
}

///|
pub async fn NotificationStore::silence_operator(
  self : NotificationStore,
  action : @notifications.NotificationSilenceAction,
) -> @notifications.NotificationRecord {
  self.replace_record(action.notification_id, record => {
    operator_record(record)
    record.silence(action)
  })
}

///|
pub async fn NotificationStore::assign_operator(
  self : NotificationStore,
  action : @notifications.NotificationAssignmentAction,
) -> @notifications.NotificationRecord {
  self.replace_record(action.notification_id, record => {
    operator_record(record)
    record.assign(action)
  })
}

///|
fn delivery_ineligible_reason(
  record : @notifications.NotificationRecord,
  now_unix_ms : Int64,
) -> String? {
  if record.lifecycle == Resolved {
    Some("NotificationResolved")
  } else if record.event.expires_unix_ms.map_or(false, expiry => {
      expiry <= now_unix_ms
    }) {
    Some("NotificationExpired")
  } else if record.silenced_until_unix_ms.map_or(false, until => {
      until > now_unix_ms
    }) {
    Some("NotificationSilenced")
  } else {
    None
  }
}

///| Rechecks lifecycle immediately before transport. This closes the race in

///|
/// which an operator resolves or silences an alert after the worker claims it.
pub async fn NotificationStore::skip_delivery_if_ineligible(
  self : NotificationStore,
  delivery_id : String,
  expected_attempt_count : Int,
  now_unix_ms : Int64,
) -> @notifications.NotificationDelivery? {
  self.mutex.acquire()
  let previous = self.deliveries.copy()
  try {
    guard self.deliveries.get(delivery_id) is Some(delivery) &&
      delivery.state == Delivering &&
      delivery.attempt_count == expected_attempt_count &&
      self.records.get(delivery.notification_id) is Some(record) else {
      self.mutex.release()
      return None
    }
    guard delivery_ineligible_reason(record, now_unix_ms) is Some(reason) else {
      self.mutex.release()
      return None
    }
    let skipped = {
      ..delivery,
      state: DeliverySkipped,
      next_attempt_unix_ms: None,
      provider_receipt: None,
      last_error_code: Some(reason),
      updated_unix_ms: now_unix_ms,
    }
    self.deliveries[delivery_id] = skipped
    self.persist()
    self.mutex.release()
    Some(skipped)
  } catch {
    error => {
      self.deliveries = previous
      self.mutex.release()
      raise error
    }
  }
}

///| Requeues exactly the dead-letter generation the operator inspected and

///| records a bounded durable receipt. The delivery ID remains stable so the

///|
/// downstream adapter's idempotency key still protects ambiguous outcomes.
pub async fn NotificationStore::redrive_dead_letter(
  self : NotificationStore,
  action : @notifications.NotificationDeliveryRedriveAction,
) -> @notifications.NotificationDeliveryRedriveReceipt {
  if !@contracts.valid_identifier(action.delivery_id) ||
    !@contracts.valid_identifier(action.actor_ref) ||
    action.expected_attempt_count <= 0 ||
    action.expected_updated_unix_ms <= 0L ||
    action.now_unix_ms < action.expected_updated_unix_ms {
    raise @notifications.NotificationError::InvalidInput(
      "invalid notification redrive",
    )
  }
  self.mutex.acquire()
  let previous_deliveries = self.deliveries.copy()
  let previous_audit = self.redrive_audit.copy()
  try {
    guard self.deliveries.get(action.delivery_id) is Some(delivery) else {
      raise @notifications.NotificationError::NotFound(action.delivery_id)
    }
    if delivery.state != DeadLetter {
      raise @notifications.NotificationError::InvalidTransition(
        "only dead-letter deliveries may be redriven",
      )
    }
    if delivery.attempt_count != action.expected_attempt_count ||
      delivery.updated_unix_ms != action.expected_updated_unix_ms {
      raise @notifications.NotificationError::StaleGeneration
    }
    let receipt : @notifications.NotificationDeliveryRedriveReceipt = {
      receipt_id: "redrive-\{action.now_unix_ms}-\{self.redrive_audit.length() + 1}",
      delivery_id: action.delivery_id,
      actor_ref: action.actor_ref,
      previous_attempt_count: delivery.attempt_count,
      accepted_unix_ms: action.now_unix_ms,
    }
    self.deliveries[action.delivery_id] = {
      ..delivery,
      state: PendingDelivery,
      attempt_count: 0,
      next_attempt_unix_ms: Some(action.now_unix_ms),
      provider_receipt: None,
      last_error_code: None,
      updated_unix_ms: action.now_unix_ms,
    }
    self.redrive_audit.push(receipt)
    while self.redrive_audit.length() > 1000 {
      ignore(self.redrive_audit.remove(0))
    }
    self.persist()
    self.mutex.release()
    receipt
  } catch {
    error => {
      self.deliveries = previous_deliveries
      self.redrive_audit.clear()
      for receipt in previous_audit {
        self.redrive_audit.push(receipt)
      }
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn NotificationStore::claim_due_deliveries(
  self : NotificationStore,
  now_unix_ms : Int64,
  lease_duration_ms : Int64,
  limit : Int,
) -> Array[@notifications.NotificationDelivery] {
  if now_unix_ms <= 0L ||
    lease_duration_ms <= 0L ||
    lease_duration_ms > 300000L ||
    limit <= 0 ||
    limit > 1000 {
    raise @notifications.NotificationError::InvalidInput(
      "invalid delivery claim",
    )
  }
  self.mutex.acquire()
  let previous = self.deliveries.copy()
  try {
    let due = sorted_deliveries(self.deliveries).filter(delivery => {
      (
        delivery.state == PendingDelivery ||
        delivery.state == RetryScheduled ||
        delivery.state == Delivering
      ) &&
      delivery.next_attempt_unix_ms.map_or(false, due_at => {
        due_at <= now_unix_ms
      })
    })
    let claimed : Array[@notifications.NotificationDelivery] = []
    for delivery in due {
      if claimed.length() >= limit {
        break
      }
      let ineligible = match self.records.get(delivery.notification_id) {
        Some(record) => delivery_ineligible_reason(record, now_unix_ms)
        None => Some("NotificationRecordMissing")
      }
      if ineligible is Some(reason) {
        self.deliveries[delivery.delivery_id] = {
          ..delivery,
          state: DeliverySkipped,
          next_attempt_unix_ms: None,
          provider_receipt: None,
          last_error_code: Some(reason),
          updated_unix_ms: now_unix_ms,
        }
      } else if delivery.attempt_count >= self.maximum_delivery_attempts {
        self.deliveries[delivery.delivery_id] = {
          ..delivery,
          state: DeadLetter,
          next_attempt_unix_ms: None,
          last_error_code: Some("DeliveryAttemptLimit"),
          updated_unix_ms: now_unix_ms,
        }
      } else {
        let next = {
          ..delivery,
          state: Delivering,
          attempt_count: delivery.attempt_count + 1,
          next_attempt_unix_ms: Some(now_unix_ms + lease_duration_ms),
          updated_unix_ms: now_unix_ms,
        }
        self.deliveries[delivery.delivery_id] = next
        claimed.push(next)
      }
    }
    self.persist()
    self.mutex.release()
    claimed
  } catch {
    error => {
      self.deliveries = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn NotificationStore::record_delivery_result(
  self : NotificationStore,
  result : @notifications.DeliveryResult,
) -> @notifications.NotificationDelivery {
  self.mutex.acquire()
  let previous = self.deliveries.copy()
  try {
    guard self.deliveries.get(result.delivery_id) is Some(delivery) else {
      raise @notifications.NotificationError::NotFound(result.delivery_id)
    }
    let updated = delivery.record_result(result, self.maximum_delivery_attempts)
    self.deliveries[result.delivery_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.deliveries = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn NotificationStore::snapshot(
  self : NotificationStore,
) -> @notifications.NotificationSnapshot {
  self.mutex.acquire()
  let snapshot = self.snapshot_unlocked()
  self.mutex.release()
  snapshot
}

///| Lightweight scrape projection; avoids copying notification records,

///|
/// preferences and redrive receipts for every Prometheus request.
pub async fn NotificationStore::delivery_metrics(
  self : NotificationStore,
) -> (Int, Int, @notifications.NotificationWorkerHealth) {
  self.mutex.acquire()
  let pending = self.deliveries
    .values()
    .count_if(delivery => {
      delivery.state == PendingDelivery ||
      delivery.state == RetryScheduled ||
      delivery.state == Delivering
    })
  let dead = self.deliveries
    .values()
    .count_if(delivery => delivery.state == DeadLetter)
  let health = self.worker_health
  self.mutex.release()
  (pending, dead, health)
}
