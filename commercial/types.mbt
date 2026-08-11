///|
pub let contract_version : String = "lunanexa.commercial.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.commercial.snapshot.v1"

///|
pub let export_schema_version : String = "lunanexa.commercial.export.v1"

///|
pub(all) suberror CommercialError {
  InvalidInput(String)
  NotFound(String)
  AlreadyExists(String)
  TenantMismatch
  IdempotencyConflict(String)
  ArithmeticOverflow
  CurrencyMismatch
  PeriodFinalized(String)
  InvalidTransition(String)
  PermissionDenied(String)
  SeparationOfDuties(String)
  AdmissionDenied(String)
} derive(Debug, Eq)

///|
pub(all) enum IdempotencyResult {
  Created
  Replayed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OrganizationState {
  PendingVerification
  Active
  Suspended
  Closed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Organization {
  organization_id : String
  display_name : String
  state : OrganizationState
  verification_ref : String?
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CostCenter {
  cost_center_id : String
  organization_id : String
  parent_cost_center_id : String?
  display_name : String
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Project {
  project_id : String
  organization_id : String
  cost_center_id : String
  display_name : String
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FixedMoney {
  minor_units : Int64
  currency : String
  scale : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct UsageObservation {
  event_id : String
  organization_id : String
  project_id : String
  actor_ref : String
  workload_id : String
  node_id : String
  lease_epoch : Int64
  meter : String
  quantity : Int64
  unit : String
  started_unix_ms : Int64
  ended_unix_ms : Int64
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RateCard {
  rate_card_id : String
  version : String
  meter : String
  unit : String
  unit_price : FixedMoney
  effective_from_unix_ms : Int64
  effective_until_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum LedgerEntryKind {
  Charge
  Adjustment
  Credit
  Debit
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct LedgerEntry {
  entry_id : String
  organization_id : String
  cost_center_id : String
  project_id : String
  organization_name_snapshot : String
  cost_center_name_snapshot : String
  project_name_snapshot : String
  source_event_id : String
  linked_entry_id : String?
  kind : LedgerEntryKind
  meter : String
  quantity : Int64
  unit : String
  amount : FixedMoney
  rate_card_id : String
  rate_card_version : String
  service_started_unix_ms : Int64
  service_ended_unix_ms : Int64
  recorded_unix_ms : Int64
  reason : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct FinalizedPeriod {
  period_id : String
  organization_id : String
  started_unix_ms : Int64
  ended_unix_ms : Int64
  billing_timezone : String
  entry_ids : Array[String]
  total : FixedMoney
  finalized_unix_ms : Int64
  finalized_by : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BudgetAction {
  Notify
  RequireApproval
  BlockNewWork
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Budget {
  budget_id : String
  organization_id : String
  project_id : String?
  limit : FixedMoney
  warning_percent : Int
  warning_action : BudgetAction
  hard_stop : Bool
  grace_minor_units : Int64
  effective_from_unix_ms : Int64
  effective_until_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Quota {
  quota_id : String
  organization_id : String
  project_id : String?
  meter : String
  maximum_quantity : Int64
  period_started_unix_ms : Int64
  period_ended_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AdmissionDecisionKind {
  Allowed
  ApprovalRequired
  Blocked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AdmissionRequest {
  organization_id : String
  project_id : String
  meter : String
  expected_quantity : Int64
  expected_cost : FixedMoney
  required_capacity_units : Int64
  required_agreement_types : Array[String]
  now_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AdmissionDecision {
  kind : AdmissionDecisionKind
  reasons : Array[String]
  matching_commitment_id : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum CommitmentState {
  Proposed
  Approved
  ActiveCommitment
  Exhausted
  Expired
  CancelledCommitment
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapacityCommitment {
  commitment_id : String
  organization_id : String
  cluster_id : String
  gpu_class : String
  service_mode : String
  capacity_units : Int64
  effective_from_unix_ms : Int64
  effective_until_unix_ms : Int64
  created_by : String
  approved_by : String?
  state : CommitmentState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EntitlementConsumption {
  consumption_id : String
  commitment_id : String
  organization_id : String
  workload_id : String
  quantity : Int64
  consumed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AgreementTemplateState {
  DraftTemplate
  ReadyTemplate
  SupersededTemplate
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct AgreementTemplate {
  template_id : String
  agreement_type : String
  version : String
  locale : String
  effective_unix_ms : Int64
  rendered_document_hash : String
  state : AgreementTemplateState
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ClickwrapAcceptance {
  acceptance_id : String
  idempotency_key : String
  organization_id : String
  user_id : String
  template_id : String
  template_version : String
  rendered_document_hash : String
  intent : String
  presentation_context_hash : String
  network_context_hash : String
  accepted_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum AgreementState {
  DraftAgreement
  InternalReview
  ReadyForSignature
  AwaitingSigner
  PartiallySigned
  AwaitingCountersignature
  Executed
  Declined
  ExpiredAgreement
  Voided
  SupersededAgreement
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Agreement {
  agreement_id : String
  organization_id : String
  template_id : String
  template_version : String
  rendered_document_hash : String
  signer_user_id : String
  signer_authority_ref : String
  external_envelope_ref : String?
  executed_artifact_ref : String?
  executed_artifact_hash : String?
  state : AgreementState
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SignatureCallback {
  callback_id : String
  organization_id : String
  agreement_id : String
  external_envelope_ref : String
  rendered_document_hash : String
  signer_user_id : String
  expected_previous_state : AgreementState
  next_state : AgreementState
  executed_artifact_ref : String?
  executed_artifact_hash : String?
  verified : Bool
  received_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum OrganizationRole {
  OrganizationOwner
  BillingAdministrator
  FinanceViewer
  ProcurementApprover
  LegalSigner
  Deployer
  LeaseAdministrator
  Auditor
  PlatformOperator
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum CommercialPermission {
  ManageOrganization
  ManageCostCenters
  ManageBudgets
  ViewFinance
  ExportFinance
  ApproveCommitment
  SignAgreement
  DeployWorkload
  AdministerLease
  OperatePlatform
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct RoleGrant {
  grant_id : String
  organization_id : String
  user_id : String
  role : OrganizationRole
  granted_by : String
  granted_unix_ms : Int64
  expires_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommercialSummary {
  organization_id : String
  organization_count : Int
  cost_center_count : Int
  project_count : Int
  usage_event_count : Int
  ledger_entry_count : Int
  finalized_period_count : Int
  active_budget_count : Int
  active_commitment_count : Int
  pending_agreement_count : Int
  executed_agreement_count : Int
  provisional_total : FixedMoney
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommercialSnapshot {
  schema_version : String
  organizations : Array[Organization]
  cost_centers : Array[CostCenter]
  projects : Array[Project]
  usage_observations : Array[UsageObservation]
  ledger_entries : Array[LedgerEntry]
  finalized_periods : Array[FinalizedPeriod]
  budgets : Array[Budget]
  quotas : Array[Quota]
  commitments : Array[CapacityCommitment]
  consumptions : Array[EntitlementConsumption]
  agreement_templates : Array[AgreementTemplate]
  clickwrap_acceptances : Array[ClickwrapAcceptance]
  agreements : Array[Agreement]
  role_grants : Array[RoleGrant]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CommercialExport {
  schema_version : String
  organization_id : String
  generated_unix_ms : Int64
  filter_project_id : String?
  csv_content : String
  content_sha256 : String
  row_count : Int
} derive(Debug, Eq, ToJson, FromJson)
