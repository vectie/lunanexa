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

///|
async test "elapsed silence expires durably and readiness exposes pending adapters" {
  let path = temp_path("silence-expiry")
  let store = @store.NotificationStore::open(path)
  let event : @notifications.NotificationEvent = {
    ..lease_event("notice-silenced", "audit:silence"),
    audience: PlatformOperators,
    code: "NodeUnreachable",
  }
  ignore(store.enqueue(event))
  let silenced = store.silence_operator({
    notification_id: event.notification_id,
    expected_generation: 1L,
    actor_ref: "operator-a",
    now_unix_ms: 1100L,
    silenced_until_unix_ms: 1200L,
  })
  assert_eq(silenced.silenced_until_unix_ms, Some(1200L))
  assert_eq(store.expire_silences(1200L), 1)
  let reopened = @store.NotificationStore::open(path)
  let restored = reopened.record(event.notification_id).unwrap()
  assert_eq(restored.silenced_until_unix_ms, None)
  assert_eq(restored.generation, 3L)
  let readiness = reopened.delivery_readiness(false)
  assert_eq(readiness.state, AdaptersPending)
  assert_eq(readiness.supported_channels, [InApp])
  @fs.remove(path)
}

///|
async test "critical operator alert escalates and resolved claimed work is skipped" {
  let path = temp_path("operator-escalation-skip")
  let store = @store.NotificationStore::open(path)
  let event : @notifications.NotificationEvent = {
    ..lease_event("operator-critical", "audit:operator-critical"),
    audience: PlatformOperators,
    code: "NodeUnreachable",
    severity: Critical,
    expires_unix_ms: None,
  }
  ignore(store.enqueue(event))
  let snapshot = store.snapshot()
  assert_true(snapshot.deliveries.any(delivery => delivery.channel == Webhook))
  let claimed = store.claim_due_deliveries(1000L, 100L, 10)
  assert_eq(claimed.length(), 1)
  ignore(
    store.resolve_operator({
      notification_id: event.notification_id,
      expected_generation: 1L,
      actor_ref: "operator-a",
      now_unix_ms: 1050L,
    }),
  )
  let skipped = store.skip_delivery_if_ineligible(
    claimed[0].delivery_id,
    claimed[0].attempt_count,
    1060L,
  )
  assert_true(skipped is Some({ state: DeliverySkipped, .. }))
  let reopened = @store.NotificationStore::open(path)
  assert_true(
    reopened.snapshot().deliveries.any(delivery => {
      delivery.state == DeliverySkipped &&
      delivery.last_error_code == Some("NotificationResolved")
    }),
  )
  @fs.remove(path)
}

///|
async test "expired and silenced outbound work is never claimed" {
  let path = temp_path("expiry-silence-skip")
  let store = @store.NotificationStore::open(path)
  ignore(
    store.set_preference({
      preference_id: "pref-expiry",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      topic: LeaseLifecycle,
      channels: [InApp, Webhook],
      minimum_severity: Information,
      updated_unix_ms: 900L,
    }),
  )
  ignore(store.enqueue(lease_event("expired-outbound", "audit:expired")))
  assert_eq(store.claim_due_deliveries(10000L, 100L, 10).length(), 0)
  assert_true(
    store.snapshot().deliveries.any(delivery => {
      delivery.notification_id == "expired-outbound" &&
      delivery.channel == Webhook &&
      delivery.state == DeliverySkipped
    }),
  )
  @fs.remove(path)
}

///|
async test "dead-letter redrive is generation fenced audited and restart durable" {
  let path = temp_path("redrive")
  let store = @store.NotificationStore::open(path, maximum_delivery_attempts=1)
  ignore(
    store.set_preference({
      preference_id: "pref-redrive",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      topic: LeaseLifecycle,
      channels: [InApp, Email],
      minimum_severity: Information,
      updated_unix_ms: 900L,
    }),
  ) catch {
    error => fail("preference failed: \{Repr(error)}")
  }
  ignore(store.enqueue(lease_event("notice-redrive", "audit:redrive"))) catch {
    error => fail("enqueue failed: \{Repr(error)}")
  }
  let claimed = store.claim_due_deliveries(1000L, 100L, 10) catch {
    error => fail("claim failed: \{Repr(error)}")
  }
  let claimed = claimed[0]
  let dead = store.record_delivery_result({
    delivery_id: claimed.delivery_id,
    expected_attempt_count: claimed.attempt_count,
    delivered: false,
    retryable: false,
    provider_receipt: None,
    error_code: Some("ProviderRejected"),
    next_attempt_unix_ms: None,
    now_unix_ms: 1100L,
  }) catch {
    error => fail("dead-letter result failed: \{Repr(error)}")
  }
  let receipt = store.redrive_dead_letter({
    delivery_id: dead.delivery_id,
    expected_attempt_count: dead.attempt_count,
    expected_updated_unix_ms: dead.updated_unix_ms,
    actor_ref: "operator-a",
    now_unix_ms: 1200L,
  }) catch {
    error => fail("redrive failed: \{Repr(error)}")
  }
  assert_eq(receipt.previous_attempt_count, 1)
  try
    store.redrive_dead_letter({
      delivery_id: dead.delivery_id,
      expected_attempt_count: dead.attempt_count,
      expected_updated_unix_ms: dead.updated_unix_ms,
      actor_ref: "operator-a",
      now_unix_ms: 1300L,
    })
  catch {
    @notifications.NotificationError::InvalidTransition(_) => ()
    _ => fail("unexpected redrive failure")
  } noraise {
    _ => fail("stale redrive must fail")
  }
  let reopened = @store.NotificationStore::open(
    path,
    maximum_delivery_attempts=1,
  ) catch {
    error => fail("reopen failed: \{Repr(error)}")
  }
  assert_eq(reopened.snapshot().redrive_audit.length(), 1)
  assert_true(
    reopened.snapshot().deliveries.any(delivery => {
      delivery.delivery_id == dead.delivery_id &&
      delivery.state == PendingDelivery &&
      delivery.attempt_count == 0
    }),
  )
  @fs.remove(path)
}

///|
async test "active retention is hard bounded and newest active dedupe wins" {
  let path = temp_path("hard-cap")
  let store = @store.NotificationStore::open(path, history_limit=2)
  let first : @notifications.NotificationEvent = {
    ..lease_event("notice-old", "audit:old"),
    audience: PlatformOperators,
    code: "NodeUnreachable",
  }
  ignore(store.enqueue(first))
  ignore(
    store.resolve_operator({
      notification_id: first.notification_id,
      expected_generation: 1L,
      actor_ref: "operator-a",
      now_unix_ms: 1100L,
    }),
  )
  let recurrent = {
    ..first,
    notification_id: "notice-new",
    source_receipt: "audit:new",
    created_unix_ms: 1200L,
  }
  ignore(store.enqueue(recurrent))
  assert_eq(
    store
    .record_by_deduplication_key(first.deduplication_key, first.audience)
    .map(record => record.event.notification_id),
    Some("notice-new"),
  )
  ignore(
    store.enqueue({
      ..first,
      notification_id: "notice-other",
      deduplication_key: "other-key",
      source_receipt: "audit:other",
      created_unix_ms: 1300L,
    }),
  )
  try
    store.enqueue({
      ..first,
      notification_id: "notice-overflow",
      deduplication_key: "overflow-key",
      source_receipt: "audit:overflow",
      created_unix_ms: 1400L,
    })
  catch {
    @notifications.NotificationError::InvalidInput(_) => ()
    _ => fail("unexpected capacity failure")
  } noraise {
    _ => fail("active capacity must fail closed")
  }
  assert_eq(store.snapshot().records.length(), 2)
  @fs.remove(path)
}

///|
async test "worker readiness requires recent successful delivery and survives restart" {
  let path = temp_path("worker-health")
  let store = @store.NotificationStore::open(path)
  assert_eq(
    store.delivery_readiness(true, now_unix_ms=1000L).state,
    AdaptersPending,
  )
  ignore(store.record_worker_pass(1000L, 1, 1, 0, 0))
  assert_eq(
    store.delivery_readiness(true, now_unix_ms=1001L).state,
    DeliveryReady,
  )
  let reopened = @store.NotificationStore::open(path)
  assert_eq(
    reopened.delivery_readiness(true, now_unix_ms=1002L).state,
    DeliveryReady,
  )
  ignore(reopened.record_worker_failure(1100L, "WorkerPassFailed"))
  ignore(reopened.record_worker_pass(1101L, 0, 0, 0, 0))
  assert_eq(
    reopened.delivery_readiness(true, now_unix_ms=1102L).state,
    DeliveryDegraded,
  )
  let stale = @store.NotificationStore::open(path)
  assert_eq(
    stale.delivery_readiness(
      true,
      now_unix_ms=400000L,
      worker_freshness_ms=1000L,
    ).state,
    DeliveryDegraded,
  )
  @fs.remove(path)
}
