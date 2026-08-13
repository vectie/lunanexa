///|
fn subject_event() -> @notifications.NotificationEvent {
  {
    version: @notifications.contract_version,
    notification_id: "notice-1",
    deduplication_key: "lease-1-ready",
    source_receipt: "audit:lease-1:active",
    topic: LeaseLifecycle,
    code: "LeaseAccessReady",
    severity: Information,
    audience: Subject(tenant_ref="tenant-a", subject_ref="subject-a"),
    title_key: "notifications.lease_ready.title",
    body_key: "notifications.lease_ready.body",
    parameters: { "lease_id": "lease-1" },
    created_unix_ms: 1000L,
    expires_unix_ms: Some(5000L),
  }
}

///|
test "notification lifecycle is generation fenced and terminal" {
  let event = subject_event()
  @notifications.validate_event(event)
  let initial : @notifications.NotificationRecord = {
    event,
    lifecycle: Unread,
    generation: 1L,
    assigned_to: None,
    acknowledged_by: None,
    acknowledged_unix_ms: None,
    silenced_until_unix_ms: None,
    resolved_by: None,
    resolved_unix_ms: None,
    updated_unix_ms: 1000L,
  }
  let read = initial.mark_read({
    notification_id: "notice-1",
    expected_generation: 1L,
    actor_ref: "subject-a",
    now_unix_ms: 1100L,
  })
  assert_eq(read.lifecycle, Read)
  let acknowledged = read.acknowledge({
    notification_id: "notice-1",
    expected_generation: 2L,
    actor_ref: "operator-a",
    now_unix_ms: 1200L,
  })
  let resolved = acknowledged.resolve({
    notification_id: "notice-1",
    expected_generation: 3L,
    actor_ref: "operator-a",
    now_unix_ms: 1300L,
  })
  assert_eq(resolved.lifecycle, Resolved)
  try
    acknowledged.resolve({
      notification_id: "notice-1",
      expected_generation: 2L,
      actor_ref: "operator-a",
      now_unix_ms: 1400L,
    })
  catch {
    StaleGeneration => ()
    _ => fail("expected stale generation")
  } noraise {
    _ => fail("expected stale generation")
  }
}

///|
test "alert rules produce stable localized event keys" {
  let rule : @notifications.AlertRule = {
    rule_id: "node-unreachable",
    topic: ClusterHealth,
    code: "NodeUnreachable",
    severity: Critical,
    comparator: AtLeast,
    threshold: 1L,
    title_key: "alerts.node_unreachable.title",
    body_key: "alerts.node_unreachable.body",
    audience: PlatformOperators,
    enabled: true,
  }
  let event = @notifications.alert_event(
    rule,
    {
      observation_id: "observation-1",
      dimension_ref: "node-1",
      value: 1L,
      observed_unix_ms: 2000L,
      source_receipt: "health:node-1:2000",
    },
    "notice-node-1",
  )
  guard event is Some(fired) else { fail("expected alert") }
  assert_eq(fired.deduplication_key, "node-unreachable-node-1")
  assert_eq(fired.parameters["threshold"], "1")
}

///|
test "preferences always retain the in-app channel" {
  try
    @notifications.validate_preference({
      preference_id: "pref-1",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      topic: LeaseLifecycle,
      channels: [Email],
      minimum_severity: Warning,
      updated_unix_ms: 1000L,
    })
  catch {
    InvalidInput(_) => ()
    _ => fail("expected invalid preference")
  } noraise {
    _ => fail("expected invalid preference")
  }
}

///|
test "notification receipts and parameters reject secret-shaped material" {
  for
    value in [
      "Bearer production-token", "authorization: private", "private key data", "raw_prompt customer text",
      "model_output private text",
    ] {
    let event = { ..subject_event(), source_receipt: value }
    try @notifications.validate_event(event) catch {
      InvalidInput(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("secret-shaped notification receipt was accepted")
    }
  }
}
