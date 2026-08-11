///|
pub(all) struct AutoscalePolicy {
  policy_version : String
  min_replicas : Int
  max_replicas : Int
  scale_up_step : Int
  scale_down_step : Int
  sample_window_ms : Int64
  cooldown_ms : Int64
  target_p95_latency_ms : Int64
  target_queue_depth : Int
  required_lease_generation : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AutoscaleSnapshot {
  deployment_id : String
  desired_replicas : Int
  ready_replicas : Int
  available_replica_capacity : Int
  p95_latency_ms : Int64
  queue_depth : Int
  oldest_sample_unix_ms : Int64
  newest_sample_unix_ms : Int64
  last_scale_unix_ms : Int64?
  observed_lease_generation : Int64
  lease_expires_unix_ms : Int64
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AutoscaleReason {
  InvalidPolicy
  InvalidSnapshot
  LeaseFenceMismatch
  LeaseExpired
  InsufficientWindow
  CooldownActive
  Stabilizing
  AtReplicaBound
  NoAvailableCapacity
  MetricsWithinTarget
  LatencyPressure
  QueuePressure
  SustainedLowUtilization
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AutoscaleDecision {
  Hold(reason~ : AutoscaleReason)
  ScaleUp(target_replicas~ : Int, reason~ : AutoscaleReason)
  ScaleDown(target_replicas~ : Int, reason~ : AutoscaleReason)
} derive(Debug, Eq, ToJson, FromJson)

///|
fn valid_autoscale_policy(policy : AutoscalePolicy) -> Bool {
  !policy.policy_version.is_empty() &&
  policy.min_replicas >= 0 &&
  policy.max_replicas >= policy.min_replicas &&
  policy.max_replicas <= 1024 &&
  policy.scale_up_step > 0 &&
  policy.scale_down_step > 0 &&
  policy.sample_window_ms > 0L &&
  policy.cooldown_ms >= 0L &&
  policy.target_p95_latency_ms > 0L &&
  policy.target_queue_depth >= 0 &&
  policy.required_lease_generation > 0L
}

///|
pub fn decide_autoscale(
  policy : AutoscalePolicy,
  snapshot : AutoscaleSnapshot,
) -> AutoscaleDecision {
  if !valid_autoscale_policy(policy) {
    return Hold(reason=InvalidPolicy)
  }
  if snapshot.deployment_id.is_empty() ||
    snapshot.desired_replicas < policy.min_replicas ||
    snapshot.desired_replicas > policy.max_replicas ||
    snapshot.ready_replicas < 0 ||
    snapshot.ready_replicas > snapshot.desired_replicas ||
    snapshot.available_replica_capacity < 0 ||
    snapshot.p95_latency_ms < 0L ||
    snapshot.queue_depth < 0 ||
    snapshot.oldest_sample_unix_ms < 0L ||
    snapshot.newest_sample_unix_ms < snapshot.oldest_sample_unix_ms ||
    snapshot.newest_sample_unix_ms > snapshot.now_unix_ms {
    return Hold(reason=InvalidSnapshot)
  }
  if snapshot.observed_lease_generation != policy.required_lease_generation {
    return Hold(reason=LeaseFenceMismatch)
  }
  if snapshot.now_unix_ms >= snapshot.lease_expires_unix_ms {
    return Hold(reason=LeaseExpired)
  }
  if snapshot.newest_sample_unix_ms - snapshot.oldest_sample_unix_ms <
    policy.sample_window_ms {
    return Hold(reason=InsufficientWindow)
  }
  match snapshot.last_scale_unix_ms {
    Some(last) if last > snapshot.now_unix_ms =>
      return Hold(reason=InvalidSnapshot)
    Some(last) if snapshot.now_unix_ms - last < policy.cooldown_ms =>
      return Hold(reason=CooldownActive)
    _ => ()
  }
  let latency_pressure = snapshot.p95_latency_ms > policy.target_p95_latency_ms
  let queue_pressure = snapshot.queue_depth > policy.target_queue_depth
  if latency_pressure || queue_pressure {
    if snapshot.desired_replicas >= policy.max_replicas {
      return Hold(reason=AtReplicaBound)
    }
    if snapshot.available_replica_capacity == 0 {
      return Hold(reason=NoAvailableCapacity)
    }
    let increment = policy.scale_up_step.min(
      snapshot.available_replica_capacity,
    )
    let target = (snapshot.desired_replicas + increment).min(
      policy.max_replicas,
    )
    return ScaleUp(
      target_replicas=target,
      reason=if queue_pressure { QueuePressure } else { LatencyPressure },
    )
  }
  if snapshot.ready_replicas < snapshot.desired_replicas {
    return Hold(reason=Stabilizing)
  }
  if snapshot.queue_depth == 0 &&
    snapshot.p95_latency_ms <= policy.target_p95_latency_ms / 2L {
    if snapshot.desired_replicas <= policy.min_replicas {
      return Hold(reason=AtReplicaBound)
    }
    return ScaleDown(
      target_replicas=(snapshot.desired_replicas - policy.scale_down_step).max(
        policy.min_replicas,
      ),
      reason=SustainedLowUtilization,
    )
  }
  Hold(reason=MetricsWithinTarget)
}
