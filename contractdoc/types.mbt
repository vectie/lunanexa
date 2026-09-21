///|
pub let contract_version : String = "lunanexa.contract-document.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.contract-document.snapshot.v6"

///|
pub(all) suberror ContractDocumentError {
  InvalidInput(String)
  NotFound(String)
  AlreadyExists(String)
  IdempotencyConflict(String)
  StaleRevision
  InvalidTransition(String)
  MissingRequiredFields(Array[String])
  TemplateMismatch
  ConfirmationMismatch
  ForbiddenSecret(String)
  ContractNotEffective(String)
  ContractNotRenewable(String)
  InvalidEvidence(String)
  InvalidExecutionDate(String)
  SettlementMismatch(String)
  ContractApprovalNotFound(String)
  ContractApprovalSelfDecision(String)
  ContractApprovalAlreadyDecided(String)
} derive(Debug, Eq)

///|
pub extend ContractDocumentError with Debug::{to_repr}

///|
pub extend ContractDocumentError with Eq::{not_equal, equal}

///|
pub(all) enum ContractFormKind {
  MasterLease
  ReservationApplication
  AccessConfirmation
  ViolationNotice
  DamageAssessment
  SettlementConfirmation
  EarlyTerminationApplication
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFormKind with Debug::{to_repr}

///|
pub extend ContractFormKind with Eq::{not_equal, equal}

///|
pub extend ContractFormKind with ToJson::{to_json}

///|
pub extend ContractFormKind with FromJson::{from_json}

///|
/// The lifecycle stage at which a source form may start a new packet. Initial
/// forms open the contract relationship; effective-stage forms follow an
/// already effective packet through `preceding_packet_ref`.
pub(all) enum ContractFormStage {
  InitialStage
  EffectiveStage
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFormStage with Debug::{to_repr}

///|
pub extend ContractFormStage with Eq::{not_equal, equal}

///|
pub extend ContractFormStage with ToJson::{to_json}

///|
pub extend ContractFormStage with FromJson::{from_json}

///|
pub(all) enum ContractFieldKind {
  PlainText
  Identifier
  CalendarDate
  WholeNumber
  MoneyAmount
  MoneyUppercase
  Choice
  MultilineText
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFieldKind with Debug::{to_repr}

///|
pub extend ContractFieldKind with Eq::{not_equal, equal}

///|
pub extend ContractFieldKind with ToJson::{to_json}

///|
pub extend ContractFieldKind with FromJson::{from_json}

///|
pub(all) enum ContractCollectionPolicy {
  PersistedContractData
  PersistedPersonalContact
  CompleteOffline
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractCollectionPolicy with Debug::{to_repr}

///|
pub extend ContractCollectionPolicy with Eq::{not_equal, equal}

///|
pub extend ContractCollectionPolicy with ToJson::{to_json}

///|
pub extend ContractCollectionPolicy with FromJson::{from_json}

///|
/// Declares who owns the authoritative value for one source-document slot.
/// `PlatformDerived` values are copied from durable LunaNexa authorities and
/// are never editable in either browser. `OfflineParticipant` values remain
/// outside the online packet entirely.
pub(all) enum ContractFieldOwner {
  CustomerMessenger
  ManagerOperator
  PlatformDerived
  OfflineParticipant
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFieldOwner with Debug::{to_repr}

///|
pub extend ContractFieldOwner with Eq::{not_equal, equal}

///|
pub extend ContractFieldOwner with ToJson::{to_json}

///|
pub extend ContractFieldOwner with FromJson::{from_json}

///|
pub(all) struct ContractFieldDefinition {
  field_id : String
  form : ContractFormKind
  label_zh_cn : String
  label_en : String
  kind : ContractFieldKind
  required : Bool
  maximum_characters : Int
  allowed_values : Array[String]
  collection_policy : ContractCollectionPolicy
  owner : ContractFieldOwner
  locator : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFieldDefinition with Debug::{to_repr}

///|
pub extend ContractFieldDefinition with Eq::{not_equal, equal}

///|
pub extend ContractFieldDefinition with ToJson::{to_json}

///|
pub extend ContractFieldDefinition with FromJson::{from_json}

///|
pub(all) struct ContractFormDefinition {
  form : ContractFormKind
  title_zh_cn : String
  title_en : String
  field_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFormDefinition with Debug::{to_repr}

///|
pub extend ContractFormDefinition with Eq::{not_equal, equal}

///|
pub extend ContractFormDefinition with ToJson::{to_json}

///|
pub extend ContractFormDefinition with FromJson::{from_json}

///|
pub(all) struct ContractTemplateManifest {
  contract_version : String
  collection_id : String
  template_id : String
  template_version : String
  locale : String
  filename : String
  media_type : String
  sha256 : String
  fillable_filename : String
  fillable_sha256 : String
  byte_count : Int64
  page_count : Int
  section_count : Int
  forms : Array[ContractFormDefinition]
  fields : Array[ContractFieldDefinition]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractTemplateManifest with Debug::{to_repr}

///|
pub extend ContractTemplateManifest with Eq::{not_equal, equal}

///|
pub extend ContractTemplateManifest with ToJson::{to_json}

///|
pub extend ContractTemplateManifest with FromJson::{from_json}

///|
pub(all) struct ContractFieldValue {
  field_id : String
  value : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFieldValue with Debug::{to_repr}

///|
pub extend ContractFieldValue with Eq::{not_equal, equal}

///|
pub extend ContractFieldValue with ToJson::{to_json}

///|
pub extend ContractFieldValue with FromJson::{from_json}

///|
/// One styled text run produced by MoonLeaf's neutral DOCX scene.
pub(all) struct ContractPreviewRun {
  text : String
  bold : Bool
  italic : Bool
  underline : Bool
  font_size_half_points : Int?
  color : String?
  font_ascii : String?
  font_east_asia : String?
  font_complex_script : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewRun with Debug::{to_repr}

///|
pub extend ContractPreviewRun with Eq::{not_equal, equal}

///|
pub extend ContractPreviewRun with ToJson::{to_json}

///|
pub extend ContractPreviewRun with FromJson::{from_json}

///|
pub(all) struct ContractPreviewParagraph {
  runs : Array[ContractPreviewRun]
  alignment : String?
  spacing_before_twips : Int?
  spacing_after_twips : Int?
  line_twips : Int?
  line_rule : String?
  left_indent_twips : Int?
  right_indent_twips : Int?
  first_line_twips : Int?
  hanging_twips : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewParagraph with Debug::{to_repr}

///|
pub extend ContractPreviewParagraph with Eq::{not_equal, equal}

///|
pub extend ContractPreviewParagraph with ToJson::{to_json}

///|
pub extend ContractPreviewParagraph with FromJson::{from_json}

///|
pub(all) struct ContractPreviewCell {
  text : String
  paragraphs : Array[ContractPreviewParagraph]
  grid_span : Int
  vertical_merge : String?
  width_twips : Int?
  margin_top_twips : Int?
  margin_right_twips : Int?
  margin_bottom_twips : Int?
  margin_left_twips : Int?
  vertical_alignment : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewCell with Debug::{to_repr}

///|
pub extend ContractPreviewCell with Eq::{not_equal, equal}

///|
pub extend ContractPreviewCell with ToJson::{to_json}

///|
pub extend ContractPreviewCell with FromJson::{from_json}

///|
pub(all) struct ContractPreviewRow {
  cells : Array[ContractPreviewCell]
  height_twips : Int?
  height_rule : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewRow with Debug::{to_repr}

///|
pub extend ContractPreviewRow with Eq::{not_equal, equal}

///|
pub extend ContractPreviewRow with ToJson::{to_json}

///|
pub extend ContractPreviewRow with FromJson::{from_json}

///| A provider-neutral MoonLeaf block. `kind` is one of paragraph, heading,

///|
/// list-item, or table. Table cells preserve source text and line breaks.
pub(all) struct ContractPreviewBlock {
  kind : String
  level : Int
  ordered : Bool
  runs : Array[ContractPreviewRun]
  rows : Array[ContractPreviewRow]
  alignment : String?
  spacing_before_twips : Int?
  spacing_after_twips : Int?
  line_twips : Int?
  line_rule : String?
  left_indent_twips : Int?
  right_indent_twips : Int?
  first_line_twips : Int?
  hanging_twips : Int?
  grid_widths_twips : Array[Int]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewBlock with Debug::{to_repr}

///|
pub extend ContractPreviewBlock with Eq::{not_equal, equal}

///|
pub extend ContractPreviewBlock with ToJson::{to_json}

///|
pub extend ContractPreviewBlock with FromJson::{from_json}

///| Bounded live preview derived from the authoritative fillable DOCX by

///|
/// MoonLeaf. This is a semantic scene, not a raster or invented reflow.
pub(all) struct ContractPreviewDocument {
  engine : String
  packet_id : String
  packet_revision : Int64
  form : ContractFormKind
  blocks : Array[ContractPreviewBlock]
  pages : Array[Array[ContractPreviewBlock]]
  diagnostic_codes : Array[String]
  page_width_twips : Int?
  page_height_twips : Int?
  margin_top_twips : Int?
  margin_right_twips : Int?
  margin_bottom_twips : Int?
  margin_left_twips : Int?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewDocument with Debug::{to_repr}

///|
pub extend ContractPreviewDocument with Eq::{not_equal, equal}

///|
pub extend ContractPreviewDocument with ToJson::{to_json}

///|
pub extend ContractPreviewDocument with FromJson::{from_json}

///|
/// A source marker and its field-free value in a MoonLeaf preview scene.
pub(all) struct ContractPreviewMarker {
  marker : String
  value : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewMarker with Debug::{to_repr}

///|
pub extend ContractPreviewMarker with Eq::{not_equal, equal}

///|
pub extend ContractPreviewMarker with ToJson::{to_json}

///|
pub extend ContractPreviewMarker with FromJson::{from_json}

///|
/// A build-time MoonLeaf scene used only when the browser runs in demo mode.
/// The scene is generated from the same authoritative DOCX as live previews.
pub(all) struct ContractPreviewTemplate {
  template_id : String
  template_version : String
  template_sha256 : String
  scene : ContractPreviewDocument
  /// The owning form for every physical page in `scene.pages`.
  ///
  /// This is emitted by MoonLeaf from the declared source-form headings. It
  /// lets the browser select one source contract without relying on a second
  /// template, a hard-coded page-number table, or browser reflow.
  page_forms : Array[ContractFormKind]
  marker_defaults : Array[ContractPreviewMarker]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPreviewTemplate with Debug::{to_repr}

///|
pub extend ContractPreviewTemplate with Eq::{not_equal, equal}

///|
pub extend ContractPreviewTemplate with ToJson::{to_json}

///|
pub extend ContractPreviewTemplate with FromJson::{from_json}

///|
pub(all) struct ContractFieldAssignment {
  field_id : String
  value : String
  owner : ContractFieldOwner
  source_ref : String
  updated_by : String
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractFieldAssignment with Debug::{to_repr}

///|
pub extend ContractFieldAssignment with Eq::{not_equal, equal}

///|
pub extend ContractFieldAssignment with ToJson::{to_json}

///|
pub extend ContractFieldAssignment with FromJson::{from_json}

///|
pub(all) struct ContractCompletionSummary {
  customer_required : Int
  customer_completed : Int
  operator_required : Int
  operator_completed : Int
  system_required : Int
  system_completed : Int
  offline_fields : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractCompletionSummary with Debug::{to_repr}

///|
pub extend ContractCompletionSummary with Eq::{not_equal, equal}

///|
pub extend ContractCompletionSummary with ToJson::{to_json}

///|
pub extend ContractCompletionSummary with FromJson::{from_json}

///|
pub(all) enum ContractPacketState {
  InformationDraft
  ReadyForConfirmation
  InformationConfirmed
  GenerationRequested
  Generated
  GenerationFailed
  Effective
  Closed
  Superseded
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPacketState with Debug::{to_repr}

///|
pub extend ContractPacketState with Eq::{not_equal, equal}

///|
pub extend ContractPacketState with ToJson::{to_json}

///|
pub extend ContractPacketState with FromJson::{from_json}

///|
pub(all) struct ContractGeneratedArtifact {
  artifact_id : String
  media_type : String
  sha256 : String
  byte_count : Int64
  page_count : Int
  render_evidence_sha256 : String
  generated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractGeneratedArtifact with Debug::{to_repr}

///|
pub extend ContractGeneratedArtifact with Eq::{not_equal, equal}

///|
pub extend ContractGeneratedArtifact with ToJson::{to_json}

///|
pub extend ContractGeneratedArtifact with FromJson::{from_json}

///|
/// Registered evidence of the offline signed and stamped contract. Signing
/// stays offline by design; the platform only records the digest of the
/// stamped scan, the signing date, and the operator who registered it.
pub(all) struct ContractExecution {
  evidence_sha256 : String
  signed_on : String
  registered_by : String
  registered_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractExecution with Debug::{to_repr}

///|
pub extend ContractExecution with Eq::{not_equal, equal}

///|
pub extend ContractExecution with ToJson::{to_json}

///|
pub extend ContractExecution with FromJson::{from_json}

///|
pub(all) enum ContractClosureKind {
  Expired
  EarlyTermination
  Settled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractClosureKind with Debug::{to_repr}

///|
pub extend ContractClosureKind with Eq::{not_equal, equal}

///|
pub extend ContractClosureKind with ToJson::{to_json}

///|
pub extend ContractClosureKind with FromJson::{from_json}

///|
pub(all) struct ContractClosure {
  kind : ContractClosureKind
  reason : String
  closed_by : String
  closed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractClosure with Debug::{to_repr}

///|
pub extend ContractClosure with Eq::{not_equal, equal}

///|
pub extend ContractClosure with ToJson::{to_json}

///|
pub extend ContractClosure with FromJson::{from_json}

///|
pub(all) struct ContractSupersession {
  successor_ref : String
  reason : String
  superseded_by : String
  superseded_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractSupersession with Debug::{to_repr}

///|
pub extend ContractSupersession with Eq::{not_equal, equal}

///|
pub extend ContractSupersession with ToJson::{to_json}

///|
pub extend ContractSupersession with FromJson::{from_json}

///|
pub(all) struct ContractPacket {
  packet_id : String
  idempotency_key : String
  template_id : String
  template_version : String
  template_sha256 : String
  tenant_ref : String
  organization_id : String
  subject_ref : String
  order_ref : String
  preceding_packet_ref : String?
  active_forms : Array[ContractFormKind]
  values : Array[ContractFieldValue]
  assignments : Array[ContractFieldAssignment]
  values_sha256 : String?
  confirmed_by : String?
  confirmed_unix_ms : Int64?
  artifacts : Array[ContractGeneratedArtifact]
  state : ContractPacketState
  execution : ContractExecution?
  closure : ContractClosure?
  supersession : ContractSupersession?
  generation_failure : String?
  revision : Int64
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPacket with Debug::{to_repr}

///|
pub extend ContractPacket with Eq::{not_equal, equal}

///|
pub extend ContractPacket with ToJson::{to_json}

///|
pub extend ContractPacket with FromJson::{from_json}

///|
pub(all) enum ContractPacketEventKind {
  PacketCreated
  InformationUpdated
  SystemInformationSynchronized
  InformationConfirmedEvent
  GenerationRequestedEvent
  GenerationCompletedEvent
  GenerationFailedEvent
  ExecutionRegisteredEvent
  PacketClosedEvent
  PacketSupersededEvent
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPacketEventKind with Debug::{to_repr}

///|
pub extend ContractPacketEventKind with Eq::{not_equal, equal}

///|
pub extend ContractPacketEventKind with ToJson::{to_json}

///|
pub extend ContractPacketEventKind with FromJson::{from_json}

///| Values are deliberately absent: audit records field identifiers and

///|
/// digests, never names, addresses, phone numbers, contract prose, or secrets.
pub(all) struct ContractPacketEvent {
  event_id : String
  packet_id : String
  revision : Int64
  kind : ContractPacketEventKind
  actor_ref : String
  changed_field_ids : Array[String]
  values_sha256 : String?
  artifact_sha256 : String?
  occurred_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractPacketEvent with Debug::{to_repr}

///|
pub extend ContractPacketEvent with Eq::{not_equal, equal}

///|
pub extend ContractPacketEvent with ToJson::{to_json}

///|
pub extend ContractPacketEvent with FromJson::{from_json}

///|
pub(all) enum ContractApprovalStatus {
  Pending
  Approved
  Applied
  Rejected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractApprovalStatus with Debug::{to_repr}

///|
pub extend ContractApprovalStatus with Eq::{not_equal, equal}

///|
pub extend ContractApprovalStatus with ToJson::{to_json}

///|
pub extend ContractApprovalStatus with FromJson::{from_json}

///|
/// A controlled change to an effective packet. The original packet remains
/// immutable; an amendment becomes the next contractual version only after
/// its own approval/effectivity fence is satisfied.
pub(all) enum ContractAmendmentState {
  Draft
  PendingApproval
  Effective
  Superseded
  Rejected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractAmendmentState with Debug::{to_repr}

///|
pub extend ContractAmendmentState with Eq::{not_equal, equal}

///|
pub extend ContractAmendmentState with ToJson::{to_json}

///|
pub extend ContractAmendmentState with FromJson::{from_json}

///|
pub(all) struct ContractAmendment {
  amendment_id : String
  tenant_ref : String
  packet_id : String
  preceding_packet_ref : String
  base_revision : Int64
  changes : Array[ContractFieldValue]
  reason : String
  state : ContractAmendmentState
  effective_unix_ms : Int64?
  created_by : String
  created_unix_ms : Int64
  updated_unix_ms : Int64
  revision : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractAmendment with Debug::{to_repr}

///|
pub extend ContractAmendment with Eq::{not_equal, equal}

///|
pub extend ContractAmendment with ToJson::{to_json}

///|
pub extend ContractAmendment with FromJson::{from_json}

///|
/// Durable payment and acceptance obligations are separate from form text.
pub(all) enum ContractObligationKind {
  PaymentMilestone
  Acceptance
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractObligationKind with Debug::{to_repr}

///|
pub extend ContractObligationKind with Eq::{not_equal, equal}

///|
pub extend ContractObligationKind with ToJson::{to_json}

///|
pub extend ContractObligationKind with FromJson::{from_json}

///|
pub(all) enum ContractObligationState {
  Open
  Completed
  Overdue
  Waived
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractObligationState with Debug::{to_repr}

///|
pub extend ContractObligationState with Eq::{not_equal, equal}

///|
pub extend ContractObligationState with ToJson::{to_json}

///|
pub extend ContractObligationState with FromJson::{from_json}

///|
pub(all) struct ContractObligation {
  obligation_id : String
  tenant_ref : String
  packet_id : String
  kind : ContractObligationKind
  title : String
  owner_ref : String
  due_unix_ms : Int64
  amount_minor_units : Int64?
  state : ContractObligationState
  evidence_ref : String?
  completed_by : String?
  completed_unix_ms : Int64?
  /// The named operator who created the durable obligation. Legacy v5 records
  /// migrate with `None`; every v6 write records `Some(operator_id)`.
  created_by : String?
  created_unix_ms : Int64
  updated_unix_ms : Int64
  revision : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractObligation with Debug::{to_repr}

///|
pub extend ContractObligation with Eq::{not_equal, equal}

///|
pub extend ContractObligation with ToJson::{to_json}

///|
pub extend ContractObligation with FromJson::{from_json}

///|
pub(all) enum ContractProposalState {
  Draft
  PendingApproval
  Approved
  Rejected
  Applied
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractProposalState with Debug::{to_repr}

///|
pub extend ContractProposalState with Eq::{not_equal, equal}

///|
pub extend ContractProposalState with ToJson::{to_json}

///|
pub extend ContractProposalState with FromJson::{from_json}

///|
pub(all) struct ContractSettlementDraft {
  draft_id : String
  packet_id : String
  tenant_ref : String
  ledger_snapshot_sha256 : String
  amount_minor_units : Int64
  state : ContractProposalState
  created_by : String
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractSettlementDraft with Debug::{to_repr}

///|
pub extend ContractSettlementDraft with Eq::{not_equal, equal}

///|
pub extend ContractSettlementDraft with ToJson::{to_json}

///|
pub extend ContractSettlementDraft with FromJson::{from_json}

///|
pub(all) struct ContractClosureProposal {
  proposal_id : String
  packet_id : String
  tenant_ref : String
  violation_packet_ref : String
  reason : String
  state : ContractProposalState
  created_by : String
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractClosureProposal with Debug::{to_repr}

///|
pub extend ContractClosureProposal with Eq::{not_equal, equal}

///|
pub extend ContractClosureProposal with ToJson::{to_json}

///|
pub extend ContractClosureProposal with FromJson::{from_json}

///|
/// Server-owned, tenant-scoped contract number allocation.
pub(all) struct ContractNumber {
  number : String
  tenant_ref : String
  packet_id : String
  sequence : Int64
  issued_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractNumber with Debug::{to_repr}

///|
pub extend ContractNumber with Eq::{not_equal, equal}

///|
pub extend ContractNumber with ToJson::{to_json}

///|
pub extend ContractNumber with FromJson::{from_json}

///|
/// A deterministic read model for the operator business dashboard.
pub(all) struct ContractGovernanceDashboard {
  tenant_ref : String
  effective_packets : Int
  pending_approvals : Int
  overdue_obligations : Int
  open_closure_proposals : Int
  total_amount_minor_units : Int64
  next_expiry_unix_ms : Int64?
  generated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractGovernanceDashboard with Debug::{to_repr}

///|
pub extend ContractGovernanceDashboard with Eq::{not_equal, equal}

///|
pub extend ContractGovernanceDashboard with ToJson::{to_json}

///|
pub extend ContractGovernanceDashboard with FromJson::{from_json}

///|
/// One admission projection consumed by key, workspace, and machine clients.
pub(all) struct ContractAdmissionView {
  tenant_ref : String
  subject_ref : String
  effective_master_lease : Bool
  api_key_issuance_allowed : Bool
  workspace_admission_configured : Bool
  exclusive_lease_present : Bool
  evaluated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractAdmissionView with Debug::{to_repr}

///|
pub extend ContractAdmissionView with Eq::{not_equal, equal}

///|
pub extend ContractAdmissionView with ToJson::{to_json}

///|
pub extend ContractAdmissionView with FromJson::{from_json}

///|
/// The recorded intent of a pending approval. Execution registrations carry
/// the evidence digest and signing date; closures carry the kind and reason.
pub(all) struct ContractApprovalPayload {
  evidence_sha256 : String?
  signed_on : String?
  kind : ContractClosureKind?
  reason : String?
  /// Immutable commercial amount captured when approval was requested.
  amount_minor_units : Int64?
  /// Digest of the packet values reviewed by the initiator. It allows the
  /// second operator to compare a frozen fact rather than a mutable browser
  /// projection. Legacy v5 approvals migrate with `None`.
  packet_values_sha256 : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractApprovalPayload with Debug::{to_repr}

///|
pub extend ContractApprovalPayload with Eq::{not_equal, equal}

///|
pub extend ContractApprovalPayload with ToJson::{to_json}

///|
pub extend ContractApprovalPayload with FromJson::{from_json}

///|
/// A durable four-eyes approval for a high-value lifecycle action. The
/// initiator requests the transition; a different operator decides it. The
/// recorded `expected_revision` fences the decision: the transition re-runs
/// against the packet's current state at decision time.
pub(all) struct ContractApproval {
  approval_id : String
  packet_id : String
  /// `"execute"` or `"close:<kind>"`.
  action : String
  expected_revision : Int64
  payload : ContractApprovalPayload
  initiator : String
  created_unix_ms : Int64
  status : ContractApprovalStatus
  decided_by : String?
  decided_unix_ms : Int64?
  decision_reason : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractApproval with Debug::{to_repr}

///|
pub extend ContractApproval with Eq::{not_equal, equal}

///|
pub extend ContractApproval with ToJson::{to_json}

///|
pub extend ContractApproval with FromJson::{from_json}

///|
pub(all) struct ContractDocumentSnapshot {
  schema_version : String
  packets : Array[ContractPacket]
  events : Array[ContractPacketEvent]
  approvals : Array[ContractApproval]
  amendments : Array[ContractAmendment]
  obligations : Array[ContractObligation]
  settlement_drafts : Array[ContractSettlementDraft]
  closure_proposals : Array[ContractClosureProposal]
  numbers : Array[ContractNumber]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ContractDocumentSnapshot with Debug::{to_repr}

///|
pub extend ContractDocumentSnapshot with Eq::{not_equal, equal}

///|
pub extend ContractDocumentSnapshot with ToJson::{to_json}

///|
pub extend ContractDocumentSnapshot with FromJson::{from_json}
