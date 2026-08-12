///|
fn validate_action(
  record : NotificationRecord,
  action : NotificationAction,
) -> Unit raise NotificationError {
  if record.event.notification_id != action.notification_id ||
    !@contracts.valid_identifier(action.actor_ref) ||
    action.now_unix_ms < record.updated_unix_ms {
    raise InvalidInput("invalid notification action")
  }
  if action.expected_generation != record.generation {
    raise StaleGeneration
  }
}

///|
pub fn NotificationRecord::mark_read(
  self : NotificationRecord,
  action : NotificationAction,
) -> NotificationRecord raise NotificationError {
  validate_action(self, action)
  match self.lifecycle {
    Unread =>
      {
        ..self,
        lifecycle: Read,
        generation: self.generation + 1L,
        updated_unix_ms: action.now_unix_ms,
      }
    Read | Acknowledged | Resolved => self
  }
}

///|
pub fn NotificationRecord::acknowledge(
  self : NotificationRecord,
  action : NotificationAction,
) -> NotificationRecord raise NotificationError {
  validate_action(self, action)
  if self.lifecycle == Resolved {
    raise InvalidTransition("resolved notifications cannot be acknowledged")
  }
  {
    ..self,
    lifecycle: Acknowledged,
    generation: self.generation + 1L,
    acknowledged_by: Some(action.actor_ref),
    acknowledged_unix_ms: Some(action.now_unix_ms),
    updated_unix_ms: action.now_unix_ms,
  }
}

///|
pub fn NotificationRecord::resolve(
  self : NotificationRecord,
  action : NotificationAction,
) -> NotificationRecord raise NotificationError {
  validate_action(self, action)
  if self.lifecycle == Resolved {
    return self
  }
  {
    ..self,
    lifecycle: Resolved,
    generation: self.generation + 1L,
    resolved_by: Some(action.actor_ref),
    resolved_unix_ms: Some(action.now_unix_ms),
    silenced_until_unix_ms: None,
    updated_unix_ms: action.now_unix_ms,
  }
}

///|
pub fn NotificationRecord::silence(
  self : NotificationRecord,
  action : NotificationSilenceAction,
) -> NotificationRecord raise NotificationError {
  validate_action(self, {
    notification_id: action.notification_id,
    expected_generation: action.expected_generation,
    actor_ref: action.actor_ref,
    now_unix_ms: action.now_unix_ms,
  })
  if self.lifecycle == Resolved ||
    action.silenced_until_unix_ms <= action.now_unix_ms ||
    action.silenced_until_unix_ms - action.now_unix_ms > 2592000000L {
    raise InvalidTransition("notification silence must be active and bounded")
  }
  {
    ..self,
    generation: self.generation + 1L,
    silenced_until_unix_ms: Some(action.silenced_until_unix_ms),
    updated_unix_ms: action.now_unix_ms,
  }
}

///|
pub fn NotificationRecord::assign(
  self : NotificationRecord,
  action : NotificationAssignmentAction,
) -> NotificationRecord raise NotificationError {
  validate_action(self, {
    notification_id: action.notification_id,
    expected_generation: action.expected_generation,
    actor_ref: action.actor_ref,
    now_unix_ms: action.now_unix_ms,
  })
  if self.lifecycle == Resolved ||
    action.assignee_ref.map_or(false, assignee => {
      !@contracts.valid_identifier(assignee)
    }) {
    raise InvalidTransition("notification assignment is invalid")
  }
  {
    ..self,
    generation: self.generation + 1L,
    assigned_to: action.assignee_ref,
    updated_unix_ms: action.now_unix_ms,
  }
}

///|
fn severity_rank(severity : NotificationSeverity) -> Int {
  match severity {
    Information => 0
    Warning => 1
    Critical => 2
  }
}

///|
pub fn preference_allows(
  preference : NotificationPreference,
  event : NotificationEvent,
  channel : NotificationChannel,
) -> Bool {
  preference.topic == event.topic &&
  preference.channels.contains(channel) &&
  severity_rank(event.severity) >= severity_rank(preference.minimum_severity)
}

///|
pub fn alert_fires(rule : AlertRule, observation : AlertObservation) -> Bool {
  rule.enabled &&
  (match rule.comparator {
    AtLeast => observation.value >= rule.threshold
    GreaterThan => observation.value > rule.threshold
  })
}

///|
pub fn alert_event(
  rule : AlertRule,
  observation : AlertObservation,
  notification_id : String,
) -> NotificationEvent? raise NotificationError {
  validate_rule(rule)
  if !alert_fires(rule, observation) {
    return None
  }
  if !@contracts.valid_identifier(observation.observation_id) ||
    !@contracts.valid_identifier(observation.dimension_ref) ||
    !safe_public_text(observation.source_receipt, 512) ||
    observation.observed_unix_ms <= 0L {
    raise InvalidInput("invalid alert observation")
  }
  let event : NotificationEvent = {
    version: contract_version,
    notification_id,
    deduplication_key: "\{rule.rule_id}-\{observation.dimension_ref}",
    source_receipt: observation.source_receipt,
    topic: rule.topic,
    code: rule.code,
    severity: rule.severity,
    audience: rule.audience,
    title_key: rule.title_key,
    body_key: rule.body_key,
    parameters: {
      "dimension_ref": observation.dimension_ref,
      "value": observation.value.to_string(),
      "threshold": rule.threshold.to_string(),
    },
    created_unix_ms: observation.observed_unix_ms,
    expires_unix_ms: None,
  }
  validate_event(event)
  Some(event)
}

///|
pub fn NotificationDelivery::record_result(
  self : NotificationDelivery,
  result : DeliveryResult,
  maximum_attempts : Int,
) -> NotificationDelivery raise NotificationError {
  if self.delivery_id != result.delivery_id ||
    self.state != Delivering ||
    self.attempt_count != result.expected_attempt_count ||
    maximum_attempts <= 0 ||
    result.now_unix_ms < self.updated_unix_ms ||
    result.provider_receipt.map_or(false, receipt => {
      !safe_public_text(receipt, 512)
    }) ||
    result.error_code.map_or(false, code => !@contracts.valid_identifier(code)) {
    raise InvalidInput("invalid delivery result")
  }
  if result.delivered {
    if result.provider_receipt is None || result.error_code is Some(_) {
      raise InvalidInput("delivered notification requires a provider receipt")
    }
    {
      ..self,
      state: Delivered,
      next_attempt_unix_ms: None,
      provider_receipt: result.provider_receipt,
      last_error_code: None,
      updated_unix_ms: result.now_unix_ms,
    }
  } else if result.retryable && self.attempt_count < maximum_attempts {
    guard result.next_attempt_unix_ms is Some(next) && next > result.now_unix_ms else {
      raise InvalidInput("retryable delivery requires a future attempt")
    }
    {
      ..self,
      state: RetryScheduled,
      next_attempt_unix_ms: Some(next),
      provider_receipt: None,
      last_error_code: result.error_code,
      updated_unix_ms: result.now_unix_ms,
    }
  } else {
    {
      ..self,
      state: DeadLetter,
      next_attempt_unix_ms: None,
      provider_receipt: None,
      last_error_code: result.error_code,
      updated_unix_ms: result.now_unix_ms,
    }
  }
}
