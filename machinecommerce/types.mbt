///|
pub let contract_version : String = "lunanexa.machine-commerce.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.machine-commerce.snapshot.v1"

///|
pub(all) suberror MachineCommerceError {
  InvalidInput(String)
  NotFound(String)
  AlreadyExists(String)
  Unauthorized(String)
  TenantMismatch
  IdempotencyConflict(String)
  StaleGeneration
  InvalidTransition(String)
  QuoteExpired
  QuoteIntegrityFailed
  PriceMismatch
  CapacityUnavailable
} derive(Debug, Eq)

///|
pub extend MachineCommerceError with Debug::{to_repr}

///|
pub extend MachineCommerceError with Eq::{not_equal, equal}

///|
pub(all) enum IdempotencyResult {
  Created
  Replayed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend IdempotencyResult with Debug::{to_repr}

///|
pub extend IdempotencyResult with Eq::{not_equal, equal}

///|
pub extend IdempotencyResult with ToJson::{to_json}

///|
pub extend IdempotencyResult with FromJson::{from_json}

///|
pub(all) enum MachineOfferingKind {
  BareMachine
  DedicatedEndpoint
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOfferingKind with Debug::{to_repr}

///|
pub extend MachineOfferingKind with Eq::{not_equal, equal}

///|
pub extend MachineOfferingKind with ToJson::{to_json}

///|
pub extend MachineOfferingKind with FromJson::{from_json}

///|
pub(all) enum MachineOfferingState {
  OfferingActive
  OfferingRetired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOfferingState with Debug::{to_repr}

///|
pub extend MachineOfferingState with Eq::{not_equal, equal}

///|
pub extend MachineOfferingState with ToJson::{to_json}

///|
pub extend MachineOfferingState with FromJson::{from_json}

///| A sellable machine SKU. `unit_price` is the price for one offering unit

///|
/// for one second; `billing_quantum_seconds` controls quote rounding.
pub(all) struct MachineOffering {
  offering_id : String
  sku : String
  display_name : String
  kind : MachineOfferingKind
  region : String
  accelerator_class : String
  accelerator_count : Int64
  memory_mib : Int64
  cpu_count : Int64
  meter : String
  unit_price : @commercial.FixedMoney
  billing_quantum_seconds : Int64
  minimum_duration_seconds : Int64
  maximum_duration_seconds : Int64
  capacity_total : Int64
  allowed_model_template_refs : Array[String]
  state : MachineOfferingState
  generation : Int64
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOffering with Debug::{to_repr}

///|
pub extend MachineOffering with Eq::{not_equal, equal}

///|
pub extend MachineOffering with ToJson::{to_json}

///|
pub extend MachineOffering with FromJson::{from_json}

///| A current inventory projection. Quotes never allocate capacity; capacity

///|
/// is reserved only after an authenticated payment settlement.
pub(all) struct MachineAvailability {
  offering_id : String
  capacity_total : Int64
  capacity_reserved : Int64
  capacity_available : Int64
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineAvailability with Debug::{to_repr}

///|
pub extend MachineAvailability with Eq::{not_equal, equal}

///|
pub extend MachineAvailability with ToJson::{to_json}

///|
pub extend MachineAvailability with FromJson::{from_json}

///|
pub(all) struct MachineOfferingView {
  offering : MachineOffering
  availability : MachineAvailability
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOfferingView with Debug::{to_repr}

///|
pub extend MachineOfferingView with Eq::{not_equal, equal}

///|
pub extend MachineOfferingView with ToJson::{to_json}

///|
pub extend MachineOfferingView with FromJson::{from_json}

///|
pub(all) struct MachineQuoteIntent {
  quote_id : String
  idempotency_key : String
  tenant_ref : String
  organization_id : String
  project_id : String
  purchaser_subject_ref : String
  offering_id : String
  /// One order purchases exactly one SKU in v1. The SKU's accelerator_count
  /// describes the complete machine or dedicated endpoint allocation.
  quantity : Int64
  duration_seconds : Int64
  unix_username : String?
  requested_model_selector : String?
  model_template_ref : String?
  valid_for_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineQuoteIntent with Debug::{to_repr}

///|
pub extend MachineQuoteIntent with Eq::{not_equal, equal}

///|
pub extend MachineQuoteIntent with ToJson::{to_json}

///|
pub extend MachineQuoteIntent with FromJson::{from_json}

///| Server-priced and HMAC-bound quote. Every tenant, SKU, model, price and

///|
/// expiry field participates in both `terms_digest` and `signature`.
pub(all) struct MachineQuote {
  quote_id : String
  idempotency_key : String
  tenant_ref : String
  organization_id : String
  project_id : String
  purchaser_subject_ref : String
  offering_id : String
  offering_kind : MachineOfferingKind
  quantity : Int64
  duration_seconds : Int64
  unix_username : String?
  requested_model_selector : String?
  model_template_ref : String?
  meter : String
  unit_price : @commercial.FixedMoney
  subtotal : @commercial.FixedMoney
  total : @commercial.FixedMoney
  terms_digest : String
  signature : String
  created_unix_ms : Int64
  valid_until_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineQuote with Debug::{to_repr}

///|
pub extend MachineQuote with Eq::{not_equal, equal}

///|
pub extend MachineQuote with ToJson::{to_json}

///|
pub extend MachineQuote with FromJson::{from_json}

///|
pub(all) struct MachineOrderIntent {
  order_id : String
  idempotency_key : String
  quote_id : String
  tenant_ref : String
  organization_id : String
  project_id : String
  purchaser_subject_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOrderIntent with Debug::{to_repr}

///|
pub extend MachineOrderIntent with Eq::{not_equal, equal}

///|
pub extend MachineOrderIntent with ToJson::{to_json}

///|
pub extend MachineOrderIntent with FromJson::{from_json}

///|
pub(all) enum MachineOrderState {
  AwaitingPayment
  PaymentSettled
  Provisioning
  Active
  CancellationPending
  TerminationPending
  CompensationPending
  Cancelled
  Terminated
  Failed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOrderState with Debug::{to_repr}

///|
pub extend MachineOrderState with Eq::{not_equal, equal}

///|
pub extend MachineOrderState with ToJson::{to_json}

///|
pub extend MachineOrderState with FromJson::{from_json}

///|
pub(all) struct MachineOrder {
  order_id : String
  idempotency_key : String
  quote_id : String
  tenant_ref : String
  organization_id : String
  project_id : String
  purchaser_subject_ref : String
  offering_id : String
  offering_kind : MachineOfferingKind
  quantity : Int64
  duration_seconds : Int64
  unix_username : String?
  requested_model_selector : String?
  model_template_ref : String?
  quoted_total : @commercial.FixedMoney
  state : MachineOrderState
  generation : Int64
  payment_ref : String?
  payment_event_id : String?
  target_lease_ref : String?
  target_deployment_ref : String?
  failure_code : String?
  compensation_ref : String?
  capacity_reserved : Bool
  active_started_unix_ms : Int64?
  last_metered_unix_ms : Int64?
  ended_unix_ms : Int64?
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOrder with Debug::{to_repr}

///|
pub extend MachineOrder with Eq::{not_equal, equal}

///|
pub extend MachineOrder with ToJson::{to_json}

///|
pub extend MachineOrder with FromJson::{from_json}

///|
pub(all) struct MachineOrderAction {
  idempotency_key : String
  expected_generation : Int64
  reason : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineOrderAction with Debug::{to_repr}

///|
pub extend MachineOrderAction with Eq::{not_equal, equal}

///|
pub extend MachineOrderAction with ToJson::{to_json}

///|
pub extend MachineOrderAction with FromJson::{from_json}

///|
pub(all) struct MachineProvisioningIntent {
  idempotency_key : String
  expected_generation : Int64
  target_lease_ref : String?
  target_deployment_ref : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineProvisioningIntent with Debug::{to_repr}

///|
pub extend MachineProvisioningIntent with Eq::{not_equal, equal}

///|
pub extend MachineProvisioningIntent with ToJson::{to_json}

///|
pub extend MachineProvisioningIntent with FromJson::{from_json}

///| Authenticated payment-provider settlement. The transaction link used by

///|
/// the provider is `machine-order:<order_id>`.
pub(all) struct MachinePaymentSettlement {
  provider_event_id : String
  payment_ref : String
  settled_amount : @commercial.FixedMoney
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachinePaymentSettlement with Debug::{to_repr}

///|
pub extend MachinePaymentSettlement with Eq::{not_equal, equal}

///|
pub extend MachinePaymentSettlement with ToJson::{to_json}

///|
pub extend MachinePaymentSettlement with FromJson::{from_json}

///|
pub(all) struct MachineMeterIntent {
  idempotency_key : String
  expected_generation : Int64
  ended_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineMeterIntent with Debug::{to_repr}

///|
pub extend MachineMeterIntent with Eq::{not_equal, equal}

///|
pub extend MachineMeterIntent with ToJson::{to_json}

///|
pub extend MachineMeterIntent with FromJson::{from_json}

///|
/// Durable, idempotent evidence ready for the commercial usage ledger.
pub(all) struct MachineUsageReceipt {
  receipt_id : String
  idempotency_key : String
  event_id : String
  order_id : String
  organization_id : String
  project_id : String
  subject_ref : String
  resource_ref : String
  meter : String
  quantity : Int64
  unit : String
  started_unix_ms : Int64
  ended_unix_ms : Int64
  observed_unix_ms : Int64
  receipt_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineUsageReceipt with Debug::{to_repr}

///|
pub extend MachineUsageReceipt with Eq::{not_equal, equal}

///|
pub extend MachineUsageReceipt with ToJson::{to_json}

///|
pub extend MachineUsageReceipt with FromJson::{from_json}

///| Durable replay record for mutating lifecycle actions. The outcome

///|
/// generation binds an idempotency key to the exact state transition.
pub(all) struct MachineActionReceipt {
  order_id : String
  idempotency_key : String
  action : String
  outcome_generation : Int64
  recorded_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineActionReceipt with Debug::{to_repr}

///|
pub extend MachineActionReceipt with Eq::{not_equal, equal}

///|
pub extend MachineActionReceipt with ToJson::{to_json}

///|
pub extend MachineActionReceipt with FromJson::{from_json}

///|
pub(all) struct MachineCommerceSnapshot {
  schema_version : String
  offerings : Array[MachineOffering]
  quotes : Array[MachineQuote]
  orders : Array[MachineOrder]
  usage_receipts : Array[MachineUsageReceipt]
  action_receipts : Array[MachineActionReceipt]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend MachineCommerceSnapshot with Debug::{to_repr}

///|
pub extend MachineCommerceSnapshot with Eq::{not_equal, equal}

///|
pub extend MachineCommerceSnapshot with ToJson::{to_json}

///|
pub extend MachineCommerceSnapshot with FromJson::{from_json}
