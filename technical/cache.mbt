///|
pub(all) enum CacheLifecycleState {
  Reserved
  Partial
  Verifying
  Ready
  Evicting
  Quarantined
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CacheEntryTelemetry {
  node_ref : String
  model_digest : String
  lifecycle : CacheLifecycleState
  logical_bytes : Int64
  transferred_bytes : Int64
  assignment_references : Int
  signature_verified : Bool
  last_access_unix_ms : Int64
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum CacheTelemetryFinding {
  MissingNodeReference
  InvalidDigest
  InvalidByteCount
  InvalidReferenceCount
  InvalidTimestamp
  ReadyWithoutCompleteTransfer
  ReadyWithoutSignature
  InvalidPressureBounds
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum CacheAction {
  RetainReferenced
  RetainBelowHighWater
  EligibleForEviction
  QuarantineInvalidTelemetry(Array[CacheTelemetryFinding])
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn validate_cache_telemetry(
  entry : CacheEntryTelemetry,
) -> Array[CacheTelemetryFinding] {
  let findings : Array[CacheTelemetryFinding] = []
  if entry.node_ref.is_empty() {
    findings.push(MissingNodeReference)
  }
  if !valid_digest(entry.model_digest) {
    findings.push(InvalidDigest)
  }
  if entry.logical_bytes <= 0L ||
    entry.transferred_bytes < 0L ||
    entry.transferred_bytes > entry.logical_bytes {
    findings.push(InvalidByteCount)
  }
  if entry.assignment_references < 0 {
    findings.push(InvalidReferenceCount)
  }
  if entry.last_access_unix_ms < 0L ||
    entry.observed_unix_ms < entry.last_access_unix_ms {
    findings.push(InvalidTimestamp)
  }
  if entry.lifecycle == Ready && entry.transferred_bytes != entry.logical_bytes {
    findings.push(ReadyWithoutCompleteTransfer)
  }
  if entry.lifecycle == Ready && !entry.signature_verified {
    findings.push(ReadyWithoutSignature)
  }
  findings
}

///|
pub fn cache_reconcile_action(
  entry : CacheEntryTelemetry,
  cache_used_bytes : Int64,
  high_water_bytes : Int64,
) -> CacheAction {
  let findings = validate_cache_telemetry(entry)
  if cache_used_bytes < 0L || high_water_bytes <= 0L {
    findings.push(InvalidPressureBounds)
  }
  if findings.length() > 0 {
    return QuarantineInvalidTelemetry(findings)
  }
  if entry.assignment_references > 0 {
    RetainReferenced
  } else if cache_used_bytes <= high_water_bytes {
    RetainBelowHighWater
  } else {
    EligibleForEviction
  }
}
