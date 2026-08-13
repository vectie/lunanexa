///|
pub(all) suberror DeliveryWorkerError {
  InvalidConfiguration(String)
} derive(Debug, Eq)

///|
enum DeliveryAdapterConfig {
  AdapterPending
  AdapterConfigured(
    endpoint~ : String,
    bearer_token~ : String,
    request_timeout_ms~ : Int
  )
}

///| Runs the provider-neutral outbound delivery boundary. Recipient lookup and

///| provider credentials stay behind the configured deployment adapter; this

///|
/// worker sends only an opaque audience and localization contract.
pub struct NotificationDeliveryWorker {
  store : @store.NotificationStore
  observability_store : @observability.ObservabilityStore?
  adapter : DeliveryAdapterConfig
  claim_lease_ms : Int64
  batch_limit : Int
  interval_ms : Int
}

///|
fn decimal_port(value : String) -> Bool {
  if value == "" ||
    value.length() > 5 ||
    !value.all(character => character >= '0' && character <= '9') {
    return false
  }
  let port = @string.parse_int64(value) catch { _ => return false }
  port > 0L && port <= 65535L
}

///|
fn safe_host(value : String) -> Bool {
  value != "" &&
  value.length() <= 253 &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '.' ||
    character == '-'
  }) &&
  !value.has_prefix(".") &&
  !value.has_suffix(".") &&
  !value.has_prefix("-") &&
  !value.has_suffix("-") &&
  !value.contains("..") &&
  value
  .split(".")
  .all(label => label != "" && !label.has_prefix("-") && !label.has_suffix("-"))
}

///|
fn safe_https_authority(authority : String) -> Bool {
  if authority == "" ||
    authority.contains("@") ||
    authority.contains("[") ||
    authority.contains("]") {
    return false
  }
  match authority.rev_find(":") {
    Some(colon) =>
      safe_host(authority[:colon].to_owned()) &&
      decimal_port(authority[colon + 1:].to_owned())
    None => safe_host(authority)
  }
}

///|
fn safe_loopback_authority(authority : String) -> Bool {
  if authority.has_prefix("127.0.0.1:") {
    decimal_port(authority[10:].to_owned())
  } else if authority.has_prefix("localhost:") {
    decimal_port(authority[10:].to_owned())
  } else if authority.has_prefix("[::1]:") {
    decimal_port(authority[6:].to_owned())
  } else {
    false
  }
}

///|
fn safe_adapter_endpoint(endpoint : String) -> Bool {
  if endpoint == "" ||
    endpoint != endpoint.trim().to_owned() ||
    endpoint.length() > 512 ||
    endpoint.contains("@") ||
    endpoint.contains("#") ||
    endpoint.contains("\\") ||
    endpoint.any(character => character.is_whitespace()) {
    return false
  }
  let (remainder, https) = if endpoint.has_prefix("https://") {
    (endpoint[8:].to_owned(), true)
  } else if endpoint.has_prefix("http://") {
    (endpoint[7:].to_owned(), false)
  } else {
    return false
  }
  guard remainder.find("/") is Some(slash) else { return false }
  let authority = remainder[:slash].to_owned()
  let path = remainder[slash:].to_owned()
  path.has_prefix("/") &&
  path.length() > 1 &&
  path.length() <= 256 &&
  !path.contains("?") &&
  !path.contains("#") &&
  path.all(character => character.is_printable() && !character.is_whitespace()) &&
  (if https {
    safe_https_authority(authority)
  } else {
    safe_loopback_authority(authority)
  })
}

///|
pub fn NotificationDeliveryWorker::adapters_pending(
  store : @store.NotificationStore,
) -> NotificationDeliveryWorker {
  {
    store,
    observability_store: None,
    adapter: AdapterPending,
    claim_lease_ms: 30000L,
    batch_limit: 100,
    interval_ms: 30000,
  }
}

///|
pub fn NotificationDeliveryWorker::configured(
  store : @store.NotificationStore,
  endpoint : String,
  bearer_token : String,
  request_timeout_ms? : Int = 5000,
  claim_lease_ms? : Int64 = 30000L,
  batch_limit? : Int = 100,
  interval_ms? : Int = 30000,
) -> NotificationDeliveryWorker raise DeliveryWorkerError {
  if !safe_adapter_endpoint(endpoint) ||
    bearer_token.length() < 32 ||
    bearer_token.length() > 4096 ||
    bearer_token.any(character => character.is_whitespace()) ||
    request_timeout_ms < 250 ||
    request_timeout_ms > 30000 ||
    claim_lease_ms < request_timeout_ms.to_int64() ||
    claim_lease_ms > 300000L ||
    batch_limit <= 0 ||
    batch_limit > 1000 ||
    interval_ms < 1000 ||
    interval_ms > 300000 {
    raise InvalidConfiguration(
      "notification delivery adapter configuration is invalid",
    )
  }
  {
    store,
    observability_store: None,
    adapter: AdapterConfigured(endpoint~, bearer_token~, request_timeout_ms~),
    claim_lease_ms,
    batch_limit,
    interval_ms,
  }
}

///| Installs the durable typed-event sink without coupling the worker to the

///|
/// HTTP server or exposing any delivery credentials through event payloads.
pub fn NotificationDeliveryWorker::with_observability_store(
  self : NotificationDeliveryWorker,
  store : @observability.ObservabilityStore,
) -> NotificationDeliveryWorker {
  { ..self, observability_store: Some(store) }
}

///|
async fn NotificationDeliveryWorker::record_delivery_pass(
  self : NotificationDeliveryWorker,
  now_unix_ms : Int64,
  summary : @notifications.NotificationDeliveryRunSummary,
) -> Unit {
  match self.observability_store {
    None => ()
    Some(store) => {
      let degraded = summary.dead_lettered > 0 ||
        summary.readiness.state == DeliveryDegraded
      ignore(
        store.record_generated({
          version: @observability.contract_version,
          event_id: "event-pending",
          timestamp_unix_ms: now_unix_ms,
          severity: if degraded {
            Error
          } else {
            Information
          },
          component: "notification-worker",
          event_code: "NotificationDeliveryBatchCompleted",
          correlation_id: "notification-delivery-batch-\{now_unix_ms}",
          actor_class: Controller,
          tenant_hash: None,
          target_type: "notification_delivery",
          outcome: if degraded {
            "degraded"
          } else if summary.attempted == 0 {
            "idle"
          } else {
            "delivered"
          },
          status_code: if degraded {
            503
          } else {
            200
          },
          duration_ms: 0L,
        }),
      )
    }
  }
}

///| Long-running bounded delivery loop. Individual adapter failures are

///|
/// retained as retry/dead-letter state. Unexpected store or worker failures are

/// persisted and propagated so the controller supervisor cannot report a

///|
/// silently healthy task.
pub async fn NotificationDeliveryWorker::run_forever(
  self : NotificationDeliveryWorker,
) -> Unit {
  for ;; {
    let now = @async.now()
    ignore(self.run_once(now)) catch {
      error => {
        ignore(self.store.record_worker_failure(now, "WorkerPassFailed")) catch {
          _ => ()
        }
        raise error
      }
    }
    @async.sleep(self.interval_ms)
  }
}

///|
pub async fn NotificationDeliveryWorker::readiness(
  self : NotificationDeliveryWorker,
  now_unix_ms? : Int64 = 0L,
) -> @notifications.NotificationDeliveryReadiness {
  self.store.delivery_readiness(
    self.adapter is AdapterConfigured(..),
    now_unix_ms~,
  )
}

///|
fn delivery_envelope(
  delivery : @notifications.NotificationDelivery,
  record : @notifications.NotificationRecord,
) -> @notifications.NotificationDeliveryEnvelope {
  let event = record.event
  {
    version: event.version,
    delivery_id: delivery.delivery_id,
    channel: delivery.channel,
    audience: event.audience,
    topic: event.topic,
    code: event.code,
    severity: event.severity,
    title_key: event.title_key,
    body_key: event.body_key,
    parameters: event.parameters,
    created_unix_ms: event.created_unix_ms,
  }
}

///|
fn retry_delay_ms(attempt_count : Int) -> Int64 {
  let exponent = (attempt_count - 1).max(0).min(10)
  let mut delay = 1000L
  for _ in 0..<exponent {
    delay *= 2L
  }
  delay.min(300000L)
}

///|
priv enum AdapterAttempt {
  AdapterAccepted(String)
  AdapterRetry(String)
  AdapterRejected(String)
}

///|
async fn call_adapter(
  endpoint : String,
  bearer_token : String,
  delivery : @notifications.NotificationDelivery,
  envelope : @notifications.NotificationDeliveryEnvelope,
) -> AdapterAttempt {
  let stream = @http.post_stream(endpoint, headers={
    "Authorization": "Bearer \{bearer_token}",
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Idempotency-Key": delivery.delivery_id,
  })
  defer stream.close()
  stream.write(envelope.to_json())
  let head = stream.end_request()
  if head.code >= 300 && head.code < 400 {
    return AdapterRejected("AdapterRedirectRejected")
  }
  let content_type = head.headers
    .iter()
    .find_first(entry => entry.0.to_lower() == "content-type")
    .map(entry => entry.1.to_lower())
  let buffer = @buffer.Buffer(size_hint=4096)
  for total = 0 {
    let remaining = 4097 - total
    match stream.read_some(max_len=remaining.min(4096)) {
      None => break
      Some(chunk) => {
        let next = total + chunk.length()
        if next > 4096 {
          return AdapterRejected("AdapterResponseTooLarge")
        }
        buffer.write_bytes(chunk)
        continue next
      }
    }
  }
  let retryable = head.code == 408 || head.code == 429 || head.code >= 500
  if head.code < 200 || head.code >= 300 {
    return if retryable {
      AdapterRetry("AdapterRetryableResponse")
    } else {
      AdapterRejected("AdapterRejectedResponse")
    }
  }
  if !content_type.map_or(false, value => value.has_prefix("application/json")) {
    return AdapterRejected("AdapterContentTypeRejected")
  }
  let body_text = @utf8.decode(buffer.to_bytes()) catch {
    _ => return AdapterRejected("AdapterMalformedResponse")
  }
  let receipt : @notifications.NotificationAdapterReceipt = @json.from_json(
    @json.parse(body_text),
  ) catch {
    _ => return AdapterRejected("AdapterMalformedResponse")
  }
  if !@contracts.valid_identifier(receipt.provider_receipt, maximum_length=512) {
    return AdapterRejected("AdapterMalformedResponse")
  }
  AdapterAccepted(receipt.provider_receipt)
}

///|
async fn NotificationDeliveryWorker::deliver_one(
  self : NotificationDeliveryWorker,
  endpoint : String,
  bearer_token : String,
  request_timeout_ms : Int,
  delivery : @notifications.NotificationDelivery,
  now_unix_ms : Int64,
) -> @notifications.NotificationDelivery {
  guard self.store.record(delivery.notification_id) is Some(record) else {
    return self.store.record_delivery_result({
      delivery_id: delivery.delivery_id,
      expected_attempt_count: delivery.attempt_count,
      delivered: false,
      retryable: false,
      provider_receipt: None,
      error_code: Some("NotificationRecordMissing"),
      next_attempt_unix_ms: None,
      now_unix_ms,
    })
  }
  let envelope = delivery_envelope(delivery, record)
  @notifications.validate_delivery_envelope(envelope)
  let attempt = @async.with_timeout(request_timeout_ms, () => {
    call_adapter(endpoint, bearer_token, delivery, envelope)
  }) catch {
    _ =>
      return self.store.record_delivery_result({
        delivery_id: delivery.delivery_id,
        expected_attempt_count: delivery.attempt_count,
        delivered: false,
        retryable: true,
        provider_receipt: None,
        error_code: Some("AdapterTransportUnavailable"),
        next_attempt_unix_ms: Some(
          now_unix_ms + retry_delay_ms(delivery.attempt_count),
        ),
        now_unix_ms,
      })
  }
  match attempt {
    AdapterAccepted(provider_receipt) =>
      self.store.record_delivery_result({
        delivery_id: delivery.delivery_id,
        expected_attempt_count: delivery.attempt_count,
        delivered: true,
        retryable: false,
        provider_receipt: Some(provider_receipt),
        error_code: None,
        next_attempt_unix_ms: None,
        now_unix_ms,
      })
    AdapterRetry(error_code) =>
      self.store.record_delivery_result({
        delivery_id: delivery.delivery_id,
        expected_attempt_count: delivery.attempt_count,
        delivered: false,
        retryable: true,
        provider_receipt: None,
        error_code: Some(error_code),
        next_attempt_unix_ms: Some(
          now_unix_ms + retry_delay_ms(delivery.attempt_count),
        ),
        now_unix_ms,
      })
    AdapterRejected(error_code) =>
      self.store.record_delivery_result({
        delivery_id: delivery.delivery_id,
        expected_attempt_count: delivery.attempt_count,
        delivered: false,
        retryable: false,
        provider_receipt: None,
        error_code: Some(error_code),
        next_attempt_unix_ms: None,
        now_unix_ms,
      })
  }
}

///| Executes at most one bounded delivery batch. When no external adapter is

///| configured it does not claim queue records; readiness remains explicitly

///|
/// `AdaptersPending` while intrinsic in-app delivery continues to work.
pub async fn NotificationDeliveryWorker::run_once(
  self : NotificationDeliveryWorker,
  now_unix_ms : Int64,
) -> @notifications.NotificationDeliveryRunSummary {
  if now_unix_ms <= 0L {
    raise @notifications.NotificationError::InvalidInput(
      "invalid delivery worker time",
    )
  }
  guard self.adapter
    is AdapterConfigured(endpoint~, bearer_token~, request_timeout_ms~) else {
    ignore(self.store.record_worker_pass(now_unix_ms, 0, 0, 0, 0))
    let summary : @notifications.NotificationDeliveryRunSummary = {
      attempted: 0,
      delivered: 0,
      retry_scheduled: 0,
      dead_lettered: 0,
      skipped: 0,
      readiness: self.readiness(now_unix_ms~),
    }
    self.record_delivery_pass(now_unix_ms, summary)
    return summary
  }
  let claimed = self.store.claim_due_deliveries(
    now_unix_ms,
    self.claim_lease_ms,
    self.batch_limit,
  )
  let mut delivered = 0
  let mut retried = 0
  let mut dead = 0
  let mut skipped = 0
  for item in claimed {
    match
      self.store.skip_delivery_if_ineligible(
        item.delivery_id,
        item.attempt_count,
        now_unix_ms,
      ) {
      Some(_) => {
        skipped += 1
        continue
      }
      None => ()
    }
    let result = self.deliver_one(
      endpoint, bearer_token, request_timeout_ms, item, now_unix_ms,
    )
    match result.state {
      Delivered => delivered += 1
      RetryScheduled => retried += 1
      DeadLetter => dead += 1
      DeliverySkipped => skipped += 1
      _ => ()
    }
  }
  ignore(
    self.store.record_worker_pass(
      now_unix_ms,
      claimed.length(),
      delivered,
      retried,
      dead,
    ),
  )
  let summary : @notifications.NotificationDeliveryRunSummary = {
    attempted: claimed.length(),
    delivered,
    retry_scheduled: retried,
    dead_lettered: dead,
    skipped,
    readiness: self.readiness(now_unix_ms~),
  }
  self.record_delivery_pass(now_unix_ms, summary)
  summary
}
