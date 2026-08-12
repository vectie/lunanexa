///|
fn admission_limits() -> @technical.AdmissionLimits {
  {
    max_running: 2,
    max_queued: 3,
    max_tenant_running: 1,
    max_tenant_queued: 1,
    max_payload_bytes: 4096L,
  }
}

///|
fn admission_snapshot() -> @technical.AdmissionSnapshot {
  {
    running: 0,
    queued: 0,
    tenant_running: 0,
    tenant_queued: 0,
    payload_bytes: 1024L,
    deadline_unix_ms: 2000L,
    now_unix_ms: 1000L,
    lease_valid: true,
  }
}

///|
test "bounded admission starts queues and rejects deterministically" {
  assert_eq(
    @technical.decide_admission(admission_limits(), admission_snapshot()),
    StartImmediately,
  )
  assert_eq(
    @technical.decide_admission(admission_limits(), {
      ..admission_snapshot(),
      running: 1,
      tenant_running: 1,
    }),
    Queue(position=1),
  )
  assert_eq(
    @technical.decide_admission(admission_limits(), {
      ..admission_snapshot(),
      running: 2,
      queued: 3,
      tenant_running: 1,
      tenant_queued: 1,
    }),
    Reject(reason=TenantRunningLimit, retryable=true),
  )
  assert_eq(
    @technical.decide_admission(admission_limits(), {
      ..admission_snapshot(),
      payload_bytes: 4097L,
    }),
    Reject(reason=PayloadTooLarge, retryable=false),
  )
}
