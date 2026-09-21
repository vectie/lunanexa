///|
pub let contract_version : String = "lunanexa.enterprise-portal.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.enterprise-portal.snapshot.v1"

///|
pub(all) enum EnterpriseRole {
  OrganizationAdministrator
  LegalSigner
  LeaseRequester
  BillingViewer
  Developer
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend EnterpriseRole with Debug::{to_repr}

///|
pub extend EnterpriseRole with Eq::{not_equal, equal}

///|
pub extend EnterpriseRole with ToJson::{to_json}

///|
pub extend EnterpriseRole with FromJson::{from_json}

///|
pub(all) struct EnterpriseMembership {
  membership_id : String
  tenant_ref : String
  organization_id : String
  subject_ref : String
  roles : Array[EnterpriseRole]
  active : Bool
  created_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend EnterpriseMembership with Debug::{to_repr}

///|
pub extend EnterpriseMembership with Eq::{not_equal, equal}

///|
pub extend EnterpriseMembership with ToJson::{to_json}

///|
pub extend EnterpriseMembership with FromJson::{from_json}

///|
pub(all) enum PortalAgreementState {
  ReviewRequired
  SignatureRequested
  Executed
  Declined
  Superseded
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PortalAgreementState with Debug::{to_repr}

///|
pub extend PortalAgreementState with Eq::{not_equal, equal}

///|
pub extend PortalAgreementState with ToJson::{to_json}

///|
pub extend PortalAgreementState with FromJson::{from_json}

///|
pub(all) struct PortalAgreement {
  agreement_id : String
  tenant_ref : String
  organization_id : String
  template_ref : String
  title : String
  summary : String
  rendered_document_hash : String
  state : PortalAgreementState
  generation : Int64
  signer_subject_ref : String?
  signature_request_receipt : String?
  executed_artifact_hash : String?
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PortalAgreement with Debug::{to_repr}

///|
pub extend PortalAgreement with Eq::{not_equal, equal}

///|
pub extend PortalAgreement with ToJson::{to_json}

///|
pub extend PortalAgreement with FromJson::{from_json}

///|
pub(all) struct SignatureRequest {
  agreement_id : String
  expected_generation : Int64
  idempotency_key : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend SignatureRequest with Debug::{to_repr}

///|
pub extend SignatureRequest with Eq::{not_equal, equal}

///|
pub extend SignatureRequest with ToJson::{to_json}

///|
pub extend SignatureRequest with FromJson::{from_json}

///|
pub(all) struct AgreementExecution {
  agreement_id : String
  expected_generation : Int64
  signer_subject_ref : String
  executed_artifact_hash : String
  evidence_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AgreementExecution with Debug::{to_repr}

///|
pub extend AgreementExecution with Eq::{not_equal, equal}

///|
pub extend AgreementExecution with ToJson::{to_json}

///|
pub extend AgreementExecution with FromJson::{from_json}

///|
pub(all) enum LeaseRequestState {
  Submitted
  Approved
  Rejected
  Cancelled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LeaseRequestState with Debug::{to_repr}

///|
pub extend LeaseRequestState with Eq::{not_equal, equal}

///|
pub extend LeaseRequestState with ToJson::{to_json}

///|
pub extend LeaseRequestState with FromJson::{from_json}

///|
pub(all) struct LeaseRequestSubmission {
  request_id : String
  idempotency_key : String
  tenant_ref : String
  organization_id : String
  project_id : String
  unix_username : String
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  requested_model_ids : Array[String]
  justification : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LeaseRequestSubmission with Debug::{to_repr}

///|
pub extend LeaseRequestSubmission with Eq::{not_equal, equal}

///|
pub extend LeaseRequestSubmission with ToJson::{to_json}

///|
pub extend LeaseRequestSubmission with FromJson::{from_json}

///|
pub(all) struct EnterpriseLeaseRequest {
  submission : LeaseRequestSubmission
  subject_ref : String
  state : LeaseRequestState
  generation : Int64
  assigned_node_id : String?
  exclusive_lease_id : String?
  decision_receipt : String?
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend EnterpriseLeaseRequest with Debug::{to_repr}

///|
pub extend EnterpriseLeaseRequest with Eq::{not_equal, equal}

///|
pub extend EnterpriseLeaseRequest with ToJson::{to_json}

///|
pub extend EnterpriseLeaseRequest with FromJson::{from_json}

///|
pub(all) enum LeaseReviewDecision {
  Approve
  Reject
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LeaseReviewDecision with Debug::{to_repr}

///|
pub extend LeaseReviewDecision with Eq::{not_equal, equal}

///|
pub extend LeaseReviewDecision with ToJson::{to_json}

///|
pub extend LeaseReviewDecision with FromJson::{from_json}

///|
pub(all) struct LeaseReview {
  request_id : String
  expected_generation : Int64
  decision : LeaseReviewDecision
  node_id : String?
  evidence_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend LeaseReview with Debug::{to_repr}

///|
pub extend LeaseReview with Eq::{not_equal, equal}

///|
pub extend LeaseReview with ToJson::{to_json}

///|
pub extend LeaseReview with FromJson::{from_json}

///|
pub(all) struct PortalSnapshot {
  schema_version : String
  memberships : Array[EnterpriseMembership]
  agreements : Array[PortalAgreement]
  lease_requests : Array[EnterpriseLeaseRequest]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PortalSnapshot with Debug::{to_repr}

///|
pub extend PortalSnapshot with Eq::{not_equal, equal}

///|
pub extend PortalSnapshot with ToJson::{to_json}

///|
pub extend PortalSnapshot with FromJson::{from_json}

///|
pub(all) struct EnterpriseSelfView {
  version : String
  membership : EnterpriseMembership
  agreements : Array[PortalAgreement]
  lease_requests : Array[EnterpriseLeaseRequest]
  can_sign : Bool
  can_request_lease : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend EnterpriseSelfView with Debug::{to_repr}

///|
pub extend EnterpriseSelfView with Eq::{not_equal, equal}

///|
pub extend EnterpriseSelfView with ToJson::{to_json}

///|
pub extend EnterpriseSelfView with FromJson::{from_json}

///|
/// Tenant-safe projection of the central model registry. Artifact URIs,
/// signature references, node topology and runtime credentials are omitted.
pub(all) struct EnterpriseModelSummary {
  model_id : String
  version : String
  alias_name : String?
  compatible_architectures : Array[String]
  minimum_memory_mib : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend EnterpriseModelSummary with Debug::{to_repr}

///|
pub extend EnterpriseModelSummary with Eq::{not_equal, equal}

///|
pub extend EnterpriseModelSummary with ToJson::{to_json}

///|
pub extend EnterpriseModelSummary with FromJson::{from_json}

///|
pub(all) suberror PortalError {
  InvalidInput(String)
  NotFound(String)
  AlreadyExists(String)
  Unauthorized(String)
  OrganizationSelectionRequired
  TenantMismatch
  IdempotencyConflict(String)
  InvalidTransition(String)
  StaleGeneration
  AgreementRequired
} derive(Debug, Eq)

///|
pub extend PortalError with Debug::{to_repr}

///|
pub extend PortalError with Eq::{not_equal, equal}
