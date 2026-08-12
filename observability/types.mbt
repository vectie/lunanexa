///|
pub let contract_version : String = "lunanexa.observability.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.observability.snapshot.v1"

///|
pub(all) suberror ObservabilityError {
  InvalidEvent(String)
  InvalidSnapshot(String)
} derive(Debug, Eq)

///|
pub(all) enum OperationalSeverity {
  Debug
  Information
  Warning
  Error
  Critical
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OperationalActorClass {
  Anonymous
  Operator
  Customer
  NodeAgent
  Provider
  Controller
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct OperationalCounter {
  event_code : String
  target_type : String
  outcome : String
  status_class : String
  value : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ObservabilitySnapshot {
  schema_version : String
  events : Array[OperationalEvent]
  counters : Array[OperationalCounter]
} derive(Debug, Eq, ToJson, FromJson)
