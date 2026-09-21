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
pub extend NotificationError with Debug::{to_repr}

///|
pub extend NotificationError with Eq::{not_equal, equal}

///|
pub(all) enum NotificationSeverity {
  Information
  Warning
  Critical
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationSeverity with Debug::{to_repr}

///|
pub extend NotificationSeverity with Eq::{not_equal, equal}

///|
pub extend NotificationSeverity with ToJson::{to_json}

///|
pub extend NotificationSeverity with FromJson::{from_json}

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
  Announcement
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationTopic with Debug::{to_repr}

///|
pub extend NotificationTopic with Eq::{not_equal, equal}

///|
pub extend NotificationTopic with ToJson::{to_json}

///|
pub extend NotificationTopic with FromJson::{from_json}

///|
pub(all) enum NotificationAudience {
  PlatformOperators
  TenantUsers(tenant_ref~ : String)
  Subject(tenant_ref~ : String, subject_ref~ : String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationAudience with Debug::{to_repr}

///|
pub extend NotificationAudience with Eq::{not_equal, equal}

///|
pub extend NotificationAudience with ToJson::{to_json}

///|
pub extend NotificationAudience with FromJson::{from_json}

///|
pub(all) enum NotificationLifecycle {
  Unread
  Read
  Acknowledged
  Resolved
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationLifecycle with Debug::{to_repr}

///|
pub extend NotificationLifecycle with Eq::{not_equal, equal}

///|
pub extend NotificationLifecycle with ToJson::{to_json}

///|
pub extend NotificationLifecycle with FromJson::{from_json}

///|
pub(all) enum NotificationChannel {
  InApp
  Email
  Sms
  Webhook
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationChannel with Debug::{to_repr}

///|
pub extend NotificationChannel with Eq::{not_equal, equal}

///|
pub extend NotificationChannel with ToJson::{to_json}

///|
pub extend NotificationChannel with FromJson::{from_json}

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
pub extend DeliveryState with Debug::{to_repr}

///|
pub extend DeliveryState with Eq::{not_equal, equal}

///|
pub extend DeliveryState with ToJson::{to_json}

///|
pub extend DeliveryState with FromJson::{from_json}

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
pub extend NotificationEvent with Debug::{to_repr}

///|
pub extend NotificationEvent with Eq::{not_equal, equal}

///|
pub extend NotificationEvent with ToJson::{to_json}

///|
pub extend NotificationEvent with FromJson::{from_json}

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
pub extend NotificationRecord with Debug::{to_repr}

///|
pub extend NotificationRecord with Eq::{not_equal, equal}

///|
pub extend NotificationRecord with ToJson::{to_json}

///|
pub extend NotificationRecord with FromJson::{from_json}

///|
pub(all) struct NotificationAction {
  notification_id : String
  expected_generation : Int64
  actor_ref : String
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationAction with Debug::{to_repr}

///|
pub extend NotificationAction with Eq::{not_equal, equal}

///|
pub extend NotificationAction with ToJson::{to_json}

///|
pub extend NotificationAction with FromJson::{from_json}

///|
pub(all) struct NotificationSilenceAction {
  notification_id : String
  expected_generation : Int64
  actor_ref : String
  now_unix_ms : Int64
  silenced_until_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationSilenceAction with Debug::{to_repr}

///|
pub extend NotificationSilenceAction with Eq::{not_equal, equal}

///|
pub extend NotificationSilenceAction with ToJson::{to_json}

///|
pub extend NotificationSilenceAction with FromJson::{from_json}

///|
pub(all) struct NotificationAssignmentAction {
  notification_id : String
  expected_generation : Int64
  actor_ref : String
  assignee_ref : String?
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationAssignmentAction with Debug::{to_repr}

///|
pub extend NotificationAssignmentAction with Eq::{not_equal, equal}

///|
pub extend NotificationAssignmentAction with ToJson::{to_json}

///|
pub extend NotificationAssignmentAction with FromJson::{from_json}

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
pub extend NotificationDelivery with Debug::{to_repr}

///|
pub extend NotificationDelivery with Eq::{not_equal, equal}

///|
pub extend NotificationDelivery with ToJson::{to_json}

///|
pub extend NotificationDelivery with FromJson::{from_json}

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
pub extend DeliveryResult with Debug::{to_repr}

///|
pub extend DeliveryResult with Eq::{not_equal, equal}

///|
pub extend DeliveryResult with ToJson::{to_json}

///|
pub extend DeliveryResult with FromJson::{from_json}

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
pub extend NotificationPreference with Debug::{to_repr}

///|
pub extend NotificationPreference with Eq::{not_equal, equal}

///|
pub extend NotificationPreference with ToJson::{to_json}

///|
pub extend NotificationPreference with FromJson::{from_json}

///| Tenant-safe preference projection. Durable identity and tenant bindings

///|
/// are enforced by the server and are never returned to the browser.
pub(all) struct NotificationPreferenceView {
  topic : NotificationTopic
  channels : Array[NotificationChannel]
  minimum_severity : NotificationSeverity
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationPreferenceView with Debug::{to_repr}

///|
pub extend NotificationPreferenceView with Eq::{not_equal, equal}

///|
pub extend NotificationPreferenceView with ToJson::{to_json}

///|
pub extend NotificationPreferenceView with FromJson::{from_json}

///|
pub(all) enum AlertComparator {
  AtLeast
  GreaterThan
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AlertComparator with Debug::{to_repr}

///|
pub extend AlertComparator with Eq::{not_equal, equal}

///|
pub extend AlertComparator with ToJson::{to_json}

///|
pub extend AlertComparator with FromJson::{from_json}

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
pub extend AlertRule with Debug::{to_repr}

///|
pub extend AlertRule with Eq::{not_equal, equal}

///|
pub extend AlertRule with ToJson::{to_json}

///|
pub extend AlertRule with FromJson::{from_json}

///|
pub(all) struct AlertObservation {
  observation_id : String
  dimension_ref : String
  value : Int64
  observed_unix_ms : Int64
  source_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AlertObservation with Debug::{to_repr}

///|
pub extend AlertObservation with Eq::{not_equal, equal}

///|
pub extend AlertObservation with ToJson::{to_json}

///|
pub extend AlertObservation with FromJson::{from_json}

///|
pub(all) struct NotificationSnapshot {
  schema_version : String
  records : Array[NotificationRecord]
  deliveries : Array[NotificationDelivery]
  preferences : Array[NotificationPreference]
  worker_health : NotificationWorkerHealth
  redrive_audit : Array[NotificationDeliveryRedriveReceipt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationSnapshot with Debug::{to_repr}

///|
pub extend NotificationSnapshot with Eq::{not_equal, equal}

///|
pub extend NotificationSnapshot with ToJson::{to_json}

///|
pub extend NotificationSnapshot with FromJson::{from_json}

///| Durable health of the autonomous outbound-delivery worker. A configured

///|
/// adapter is not considered ready until a real delivery attempt succeeds.
pub(all) struct NotificationWorkerHealth {
  generation : Int64
  last_heartbeat_unix_ms : Int64?
  last_attempt_unix_ms : Int64?
  last_success_unix_ms : Int64?
  last_failure_unix_ms : Int64?
  consecutive_failures : Int
  last_error_code : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationWorkerHealth with Debug::{to_repr}

///|
pub extend NotificationWorkerHealth with Eq::{not_equal, equal}

///|
pub extend NotificationWorkerHealth with ToJson::{to_json}

///|
pub extend NotificationWorkerHealth with FromJson::{from_json}

///|
/// Generation-fenced operator request to redrive one dead-letter delivery.
pub(all) struct NotificationDeliveryRedriveAction {
  delivery_id : String
  expected_attempt_count : Int
  expected_updated_unix_ms : Int64
  actor_ref : String
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationDeliveryRedriveAction with Debug::{to_repr}

///|
pub extend NotificationDeliveryRedriveAction with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryRedriveAction with ToJson::{to_json}

///|
pub extend NotificationDeliveryRedriveAction with FromJson::{from_json}

///|
/// Durable audit receipt for an accepted dead-letter redrive.
pub(all) struct NotificationDeliveryRedriveReceipt {
  receipt_id : String
  delivery_id : String
  actor_ref : String
  previous_attempt_count : Int
  accepted_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationDeliveryRedriveReceipt with Debug::{to_repr}

///|
pub extend NotificationDeliveryRedriveReceipt with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryRedriveReceipt with ToJson::{to_json}

///|
pub extend NotificationDeliveryRedriveReceipt with FromJson::{from_json}

///|
pub(all) enum NotificationDeliveryReadinessState {
  DeliveryReady
  AdaptersPending
  DeliveryDegraded
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationDeliveryReadinessState with Debug::{to_repr}

///|
pub extend NotificationDeliveryReadinessState with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryReadinessState with ToJson::{to_json}

///|
pub extend NotificationDeliveryReadinessState with FromJson::{from_json}

///| Public management projection for the outbound notification boundary. It

///| reports configuration and queue health without returning provider

///|
/// endpoints, credentials, recipient addresses, or message bodies.
pub(all) struct NotificationDeliveryReadiness {
  version : String
  state : NotificationDeliveryReadinessState
  adapter_configured : Bool
  pending_count : Int
  delivering_count : Int
  dead_letter_count : Int
  capacity_exhausted : Bool
  worker_health : NotificationWorkerHealth
  supported_channels : Array[NotificationChannel]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationDeliveryReadiness with Debug::{to_repr}

///|
pub extend NotificationDeliveryReadiness with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryReadiness with ToJson::{to_json}

///|
pub extend NotificationDeliveryReadiness with FromJson::{from_json}

///| Bounded provider-neutral request sent to the deployment-owned delivery

///| adapter. The adapter resolves recipient destinations from the opaque

///| audience; LunaNexa never stores email addresses, phone numbers, or webhook

///|
/// secrets in notification state.
pub(all) struct NotificationDeliveryEnvelope {
  version : String
  delivery_id : String
  channel : NotificationChannel
  audience : NotificationAudience
  topic : NotificationTopic
  code : String
  severity : NotificationSeverity
  title_key : String
  body_key : String
  parameters : Map[String, String]
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationDeliveryEnvelope with Debug::{to_repr}

///|
pub extend NotificationDeliveryEnvelope with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryEnvelope with ToJson::{to_json}

///|
pub extend NotificationDeliveryEnvelope with FromJson::{from_json}

///|
/// Minimal response accepted from an outbound delivery adapter.
pub(all) struct NotificationAdapterReceipt {
  provider_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationAdapterReceipt with Debug::{to_repr}

///|
pub extend NotificationAdapterReceipt with Eq::{not_equal, equal}

///|
pub extend NotificationAdapterReceipt with ToJson::{to_json}

///|
pub extend NotificationAdapterReceipt with FromJson::{from_json}

///|
/// Result of one bounded autonomous notification reconciliation pass.
pub(all) struct NotificationReconciliationSummary {
  reconciled_unix_ms : Int64
  subject_count : Int
  operator_alert_count : Int
  expired_silence_count : Int
  pending_delivery_count : Int
  dead_letter_count : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationReconciliationSummary with Debug::{to_repr}

///|
pub extend NotificationReconciliationSummary with Eq::{not_equal, equal}

///|
pub extend NotificationReconciliationSummary with ToJson::{to_json}

///|
pub extend NotificationReconciliationSummary with FromJson::{from_json}

///|
pub(all) struct NotificationDeliveryRunSummary {
  attempted : Int
  delivered : Int
  retry_scheduled : Int
  dead_lettered : Int
  skipped : Int
  readiness : NotificationDeliveryReadiness
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationDeliveryRunSummary with Debug::{to_repr}

///|
pub extend NotificationDeliveryRunSummary with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryRunSummary with ToJson::{to_json}

///|
pub extend NotificationDeliveryRunSummary with FromJson::{from_json}
