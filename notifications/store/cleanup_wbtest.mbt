///|
fn cleanup_event(id : String) -> @notifications.NotificationEvent {
  {
    version: @notifications.contract_version,
    notification_id: id,
    deduplication_key: "dedup-\{id}",
    source_receipt: "source-\{id}",
    topic: ClusterHealth,
    code: "NodeUnavailable",
    severity: Warning,
    audience: PlatformOperators,
    title_key: "notifications.node.title",
    body_key: "notifications.node.body",
    parameters: {},
    created_unix_ms: 1000L,
    expires_unix_ms: None,
  }
}

///|
fn cleanup_store() -> NotificationStore raise {
  // An ordinary file open below a character device deterministically fails;
  // no production path, external service, or timing-sensitive disk fill.
  let store = NotificationStore::empty(
    NotificationFile("/dev/null/notification.json"),
    100,
    3,
  )
  for id in ["active", "silenced"] {
    store.records[id] = {
      event: cleanup_event(id),
      lifecycle: Unread,
      generation: 1L,
      assigned_to: None,
      acknowledged_by: None,
      acknowledged_unix_ms: None,
      silenced_until_unix_ms: if id == "silenced" {
        Some(1500L)
      } else {
        None
      },
      resolved_by: None,
      resolved_unix_ms: None,
      updated_unix_ms: 1000L,
    }
  }
  for
    entry in [
      ("delivery-active", "active", @notifications.DeliveryState::Delivering),
      ("delivery-silenced", "silenced", Delivering),
      ("delivery-dead", "active", DeadLetter),
      ("delivery-pending", "active", PendingDelivery),
    ] {
    let (id, notice, state) = entry
    store.deliveries[id] = {
      delivery_id: id,
      notification_id: notice,
      channel: Email,
      state,
      attempt_count: 1,
      next_attempt_unix_ms: Some(1100L),
      provider_receipt: None,
      last_error_code: None,
      updated_unix_ms: 1000L,
    }
  }
  store
}

///|
async test "all ten notification mutations roll back and release after persistence failure" {
  let store = cleanup_store()
  let before = store.snapshot()
  let operations : Array[async () -> Unit] = [
    () => ignore(store.enqueue(cleanup_event("new"))),
    () => {
      ignore(
        store.set_preference({
          preference_id: "preference-new",
          tenant_ref: "tenant-new",
          subject_ref: "subject-new",
          topic: ClusterHealth,
          channels: [InApp, Email],
          minimum_severity: Information,
          updated_unix_ms: 1100L,
        }),
      )
    },
    () => ignore(store.expire_silences(1600L)),
    () => ignore(store.record_worker_pass(1100L, 1, 1, 0, 0)),
    () => ignore(store.record_worker_failure(1100L, "AdapterFailed")),
    () => {
      ignore(
        store.acknowledge_operator({
          notification_id: "active",
          expected_generation: 1L,
          actor_ref: "operator-new",
          now_unix_ms: 1100L,
        }),
      )
    },
    () => {
      ignore(store.skip_delivery_if_ineligible("delivery-silenced", 1, 1100L))
    },
    () => {
      ignore(
        store.redrive_dead_letter({
          delivery_id: "delivery-dead",
          expected_attempt_count: 1,
          expected_updated_unix_ms: 1000L,
          actor_ref: "operator-new",
          now_unix_ms: 1100L,
        }),
      )
    },
    () => ignore(store.claim_due_deliveries(1100L, 100L, 10)),
    () => {
      ignore(
        store.record_delivery_result({
          delivery_id: "delivery-active",
          expected_attempt_count: 1,
          delivered: true,
          retryable: false,
          provider_receipt: Some("provider-receipt"),
          error_code: None,
          next_attempt_unix_ms: None,
          now_unix_ms: 1100L,
        }),
      )
    },
  ]
  for index, operation in operations {
    // A second failure exposes a leaked lock that the first call alone misses.
    for _ in 0..<2 {
      try operation() catch {
        error =>
          if !"\{Repr(error)}".contains("async/os_error.OSError") {
            fail("Operation \{index} did not reach persistence: \{Repr(error)}")
          }
      } noraise {
        _ => fail("persistence unexpectedly succeeded")
      }
      assert_true(store.mutex.try_acquire())
      store.mutex.release()
      assert_eq(store.snapshot(), before)
    }
  }
  // These early-return paths must neither persist nor release the lock twice.
  assert_eq(store.enqueue(cleanup_event("active")), before.records[0])
  assert_eq(store.skip_delivery_if_ineligible("missing", 1, 1100L), None)
  assert_eq(
    store.skip_delivery_if_ineligible("delivery-active", 1, 1100L),
    None,
  )
  assert_eq(store.snapshot(), before)
}

///|
async test "cancelling a notification lock waiter preserves the owner and state" {
  let store = cleanup_store()
  let before = store.snapshot()
  store.mutex.acquire()
  let cancelled = @async.with_timeout_opt(10, () => {
    store.record_worker_pass(1100L, 1, 1, 0, 0)
  })
  assert_eq(cancelled, None)
  assert_false(store.mutex.try_acquire())
  store.mutex.release()
  assert_true(store.mutex.try_acquire())
  store.mutex.release()
  assert_eq(store.snapshot(), before)
  assert_eq(store.enqueue(cleanup_event("active")), before.records[0])
}
