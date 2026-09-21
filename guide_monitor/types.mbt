///|
pub let contract_version : String = "lunanexa.guide-monitor.v1"

///|
pub(all) suberror GuideMonitorError {
  InvalidPolicy(String)
  InvalidObservation(String)
  InvalidSignature
  StaleObservation
} derive(Debug, Eq)

///|
pub(all) struct GuideMonitorPolicy {
  target_ref : String
  probe_interval_ms : Int64
  observation_max_age_ms : Int64
  future_skew_ms : Int64
  knowledge_max_age_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GuideProbePlan {
  version : String
  target_ref : String
  correlation_receipt : String
  scheduled_unix_ms : Int64
  health_path : String
  diagnostics_path : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GuideHealthObservation {
  version : String
  observation_id : String
  target_ref : String
  correlation_receipt : String
  scheduled_unix_ms : Int64
  observed_unix_ms : Int64
  coursebook_ok : Bool
  admin_diagnostics_enabled : Bool
  admin_diagnostics_ok : Bool
  knowledge_revision : String
  knowledge_stale : Bool
  knowledge_age_ms : Int64
  signature : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct GuideMonitorResult {
  observation_id : String
  adapter_alert_active : Bool
  knowledge_alert_active : Bool
  adapter_record : @notifications.NotificationRecord?
  knowledge_record : @notifications.NotificationRecord?
} derive(Debug, Eq, ToJson, FromJson)
