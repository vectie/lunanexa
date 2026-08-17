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
  let buckets = store.latency_buckets()
  assert_eq(
    buckets.filter(bucket => {
      bucket.target_type == "workload" && bucket.upper_bound_ms == Some(50L)
    })[0].count,
    2L,
  )
  let readiness = store.readiness()
  assert_eq(readiness.event_history_count, 2)
  assert_eq(readiness.event_history_limit, 2)
  assert_eq(readiness.state, ObservabilityDegraded)
  let latency = store.latency_summaries()
  assert_eq(latency[0].count, 2L)
  assert_eq(latency[0].sum_ms, 24L)
  let prometheus = store.prometheus_latency_fragment()
  assert_false(
    prometheus.contains(
      "# TYPE lunanexa_operational_request_duration_ms histogram",
    ),
  )
  assert_true(prometheus.contains("recent_window_bucket gauge"))
  assert_true(prometheus.contains("le=\"+Inf\"} 2"))
  assert_true(prometheus.contains("_sum{target_type=\"workload\"} 24"))
  assert_true(prometheus.contains("_count{target_type=\"workload\"} 2"))
  let reopened = @observability.ObservabilityStore::open(
    path,
    event_history_limit=2,
  )
  assert_eq(reopened.snapshot(), snapshot)
  assert_false(@fs.read_file(path).text().contains("Bearer"))
  @fs.rmdir(directory, recursive=true)
}

///|
async test "external export readiness requires fresh durable proof" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-export-proof-")
  let path = "\{directory}/events.json"
  let store = @observability.ObservabilityStore::open(
    path,
    event_history_limit=2,
    emit_json_lines=true,
  )
  assert_eq(
    store.readiness(external_collector_configured=true, now_unix_ms=1000L).state,
    ExternalCollectorPending,
  )
  ignore(
    store.record_external_export_proof({
      proof_receipt: "collector-export-1",
      exported_unix_ms: 1000L,
    }),
  )
  let ready = store.readiness(
    external_collector_configured=true,
    now_unix_ms=1001L,
  )
  assert_eq(ready.state, LocalJsonReady)
  assert_true(ready.external_export_verified)
  for index in 0..<3 {
    ignore(
      store.record_generated({
        ..event("ignored-\{index}", 1001L + index.to_int64()),
        event_id: "event-pending",
      }),
    )
  }
  assert_false(
    store.snapshot().events.any(value => {
      value.event_code == "ExternalCollectorExportVerified"
    }),
  )
  assert_eq(
    store.readiness(external_collector_configured=true, now_unix_ms=1005L).state,
    LocalJsonReady,
  )
  let reopened = @observability.ObservabilityStore::open(
    path,
    event_history_limit=2,
    emit_json_lines=true,
  )
  assert_eq(
    reopened.readiness(external_collector_configured=true, now_unix_ms=1002L).state,
    LocalJsonReady,
  )
  assert_eq(
    reopened.readiness(
      external_collector_configured=true,
      now_unix_ms=400000L,
      external_export_freshness_ms=1000L,
    ).state,
    ExternalCollectorPending,
  )
  @fs.rmdir(directory, recursive=true)
}

///|
async test "event identifiers are idempotent but conflicting replay is rejected" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-replay-")
  let store = @observability.ObservabilityStore::open(
    "\{directory}/events.json",
  )
  store.record(event("event-replay", 1L))
  store.record(event("event-replay", 1L))
  try store.record({ ..event("event-replay", 1L), duration_ms: 13L }) catch {
    @observability.ObservabilityError::EventConflict("event-replay") => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("conflicting replay was accepted")
  }
  assert_eq(store.snapshot().events.length(), 1)
  assert_eq(store.snapshot().counters[0].value, 1L)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "generated event identities are monotonic under identical timestamps" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-generated-")
  let store = @observability.ObservabilityStore::open(
    "\{directory}/events.json",
  )
  let first = store.record_generated(event("ignored-a", 1000L))
  let second = store.record_generated(event("ignored-b", 1000L))
  assert_eq(first.event_id, "event-operational-1000-1")
  assert_eq(second.event_id, "event-operational-1000-2")
  assert_eq(store.snapshot().events.length(), 2)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "contract document reconciliation events are allowlisted" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-contract-document-")
  let store = @observability.ObservabilityStore::open(
    "\{directory}/events.json",
  )
  store.record_component_event(
    "event-contract-document-reconcile",
    1000L,
    Information,
    "controller",
    "ContractExpiryReconciliationCompleted",
    "contract-document-reconcile",
    "contract_document",
    "healthy",
    200,
    0L,
  )
  let snapshot = store.snapshot()
  assert_eq(snapshot.events.length(), 1)
  assert_eq(snapshot.events[0].target_type, "contract_document")
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
  for
    correlation in [
      "bearer-production-token", "raw-prompt-customer-text", "model-output-private",
      "private-key-material",
    ] {
    try
      store.record({
        ..event("event-\{correlation}", 2L),
        correlation_id: correlation,
      })
    catch {
      @observability.ObservabilityError::InvalidEvent(_) => ()
      error => fail("unexpected error: \{Repr(error)}")
    } noraise {
      _ => fail("secret-shaped correlation was accepted")
    }
  }
  assert_eq(store.snapshot().events.length(), 0)
  @fs.rmdir(directory, recursive=true)
}

///|
async fn expect_invalid_snapshot(
  snapshot : @observability.ObservabilitySnapshot,
  label : String,
) -> Unit {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-invalid-snapshot-")
  let path = "\{directory}/events.json"
  @fs.write_file(
    path,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  try @observability.ObservabilityStore::open(path) catch {
    @observability.ObservabilityError::InvalidSnapshot(_) => ()
    error => fail("\{label}: unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("\{label}: invalid snapshot was accepted")
  }
  @fs.rmdir(directory, recursive=true)
}

///|
async test "snapshot restore rejects unbounded cardinality overflow and inconsistent sequences" {
  let counters : Array[@observability.OperationalCounter] = []
  for index in 0..<=@observability.maximum_operational_counter_series {
    counters.push({
      event_code: "Series\{index}",
      target_type: "workload",
      outcome: "accepted",
      status_class: "2xx",
      value: 1L,
    })
  }
  expect_invalid_snapshot(
    {
      schema_version: @observability.snapshot_schema_version,
      events: [],
      counters,
      last_external_export_unix_ms: None,
    },
    "cardinality",
  )
  expect_invalid_snapshot(
    {
      schema_version: @observability.snapshot_schema_version,
      events: [],
      counters: [
        {
          event_code: "OverflowA",
          target_type: "workload",
          outcome: "accepted",
          status_class: "2xx",
          value: @int64.MAX_VALUE,
        },
        {
          event_code: "OverflowB",
          target_type: "workload",
          outcome: "accepted",
          status_class: "2xx",
          value: 1L,
        },
      ],
      last_external_export_unix_ms: None,
    },
    "overflow",
  )
  expect_invalid_snapshot(
    {
      schema_version: @observability.snapshot_schema_version,
      events: [event("event-duplicate", 1L), event("event-duplicate", 1L)],
      counters: [
        {
          event_code: "ApiRequestCompleted",
          target_type: "workload",
          outcome: "accepted",
          status_class: "2xx",
          value: 2L,
        },
      ],
      last_external_export_unix_ms: None,
    },
    "duplicate-event",
  )
  expect_invalid_snapshot(
    {
      schema_version: @observability.snapshot_schema_version,
      events: [event("event-operational-1-2", 1L)],
      counters: [
        {
          event_code: "ApiRequestCompleted",
          target_type: "workload",
          outcome: "accepted",
          status_class: "2xx",
          value: 1L,
        },
      ],
      last_external_export_unix_ms: None,
    },
    "generated-sequence",
  )
  expect_invalid_snapshot(
    {
      schema_version: @observability.snapshot_schema_version,
      events: [event("event-operational-malformed", 1L)],
      counters: [
        {
          event_code: "ApiRequestCompleted",
          target_type: "workload",
          outcome: "accepted",
          status_class: "2xx",
          value: 1L,
        },
      ],
      last_external_export_unix_ms: None,
    },
    "malformed-generated-sequence",
  )
  expect_invalid_snapshot(
    {
      schema_version: @observability.snapshot_schema_version,
      events: [event("event-no-counter", 1L)],
      counters: [],
      last_external_export_unix_ms: None,
    },
    "missing-counter",
  )
}

///|
async test "new metric series fail atomically at the cardinality bound" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-cardinality-")
  let path = "\{directory}/events.json"
  let counters : Array[@observability.OperationalCounter] = []
  for index in 0..<@observability.maximum_operational_counter_series {
    counters.push({
      event_code: "Series\{index}",
      target_type: "workload",
      outcome: "accepted",
      status_class: "2xx",
      value: 1L,
    })
  }
  @fs.write_file(
    path,
    @observability.ObservabilitySnapshot::{
      schema_version: @observability.snapshot_schema_version,
      events: [],
      counters,
      last_external_export_unix_ms: None,
    }
    .to_json()
    .stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let store = @observability.ObservabilityStore::open(path)
  try store.record(event("event-new-series", 1L)) catch {
    @observability.ObservabilityError::InvalidEvent(_) => ()
    error => fail("unexpected cardinality error: \{Repr(error)}")
  } noraise {
    _ => fail("new counter series exceeded the cardinality bound")
  }
  assert_eq(
    store.snapshot().counters.length(),
    @observability.maximum_operational_counter_series,
  )
  try store.record(event("event-operational-1-1", 1L)) catch {
    @observability.ObservabilityError::InvalidEvent(_) => ()
    error => fail("unexpected reserved identifier error: \{Repr(error)}")
  } noraise {
    _ => fail("reserved generated identifier was accepted")
  }
  assert_eq(store.snapshot().events.length(), 0)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "counter and generated sequence overflow fail atomically" {
  let directory = @fs.tmpdir(prefix="lunanexa-observability-overflow-")
  let path = "\{directory}/events.json"
  let snapshot : @observability.ObservabilitySnapshot = {
    schema_version: @observability.snapshot_schema_version,
    events: [],
    counters: [
      {
        event_code: "ApiRequestCompleted",
        target_type: "workload",
        outcome: "accepted",
        status_class: "2xx",
        value: @int64.MAX_VALUE - 1L,
      },
    ],
    last_external_export_unix_ms: None,
  }
  @fs.write_file(
    path,
    snapshot.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  let store = @observability.ObservabilityStore::open(path)
  store.record(event("event-at-limit", 1L))
  try store.record(event("event-overflow", 2L)) catch {
    @observability.ObservabilityError::InvalidEvent(_) => ()
    error => fail("unexpected counter error: \{Repr(error)}")
  } noraise {
    _ => fail("overflowing counter update was accepted")
  }
  try store.record_generated(event("ignored", 3L)) catch {
    @observability.ObservabilityError::InvalidEvent(_) => ()
    error => fail("unexpected sequence error: \{Repr(error)}")
  } noraise {
    _ => fail("overflowing generated sequence was accepted")
  }
  let after = store.snapshot()
  assert_eq(after.events.length(), 1)
  assert_eq(after.events[0].event_id, "event-at-limit")
  assert_eq(after.counters[0].value, @int64.MAX_VALUE)
  let reopened = @observability.ObservabilityStore::open(path)
  assert_eq(reopened.snapshot(), after)
  @fs.rmdir(directory, recursive=true)
}

///|
test "production reconciliation event vocabulary remains bounded" {
  for
    value in [
      (
        "event-artifact-verification-health-1000", "ArtifactVerificationHealthReconciled",
        "artifact",
      ),
      (
        "event-commercial-reconciliation-health-1000", "CommercialReconciliationHealthReconciled",
        "commercial",
      ),
      (
        "event-offline-commerce-reconcile-1000", "OfflineCommerceReconciliationCompleted",
        "commercial",
      ),
    ] {
    @observability.validate_event({
      version: @observability.contract_version,
      event_id: value.0,
      timestamp_unix_ms: 1000L,
      severity: Information,
      component: "controller",
      event_code: value.1,
      correlation_id: "production-health-1000",
      actor_class: Controller,
      tenant_hash: None,
      target_type: value.2,
      outcome: "healthy",
      status_code: 200,
      duration_ms: 0L,
    })
  }
}

///|
async test "observability snapshot and counters restart through PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  database.save_opaque_snapshot(
    "observability",
    @observability.snapshot_schema_version,
    @observability.ObservabilitySnapshot::{
      schema_version: @observability.snapshot_schema_version,
      events: [],
      counters: [],
      last_external_export_unix_ms: None,
    }
    .to_json()
    .stringify(),
  )
  let store = @observability.ObservabilityStore::open_postgres(database)
  let now = @async.now()
  let id = "postgres-event-\{now}"
  store.record(event(id, now))
  let reopened = @observability.ObservabilityStore::open_postgres(database)
  assert_true(reopened.snapshot().events.any(value => value.event_id == id))
  assert_true(
    reopened.snapshot().counters.any(counter => {
      counter.event_code == "ApiRequestCompleted" && counter.value >= 1L
    }),
  )
  database.close()
}
