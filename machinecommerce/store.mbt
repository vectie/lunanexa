///|
pub struct MachineCommerceStore {
  signing_secret : String
  offerings : Map[String, MachineOffering]
  quotes : Map[String, MachineQuote]
  quote_keys : Map[String, String]
  orders : Map[String, MachineOrder]
  order_keys : Map[String, String]
  quote_orders : Map[String, String]
  payment_events : Map[String, String]
  action_receipts : Map[String, MachineActionReceipt]
  usage_receipts : Map[String, MachineUsageReceipt]
  meter_keys : Map[String, String]
}

///|
fn scoped_key(subject_ref : String, idempotency_key : String) -> String {
  "\{subject_ref}:\{idempotency_key}"
}

///|
fn[T] sorted_values(values : Map[String, T]) -> Array[T] {
  let pairs = values.to_array()
  pairs.sort_by((left, right) => left.0.compare(right.0))
  pairs.map(pair => pair.1)
}

///|
fn sha256_text(value : String) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))}"
}

///|
fn hmac_text(value : String, secret : String) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(secret).view(),
      @utf8.encode(value).view(),
    ),
  )
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
fn option_material(value : String?) -> String {
  value.unwrap_or("-")
}

///|
fn quote_material(quote : MachineQuote) -> String {
  "\{contract_version}|\{quote.quote_id}|\{quote.idempotency_key}|\{quote.tenant_ref}|\{quote.organization_id}|\{quote.project_id}|\{quote.purchaser_subject_ref}|\{quote.offering_id}|\{Repr(quote.offering_kind)}|\{quote.quantity}|\{quote.duration_seconds}|\{option_material(quote.unix_username)}|\{option_material(quote.requested_model_selector)}|\{option_material(quote.model_template_ref)}|\{quote.meter}|\{quote.unit_price.minor_units}|\{quote.unit_price.currency}|\{quote.unit_price.scale}|\{quote.subtotal.minor_units}|\{quote.total.minor_units}|\{quote.created_unix_ms}|\{quote.valid_until_unix_ms}"
}

///|
fn quote_signature(quote : MachineQuote, secret : String) -> String {
  hmac_text("\{quote_material(quote)}|\{quote.terms_digest}", secret)
}

///|
fn receipt_material(receipt : MachineUsageReceipt) -> String {
  "\{contract_version}|\{receipt.receipt_id}|\{receipt.idempotency_key}|\{receipt.event_id}|\{receipt.order_id}|\{receipt.organization_id}|\{receipt.project_id}|\{receipt.subject_ref}|\{receipt.resource_ref}|\{receipt.meter}|\{receipt.quantity}|\{receipt.unit}|\{receipt.started_unix_ms}|\{receipt.ended_unix_ms}|\{receipt.observed_unix_ms}"
}

///|
fn checked_multiply(
  left : Int64,
  right : Int64,
) -> Int64 raise MachineCommerceError {
  if left < 0L ||
    right < 0L ||
    (left != 0L && right > 0x7fffffffffffffffL / left) {
    raise InvalidInput("machine quote amount overflow")
  }
  left * right
}

///|
fn billed_seconds(duration_seconds : Int64, quantum : Int64) -> Int64 {
  (duration_seconds + quantum - 1L) / quantum * quantum
}

///|
pub fn MachineCommerceStore::new(
  signing_secret : String,
) -> MachineCommerceStore raise MachineCommerceError {
  if signing_secret.length() < 32 || signing_secret.length() > 4096 {
    raise InvalidInput(
      "machine quote signing secret must contain at least 32 characters",
    )
  }
  {
    signing_secret,
    offerings: Map([]),
    quotes: Map([]),
    quote_keys: Map([]),
    orders: Map([]),
    order_keys: Map([]),
    quote_orders: Map([]),
    payment_events: Map([]),
    action_receipts: Map([]),
    usage_receipts: Map([]),
    meter_keys: Map([]),
  }
}

///|
pub fn MachineCommerceStore::snapshot(
  self : MachineCommerceStore,
) -> MachineCommerceSnapshot {
  {
    schema_version: snapshot_schema_version,
    offerings: sorted_values(self.offerings),
    quotes: sorted_values(self.quotes),
    orders: sorted_values(self.orders),
    usage_receipts: sorted_values(self.usage_receipts),
    action_receipts: sorted_values(self.action_receipts),
  }
}

///|
pub fn MachineCommerceStore::from_snapshot(
  signing_secret : String,
  snapshot : MachineCommerceSnapshot,
) -> MachineCommerceStore raise MachineCommerceError {
  if snapshot.schema_version != snapshot_schema_version {
    raise InvalidInput("unsupported machine-commerce snapshot")
  }
  let store = MachineCommerceStore::new(signing_secret)
  for offering in snapshot.offerings {
    validate_offering(offering)
    if store.offerings.contains(offering.offering_id) {
      raise InvalidInput("duplicate machine offering")
    }
    store.offerings[offering.offering_id] = offering
  }
  for quote in snapshot.quotes {
    validate_quote(quote)
    if !store.offerings.contains(quote.offering_id) ||
      store.quotes.contains(quote.quote_id) ||
      !store.verify_quote(quote) {
      raise InvalidInput("invalid persisted machine quote")
    }
    let key = scoped_key(quote.purchaser_subject_ref, quote.idempotency_key)
    if store.quote_keys.contains(key) {
      raise InvalidInput("duplicate quote idempotency key")
    }
    store.quotes[quote.quote_id] = quote
    store.quote_keys[key] = quote.quote_id
  }
  for order in snapshot.orders {
    validate_order(order)
    if !store.quotes.contains(order.quote_id) ||
      store.orders.contains(order.order_id) ||
      store.quote_orders.contains(order.quote_id) {
      raise InvalidInput("invalid persisted machine order")
    }
    let key = scoped_key(order.purchaser_subject_ref, order.idempotency_key)
    if store.order_keys.contains(key) {
      raise InvalidInput("duplicate order idempotency key")
    }
    store.orders[order.order_id] = order
    store.order_keys[key] = order.order_id
    store.quote_orders[order.quote_id] = order.order_id
    match order.payment_event_id {
      Some(event_id) => store.payment_events[event_id] = order.order_id
      None => ()
    }
  }
  for receipt in snapshot.usage_receipts {
    if !store.orders.contains(receipt.order_id) ||
      store.usage_receipts.contains(receipt.receipt_id) ||
      store.meter_keys.contains(
        scoped_key(receipt.order_id, receipt.idempotency_key),
      ) ||
      receipt.receipt_digest != sha256_text(receipt_material(receipt)) {
      raise InvalidInput("invalid persisted machine usage receipt")
    }
    store.usage_receipts[receipt.receipt_id] = receipt
    store.meter_keys[scoped_key(receipt.order_id, receipt.idempotency_key)] = receipt.receipt_id
  }
  for receipt in snapshot.action_receipts {
    let key = scoped_key(receipt.order_id, receipt.idempotency_key)
    if !store.orders.contains(receipt.order_id) ||
      !valid_id(receipt.idempotency_key) ||
      !valid_id(receipt.action) ||
      receipt.outcome_generation <= 1L ||
      receipt.recorded_unix_ms <= 0L ||
      store.action_receipts.contains(key) {
      raise InvalidInput("invalid persisted machine action receipt")
    }
    store.action_receipts[key] = receipt
  }
  store
}

///|
fn MachineCommerceStore::action_replay(
  self : MachineCommerceStore,
  key : String,
  action : String,
  order : MachineOrder,
) -> Bool raise MachineCommerceError {
  match self.action_receipts.get(key) {
    Some(receipt) if receipt.action == action &&
      receipt.outcome_generation == order.generation => true
    Some(_) => raise IdempotencyConflict(key)
    None => false
  }
}

///|
fn MachineCommerceStore::record_action(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  action : String,
  outcome_generation : Int64,
  now_unix_ms : Int64,
) -> Unit {
  self.action_receipts[scoped_key(order_id, idempotency_key)] = {
    order_id,
    idempotency_key,
    action,
    outcome_generation,
    recorded_unix_ms: now_unix_ms,
  }
}

///|
pub fn MachineCommerceStore::put_offering(
  self : MachineCommerceStore,
  offering : MachineOffering,
) -> (MachineOffering, IdempotencyResult) raise MachineCommerceError {
  validate_offering(offering)
  match self.offerings.get(offering.offering_id) {
    Some(existing) if existing == offering => (existing, Replayed)
    Some(existing) => {
      if offering.generation != existing.generation + 1L ||
        offering.created_unix_ms != existing.created_unix_ms ||
        offering.updated_unix_ms <= existing.updated_unix_ms {
        raise StaleGeneration
      }
      if offering.capacity_total < self.reserved_for(offering.offering_id) {
        raise InvalidInput("offering capacity is below active reservations")
      }
      self.offerings[offering.offering_id] = offering
      (offering, Created)
    }
    None => {
      if offering.generation != 1L {
        raise StaleGeneration
      }
      self.offerings[offering.offering_id] = offering
      (offering, Created)
    }
  }
}

///|
fn MachineCommerceStore::reserved_for(
  self : MachineCommerceStore,
  offering_id : String,
) -> Int64 {
  self.orders
  .values()
  .fold(init=0L, (total, order) => {
    if order.offering_id == offering_id && order.capacity_reserved {
      total + order.quantity
    } else {
      total
    }
  })
}

///|
pub fn MachineCommerceStore::availability(
  self : MachineCommerceStore,
  offering_id : String,
  now_unix_ms : Int64,
) -> MachineAvailability raise MachineCommerceError {
  guard self.offerings.get(offering_id) is Some(offering) else {
    raise NotFound("machine offering")
  }
  let reserved = self.reserved_for(offering_id)
  {
    offering_id,
    capacity_total: offering.capacity_total,
    capacity_reserved: reserved,
    capacity_available: offering.capacity_total - reserved,
    observed_unix_ms: now_unix_ms,
  }
}

///|
pub fn MachineCommerceStore::active_offerings(
  self : MachineCommerceStore,
) -> Array[MachineOffering] {
  sorted_values(self.offerings).filter(offering => {
    offering.state == OfferingActive
  })
}

///|
fn MachineCommerceStore::verify_quote(
  self : MachineCommerceStore,
  quote : MachineQuote,
) -> Bool {
  let material = quote_material(quote)
  quote.terms_digest == sha256_text(material) &&
  constant_time_equal(
    quote.signature,
    quote_signature(quote, self.signing_secret),
  )
}

///|
pub fn MachineCommerceStore::create_quote(
  self : MachineCommerceStore,
  intent : MachineQuoteIntent,
  now_unix_ms : Int64,
) -> (MachineQuote, IdempotencyResult) raise MachineCommerceError {
  validate_quote_intent(intent)
  if now_unix_ms <= 0L {
    raise InvalidInput("invalid quote creation time")
  }
  let key = scoped_key(intent.purchaser_subject_ref, intent.idempotency_key)
  match self.quote_keys.get(key) {
    Some(quote_id) => {
      let existing = self.quotes[quote_id]
      let same = existing.quote_id == intent.quote_id &&
        existing.tenant_ref == intent.tenant_ref &&
        existing.organization_id == intent.organization_id &&
        existing.project_id == intent.project_id &&
        existing.offering_id == intent.offering_id &&
        existing.quantity == intent.quantity &&
        existing.duration_seconds == intent.duration_seconds &&
        existing.unix_username == intent.unix_username &&
        existing.requested_model_selector == intent.requested_model_selector &&
        existing.model_template_ref == intent.model_template_ref
      if same {
        return (existing, Replayed)
      }
      raise IdempotencyConflict(intent.idempotency_key)
    }
    None => ()
  }
  if self.quotes.contains(intent.quote_id) {
    raise AlreadyExists("machine quote")
  }
  guard self.offerings.get(intent.offering_id) is Some(offering) else {
    raise NotFound("machine offering")
  }
  if offering.state != OfferingActive {
    raise InvalidTransition("machine offering is not active")
  }
  if intent.quantity > offering.capacity_total ||
    intent.quantity != 1L ||
    intent.duration_seconds < offering.minimum_duration_seconds ||
    intent.duration_seconds > offering.maximum_duration_seconds {
    raise InvalidInput("requested machine quantity or duration is unavailable")
  }
  match offering.kind {
    BareMachine =>
      if intent.requested_model_selector is Some(_) ||
        intent.model_template_ref is Some(_) ||
        intent.unix_username is None {
        raise InvalidInput("bare-machine quote cannot select a managed model")
      }
    DedicatedEndpoint => {
      guard intent.requested_model_selector is Some(_) &&
        intent.model_template_ref is Some(template_ref) &&
        intent.unix_username is None else {
        raise InvalidInput(
          "dedicated endpoint quote requires a model selection",
        )
      }
      if !offering.allowed_model_template_refs.contains(template_ref) {
        raise InvalidInput("model template is unavailable for this offering")
      }
    }
  }
  let seconds = billed_seconds(
    intent.duration_seconds,
    offering.billing_quantum_seconds,
  )
  let unit_count = checked_multiply(seconds, intent.quantity)
  let subtotal_minor = checked_multiply(
    unit_count,
    offering.unit_price.minor_units,
  )
  let subtotal : @commercial.FixedMoney = {
    minor_units: subtotal_minor,
    currency: offering.unit_price.currency,
    scale: offering.unit_price.scale,
  }
  let unsigned : MachineQuote = {
    quote_id: intent.quote_id,
    idempotency_key: intent.idempotency_key,
    tenant_ref: intent.tenant_ref,
    organization_id: intent.organization_id,
    project_id: intent.project_id,
    purchaser_subject_ref: intent.purchaser_subject_ref,
    offering_id: offering.offering_id,
    offering_kind: offering.kind,
    quantity: intent.quantity,
    duration_seconds: intent.duration_seconds,
    unix_username: intent.unix_username,
    requested_model_selector: intent.requested_model_selector,
    model_template_ref: intent.model_template_ref,
    meter: offering.meter,
    unit_price: offering.unit_price,
    subtotal,
    total: subtotal,
    terms_digest: "",
    signature: "",
    created_unix_ms: now_unix_ms,
    valid_until_unix_ms: now_unix_ms + intent.valid_for_ms,
  }
  let digested = {
    ..unsigned,
    terms_digest: sha256_text(quote_material(unsigned)),
  }
  let quote = {
    ..digested,
    signature: quote_signature(digested, self.signing_secret),
  }
  self.quotes[quote.quote_id] = quote
  self.quote_keys[key] = quote.quote_id
  (quote, Created)
}

///|
pub fn MachineCommerceStore::create_order(
  self : MachineCommerceStore,
  intent : MachineOrderIntent,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  validate_order_intent(intent)
  let key = scoped_key(intent.purchaser_subject_ref, intent.idempotency_key)
  match self.order_keys.get(key) {
    Some(order_id) => {
      let existing = self.orders[order_id]
      if existing.order_id == intent.order_id &&
        existing.quote_id == intent.quote_id &&
        existing.tenant_ref == intent.tenant_ref &&
        existing.organization_id == intent.organization_id &&
        existing.project_id == intent.project_id {
        return (existing, Replayed)
      }
      raise IdempotencyConflict(intent.idempotency_key)
    }
    None => ()
  }
  if self.orders.contains(intent.order_id) ||
    self.quote_orders.contains(intent.quote_id) {
    raise AlreadyExists("machine order")
  }
  guard self.quotes.get(intent.quote_id) is Some(quote) else {
    raise NotFound("machine quote")
  }
  if quote.tenant_ref != intent.tenant_ref ||
    quote.organization_id != intent.organization_id ||
    quote.project_id != intent.project_id ||
    quote.purchaser_subject_ref != intent.purchaser_subject_ref {
    raise TenantMismatch
  }
  if now_unix_ms > quote.valid_until_unix_ms {
    raise QuoteExpired
  }
  if !self.verify_quote(quote) {
    raise QuoteIntegrityFailed
  }
  let order : MachineOrder = {
    order_id: intent.order_id,
    idempotency_key: intent.idempotency_key,
    quote_id: quote.quote_id,
    tenant_ref: quote.tenant_ref,
    organization_id: quote.organization_id,
    project_id: quote.project_id,
    purchaser_subject_ref: quote.purchaser_subject_ref,
    offering_id: quote.offering_id,
    offering_kind: quote.offering_kind,
    quantity: quote.quantity,
    duration_seconds: quote.duration_seconds,
    unix_username: quote.unix_username,
    requested_model_selector: quote.requested_model_selector,
    model_template_ref: quote.model_template_ref,
    quoted_total: quote.total,
    state: AwaitingPayment,
    generation: 1L,
    payment_ref: None,
    payment_event_id: None,
    target_lease_ref: None,
    target_deployment_ref: None,
    failure_code: None,
    compensation_ref: None,
    capacity_reserved: false,
    active_started_unix_ms: None,
    last_metered_unix_ms: None,
    ended_unix_ms: None,
    created_unix_ms: now_unix_ms,
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order.order_id] = order
  self.order_keys[key] = order.order_id
  self.quote_orders[quote.quote_id] = order.order_id
  (order, Created)
}

///| Idempotent provider callback target. This is the only transition that may

///|
/// reserve capacity, and it rejects any amount other than the signed quote.
pub fn MachineCommerceStore::activate_settled_payment(
  self : MachineCommerceStore,
  order_id : String,
  settlement : MachinePaymentSettlement,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) else {
    raise NotFound("machine order")
  }
  if !valid_id(settlement.provider_event_id) ||
    !valid_id(settlement.payment_ref) ||
    now_unix_ms <= 0L {
    raise InvalidInput("invalid machine payment settlement")
  }
  match self.payment_events.get(settlement.provider_event_id) {
    Some(existing_order_id) if existing_order_id == order_id &&
      order.payment_event_id == Some(settlement.provider_event_id) &&
      order.payment_ref == Some(settlement.payment_ref) &&
      settlement.settled_amount == order.quoted_total =>
      return (order, Replayed)
    Some(_) => raise IdempotencyConflict(settlement.provider_event_id)
    None => ()
  }
  if order.state != AwaitingPayment {
    raise InvalidTransition("machine order is not awaiting payment")
  }
  if settlement.settled_amount != order.quoted_total {
    raise PriceMismatch
  }
  let available = self.availability(order.offering_id, now_unix_ms)
  let (state, failure_code, reserved) = if available.capacity_available <
    order.quantity {
    (CompensationPending, Some("CapacityUnavailableAfterPayment"), false)
  } else {
    (PaymentSettled, None, true)
  }
  let updated = {
    ..order,
    state,
    generation: order.generation + 1L,
    payment_ref: Some(settlement.payment_ref),
    payment_event_id: Some(settlement.provider_event_id),
    failure_code,
    capacity_reserved: reserved,
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.payment_events[settlement.provider_event_id] = order_id
  (updated, Created)
}

///|
pub fn MachineCommerceStore::start_provisioning(
  self : MachineCommerceStore,
  order_id : String,
  intent : MachineProvisioningIntent,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) else {
    raise NotFound("machine order")
  }
  if !valid_id(intent.idempotency_key) ||
    intent.target_lease_ref.map_or(false, value => !valid_id(value)) ||
    intent.target_deployment_ref.map_or(false, value => !valid_id(value)) {
    raise InvalidInput("invalid provisioning intent")
  }
  let key = scoped_key(order_id, intent.idempotency_key)
  if self.action_replay(key, "provision", order) {
    return (order, Replayed)
  }
  if intent.expected_generation != order.generation {
    raise StaleGeneration
  }
  if order.state != PaymentSettled ||
    order.payment_ref is None ||
    !order.capacity_reserved {
    raise InvalidTransition("settled payment is required before provisioning")
  }
  match order.offering_kind {
    DedicatedEndpoint =>
      if intent.target_deployment_ref is None ||
        intent.target_lease_ref is Some(_) {
        raise InvalidInput(
          "dedicated endpoint provisioning requires only a managed deployment",
        )
      }
    BareMachine =>
      if intent.target_lease_ref is None ||
        intent.target_deployment_ref is Some(_) {
        raise InvalidInput(
          "bare-machine provisioning requires only an exclusive lease",
        )
      }
  }
  let updated = {
    ..order,
    state: Provisioning,
    generation: order.generation + 1L,
    target_lease_ref: intent.target_lease_ref,
    target_deployment_ref: intent.target_deployment_ref,
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.record_action(
    order_id,
    intent.idempotency_key,
    "provision",
    updated.generation,
    now_unix_ms,
  )
  (updated, Created)
}

///|
pub fn MachineCommerceStore::complete_provisioning(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) else {
    raise NotFound("machine order")
  }
  let key = scoped_key(order_id, idempotency_key)
  if self.action_replay(key, "active", order) {
    return (order, Replayed)
  }
  if expected_generation != order.generation {
    raise StaleGeneration
  }
  if order.state != Provisioning {
    raise InvalidTransition("machine order is not provisioning")
  }
  let updated = {
    ..order,
    state: Active,
    generation: order.generation + 1L,
    active_started_unix_ms: Some(now_unix_ms),
    last_metered_unix_ms: Some(now_unix_ms),
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.record_action(
    order_id,
    idempotency_key,
    "active",
    updated.generation,
    now_unix_ms,
  )
  (updated, Created)
}

///|
pub fn MachineCommerceStore::order(
  self : MachineCommerceStore,
  order_id : String,
) -> MachineOrder? {
  self.orders.get(order_id)
}

///|
pub fn MachineCommerceStore::quote(
  self : MachineCommerceStore,
  quote_id : String,
) -> MachineQuote? {
  self.quotes.get(quote_id)
}

///|
pub fn MachineCommerceStore::orders_for_subject(
  self : MachineCommerceStore,
  subject_ref : String,
) -> Array[MachineOrder] {
  sorted_values(self.orders).filter(order => {
    order.purchaser_subject_ref == subject_ref
  })
}

///|
/// Durably binds an API-key identifier to one active paid dedicated order.
/// The raw key is owned by the access store and never enters machine state.
pub fn MachineCommerceStore::bind_access_key(
  self : MachineCommerceStore,
  order_id : String,
  subject_ref : String,
  key_id : String,
  now_unix_ms : Int64,
) -> MachineActionReceipt raise MachineCommerceError {
  if !valid_id(key_id) || now_unix_ms <= 0L {
    raise InvalidInput("invalid dedicated access-key binding")
  }
  guard self.orders.get(order_id) is Some(order) &&
    order.purchaser_subject_ref == subject_ref else {
    raise NotFound("machine order")
  }
  if order.offering_kind != DedicatedEndpoint ||
    order.state != Active ||
    order.target_deployment_ref is None ||
    order.requested_model_selector is None {
    raise InvalidTransition("dedicated machine order is not active")
  }
  for receipt in self.action_receipts.values() {
    if receipt.action == "access-key" &&
      receipt.idempotency_key == key_id &&
      receipt.order_id != order_id {
      raise IdempotencyConflict(key_id)
    }
  }
  let key = scoped_key(order_id, key_id)
  match self.action_receipts.get(key) {
    Some(receipt) if receipt.action == "access-key" => receipt
    Some(_) => raise IdempotencyConflict(key_id)
    None => {
      self.record_action(
        order_id,
        key_id,
        "access-key",
        order.generation,
        now_unix_ms,
      )
      self.action_receipts[key]
    }
  }
}

///|
/// Resolves only the durable identifier binding. Callers must separately
/// validate the access credential and the order's current lifecycle state.
pub fn MachineCommerceStore::order_for_access_key(
  self : MachineCommerceStore,
  key_id : String,
) -> MachineOrder? {
  for receipt in self.action_receipts.values() {
    if receipt.action == "access-key" && receipt.idempotency_key == key_id {
      return self.orders.get(receipt.order_id)
    }
  }
  None
}

///|
pub fn MachineCommerceStore::request_cancel(
  self : MachineCommerceStore,
  subject_ref : String,
  order_id : String,
  action : MachineOrderAction,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) &&
    order.purchaser_subject_ref == subject_ref else {
    raise NotFound("machine order")
  }
  if !valid_id(action.idempotency_key) || !valid_label(action.reason, 256) {
    raise InvalidInput("invalid cancellation request")
  }
  let key = scoped_key(order_id, action.idempotency_key)
  if self.action_replay(key, "cancel", order) {
    return (order, Replayed)
  }
  if action.expected_generation != order.generation {
    raise StaleGeneration
  }
  let (state, reserved) = match order.state {
    AwaitingPayment => (Cancelled, false)
    PaymentSettled => (CancellationPending, false)
    Provisioning => (CancellationPending, true)
    _ => raise InvalidTransition("machine order cannot be cancelled")
  }
  let updated = {
    ..order,
    state,
    generation: order.generation + 1L,
    failure_code: Some("CustomerCancellation"),
    capacity_reserved: reserved,
    ended_unix_ms: if state == Cancelled {
      Some(now_unix_ms)
    } else {
      None
    },
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.record_action(
    order_id,
    action.idempotency_key,
    "cancel",
    updated.generation,
    now_unix_ms,
  )
  (updated, Created)
}

///|
pub fn MachineCommerceStore::request_termination(
  self : MachineCommerceStore,
  subject_ref : String,
  order_id : String,
  action : MachineOrderAction,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) &&
    order.purchaser_subject_ref == subject_ref else {
    raise NotFound("machine order")
  }
  if !valid_id(action.idempotency_key) || !valid_label(action.reason, 256) {
    raise InvalidInput("invalid termination request")
  }
  let key = scoped_key(order_id, action.idempotency_key)
  if self.action_replay(key, "terminate", order) {
    return (order, Replayed)
  }
  if action.expected_generation != order.generation {
    raise StaleGeneration
  }
  if order.state != Active {
    raise InvalidTransition("only an active machine order can be terminated")
  }
  let updated = {
    ..order,
    state: TerminationPending,
    generation: order.generation + 1L,
    failure_code: Some("CustomerTermination"),
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.record_action(
    order_id,
    action.idempotency_key,
    "terminate",
    updated.generation,
    now_unix_ms,
  )
  (updated, Created)
}

///| Marks a provisioning or active order failed. Paid orders enter

///|
/// `CompensationPending` until cleanup/refund evidence is recorded.
pub fn MachineCommerceStore::record_failure(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  failure_code : String,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) else {
    raise NotFound("machine order")
  }
  if !valid_id(idempotency_key) || !valid_id(failure_code) {
    raise InvalidInput("invalid machine failure")
  }
  let key = scoped_key(order_id, idempotency_key)
  if self.action_replay(key, "failure", order) {
    return (order, Replayed)
  }
  if expected_generation != order.generation {
    raise StaleGeneration
  }
  if order.state != PaymentSettled &&
    order.state != Provisioning &&
    order.state != Active {
    raise InvalidTransition("machine order cannot fail from its current state")
  }
  let paid = order.payment_ref is Some(_)
  let updated = {
    ..order,
    state: if paid {
      CompensationPending
    } else {
      Failed
    },
    generation: order.generation + 1L,
    failure_code: Some(failure_code),
    capacity_reserved: if paid {
      order.capacity_reserved
    } else {
      false
    },
    ended_unix_ms: if paid {
      None
    } else {
      Some(now_unix_ms)
    },
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.record_action(
    order_id,
    idempotency_key,
    "failure",
    updated.generation,
    now_unix_ms,
  )
  (updated, Created)
}

///|
/// Completes cancellation, termination, refund, and cleanup compensation.
pub fn MachineCommerceStore::complete_compensation(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  compensation_ref : String,
  now_unix_ms : Int64,
) -> (MachineOrder, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) else {
    raise NotFound("machine order")
  }
  if !valid_id(idempotency_key) || !valid_id(compensation_ref) {
    raise InvalidInput("invalid compensation evidence")
  }
  let key = scoped_key(order_id, idempotency_key)
  if self.action_replay(key, "compensated", order) {
    return (order, Replayed)
  }
  if expected_generation != order.generation {
    raise StaleGeneration
  }
  let terminal = match order.state {
    CancellationPending => Cancelled
    TerminationPending => Terminated
    CompensationPending => Failed
    _ => raise InvalidTransition("machine order has no pending compensation")
  }
  let updated = {
    ..order,
    state: terminal,
    generation: order.generation + 1L,
    compensation_ref: Some(compensation_ref),
    capacity_reserved: false,
    ended_unix_ms: Some(now_unix_ms),
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.record_action(
    order_id,
    idempotency_key,
    "compensated",
    updated.generation,
    now_unix_ms,
  )
  (updated, Created)
}

///| Atomically closes an active lease interval, emits its final billable usage

///| receipt, releases inventory, and records cleanup/refund evidence. This is

///|
/// the terminal path used for a customer-requested termination.
pub fn MachineCommerceStore::complete_termination_with_usage(
  self : MachineCommerceStore,
  order_id : String,
  idempotency_key : String,
  expected_generation : Int64,
  compensation_ref : String,
  ended_unix_ms : Int64,
  now_unix_ms : Int64,
) -> (MachineOrder, MachineUsageReceipt, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) else {
    raise NotFound("machine order")
  }
  let key = scoped_key(order_id, idempotency_key)
  match self.action_receipts.get(key) {
    Some(action) if action.action == "termination-complete" &&
      action.outcome_generation == order.generation => {
      guard self.meter_keys.get(key) is Some(receipt_id) else {
        raise InvalidInput("termination replay has no usage receipt")
      }
      return (order, self.usage_receipts[receipt_id], Replayed)
    }
    Some(_) => raise IdempotencyConflict(idempotency_key)
    None => ()
  }
  if !valid_id(idempotency_key) || !valid_id(compensation_ref) {
    raise InvalidInput("invalid termination completion evidence")
  }
  if expected_generation != order.generation {
    raise StaleGeneration
  }
  if order.state != TerminationPending {
    raise InvalidTransition("machine order is not awaiting termination")
  }
  guard order.last_metered_unix_ms is Some(started_unix_ms) else {
    raise InvalidTransition("machine order has no active billing interval")
  }
  if ended_unix_ms <= started_unix_ms || ended_unix_ms > now_unix_ms {
    raise InvalidInput("invalid terminal usage interval")
  }
  guard self.offerings.get(order.offering_id) is Some(offering) else {
    raise NotFound("machine offering")
  }
  let resource_ref = match order.offering_kind {
    BareMachine => order.target_lease_ref.unwrap()
    DedicatedEndpoint => order.target_deployment_ref.unwrap()
  }
  let quantity = checked_multiply(
    (ended_unix_ms - started_unix_ms + 999L) / 1000L,
    order.quantity,
  )
  let receipt_id = "usage-termination-\{order_id}-\{order.generation}"
  let unsigned : MachineUsageReceipt = {
    receipt_id,
    idempotency_key,
    event_id: "machine-order:\{order_id}:termination:\{order.generation}",
    order_id,
    organization_id: order.organization_id,
    project_id: order.project_id,
    subject_ref: order.purchaser_subject_ref,
    resource_ref,
    meter: offering.meter,
    quantity,
    unit: "second",
    started_unix_ms,
    ended_unix_ms,
    observed_unix_ms: now_unix_ms,
    receipt_digest: "",
  }
  let receipt = {
    ..unsigned,
    receipt_digest: sha256_text(receipt_material(unsigned)),
  }
  let updated = {
    ..order,
    state: Terminated,
    generation: order.generation + 1L,
    compensation_ref: Some(compensation_ref),
    capacity_reserved: false,
    last_metered_unix_ms: Some(ended_unix_ms),
    ended_unix_ms: Some(ended_unix_ms),
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.usage_receipts[receipt_id] = receipt
  self.meter_keys[key] = receipt_id
  self.record_action(
    order_id,
    idempotency_key,
    "termination-complete",
    updated.generation,
    now_unix_ms,
  )
  (updated, receipt, Created)
}

///|
pub fn MachineCommerceStore::record_usage(
  self : MachineCommerceStore,
  order_id : String,
  intent : MachineMeterIntent,
  now_unix_ms : Int64,
) -> (MachineOrder, MachineUsageReceipt, IdempotencyResult) raise MachineCommerceError {
  guard self.orders.get(order_id) is Some(order) else {
    raise NotFound("machine order")
  }
  let key = scoped_key(order_id, intent.idempotency_key)
  match self.meter_keys.get(key) {
    Some(receipt_id) =>
      return (order, self.usage_receipts[receipt_id], Replayed)
    None => ()
  }
  if !valid_id(intent.idempotency_key) ||
    intent.expected_generation != order.generation {
    if intent.expected_generation != order.generation {
      raise StaleGeneration
    }
    raise InvalidInput("invalid machine meter request")
  }
  if order.state != Active && order.state != TerminationPending {
    raise InvalidTransition("machine order is not billable")
  }
  guard order.last_metered_unix_ms is Some(started_unix_ms) else {
    raise InvalidTransition("machine order has no active lease interval")
  }
  let resource_ref = match order.offering_kind {
    BareMachine => order.target_lease_ref.unwrap()
    DedicatedEndpoint => order.target_deployment_ref.unwrap()
  }
  if intent.ended_unix_ms <= started_unix_ms ||
    intent.ended_unix_ms > now_unix_ms {
    raise InvalidInput("invalid machine usage interval")
  }
  guard self.offerings.get(order.offering_id) is Some(offering) else {
    raise NotFound("machine offering")
  }
  let elapsed_ms = intent.ended_unix_ms - started_unix_ms
  let quantity = checked_multiply((elapsed_ms + 999L) / 1000L, order.quantity)
  let receipt_id = "usage-\{order_id}-\{order.generation}"
  let unsigned : MachineUsageReceipt = {
    receipt_id,
    idempotency_key: intent.idempotency_key,
    event_id: "machine-order:\{order_id}:usage:\{order.generation}",
    order_id,
    organization_id: order.organization_id,
    project_id: order.project_id,
    subject_ref: order.purchaser_subject_ref,
    resource_ref,
    meter: offering.meter,
    quantity,
    unit: "second",
    started_unix_ms,
    ended_unix_ms: intent.ended_unix_ms,
    observed_unix_ms: now_unix_ms,
    receipt_digest: "",
  }
  let receipt = {
    ..unsigned,
    receipt_digest: sha256_text(receipt_material(unsigned)),
  }
  let updated = {
    ..order,
    generation: order.generation + 1L,
    last_metered_unix_ms: Some(intent.ended_unix_ms),
    updated_unix_ms: now_unix_ms,
  }
  self.orders[order_id] = updated
  self.usage_receipts[receipt_id] = receipt
  self.meter_keys[key] = receipt_id
  (updated, receipt, Created)
}

///|
pub fn MachineUsageReceipt::commercial_observation(
  self : MachineUsageReceipt,
) -> @commercial.UsageObservation {
  {
    event_id: self.event_id,
    organization_id: self.organization_id,
    project_id: self.project_id,
    actor_ref: self.subject_ref,
    workload_id: self.order_id,
    node_id: self.resource_ref,
    lease_epoch: 1L,
    meter: self.meter,
    quantity: self.quantity,
    unit: self.unit,
    started_unix_ms: self.started_unix_ms,
    ended_unix_ms: self.ended_unix_ms,
    observed_unix_ms: self.observed_unix_ms,
  }
}
