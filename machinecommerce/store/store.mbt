///|
enum MachineCommercePersistence {
  MachineCommerceFile(String)
  MachineCommercePostgres(@database.PostgresDatabase)
}

///| Durable, serialized access to machine catalog, signed quotes, paid orders,

///|
/// inventory reservations, lifecycle compensation and metering receipts.
pub struct MachineCommerceStore {
  persistence : MachineCommercePersistence
  signing_secret : String
  mut core : @machinecommerce.MachineCommerceStore
  mutex : @async.Mutex
}

///|
async fn write_snapshot(
  path : String,
  snapshot : @machinecommerce.MachineCommerceSnapshot,
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
fn decode_snapshot(
  payload : String,
) -> @machinecommerce.MachineCommerceSnapshot raise @machinecommerce.MachineCommerceError {
  @json.from_json(@json.parse(payload)) catch {
    error =>
      raise InvalidInput("invalid machine-commerce snapshot: \{Repr(error)}")
  }
}

///|
fn MachineCommerceStore::empty(
  persistence : MachineCommercePersistence,
  signing_secret : String,
) -> MachineCommerceStore raise @machinecommerce.MachineCommerceError {
  {
    persistence,
    signing_secret,
    core: @machinecommerce.MachineCommerceStore::new(signing_secret),
    mutex: Mutex(),
  }
}

///|
pub async fn MachineCommerceStore::open(
  path : String,
  signing_secret : String,
) -> MachineCommerceStore {
  if path.trim() == "" {
    raise @machinecommerce.MachineCommerceError::InvalidInput(
      "machine-commerce store path is empty",
    )
  }
  let store = MachineCommerceStore::empty(
    MachineCommerceFile(path),
    signing_secret,
  )
  if @fs.exists(path) {
    store.core = @machinecommerce.MachineCommerceStore::from_snapshot(
      signing_secret,
      decode_snapshot(@fs.read_file(path).text()),
    )
  } else {
    write_snapshot(path, store.core.snapshot())
  }
  store
}

///|
pub async fn MachineCommerceStore::open_postgres(
  database : @database.PostgresDatabase,
  signing_secret : String,
) -> MachineCommerceStore {
  let store = MachineCommerceStore::empty(
    MachineCommercePostgres(database),
    signing_secret,
  )
  match
    database.load_snapshot(
      "machine_commerce", @machinecommerce.snapshot_schema_version,
    ) {
    Some(payload) =>
      store.core = @machinecommerce.MachineCommerceStore::from_snapshot(
        signing_secret,
        decode_snapshot(payload),
      )
    None =>
      database.save_opaque_snapshot(
        "machine_commerce",
        @machinecommerce.snapshot_schema_version,
        store.core.snapshot().to_json().stringify(),
      )
  }
  store
}

///|
async fn MachineCommerceStore::persist(self : MachineCommerceStore) -> Unit {
  let snapshot = self.core.snapshot()
  match self.persistence {
    MachineCommerceFile(path) => write_snapshot(path, snapshot)
    MachineCommercePostgres(database) =>
      database.save_opaque_snapshot(
        "machine_commerce",
        @machinecommerce.snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn MachineCommerceStore::rollback(
  self : MachineCommerceStore,
  before : @machinecommerce.MachineCommerceSnapshot,
) -> Unit raise @machinecommerce.MachineCommerceError {
  self.core = @machinecommerce.MachineCommerceStore::from_snapshot(
    self.signing_secret,
    before,
  )
}

///|
pub async fn MachineCommerceStore::snapshot(
  self : MachineCommerceStore,
) -> @machinecommerce.MachineCommerceSnapshot {
  self.mutex.acquire()
  let snapshot = self.core.snapshot()
  self.mutex.release()
  snapshot
}

///| Restores a previously captured durable snapshot. This is intentionally

///| public so a cross-store provider callback can compensate the machine

///|
/// transition when its commercial authority commit fails.
pub async fn MachineCommerceStore::replace_from_snapshot(
  self : MachineCommerceStore,
  snapshot : @machinecommerce.MachineCommerceSnapshot,
) -> Unit {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let restored = @machinecommerce.MachineCommerceStore::from_snapshot(
    self.signing_secret,
    snapshot,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.core = restored
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
}

///|
pub async fn MachineCommerceStore::active_offerings(
  self : MachineCommerceStore,
) -> Array[@machinecommerce.MachineOffering] {
  self.mutex.acquire()
  let offerings = self.core.active_offerings()
  self.mutex.release()
  offerings
}

///|
pub async fn MachineCommerceStore::availability(
  self : MachineCommerceStore,
  offering_id : String,
  now_unix_ms : Int64,
) -> @machinecommerce.MachineAvailability {
  self.mutex.acquire()
  let result = self.core.availability(offering_id, now_unix_ms) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::order(
  self : MachineCommerceStore,
  order_id : String,
) -> @machinecommerce.MachineOrder? {
  self.mutex.acquire()
  let result = self.core.order(order_id)
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::quote(
  self : MachineCommerceStore,
  quote_id : String,
) -> @machinecommerce.MachineQuote? {
  self.mutex.acquire()
  let result = self.core.quote(quote_id)
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::orders_for_subject(
  self : MachineCommerceStore,
  subject_ref : String,
) -> Array[@machinecommerce.MachineOrder] {
  self.mutex.acquire()
  let result = self.core.orders_for_subject(subject_ref)
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::order_for_access_key(
  self : MachineCommerceStore,
  key_id : String,
) -> @machinecommerce.MachineOrder? {
  self.mutex.acquire()
  let result = self.core.order_for_access_key(key_id)
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::bind_access_key(
  self : MachineCommerceStore,
  order_id : String,
  subject_ref : String,
  key_id : String,
  now_unix_ms : Int64,
) -> @machinecommerce.MachineActionReceipt {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.bind_access_key(
    order_id, subject_ref, key_id, now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::put_offering(
  self : MachineCommerceStore,
  offering : @machinecommerce.MachineOffering,
) -> (@machinecommerce.MachineOffering, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.put_offering(offering) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::create_quote(
  self : MachineCommerceStore,
  intent : @machinecommerce.MachineQuoteIntent,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineQuote, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.create_quote(intent, now_unix_ms) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::create_order(
  self : MachineCommerceStore,
  intent : @machinecommerce.MachineOrderIntent,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.create_order(intent, now_unix_ms) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::activate_settled_payment(
  self : MachineCommerceStore,
  order_id : String,
  settlement : @machinecommerce.MachinePaymentSettlement,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.activate_settled_payment(
    order_id, settlement, now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::start_provisioning(
  self : MachineCommerceStore,
  order_id : String,
  intent : @machinecommerce.MachineProvisioningIntent,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.start_provisioning(order_id, intent, now_unix_ms) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::complete_provisioning(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.complete_provisioning(
    order_id, idempotency_key, expected_generation, now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::request_cancel(
  self : MachineCommerceStore,
  subject_ref : String,
  order_id : String,
  action : @machinecommerce.MachineOrderAction,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.request_cancel(
    subject_ref, order_id, action, now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::request_termination(
  self : MachineCommerceStore,
  subject_ref : String,
  order_id : String,
  action : @machinecommerce.MachineOrderAction,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.request_termination(
    subject_ref, order_id, action, now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::record_failure(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  failure_code : String,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.record_failure(
    order_id, idempotency_key, expected_generation, failure_code, now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::complete_compensation(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  compensation_ref : String,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.complete_compensation(
    order_id, idempotency_key, expected_generation, compensation_ref, now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::complete_termination_with_usage(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  compensation_ref : String,
  ended_unix_ms : Int64,
  now_unix_ms : Int64,
) -> (
  @machinecommerce.MachineOrder,
  @machinecommerce.MachineUsageReceipt,
  @machinecommerce.IdempotencyResult,
) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.complete_termination_with_usage(
    order_id, idempotency_key, expected_generation, compensation_ref, ended_unix_ms,
    now_unix_ms,
  ) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}

///|
pub async fn MachineCommerceStore::record_usage(
  self : MachineCommerceStore,
  order_id : String,
  intent : @machinecommerce.MachineMeterIntent,
  now_unix_ms : Int64,
) -> (
  @machinecommerce.MachineOrder,
  @machinecommerce.MachineUsageReceipt,
  @machinecommerce.IdempotencyResult,
) {
  self.mutex.acquire()
  let before = self.core.snapshot()
  let result = self.core.record_usage(order_id, intent, now_unix_ms) catch {
    error => {
      self.mutex.release()
      raise error
    }
  }
  self.persist() catch {
    error => {
      self.rollback(before)
      self.mutex.release()
      raise error
    }
  }
  self.mutex.release()
  result
}
