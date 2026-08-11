///|
fn sha256_hex(value : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
fn stable_ref(prefix : String, value : String) -> String {
  "\{prefix}_\{sha256_hex(value)}"
}

///|
fn webhook_material(event : WebhookEvent) -> String {
  let unsigned = { ..event, signature: "" }
  "lunafide.webhook-test-mac.v1|\{unsigned.to_json().stringify()}"
}

///|
/// Produces a test-only MAC. It is useful for callback rejection tests and is
/// not a production cryptographic trust or qualified-signature mechanism.
pub fn sign_webhook(event : WebhookEvent, test_secret : String) -> String {
  if test_secret == "" {
    ""
  } else {
    let key = @utf8.encode(test_secret)
    let material = @utf8.encode(webhook_material(event))
    @crypto.bytes_to_hex_string(
      @crypto.hmac(@crypto.SHA256::new(), key.view(), material.view()),
    )
  }
}

///|
pub fn webhook_signature_valid(
  event : WebhookEvent,
  test_secret : String,
) -> Bool {
  test_secret != "" &&
  event.signature != "" &&
  event.signature == sign_webhook(event, test_secret)
}

///|
pub struct WebhookReceiver {
  seen_event_ids : Map[String, Unit]
  last_sequences : Map[String, Int64]
}

///|
pub fn WebhookReceiver::new() -> WebhookReceiver {
  { seen_event_ids: Map([]), last_sequences: Map([]) }
}

///|
fn callback_stream(event : WebhookEvent) -> String {
  "\{event.tenant_ref}|\{event.aggregate_ref}"
}

///|
/// Verifies and consumes exactly one simulator callback. Validation completes
/// before replay state is mutated, so a forged event cannot reserve an ID.
pub fn WebhookReceiver::accept(
  self : WebhookReceiver,
  event : WebhookEvent,
  test_secret : String,
  expected_tenant_ref : String,
  expected_aggregate_ref : String,
  now_unix_ms : Int64,
  max_clock_skew_ms : Int64,
) -> Unit raise LunaFideError {
  if event.protocol_version != protocol_version ||
    event.provider != "LunaFide" ||
    event.environment != "test-only" ||
    event.auth_scheme != "HMAC-SHA256-TEST-ONLY" ||
    event.key_id != "lunafide-ephemeral-v1" ||
    event.tenant_ref != expected_tenant_ref ||
    event.aggregate_ref != expected_aggregate_ref ||
    !webhook_signature_valid(event, test_secret) {
    raise LunaFideError::ForgedWebhook(event.event_id)
  }
  if max_clock_skew_ms < 0L ||
    (now_unix_ms - event.occurred_unix_ms).abs() > max_clock_skew_ms {
    raise LunaFideError::ExpiredWebhook(event.event_id)
  }
  if self.seen_event_ids.contains(event.event_id) {
    raise LunaFideError::ReplayWebhook(event.event_id)
  }
  let stream = callback_stream(event)
  match self.last_sequences.get(stream) {
    Some(previous) if event.sequence <= previous =>
      raise LunaFideError::StaleWebhook(event.event_id)
    _ => ()
  }
  self.seen_event_ids[event.event_id] = ()
  self.last_sequences[stream] = event.sequence
}
