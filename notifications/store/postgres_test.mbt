///|
async test "notification snapshot persists lifecycle and delivery through PostgreSQL" {
  guard @env.get_env_var("LUNANEXA_TEST_DATABASE_URL") is Some(url) else {
    return
  }
  let database = @database.PostgresDatabase::open(url)
  let unique = @async.now()
  // Isolate this test from any snapshot written by another package in the same
  // integration database.
  database.save_opaque_snapshot(
    "notifications",
    @notifications.snapshot_schema_version,
    @notifications.NotificationSnapshot::{
      schema_version: @notifications.snapshot_schema_version,
      records: [],
      deliveries: [],
      preferences: [],
      worker_health: {
        generation: 0L,
        last_heartbeat_unix_ms: None,
        last_attempt_unix_ms: None,
        last_success_unix_ms: None,
        last_failure_unix_ms: None,
        consecutive_failures: 0,
        last_error_code: None,
      },
      redrive_audit: [],
    }
    .to_json()
    .stringify(),
  )
  let store = @store.NotificationStore::open_postgres(database)
  let now = unique
  let event : @notifications.NotificationEvent = {
    version: @notifications.contract_version,
    notification_id: "postgres-notice-\{now}",
    deduplication_key: "postgres-lease-\{now}",
    source_receipt: "postgres-test:\{now}",
    topic: LeaseLifecycle,
    code: "LeaseExpiring",
    severity: Warning,
    audience: Subject(
      tenant_ref="tenant-postgres",
      subject_ref="subject-postgres",
    ),
    title_key: "notifications.lease_expiring.title",
    body_key: "notifications.lease_expiring.body",
    parameters: { "lease_ref": "lease-postgres" },
    created_unix_ms: now,
    expires_unix_ms: None,
  }
  ignore(store.enqueue(event))
  ignore(
    store.mark_read_for_subject("tenant-postgres", "subject-postgres", {
      notification_id: event.notification_id,
      expected_generation: 1L,
      actor_ref: "subject-postgres",
      now_unix_ms: now + 1L,
    }),
  )
  let reopened = @store.NotificationStore::open_postgres(database)
  let restored = reopened.records_for_subject(
    "tenant-postgres",
    "subject-postgres",
    now + 2L,
  )
  assert_eq(restored.length(), 1)
  assert_eq(restored[0].lifecycle, Read)
  assert_eq(reopened.snapshot().deliveries.length(), 1)
  database.close()
}
