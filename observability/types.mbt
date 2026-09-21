///|
pub let contract_version : String = "lunanexa.observability.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.observability.snapshot.v1"

///| Hard upper bound for the lifetime metric-series set. Operational labels

///| are deliberately finite, and a corrupt snapshot or untrusted event stream

///|
/// must not turn the controller into an unbounded metrics cardinality sink.
pub let maximum_operational_counter_series : Int = 4096

///|
pub(all) suberror ObservabilityError {
  InvalidEvent(String)
  InvalidSnapshot(String)
  EventConflict(String)
} derive(Debug, Eq)

///|
pub extend ObservabilityError with Debug::{to_repr}

///|
pub extend ObservabilityError with Eq::{not_equal, equal}

///|
pub(all) enum OperationalSeverity {
  Debug
  Information
  Warning
  Error
  Critical
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OperationalSeverity with Debug::{to_repr}

///|
pub extend OperationalSeverity with Eq::{not_equal, equal}

///|
pub extend OperationalSeverity with ToJson::{to_json}

///|
pub extend OperationalSeverity with FromJson::{from_json}

///|
pub(all) enum OperationalActorClass {
  Anonymous
  Operator
  Customer
  NodeAgent
  Provider
  Controller
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OperationalActorClass with Debug::{to_repr}

///|
pub extend OperationalActorClass with Eq::{not_equal, equal}

///|
pub extend OperationalActorClass with ToJson::{to_json}

///|
pub extend OperationalActorClass with FromJson::{from_json}

///| A bounded structured operational event. It deliberately excludes request

///| bodies, raw identity values, tokens, prompts, model output and document

///| bytes. High-cardinality identity belongs only in the correlation field or

///|
/// audit authority, never metric labels.
pub(all) struct OperationalEvent {
  version : String
  event_id : String
  timestamp_unix_ms : Int64
  severity : OperationalSeverity
  component : String
  event_code : String
  correlation_id : String
  actor_class : OperationalActorClass
  tenant_hash : String?
  target_type : String
  outcome : String
  status_code : Int
  duration_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OperationalEvent with Debug::{to_repr}

///|
pub extend OperationalEvent with Eq::{not_equal, equal}

///|
pub extend OperationalEvent with ToJson::{to_json}

///|
pub extend OperationalEvent with FromJson::{from_json}

///|
pub(all) struct OperationalCounter {
  event_code : String
  target_type : String
  outcome : String
  status_class : String
  value : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OperationalCounter with Debug::{to_repr}

///|
pub extend OperationalCounter with Eq::{not_equal, equal}

///|
pub extend OperationalCounter with ToJson::{to_json}

///|
pub extend OperationalCounter with FromJson::{from_json}

///|
pub(all) struct ObservabilitySnapshot {
  schema_version : String
  events : Array[OperationalEvent]
  counters : Array[OperationalCounter]
  last_external_export_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ObservabilitySnapshot with Debug::{to_repr}

///|
pub extend ObservabilitySnapshot with Eq::{not_equal, equal}

///|
pub extend ObservabilitySnapshot with ToJson::{to_json}

///|
pub extend ObservabilitySnapshot with FromJson::{from_json}

///|
pub(all) struct OperationalLatencyBucket {
  target_type : String
  upper_bound_ms : Int64?
  count : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OperationalLatencyBucket with Debug::{to_repr}

///|
pub extend OperationalLatencyBucket with Eq::{not_equal, equal}

///|
pub extend OperationalLatencyBucket with ToJson::{to_json}

///|
pub extend OperationalLatencyBucket with FromJson::{from_json}

///|
pub(all) struct OperationalLatencySummary {
  target_type : String
  count : Int64
  sum_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OperationalLatencySummary with Debug::{to_repr}

///|
pub extend OperationalLatencySummary with Eq::{not_equal, equal}

///|
pub extend OperationalLatencySummary with ToJson::{to_json}

///|
pub extend OperationalLatencySummary with FromJson::{from_json}

///|
pub(all) enum ObservabilityReadinessState {
  LocalJsonReady
  ExternalCollectorPending
  ObservabilityDegraded
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ObservabilityReadinessState with Debug::{to_repr}

///|
pub extend ObservabilityReadinessState with Eq::{not_equal, equal}

///|
pub extend ObservabilityReadinessState with ToJson::{to_json}

///|
pub extend ObservabilityReadinessState with FromJson::{from_json}

///|
pub(all) struct ObservabilityReadiness {
  version : String
  state : ObservabilityReadinessState
  persistence_available : Bool
  json_lines_enabled : Bool
  external_collector_configured : Bool
  external_export_verified : Bool
  last_external_export_unix_ms : Int64?
  event_history_count : Int
  event_history_limit : Int
  oldest_event_unix_ms : Int64?
  newest_event_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ObservabilityReadiness with Debug::{to_repr}

///|
pub extend ObservabilityReadiness with Eq::{not_equal, equal}

///|
pub extend ObservabilityReadiness with ToJson::{to_json}

///|
pub extend ObservabilityReadiness with FromJson::{from_json}

///| Bounded proof posted only after the deployment-owned collector confirms

///|
/// that an event reached its external sink.
pub(all) struct ExternalExportProof {
  proof_receipt : String
  exported_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExternalExportProof with Debug::{to_repr}

///|
pub extend ExternalExportProof with Eq::{not_equal, equal}

///|
pub extend ExternalExportProof with ToJson::{to_json}

///|
pub extend ExternalExportProof with FromJson::{from_json}
