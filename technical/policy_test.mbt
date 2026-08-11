///|
fn autoscale_policy() -> @technical.AutoscalePolicy {
  {
    policy_version: "autoscale-v1",
    min_replicas: 1,
    max_replicas: 4,
    scale_up_step: 2,
    scale_down_step: 1,
    sample_window_ms: 60000L,
    cooldown_ms: 30000L,
    target_p95_latency_ms: 500L,
    target_queue_depth: 4,
    required_lease_generation: 7L,
  }
}

///|
fn autoscale_snapshot() -> @technical.AutoscaleSnapshot {
  {
    deployment_id: "deployment-1",
    desired_replicas: 1,
    ready_replicas: 1,
    available_replica_capacity: 3,
    p95_latency_ms: 600L,
    queue_depth: 0,
    oldest_sample_unix_ms: 100000L,
    newest_sample_unix_ms: 160000L,
    last_scale_unix_ms: None,
    observed_lease_generation: 7L,
    lease_expires_unix_ms: 300000L,
    now_unix_ms: 160000L,
  }
}

///|
test "autoscaling is bounded by capacity window cooldown and lease fence" {
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), autoscale_snapshot()),
    ScaleUp(target_replicas=3, reason=LatencyPressure),
  )
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), {
      ..autoscale_snapshot(),
      available_replica_capacity: 1,
    }),
    ScaleUp(target_replicas=2, reason=LatencyPressure),
  )
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), {
      ..autoscale_snapshot(),
      observed_lease_generation: 6L,
    }),
    Hold(reason=LeaseFenceMismatch),
  )
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), {
      ..autoscale_snapshot(),
      last_scale_unix_ms: Some(150000L),
    }),
    Hold(reason=CooldownActive),
  )
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), {
      ..autoscale_snapshot(),
      newest_sample_unix_ms: 120000L,
    }),
    Hold(reason=InsufficientWindow),
  )
}

///|
test "scale down waits for readiness and never crosses minimum" {
  let quiet = {
    ..autoscale_snapshot(),
    desired_replicas: 3,
    ready_replicas: 3,
    p95_latency_ms: 100L,
  }
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), quiet),
    ScaleDown(target_replicas=2, reason=SustainedLowUtilization),
  )
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), {
      ..quiet,
      ready_replicas: 2,
    }),
    Hold(reason=Stabilizing),
  )
  assert_eq(
    @technical.decide_autoscale(autoscale_policy(), {
      ..quiet,
      desired_replicas: 1,
      ready_replicas: 1,
    }),
    Hold(reason=AtReplicaBound),
  )
}

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
