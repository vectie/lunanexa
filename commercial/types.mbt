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
pub extend CommercialError with Debug::{to_repr}

///|
pub extend CommercialError with Eq::{not_equal, equal}

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
pub(all) enum OrganizationState {
  Draft
  PendingVerification
  Active
  Rejected
  Suspended
  Closed
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OrganizationState with Debug::{to_repr}

///|
pub extend OrganizationState with Eq::{not_equal, equal}

///|
pub extend OrganizationState with ToJson::{to_json}

///|
pub extend OrganizationState with FromJson::{from_json}

///|
pub(all) enum OrganizationSubjectKind {
  Individual
  Company
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OrganizationSubjectKind with Debug::{to_repr}

///|
pub extend OrganizationSubjectKind with Eq::{not_equal, equal}

///|
pub extend OrganizationSubjectKind with ToJson::{to_json}

///|
pub extend OrganizationSubjectKind with FromJson::{from_json}

///|
pub(all) struct BillingContact {
  display_name : String
  email : String
  phone : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend BillingContact with Debug::{to_repr}

///|
pub extend BillingContact with Eq::{not_equal, equal}

///|
pub extend BillingContact with ToJson::{to_json}

///|
pub extend BillingContact with FromJson::{from_json}

///|
pub(all) struct OrganizationLegalProfile {
  subject_kind : OrganizationSubjectKind
  legal_name : String
  country_code : String
  registration_number : String?
  tax_identifier : String?
  registered_address : String
  billing_contact : BillingContact
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OrganizationLegalProfile with Debug::{to_repr}

///|
pub extend OrganizationLegalProfile with Eq::{not_equal, equal}

///|
pub extend OrganizationLegalProfile with ToJson::{to_json}

///|
pub extend OrganizationLegalProfile with FromJson::{from_json}

///|
pub(all) struct Organization {
  organization_id : String
  display_name : String
  state : OrganizationState
  verification_ref : String?
  legal_profile : OrganizationLegalProfile?
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Organization with Debug::{to_repr}

///|
pub extend Organization with Eq::{not_equal, equal}

///|
pub extend Organization with ToJson::{to_json}

///|
pub extend Organization with FromJson::{from_json}

///|
pub(all) struct CostCenter {
  cost_center_id : String
  organization_id : String
  parent_cost_center_id : String?
  display_name : String
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CostCenter with Debug::{to_repr}

///|
pub extend CostCenter with Eq::{not_equal, equal}

///|
pub extend CostCenter with ToJson::{to_json}

///|
pub extend CostCenter with FromJson::{from_json}

///|
pub(all) struct Project {
  project_id : String
  organization_id : String
  cost_center_id : String
  display_name : String
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Project with Debug::{to_repr}

///|
pub extend Project with Eq::{not_equal, equal}

///|
pub extend Project with ToJson::{to_json}

///|
pub extend Project with FromJson::{from_json}

///|
pub(all) struct FixedMoney {
  minor_units : Int64
  currency : String
  scale : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend FixedMoney with Debug::{to_repr}

///|
pub extend FixedMoney with Eq::{not_equal, equal}

///|
pub extend FixedMoney with ToJson::{to_json}

///|
pub extend FixedMoney with FromJson::{from_json}

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
pub extend UsageObservation with Debug::{to_repr}

///|
pub extend UsageObservation with Eq::{not_equal, equal}

///|
pub extend UsageObservation with ToJson::{to_json}

///|
pub extend UsageObservation with FromJson::{from_json}

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
pub extend RateCard with Debug::{to_repr}

///|
pub extend RateCard with Eq::{not_equal, equal}

///|
pub extend RateCard with ToJson::{to_json}

///|
pub extend RateCard with FromJson::{from_json}

///|
pub(all) enum LedgerEntryKind {
  Charge
  Adjustment
  Credit
  Debit
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LedgerEntryKind with Debug::{to_repr}

///|
pub extend LedgerEntryKind with Eq::{not_equal, equal}

///|
pub extend LedgerEntryKind with ToJson::{to_json}

///|
pub extend LedgerEntryKind with FromJson::{from_json}

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
pub extend LedgerEntry with Debug::{to_repr}

///|
pub extend LedgerEntry with Eq::{not_equal, equal}

///|
pub extend LedgerEntry with ToJson::{to_json}

///|
pub extend LedgerEntry with FromJson::{from_json}

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
pub extend FinalizedPeriod with Debug::{to_repr}

///|
pub extend FinalizedPeriod with Eq::{not_equal, equal}

///|
pub extend FinalizedPeriod with ToJson::{to_json}

///|
pub extend FinalizedPeriod with FromJson::{from_json}

///|
pub(all) enum BudgetAction {
  Notify
  RequireApproval
  BlockNewWork
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend BudgetAction with Debug::{to_repr}

///|
pub extend BudgetAction with Eq::{not_equal, equal}

///|
pub extend BudgetAction with ToJson::{to_json}

///|
pub extend BudgetAction with FromJson::{from_json}

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
pub extend Budget with Debug::{to_repr}

///|
pub extend Budget with Eq::{not_equal, equal}

///|
pub extend Budget with ToJson::{to_json}

///|
pub extend Budget with FromJson::{from_json}

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
pub extend Quota with Debug::{to_repr}

///|
pub extend Quota with Eq::{not_equal, equal}

///|
pub extend Quota with ToJson::{to_json}

///|
pub extend Quota with FromJson::{from_json}

///|
pub(all) enum AdmissionDecisionKind {
  Allowed
  ApprovalRequired
  Blocked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AdmissionDecisionKind with Debug::{to_repr}

///|
pub extend AdmissionDecisionKind with Eq::{not_equal, equal}

///|
pub extend AdmissionDecisionKind with ToJson::{to_json}

///|
pub extend AdmissionDecisionKind with FromJson::{from_json}

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
pub extend AdmissionRequest with Debug::{to_repr}

///|
pub extend AdmissionRequest with Eq::{not_equal, equal}

///|
pub extend AdmissionRequest with ToJson::{to_json}

///|
pub extend AdmissionRequest with FromJson::{from_json}

///|
pub(all) struct AdmissionDecision {
  kind : AdmissionDecisionKind
  reasons : Array[String]
  matching_commitment_id : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AdmissionDecision with Debug::{to_repr}

///|
pub extend AdmissionDecision with Eq::{not_equal, equal}

///|
pub extend AdmissionDecision with ToJson::{to_json}

///|
pub extend AdmissionDecision with FromJson::{from_json}

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
pub extend CommitmentState with Debug::{to_repr}

///|
pub extend CommitmentState with Eq::{not_equal, equal}

///|
pub extend CommitmentState with ToJson::{to_json}

///|
pub extend CommitmentState with FromJson::{from_json}

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
pub extend CapacityCommitment with Debug::{to_repr}

///|
pub extend CapacityCommitment with Eq::{not_equal, equal}

///|
pub extend CapacityCommitment with ToJson::{to_json}

///|
pub extend CapacityCommitment with FromJson::{from_json}

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
pub extend EntitlementConsumption with Debug::{to_repr}

///|
pub extend EntitlementConsumption with Eq::{not_equal, equal}

///|
pub extend EntitlementConsumption with ToJson::{to_json}

///|
pub extend EntitlementConsumption with FromJson::{from_json}

///|
pub(all) enum AgreementTemplateState {
  DraftTemplate
  ReadyTemplate
  SupersededTemplate
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AgreementTemplateState with Debug::{to_repr}

///|
pub extend AgreementTemplateState with Eq::{not_equal, equal}

///|
pub extend AgreementTemplateState with ToJson::{to_json}

///|
pub extend AgreementTemplateState with FromJson::{from_json}

///|
pub(all) struct AgreementTemplate {
  template_id : String
  agreement_type : String
  version : String
  locale : String
  effective_unix_ms : Int64
  rendered_document_hash : String
  /// Immutable readable terms. Ready templates require either HTTPS or the
  /// platform-owned `/docs/` namespace; legacy draft snapshots may omit it.
  document_uri : String?
  state : AgreementTemplateState
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AgreementTemplate with Debug::{to_repr}

///|
pub extend AgreementTemplate with Eq::{not_equal, equal}

///|
pub extend AgreementTemplate with ToJson::{to_json}

///|
pub extend AgreementTemplate with FromJson::{from_json}

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
pub extend ClickwrapAcceptance with Debug::{to_repr}

///|
pub extend ClickwrapAcceptance with Eq::{not_equal, equal}

///|
pub extend ClickwrapAcceptance with ToJson::{to_json}

///|
pub extend ClickwrapAcceptance with FromJson::{from_json}

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
pub extend AgreementState with Debug::{to_repr}

///|
pub extend AgreementState with Eq::{not_equal, equal}

///|
pub extend AgreementState with ToJson::{to_json}

///|
pub extend AgreementState with FromJson::{from_json}

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
pub extend Agreement with Debug::{to_repr}

///|
pub extend Agreement with Eq::{not_equal, equal}

///|
pub extend Agreement with ToJson::{to_json}

///|
pub extend Agreement with FromJson::{from_json}

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
pub extend SignatureCallback with Debug::{to_repr}

///|
pub extend SignatureCallback with Eq::{not_equal, equal}

///|
pub extend SignatureCallback with ToJson::{to_json}

///|
pub extend SignatureCallback with FromJson::{from_json}

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
pub extend OrganizationRole with Debug::{to_repr}

///|
pub extend OrganizationRole with Eq::{not_equal, equal}

///|
pub extend OrganizationRole with ToJson::{to_json}

///|
pub extend OrganizationRole with FromJson::{from_json}

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
pub extend CommercialPermission with Debug::{to_repr}

///|
pub extend CommercialPermission with Eq::{not_equal, equal}

///|
pub extend CommercialPermission with ToJson::{to_json}

///|
pub extend CommercialPermission with FromJson::{from_json}

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
pub extend RoleGrant with Debug::{to_repr}

///|
pub extend RoleGrant with Eq::{not_equal, equal}

///|
pub extend RoleGrant with ToJson::{to_json}

///|
pub extend RoleGrant with FromJson::{from_json}

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
pub extend CommercialSummary with Debug::{to_repr}

///|
pub extend CommercialSummary with Eq::{not_equal, equal}

///|
pub extend CommercialSummary with ToJson::{to_json}

///|
pub extend CommercialSummary with FromJson::{from_json}

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
pub extend CommercialSnapshot with Debug::{to_repr}

///|
pub extend CommercialSnapshot with Eq::{not_equal, equal}

///|
pub extend CommercialSnapshot with ToJson::{to_json}

///|
pub extend CommercialSnapshot with FromJson::{from_json}

///|
/// Restart-complete state. Public tenant views continue to use
/// `CommercialSnapshot`; callback payloads stay inside the trusted store.
pub(all) struct CommercialDurableSnapshot {
  schema_version : String
  commercial : CommercialSnapshot
  signature_callbacks : Array[SignatureCallback]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CommercialDurableSnapshot with Debug::{to_repr}

///|
pub extend CommercialDurableSnapshot with Eq::{not_equal, equal}

///|
pub extend CommercialDurableSnapshot with ToJson::{to_json}

///|
pub extend CommercialDurableSnapshot with FromJson::{from_json}

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

///|
pub extend CommercialExport with Debug::{to_repr}

///|
pub extend CommercialExport with Eq::{not_equal, equal}

///|
pub extend CommercialExport with ToJson::{to_json}

///|
pub extend CommercialExport with FromJson::{from_json}
