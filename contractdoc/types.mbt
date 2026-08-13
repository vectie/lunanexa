///|
pub let contract_version : String = "lunanexa.contract-document.v1"

///|
pub let snapshot_schema_version : String = "lunanexa.contract-document.snapshot.v1"

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
pub(all) enum ContractPacketState {
  InformationDraft
  ReadyForConfirmation
  InformationConfirmed
  GenerationRequested
  Generated
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
  active_forms : Array[ContractFormKind]
  values : Array[ContractFieldValue]
  values_sha256 : String?
  confirmed_by : String?
  confirmed_unix_ms : Int64?
  artifacts : Array[ContractGeneratedArtifact]
  state : ContractPacketState
  revision : Int64
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ContractPacketEventKind {
  PacketCreated
  InformationUpdated
  InformationConfirmedEvent
  GenerationRequestedEvent
  GenerationCompletedEvent
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
