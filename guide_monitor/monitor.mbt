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
pub fn validate_policy(
  policy : GuideMonitorPolicy,
) -> Unit raise GuideMonitorError {
  if !@contracts.valid_identifier(policy.target_ref, maximum_length=128) ||
    policy.probe_interval_ms < 10000L ||
    policy.probe_interval_ms > 86400000L ||
    policy.observation_max_age_ms < 1000L ||
    policy.observation_max_age_ms > 3600000L ||
    policy.future_skew_ms < 0L ||
    policy.future_skew_ms > 300000L ||
    policy.knowledge_max_age_ms < 60000L ||
    policy.knowledge_max_age_ms > 2592000000L {
    raise InvalidPolicy("guide monitor policy is outside bounded limits")
  }
}

///|
pub fn probe_due(
  policy : GuideMonitorPolicy,
  last_scheduled_unix_ms : Int64?,
  now_unix_ms : Int64,
) -> Bool raise GuideMonitorError {
  validate_policy(policy)
  now_unix_ms > 0L &&
  last_scheduled_unix_ms.map_or(true, last => {
    last <= now_unix_ms && now_unix_ms - last >= policy.probe_interval_ms
  })
}

///|
pub fn scheduled_probe_plan(
  policy : GuideMonitorPolicy,
  sequence : Int64,
  now_unix_ms : Int64,
) -> GuideProbePlan raise GuideMonitorError {
  validate_policy(policy)
  if sequence <= 0L || now_unix_ms <= 0L {
    raise InvalidPolicy("guide probe sequence or time is invalid")
  }
  {
    version: contract_version,
    target_ref: policy.target_ref,
    correlation_receipt: "guide-probe-\{sequence}-\{now_unix_ms}",
    scheduled_unix_ms: now_unix_ms,
    health_path: "/health",
    diagnostics_path: "/api/coursebook/admin/diagnostics?category=overview",
  }
}

///|
fn canonical_observation(observation : GuideHealthObservation) -> String {
  { ..observation, signature: "" }.to_json().stringify()
}

///|
pub fn observation_signature(
  observation : GuideHealthObservation,
  signing_secret : String,
) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(signing_secret).view(),
      @utf8.encode(
        "lunanexa.guide-monitor.mac.v1|\{canonical_observation(observation)}",
      ).view(),
    ),
  )
}

///|
pub fn sign_observation(
  observation : GuideHealthObservation,
  signing_secret : String,
) -> GuideHealthObservation {
  {
    ..observation,
    signature: observation_signature(observation, signing_secret),
  }
}

///|
fn validate_observation_shape(
  observation : GuideHealthObservation,
) -> Unit raise GuideMonitorError {
  if observation.version != contract_version ||
    !@contracts.valid_identifier(observation.observation_id, maximum_length=128) ||
    !@contracts.valid_identifier(observation.target_ref, maximum_length=128) ||
    !@contracts.valid_identifier(
      observation.correlation_receipt,
      maximum_length=128,
    ) ||
    observation.scheduled_unix_ms <= 0L ||
    observation.observed_unix_ms < observation.scheduled_unix_ms ||
    !@contracts.valid_identifier(
      observation.knowledge_revision,
      maximum_length=128,
    ) ||
    observation.knowledge_age_ms < 0L ||
    observation.knowledge_age_ms > 315360000000L ||
    observation.signature.length() != 64 ||
    !observation.signature.all(character => {
      (character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f') ||
      (character >= 'A' && character <= 'F')
    }) {
    raise InvalidObservation("guide health observation is invalid")
  }
}

///|
pub fn verify_observation(
  policy : GuideMonitorPolicy,
  observation : GuideHealthObservation,
  signing_secret : String,
  now_unix_ms : Int64,
) -> Unit raise GuideMonitorError {
  validate_policy(policy)
  validate_observation_shape(observation)
  if signing_secret.length() < 32 || observation.target_ref != policy.target_ref {
    raise InvalidSignature
  }
  let expected = observation_signature(observation, signing_secret)
  if !constant_time_equal(observation.signature, expected) {
    raise InvalidSignature
  }
  if observation.observed_unix_ms > now_unix_ms + policy.future_skew_ms ||
    now_unix_ms - observation.observed_unix_ms > policy.observation_max_age_ms {
    raise StaleObservation
  }
}

///|
pub fn verify_planned_observation(
  policy : GuideMonitorPolicy,
  plan : GuideProbePlan,
  observation : GuideHealthObservation,
  signing_secret : String,
  now_unix_ms : Int64,
) -> Unit raise GuideMonitorError {
  if plan.version != contract_version ||
    plan.target_ref != policy.target_ref ||
    plan.health_path != "/health" ||
    plan.diagnostics_path !=
    "/api/coursebook/admin/diagnostics?category=overview" ||
    observation.target_ref != plan.target_ref ||
    observation.correlation_receipt != plan.correlation_receipt ||
    observation.scheduled_unix_ms != plan.scheduled_unix_ms {
    raise InvalidObservation("guide observation does not match its probe plan")
  }
  verify_observation(policy, observation, signing_secret, now_unix_ms)
}

///|
async fn reconcile_operator_alert(
  store : @store.NotificationStore,
  observation : GuideHealthObservation,
  active : Bool,
  deduplication_key : String,
  code : String,
  title_key : String,
  body_key : String,
  runbook_page_id : String,
  now_unix_ms : Int64,
) -> @notifications.NotificationRecord? {
  match
    store.record_by_deduplication_key(deduplication_key, PlatformOperators) {
    Some(record) if active && record.lifecycle != Resolved => Some(record)
    Some(record) if !active && record.lifecycle != Resolved =>
      Some(
        store.resolve_operator({
          notification_id: record.event.notification_id,
          expected_generation: record.generation,
          actor_ref: "guide-monitor",
          now_unix_ms,
        }),
      )
    Some(record) if active && record.lifecycle == Resolved =>
      Some(
        store.enqueue({
          version: @notifications.contract_version,
          notification_id: "guide-\{code}-\{observation.observation_id}",
          deduplication_key,
          source_receipt: "guide-monitor:\{observation.observation_id}:\{code}",
          topic: GuideDiagnostics,
          code,
          severity: if code == "GuideAdapterUnavailable" {
            Critical
          } else {
            Warning
          },
          audience: PlatformOperators,
          title_key,
          body_key,
          parameters: {
            "target_ref": observation.target_ref,
            "correlation_receipt": observation.correlation_receipt,
            "knowledge_revision": observation.knowledge_revision,
            "runbook_page_id": runbook_page_id,
          },
          created_unix_ms: now_unix_ms,
          expires_unix_ms: None,
        }),
      )
    Some(record) => Some(record)
    None if active =>
      Some(
        store.enqueue({
          version: @notifications.contract_version,
          notification_id: "guide-\{code}-\{observation.observation_id}",
          deduplication_key,
          source_receipt: "guide-monitor:\{observation.observation_id}:\{code}",
          topic: GuideDiagnostics,
          code,
          severity: if code == "GuideAdapterUnavailable" {
            Critical
          } else {
            Warning
          },
          audience: PlatformOperators,
          title_key,
          body_key,
          parameters: {
            "target_ref": observation.target_ref,
            "correlation_receipt": observation.correlation_receipt,
            "knowledge_revision": observation.knowledge_revision,
            "runbook_page_id": runbook_page_id,
          },
          created_unix_ms: now_unix_ms,
          expires_unix_ms: None,
        }),
      )
    None => None
  }
}

///|
pub async fn reconcile_observation(
  store : @store.NotificationStore,
  policy : GuideMonitorPolicy,
  observation : GuideHealthObservation,
  signing_secret : String,
  now_unix_ms : Int64,
) -> GuideMonitorResult {
  verify_observation(policy, observation, signing_secret, now_unix_ms)
  let adapter_alert_active = !observation.coursebook_ok ||
    !observation.admin_diagnostics_enabled ||
    !observation.admin_diagnostics_ok
  let knowledge_alert_active = observation.knowledge_stale ||
    observation.knowledge_age_ms > policy.knowledge_max_age_ms
  let adapter_record = reconcile_operator_alert(
    store,
    observation,
    adapter_alert_active,
    "guide-adapter-unavailable-\{policy.target_ref}",
    "GuideAdapterUnavailable",
    "alerts.guide_adapter_unavailable.title",
    "alerts.guide_adapter_unavailable.body",
    "debug-controller",
    now_unix_ms,
  )
  let knowledge_record = reconcile_operator_alert(
    store,
    observation,
    knowledge_alert_active,
    "guide-knowledge-stale-\{policy.target_ref}",
    "KnowledgeRevisionStale",
    "alerts.knowledge_revision_stale.title",
    "alerts.knowledge_revision_stale.body",
    "source-ledger",
    now_unix_ms,
  )
  {
    observation_id: observation.observation_id,
    adapter_alert_active,
    knowledge_alert_active,
    adapter_record,
    knowledge_record,
  }
}

///|
pub async fn reconcile_planned_observation(
  store : @store.NotificationStore,
  policy : GuideMonitorPolicy,
  plan : GuideProbePlan,
  observation : GuideHealthObservation,
  signing_secret : String,
  now_unix_ms : Int64,
) -> GuideMonitorResult {
  verify_planned_observation(
    policy, plan, observation, signing_secret, now_unix_ms,
  )
  reconcile_observation(store, policy, observation, signing_secret, now_unix_ms)
}
