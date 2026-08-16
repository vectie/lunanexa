///|
pub let contract_version : String = "lunanexa.contract-document.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.contract-document.snapshot.v3"

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
} derive(Debug, Eq)

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
/// The lifecycle stage at which a source form may start a new packet. Initial
/// forms open the contract relationship; effective-stage forms follow an
/// already effective packet through `preceding_packet_ref`.
pub(all) enum ContractFormStage {
  InitialStage
  EffectiveStage
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) enum ContractCollectionPolicy {
  PersistedContractData
  PersistedPersonalContact
  CompleteOffline
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct ContractFormDefinition {
  form : ContractFormKind
  title_zh_cn : String
  title_en : String
  field_ids : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct ContractFieldValue {
  field_id : String
  value : String
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct ContractPreviewRow {
  cells : Array[ContractPreviewCell]
  height_twips : Int?
  height_rule : String?
} derive(Debug, Eq, ToJson, FromJson)

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
/// A source marker and its field-free value in a MoonLeaf preview scene.
pub(all) struct ContractPreviewMarker {
  marker : String
  value : String
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct ContractFieldAssignment {
  field_id : String
  value : String
  owner : ContractFieldOwner
  source_ref : String
  updated_by : String
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) enum ContractClosureKind {
  Expired
  EarlyTermination
  Settled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ContractClosure {
  kind : ContractClosureKind
  reason : String
  closed_by : String
  closed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ContractSupersession {
  successor_ref : String
  reason : String
  superseded_by : String
  superseded_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

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
pub(all) struct ContractDocumentSnapshot {
  schema_version : String
  packets : Array[ContractPacket]
  events : Array[ContractPacketEvent]
} derive(Debug, Eq, ToJson, FromJson)
