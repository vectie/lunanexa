///|
fn safe_public_text(value : String, maximum_length : Int) -> Bool {
  let normalized = value.to_lower()
  value.length() > 0 &&
  value.length() <= maximum_length &&
  value.all(character => {
    character.is_printable() &&
    character != '<' &&
    character != '>' &&
    character != '\n' &&
    character != '\r'
  }) &&
  ![
    "bearer ", "authorization:", "password=", "private key", "ssh-rsa ", "callback_body",
    "document_bytes", "raw_prompt", "model_output",
  ].any(marker => normalized.contains(marker))
}

///|
fn valid_audience(audience : NotificationAudience) -> Bool {
  match audience {
    PlatformOperators => true
    TenantUsers(tenant_ref~) => @contracts.valid_identifier(tenant_ref)
    Subject(tenant_ref~, subject_ref~) =>
      @contracts.valid_identifier(tenant_ref) &&
      @contracts.valid_identifier(subject_ref)
  }
}

///|
pub fn validate_event(
  event : NotificationEvent,
) -> Unit raise NotificationError {
  if event.version != contract_version ||
    !@contracts.valid_identifier(event.notification_id) ||
    !@contracts.valid_identifier(event.deduplication_key) ||
    !safe_public_text(event.source_receipt, 512) ||
    !@contracts.valid_identifier(event.code) ||
    !@contracts.valid_identifier(event.title_key) ||
    !@contracts.valid_identifier(event.body_key) ||
    !valid_audience(event.audience) ||
    event.created_unix_ms <= 0L ||
    event.expires_unix_ms.map_or(false, expiry => {
      expiry <= event.created_unix_ms
    }) ||
    event.parameters.length() > 16 {
    raise InvalidInput("invalid notification event")
  }
  for key, value in event.parameters {
    if !@contracts.valid_identifier(key) || !safe_public_text(value, 256) {
      raise InvalidInput("invalid notification parameter")
    }
  }
}

///|
pub fn validate_preference(
  preference : NotificationPreference,
) -> Unit raise NotificationError {
  if !@contracts.valid_identifier(preference.preference_id) ||
    !@contracts.valid_identifier(preference.tenant_ref) ||
    !@contracts.valid_identifier(preference.subject_ref) ||
    preference.channels.length() == 0 ||
    preference.channels.length() > 4 ||
    preference.channels.any(channel => preference.channels.count(channel) != 1) ||
    !preference.channels.contains(InApp) ||
    preference.updated_unix_ms <= 0L {
    raise InvalidInput("invalid notification preference")
  }
}

///|
pub fn validate_rule(rule : AlertRule) -> Unit raise NotificationError {
  if !@contracts.valid_identifier(rule.rule_id) ||
    !@contracts.valid_identifier(rule.code) ||
    !@contracts.valid_identifier(rule.title_key) ||
    !@contracts.valid_identifier(rule.body_key) ||
    !valid_audience(rule.audience) ||
    rule.threshold < 0L {
    raise InvalidInput("invalid alert rule")
  }
}

///|
pub fn validate_delivery_envelope(
  envelope : NotificationDeliveryEnvelope,
) -> Unit raise NotificationError {
  if envelope.version != contract_version ||
    !@contracts.valid_identifier(envelope.delivery_id) ||
    envelope.channel == InApp ||
    !valid_audience(envelope.audience) ||
    !@contracts.valid_identifier(envelope.code) ||
    !@contracts.valid_identifier(envelope.title_key) ||
    !@contracts.valid_identifier(envelope.body_key) ||
    envelope.parameters.length() > 16 ||
    envelope.created_unix_ms <= 0L {
    raise InvalidInput("invalid outbound delivery envelope")
  }
  for key, value in envelope.parameters {
    if !@contracts.valid_identifier(key) || !safe_public_text(value, 256) {
      raise InvalidInput("invalid outbound delivery parameter")
    }
  }
}
