///|
fn event(
  id : String,
  timestamp : Int64,
  code? : String = "ApiRequestCompleted",
  status? : Int = 200,
) -> @observability.OperationalEvent {
  {
    version: @observability.contract_version,
    event_id: id,
    timestamp_unix_ms: timestamp,
    severity: Information,
    component: "controller",
    event_code: code,
    correlation_id: "request-test",
    actor_class: Customer,
    tenant_hash: None,
    target_type: "workload",
    outcome: if status >= 400 {
      "rejected"
    } else {
      "accepted"
    },
    status_code: status,
    duration_ms: 12L,
  }
}

///|
async test "operational events are bounded durable and aggregate low-cardinality counters" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-")
  let path = "\{directory}/events.json"
  let store = @observability.ObservabilityStore::open(
    path,
    event_history_limit=2,
  )
  store.record(event("event-1", 1L))
  store.record(event("event-2", 2L, code="ApiRequestRejected", status=429))
  store.record(event("event-3", 3L, code="ApiRequestRejected", status=429))
  let snapshot = store.snapshot()
  assert_eq(snapshot.events.length(), 2)
  assert_eq(snapshot.counters.length(), 2)
  let rejected = snapshot.counters.filter(counter => {
    counter.status_class == "4xx"
  })
  assert_eq(rejected.length(), 1)
  assert_eq(rejected[0].value, 2L)
  assert_eq(store.recent_count("ApiRequestRejected", "workload", 2L), 2)
  let reopened = @observability.ObservabilityStore::open(
    path,
    event_history_limit=2,
  )
  assert_eq(reopened.snapshot(), snapshot)
  assert_false(@fs.read_file(path).text().contains("Bearer"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "operational events reject high-cardinality or secret-shaped fields" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-invalid-")
  let store = @observability.ObservabilityStore::open(
    "\{directory}/events.json",
  )
  try
    store.record({
      ..event("event-invalid", 1L),
      target_type: "/v1/workloads/raw-id",
    })
  catch {
    @observability.ObservabilityError::InvalidEvent(_) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("unbounded target was accepted")
  }
  assert_eq(store.snapshot().events.length(), 0)
  @fs.rmdir(directory, recursive=true)
}
