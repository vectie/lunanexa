///|
fn test_event() -> @notifications.NotificationEvent {
  {
    version: @notifications.contract_version,
    notification_id: "notice-worker",
    deduplication_key: "lease-worker-ready",
    source_receipt: "audit:lease-worker:ready",
    topic: LeaseLifecycle,
    code: "LeaseAccessReady",
    severity: Information,
    audience: Subject(tenant_ref="tenant-a", subject_ref="subject-a"),
    title_key: "notifications.lease_ready.title",
    body_key: "notifications.lease_ready.body",
    parameters: { "lease_ref": "lease-worker" },
    created_unix_ms: 1000L,
    expires_unix_ms: None,
  }
}

///|
async test "adapters-pending worker leaves outbound queue unclaimed" {
  let directory = @fs.tmpdir(prefix="lunanexa-delivery-pending-")
  let store = @store.NotificationStore::open("\{directory}/notifications.json")
  let operational = @observability.ObservabilityStore::open(
    "\{directory}/operational.json",
  )
  ignore(
    store.set_preference({
      preference_id: "preference-worker",
      tenant_ref: "tenant-a",
      subject_ref: "subject-a",
      topic: LeaseLifecycle,
      channels: [InApp, Email],
      minimum_severity: Information,
      updated_unix_ms: 900L,
    }),
  )
  ignore(store.enqueue(test_event()))
  let worker = @worker.NotificationDeliveryWorker::adapters_pending(store).with_observability_store(
    operational,
  )
  let result = worker.run_once(1000L)
  assert_eq(result.attempted, 0)
  assert_eq(result.readiness.state, AdaptersPending)
  assert_eq(result.readiness.pending_count, 1)
  let snapshot = store.snapshot()
  assert_eq(
    snapshot.deliveries.count_if(value => value.state == PendingDelivery),
    1,
  )
  let events = operational.snapshot().events
  assert_eq(events.length(), 1)
  assert_eq(events[0].event_code, "NotificationDeliveryBatchCompleted")
  assert_eq(events[0].target_type, "notification_delivery")
  assert_eq(events[0].outcome, "idle")
  @fs.rmdir(directory, recursive=true)
}

///|
async test "delivery worker rejects unsafe or weak adapter configuration" {
  let directory = @fs.tmpdir(prefix="lunanexa-delivery-config-")
  let store = @store.NotificationStore::open("\{directory}/notifications.json")
  for
    endpoint in [
      "http://adapter.internal/v1/deliver", "https://user@example.test/v1/deliver",
      "https://example.test/v1/deliver#fragment", "https://example..test/v1/deliver",
      "https://-example.test/v1/deliver", "https://example-.test/v1/deliver", "https://example.test/v1/deliver?redirect=evil",
      "http://localhost.evil:8080/v1/deliver", "http://127.0.0.1:70000/v1/deliver",
    ] {
    try
      @worker.NotificationDeliveryWorker::configured(
        store, endpoint, "01234567890123456789012345678901",
      )
    catch {
      InvalidConfiguration(_) => ()
    } noraise {
      _ => fail("unsafe endpoint was accepted")
    }
  }
  try
    @worker.NotificationDeliveryWorker::configured(
      store, "https://adapter.example.test/v1/deliver", "weak-token",
    )
  catch {
    InvalidConfiguration(_) => ()
  } noraise {
    _ => fail("weak adapter token was accepted")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
priv enum AdapterTestMode {
  Success
  Redirect
  Oversize
  Slow
}

///|
async fn exercise_adapter(
  mode : AdapterTestMode,
) -> (@notifications.NotificationDeliveryRunSummary, Bool) {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let authority_ok = [false]
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(allow_failure=true) <| ((request, _, connection) => {
        let authorization = request.headers
          .iter()
          .find_first(item => item.0.to_lower() == "authorization")
          .map(item => item.1)
        let idempotency_key = request.headers
          .iter()
          .find_first(item => item.0.to_lower() == "idempotency-key")
          .map(item => item.1)
        authority_ok[0] = authorization ==
          Some("Bearer 01234567890123456789012345678901") &&
          idempotency_key == Some("delivery-notice-worker-email")
        match mode {
          Success => {
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            connection.write_string(
              "{\"provider_receipt\":\"provider-receipt-1\"}",
            )
          }
          Redirect => {
            connection.send_response(302, "Found", extra_headers={
              "Location": "http://127.0.0.1:1/private",
              "Content-Type": "application/json",
            })
            connection.write_string("{\"provider_receipt\":\"forged\"}")
          }
          Oversize => {
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            for _ in 0..<5000 {
              connection.write_string("x")
            }
          }
          Slow => {
            connection.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            @async.sleep(500)
            connection.write_string("{\"provider_receipt\":\"too-late\"}")
          }
        }
        connection.end_response()
      })
    }
    let directory = @fs.tmpdir(prefix="lunanexa-delivery-http-")
    let store = @store.NotificationStore::open(
      "\{directory}/notifications.json",
    )
    ignore(
      store.set_preference({
        preference_id: "preference-worker-http",
        tenant_ref: "tenant-a",
        subject_ref: "subject-a",
        topic: LeaseLifecycle,
        channels: [InApp, Email],
        minimum_severity: Information,
        updated_unix_ms: 900L,
      }),
    )
    ignore(store.enqueue(test_event()))
    let worker = NotificationDeliveryWorker::configured(
      store,
      "http://\{server.addr}/v1/deliver",
      "01234567890123456789012345678901",
      request_timeout_ms=250,
      claim_lease_ms=1000L,
    )
    let result = worker.run_once(1000L)
    @fs.rmdir(directory, recursive=true)
    (result, authority_ok[0])
  }
}

///|
async test "real adapter delivery is bounded authenticated and fail-closed" {
  let (success, success_authority) = exercise_adapter(Success)
  assert_true(success_authority)
  assert_eq(success.delivered, 1)
  assert_eq(success.dead_lettered, 0)
  let (redirect, redirect_authority) = exercise_adapter(Redirect)
  assert_true(redirect_authority)
  assert_eq(redirect.dead_lettered, 1)
  let (oversize, oversize_authority) = exercise_adapter(Oversize)
  assert_true(oversize_authority)
  assert_eq(oversize.dead_lettered, 1)
  let (slow, slow_authority) = exercise_adapter(Slow)
  assert_true(slow_authority)
  assert_eq(slow.retry_scheduled, 1)
}
