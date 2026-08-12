///|
pub let contract_version : String = "lunanexa.notifications.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.notifications.snapshot.v1"

///|
pub(all) suberror NotificationError {
  InvalidInput(String)
  NotFound(String)
  AlreadyExists(String)
  IdempotencyConflict(String)
  Unauthorized
  StaleGeneration
  InvalidTransition(String)
} derive(Debug, Eq)

///|
pub(all) enum NotificationSeverity {
  Information
  Warning
  Critical
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum NotificationTopic {
  ClusterHealth
  ArtifactHealth
  WorkloadAdmission
  CommercialAction
  Reconciliation
  LeaseLifecycle
  AccessCredential
  GuideDiagnostics
  DeliveryHealth
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum NotificationAudience {
  PlatformOperators
  TenantUsers(tenant_ref~ : String)
  Subject(tenant_ref~ : String, subject_ref~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum NotificationLifecycle {
  Unread
  Read
  Acknowledged
  Resolved
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum NotificationChannel {
  InApp
  Email
  Sms
  Webhook
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum DeliveryState {
  PendingDelivery
  Delivering
  Delivered
  RetryScheduled
  DeadLetter
  DeliverySkipped
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationEvent {
  version : String
  notification_id : String
  deduplication_key : String
  source_receipt : String
  topic : NotificationTopic
  code : String
  severity : NotificationSeverity
  audience : NotificationAudience
  title_key : String
  body_key : String
  parameters : Map[String, String]
  created_unix_ms : Int64
  expires_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationRecord {
  event : NotificationEvent
  lifecycle : NotificationLifecycle
  generation : Int64
  assigned_to : String?
  acknowledged_by : String?
  acknowledged_unix_ms : Int64?
  silenced_until_unix_ms : Int64?
  resolved_by : String?
  resolved_unix_ms : Int64?
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationAction {
  notification_id : String
  expected_generation : Int64
  actor_ref : String
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationSilenceAction {
  notification_id : String
  expected_generation : Int64
  actor_ref : String
  now_unix_ms : Int64
  silenced_until_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationAssignmentAction {
  notification_id : String
  expected_generation : Int64
  actor_ref : String
  assignee_ref : String?
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationDelivery {
  delivery_id : String
  notification_id : String
  channel : NotificationChannel
  state : DeliveryState
  attempt_count : Int
  next_attempt_unix_ms : Int64?
  provider_receipt : String?
  last_error_code : String?
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct DeliveryResult {
  delivery_id : String
  expected_attempt_count : Int
  delivered : Bool
  retryable : Bool
  provider_receipt : String?
  error_code : String?
  next_attempt_unix_ms : Int64?
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationPreference {
  preference_id : String
  tenant_ref : String
  subject_ref : String
  topic : NotificationTopic
  channels : Array[NotificationChannel]
  minimum_severity : NotificationSeverity
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AlertComparator {
  AtLeast
  GreaterThan
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AlertRule {
  rule_id : String
  topic : NotificationTopic
  code : String
  severity : NotificationSeverity
  comparator : AlertComparator
  threshold : Int64
  title_key : String
  body_key : String
  audience : NotificationAudience
  enabled : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AlertObservation {
  observation_id : String
  dimension_ref : String
  value : Int64
  observed_unix_ms : Int64
  source_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct NotificationSnapshot {
  schema_version : String
  records : Array[NotificationRecord]
  deliveries : Array[NotificationDelivery]
  preferences : Array[NotificationPreference]
} derive(Debug, Eq, ToJson, FromJson)
