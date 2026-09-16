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
pub(all) enum IdempotencyResult {
  Created
  Replayed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum MachineOfferingKind {
  BareMachine
  DedicatedEndpoint
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum MachineOfferingState {
  OfferingActive
  OfferingRetired
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct MachineOfferingView {
  offering : MachineOffering
  availability : MachineAvailability
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct MachineOrderAction {
  idempotency_key : String
  expected_generation : Int64
  reason : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MachineProvisioningIntent {
  idempotency_key : String
  expected_generation : Int64
  target_lease_ref : String?
  target_deployment_ref : String?
} derive(Debug, Eq, ToJson, FromJson)

///| Authenticated payment-provider settlement. The transaction link used by

///|
/// the provider is `machine-order:<order_id>`.
pub(all) struct MachinePaymentSettlement {
  provider_event_id : String
  payment_ref : String
  settled_amount : @commercial.FixedMoney
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct MachineMeterIntent {
  idempotency_key : String
  expected_generation : Int64
  ended_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct MachineCommerceSnapshot {
  schema_version : String
  offerings : Array[MachineOffering]
  quotes : Array[MachineQuote]
  orders : Array[MachineOrder]
  usage_receipts : Array[MachineUsageReceipt]
  action_receipts : Array[MachineActionReceipt]
} derive(Debug, Eq, ToJson, FromJson)
