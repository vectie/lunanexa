///|
pub let scheduler_state_version : String = "lunanexa.guide-probe-scheduler.v1"

///|
pub(all) suberror GuideProbeError {
  InvalidConfiguration(String)
  InvalidSchedulerState
  TransportUnavailable
  RedirectRejected
  ResponseTooLarge
  MalformedResponse
  UntrustedResponse
} derive(Debug, Eq)

///|
pub extend GuideProbeError with Debug::{to_repr}

///|
pub extend GuideProbeError with Eq::{not_equal, equal}

/// Configuration deliberately excludes both signing secrets so accidental
/// serialization or diagnostics cannot expose them.

///|
pub(all) struct GuideProbeConfig {
  origin : String
  allow_https : Bool
  actor_ref : String
  role : String
  maximum_response_bytes : Int
  request_timeout_ms : Int
} derive(Debug, Eq)

///|
pub extend GuideProbeConfig with Debug::{to_repr}

///|
pub extend GuideProbeConfig with Eq::{not_equal, equal}

///|
pub(all) struct GuideProbeSchedulerState {
  schema_version : String
  sequence : Int64
  last_scheduled_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend GuideProbeSchedulerState with Debug::{to_repr}

///|
pub extend GuideProbeSchedulerState with Eq::{not_equal, equal}

///|
pub extend GuideProbeSchedulerState with ToJson::{to_json}

///|
pub extend GuideProbeSchedulerState with FromJson::{from_json}

///|
pub(all) struct GuideProbeRunResult {
  was_due : Bool
  probe_ok : Bool
  failure_code : String?
  monitor_result : @guide_monitor.GuideMonitorResult?
} derive(Debug, ToJson)

///|
pub extend GuideProbeRunResult with Debug::{to_repr}

///|
pub extend GuideProbeRunResult with ToJson::{to_json}

///|
pub struct GuideProbeScheduler {
  path : String
  mut state : GuideProbeSchedulerState
  mutex : @async.Mutex
}

/// Secrets and the notification store are intentionally private and this type
/// has no JSON/debug derivation.

///|
pub struct GuideProbeWorker {
  config : GuideProbeConfig
  policy : @guide_monitor.GuideMonitorPolicy
  scheduler : GuideProbeScheduler
  notifications : @store.NotificationStore
  observability : @observability.ObservabilityStore?
  identity_secret : String
  observation_secret : String
}

///|
priv struct HealthDependency {
  ok : Bool
  enabled : Bool?
} derive(FromJson)

///|
priv struct HealthDependencies {
  coursebook : HealthDependency
  admin_diagnostics : HealthDependency
} derive(FromJson)

///|
priv struct HealthEnvelope {
  ok : Bool
  dependencies : HealthDependencies
} derive(FromJson)

///|
priv struct KnowledgeProjection {
  revision : String
  age_ms : Double
  stale : Bool
} derive(FromJson)

///|
priv struct DiagnosticsProjection {
  contract_version : String
  generated_unix_ms : Double
  knowledge : KnowledgeProjection
} derive(FromJson)

///|
priv struct DiagnosticsEnvelope {
  ok : Bool
  category : String
  correlation_receipt : String
  diagnostics : DiagnosticsProjection
} derive(FromJson)
