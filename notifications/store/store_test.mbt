///|
fn temp_path(name : String) -> String {
  "/tmp/lunanexa-notifications-\{@async.now()}-\{name}.json"
}

///|
fn lease_event(
  notification_id : String,
  source_receipt : String,
) -> @notifications.NotificationEvent {
  {
    version: @notifications.contract_version,
    notification_id,
    deduplication_key: "lease-a-ready",
    source_receipt,
    topic: LeaseLifecycle,
    code: "LeaseAccessReady",
    severity: Information,
    audience: Subject(tenant_ref="tenant-a", subject_ref="subject-a"),
    title_key: "notifications.lease_ready.title",
    body_key: "notifications.lease_ready.body",
    parameters: { "lease_id": "lease-a" },
    created_unix_ms: 1000L,
    expires_unix_ms: Some(10000L),
  }
}

///|
async test "notifications persist, replay idempotently and stay tenant scoped" {
  let path = temp_path("restart")
  let store = @store.NotificationStore::open(path)
  let event = lease_event("notice-a", "audit:lease-a:ready")
  let created = store.enqueue(event)
  let replayed = store.enqueue(event)
  assert_eq(created, replayed)
  assert_eq(
    store.records_for_subject("tenant-a", "subject-a", 2000L).length(),
    1,
  )
  assert_eq(
    store.records_for_subject("tenant-b", "subject-a", 2000L).length(),
    0,
  )
  let read = store.mark_read_for_subject("tenant-a", "subject-a", {
    notification_id: "notice-a",
    expected_generation: 1L,
    actor_ref: "subject-a",
    now_unix_ms: 2100L,
  })
  assert_eq(read.lifecycle, Read)
  let reopened = @store.NotificationStore::open(path)
  assert_eq(
    reopened.records_for_subject("tenant-a", "subject-a", 2200L)[0].lifecycle,
    Read,
  )
  @fs.remove(path)
}

///|
async test "external delivery is leased, retried and dead-lettered" {
  let path = temp_path("delivery")
  let store = @store.NotificationStore::open(path, maximum_delivery_attempts=2)
  ignore(
    store.set_preference({
      preference_id: "pref-a",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      topic: LeaseLifecycle,
      channels: [InApp, Email],
      minimum_severity: Information,
      updated_unix_ms: 900L,
    }),
  )
  ignore(store.enqueue(lease_event("notice-delivery", "audit:delivery")))
  let first = store.claim_due_deliveries(1000L, 100L, 10)
  assert_eq(first.length(), 1)
  let retry = store.record_delivery_result({
    delivery_id: first[0].delivery_id,
    expected_attempt_count: 1,
    delivered: false,
    retryable: true,
    provider_receipt: None,
    error_code: Some("ProviderUnavailable"),
    next_attempt_unix_ms: Some(1200L),
    now_unix_ms: 1100L,
  })
  assert_eq(retry.state, RetryScheduled)
  let second = store.claim_due_deliveries(1200L, 100L, 10)
  assert_eq(second.length(), 1)
  let terminal = store.record_delivery_result({
    delivery_id: second[0].delivery_id,
    expected_attempt_count: 2,
    delivered: false,
    retryable: true,
    provider_receipt: None,
    error_code: Some("ProviderUnavailable"),
    next_attempt_unix_ms: Some(1400L),
    now_unix_ms: 1300L,
  })
  assert_eq(terminal.state, DeadLetter)
  @fs.remove(path)
}

///|
async test "operator alerts support acknowledgement silence assignment and resolution" {
  let path = temp_path("operator")
  let store = @store.NotificationStore::open(path)
  let event : @notifications.NotificationEvent = {
    version: @notifications.contract_version,
    notification_id: "alert-node-a",
    deduplication_key: "node-a-unreachable",
    source_receipt: "health:node-a:1000",
    topic: ClusterHealth,
    code: "NodeUnreachable",
    severity: Critical,
    audience: PlatformOperators,
    title_key: "alerts.node_unreachable.title",
    body_key: "alerts.node_unreachable.body",
    parameters: { "node_ref": "node-a" },
    created_unix_ms: 1000L,
    expires_unix_ms: None,
  }
  ignore(store.enqueue(event))
  let acknowledged = store.acknowledge_operator({
    notification_id: "alert-node-a",
    expected_generation: 1L,
    actor_ref: "operator-a",
    now_unix_ms: 1100L,
  })
  let silenced = store.silence_operator({
    notification_id: "alert-node-a",
    expected_generation: acknowledged.generation,
    actor_ref: "operator-a",
    now_unix_ms: 1200L,
    silenced_until_unix_ms: 2200L,
  })
  let assigned = store.assign_operator({
    notification_id: "alert-node-a",
    expected_generation: silenced.generation,
    actor_ref: "operator-a",
    assignee_ref: Some("operator-b"),
    now_unix_ms: 1300L,
  })
  let resolved = store.resolve_operator({
    notification_id: "alert-node-a",
    expected_generation: assigned.generation,
    actor_ref: "operator-b",
    now_unix_ms: 1400L,
  })
  assert_eq(resolved.lifecycle, Resolved)
  assert_eq(resolved.silenced_until_unix_ms, None)
  @fs.remove(path)
}
