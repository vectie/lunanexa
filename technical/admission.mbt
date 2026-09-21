///|
pub(all) struct AdmissionLimits {
  max_running : Int
  max_queued : Int
  max_tenant_running : Int
  max_tenant_queued : Int
  max_payload_bytes : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AdmissionSnapshot {
  running : Int
  queued : Int
  tenant_running : Int
  tenant_queued : Int
  payload_bytes : Int64
  deadline_unix_ms : Int64
  now_unix_ms : Int64
  lease_valid : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AdmissionRejection {
  InvalidLimits
  InvalidSnapshot
  LeaseUnavailable
  DeadlineExpired
  PayloadTooLarge
  TenantRunningLimit
  TenantQueueLimit
  RunningCapacity
  QueueCapacity
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BackpressureDecision {
  StartImmediately
  Queue(position~ : Int)
  Reject(reason~ : AdmissionRejection, retryable~ : Bool)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn decide_admission(
  limits : AdmissionLimits,
  snapshot : AdmissionSnapshot,
) -> BackpressureDecision {
  if limits.max_running <= 0 ||
    limits.max_queued < 0 ||
    limits.max_tenant_running <= 0 ||
    limits.max_tenant_queued < 0 ||
    limits.max_payload_bytes <= 0L {
    return Reject(reason=InvalidLimits, retryable=false)
  }
  if snapshot.running < 0 ||
    snapshot.queued < 0 ||
    snapshot.tenant_running < 0 ||
    snapshot.tenant_queued < 0 ||
    snapshot.payload_bytes < 0L ||
    snapshot.deadline_unix_ms < 0L ||
    snapshot.now_unix_ms < 0L {
    return Reject(reason=InvalidSnapshot, retryable=false)
  }
  if !snapshot.lease_valid {
    return Reject(reason=LeaseUnavailable, retryable=false)
  }
  if snapshot.now_unix_ms >= snapshot.deadline_unix_ms {
    return Reject(reason=DeadlineExpired, retryable=false)
  }
  if snapshot.payload_bytes > limits.max_payload_bytes {
    return Reject(reason=PayloadTooLarge, retryable=false)
  }
  if snapshot.tenant_running < limits.max_tenant_running &&
    snapshot.running < limits.max_running {
    return StartImmediately
  }
  if snapshot.tenant_running >= limits.max_tenant_running &&
    snapshot.tenant_queued >= limits.max_tenant_queued {
    return Reject(reason=TenantRunningLimit, retryable=true)
  }
  if snapshot.running >= limits.max_running &&
    snapshot.queued >= limits.max_queued {
    return Reject(reason=RunningCapacity, retryable=true)
  }
  if snapshot.tenant_queued >= limits.max_tenant_queued {
    return Reject(reason=TenantQueueLimit, retryable=true)
  }
  if snapshot.queued >= limits.max_queued {
    return Reject(reason=QueueCapacity, retryable=true)
  }
  Queue(position=snapshot.queued + 1)
}
