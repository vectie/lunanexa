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
  history_limit : Int
  maximum_delivery_attempts : Int
  mutex : @async.Mutex
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
    let snapshot : @notifications.NotificationSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
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
      let snapshot : @notifications.NotificationSnapshot = @json.from_json(
        @json.parse(payload),
      ) catch {
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
  let mut found : @notifications.NotificationRecord? = None
  for _, record in self.records {
    if record.event.deduplication_key == deduplication_key &&
      record.event.audience == audience {
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
    guard record.event.audience
      is Subject(tenant_ref=tenant, subject_ref=subject) &&
      tenant == tenant_ref &&
      subject == subject_ref &&
      action.actor_ref == subject_ref else {
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
      if delivery.attempt_count >= self.maximum_delivery_attempts {
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
