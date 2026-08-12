///|
fn policy() -> @guide_monitor.GuideMonitorPolicy {
  {
    target_ref: "coursebook-primary",
    probe_interval_ms: 60000L,
    observation_max_age_ms: 120000L,
    future_skew_ms: 5000L,
    knowledge_max_age_ms: 604800000L,
  }
}

///|
fn observation(
  id : String,
  observed_unix_ms : Int64,
  coursebook_ok? : Bool = true,
  admin_diagnostics_enabled? : Bool = true,
  admin_diagnostics_ok? : Bool = true,
  knowledge_stale? : Bool = false,
  knowledge_age_ms? : Int64 = 1000L,
) -> @guide_monitor.GuideHealthObservation {
  @guide_monitor.sign_observation(
    {
      version: @guide_monitor.contract_version,
      observation_id: id,
      target_ref: "coursebook-primary",
      correlation_receipt: "support-\{id}",
      scheduled_unix_ms: observed_unix_ms - 1000L,
      observed_unix_ms,
      coursebook_ok,
      admin_diagnostics_enabled,
      admin_diagnostics_ok,
      knowledge_revision: "revision-2026-08-12",
      knowledge_stale,
      knowledge_age_ms,
      signature: "",
    },
    "guide-monitor-test-secret-at-least-32-bytes",
  )
}

///|
test "scheduled probe plan exposes only the two fixed read routes" {
  assert_false(@guide_monitor.probe_due(policy(), Some(95000L), 100000L))
  assert_true(@guide_monitor.probe_due(policy(), Some(40000L), 100000L))
  let plan = @guide_monitor.scheduled_probe_plan(policy(), 7L, 100000L)
  assert_eq(plan.target_ref, "coursebook-primary")
  assert_eq(plan.health_path, "/health")
  assert_eq(
    plan.diagnostics_path,
    "/api/coursebook/admin/diagnostics?category=overview",
  )
  assert_eq(plan.correlation_receipt, "guide-probe-7-100000")
}

///|
test "signed observations reject mutation, wrong target, and stale replay" {
  let signed = observation("observation-1", 100000L)
  @guide_monitor.verify_observation(
    policy(),
    signed,
    "guide-monitor-test-secret-at-least-32-bytes",
    100100L,
  )
  let forged = { ..signed, knowledge_stale: true }
  try {
    @guide_monitor.verify_observation(
      policy(),
      forged,
      "guide-monitor-test-secret-at-least-32-bytes",
      100100L,
    )
    fail("mutated observation was accepted")
  } catch {
    @guide_monitor.GuideMonitorError::InvalidSignature => ()
    _ => fail("unexpected forged observation error")
  }
  let plan = @guide_monitor.scheduled_probe_plan(policy(), 2L, 99000L)
  try {
    @guide_monitor.verify_planned_observation(
      policy(),
      plan,
      signed,
      "guide-monitor-test-secret-at-least-32-bytes",
      100100L,
    )
    fail("observation bound to another scheduled plan was accepted")
  } catch {
    @guide_monitor.GuideMonitorError::InvalidObservation(_) => ()
    _ => fail("unexpected plan-binding error")
  }
  try {
    @guide_monitor.verify_observation(
      policy(),
      signed,
      "guide-monitor-test-secret-at-least-32-bytes",
      300001L,
    )
    fail("stale observation was accepted")
  } catch {
    @guide_monitor.GuideMonitorError::StaleObservation => ()
    _ => fail("unexpected stale observation error")
  }
}

///|
async test "unavailable and stale guide state raises durable runbook-linked operator alerts" {
  let directory = @fs.tmpdir(prefix="lunanexa-guide-monitor-alert-")
  let path = "\{directory}/notifications.json"
  let store = @store.NotificationStore::open(path)
  let result = @guide_monitor.reconcile_observation(
    store,
    policy(),
    observation(
      "observation-failed",
      100000L,
      admin_diagnostics_ok=false,
      knowledge_stale=true,
      knowledge_age_ms=700000000L,
    ),
    "guide-monitor-test-secret-at-least-32-bytes",
    100100L,
  )
  assert_true(result.adapter_alert_active)
  assert_true(result.knowledge_alert_active)
  let records = store.records_for_operators(100100L)
  assert_eq(records.length(), 2)
  let mut adapter : @notifications.NotificationRecord? = None
  let mut knowledge : @notifications.NotificationRecord? = None
  for record in records {
    if record.event.code == "GuideAdapterUnavailable" {
      adapter = Some(record)
    } else if record.event.code == "KnowledgeRevisionStale" {
      knowledge = Some(record)
    }
  }
  let adapter = adapter.unwrap()
  assert_eq(adapter.event.topic, GuideDiagnostics)
  assert_eq(adapter.event.severity, Critical)
  assert_eq(adapter.event.parameters["runbook_page_id"], "debug-controller")
  let knowledge = knowledge.unwrap()
  assert_eq(knowledge.event.severity, Warning)
  assert_eq(knowledge.event.parameters["runbook_page_id"], "source-ledger")
  let reopened = @store.NotificationStore::open(path)
  assert_eq(reopened.records_for_operators(100200L).length(), 2)
  @fs.rmdir(directory, recursive=true)
}

///|
async test "healthy signed observation resolves both alerts idempotently" {
  let directory = @fs.tmpdir(prefix="lunanexa-guide-monitor-recover-")
  let store = @store.NotificationStore::open("\{directory}/notifications.json")
  ignore(
    @guide_monitor.reconcile_observation(
      store,
      policy(),
      observation(
        "observation-failed",
        100000L,
        coursebook_ok=false,
        knowledge_stale=true,
      ),
      "guide-monitor-test-secret-at-least-32-bytes",
      100100L,
    ),
  )
  let recovered = @guide_monitor.reconcile_observation(
    store,
    policy(),
    observation("observation-healthy", 101000L),
    "guide-monitor-test-secret-at-least-32-bytes",
    101100L,
  )
  assert_false(recovered.adapter_alert_active)
  assert_false(recovered.knowledge_alert_active)
  assert_true(recovered.adapter_record.unwrap().lifecycle == Resolved)
  assert_true(recovered.knowledge_record.unwrap().lifecycle == Resolved)
  let repeated = @guide_monitor.reconcile_observation(
    store,
    policy(),
    observation("observation-healthy-2", 102000L),
    "guide-monitor-test-secret-at-least-32-bytes",
    102100L,
  )
  assert_false(repeated.adapter_alert_active)
  assert_eq(store.snapshot().records.length(), 2)
  let reopened = @store.NotificationStore::open(
    "\{directory}/notifications.json",
  )
  assert_true(
    reopened.snapshot().records.all(record => record.lifecycle == Resolved),
  )
  @fs.rmdir(directory, recursive=true)
}
