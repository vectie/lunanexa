///|
fn unique_forms(forms : Array[ContractFormKind]) -> Bool {
  let seen : Array[ContractFormKind] = []
  for form in forms {
    if seen.contains(form) {
      return false
    }
    seen.push(form)
  }
  true
}

///|
pub fn new_packet(
  manifest : ContractTemplateManifest,
  packet_id : String,
  idempotency_key : String,
  tenant_ref : String,
  organization_id : String,
  subject_ref : String,
  order_ref : String,
  active_forms : Array[ContractFormKind],
  now_unix_ms : Int64,
) -> ContractPacket raise ContractDocumentError {
  validate_manifest(manifest)
  if !valid_identifier(packet_id) ||
    !valid_identifier(idempotency_key) ||
    !valid_identifier(tenant_ref) ||
    !valid_identifier(organization_id) ||
    !valid_identifier(subject_ref) ||
    !valid_identifier(order_ref) ||
    active_forms.length() == 0 ||
    !unique_forms(active_forms) ||
    active_forms.any(form => !manifest.forms.any(item => item.form == form)) ||
    now_unix_ms <= 0L {
    raise InvalidInput("invalid contract packet")
  }
  {
    packet_id,
    idempotency_key,
    template_id: manifest.template_id,
    template_version: manifest.template_version,
    template_sha256: manifest.sha256,
    tenant_ref,
    organization_id,
    subject_ref,
    order_ref,
    active_forms,
    values: [],
    assignments: [],
    values_sha256: None,
    confirmed_by: None,
    confirmed_unix_ms: None,
    artifacts: [],
    state: InformationDraft,
    revision: 1L,
    created_unix_ms: now_unix_ms,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn ContractPacket::update_information(
  self : ContractPacket,
  manifest : ContractTemplateManifest,
  expected_revision : Int64,
  changes : Array[ContractFieldValue],
  actor_owner : ContractFieldOwner,
  actor_ref : String,
  source_ref : String,
  now_unix_ms : Int64,
) -> ContractPacket raise ContractDocumentError {
  if self.revision != expected_revision {
    raise StaleRevision
  }
  if self.template_id != manifest.template_id ||
    self.template_version != manifest.template_version ||
    self.template_sha256 != manifest.sha256 {
    raise TemplateMismatch
  }
  if self.state == GenerationRequested ||
    self.state == Generated ||
    self.state == Superseded {
    raise InvalidTransition("contract packet is not editable")
  }
  if changes.length() == 0 || changes.length() > 256 {
    raise InvalidInput("contract information update is empty or too large")
  }
  if actor_owner == OfflineParticipant ||
    !valid_identifier(actor_ref) ||
    !valid_identifier(source_ref) {
    raise InvalidInput("invalid contract information authority")
  }
  let values : Map[String, String] = Map([])
  let assignments : Map[String, ContractFieldAssignment] = Map([])
  for existing in self.values {
    values[existing.field_id] = existing.value
  }
  for existing in self.assignments {
    assignments[existing.field_id] = existing
  }
  let seen : Map[String, Unit] = Map([])
  for change in changes {
    guard manifest.field(change.field_id) is Some(definition) &&
      self.active_forms.contains(definition.form) else {
      raise InvalidInput("contract field is outside the active packet")
    }
    if definition.collection_policy == CompleteOffline {
      raise ForbiddenSecret(definition.field_id)
    }
    if definition.owner != actor_owner ||
      (
        !definition.owner.can_edit(actor_owner) &&
        actor_owner != PlatformDerived
      ) {
      raise InvalidInput("contract field is owned by another participant")
    }
    if seen.contains(change.field_id) {
      raise InvalidInput("contract update repeats a field")
    }
    seen[change.field_id] = ()
    validate_field_value(definition, change.value)
    if change.value.trim() == "" {
      values.remove(change.field_id)
      assignments.remove(change.field_id)
    } else {
      values[change.field_id] = change.value
      assignments[change.field_id] = {
        field_id: change.field_id,
        value: change.value,
        owner: definition.owner,
        source_ref,
        updated_by: actor_ref,
        updated_unix_ms: now_unix_ms,
      }
    }
  }
  let updated_values = values
    .to_array()
    .map(pair => { field_id: pair.0, value: pair.1 })
  updated_values.sort_by((left, right) => left.field_id.compare(right.field_id))
  let updated_assignments = assignments.to_array().map(pair => pair.1)
  updated_assignments.sort_by((left, right) => {
    left.field_id.compare(right.field_id)
  })
  let draft = {
    ..self,
    values: updated_values,
    assignments: updated_assignments,
    values_sha256: None,
    confirmed_by: None,
    confirmed_unix_ms: None,
    state: InformationDraft,
    revision: self.revision + 1L,
    updated_unix_ms: now_unix_ms,
  }
  if missing_required_fields(manifest, draft).length() == 0 {
    { ..draft, state: ReadyForConfirmation }
  } else {
    draft
  }
}

///|
pub fn ContractPacket::confirm_information(
  self : ContractPacket,
  manifest : ContractTemplateManifest,
  expected_revision : Int64,
  values_sha256 : String,
  actor_ref : String,
  now_unix_ms : Int64,
) -> ContractPacket raise ContractDocumentError {
  if self.revision != expected_revision {
    raise StaleRevision
  }
  if self.state != ReadyForConfirmation {
    raise InvalidTransition("contract packet is not ready for confirmation")
  }
  let missing = missing_required_fields(manifest, self)
  if missing.length() > 0 {
    raise MissingRequiredFields(missing)
  }
  if !valid_sha256(values_sha256) || !valid_identifier(actor_ref) {
    raise InvalidInput("invalid contract confirmation")
  }
  {
    ..self,
    values_sha256: Some(values_sha256),
    confirmed_by: Some(actor_ref),
    confirmed_unix_ms: Some(now_unix_ms),
    state: InformationConfirmed,
    revision: self.revision + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn ContractPacket::request_generation(
  self : ContractPacket,
  expected_revision : Int64,
  expected_values_sha256 : String,
  now_unix_ms : Int64,
) -> ContractPacket raise ContractDocumentError {
  if self.revision != expected_revision {
    raise StaleRevision
  }
  if self.state != InformationConfirmed ||
    self.values_sha256 != Some(expected_values_sha256) {
    raise ConfirmationMismatch
  }
  {
    ..self,
    state: GenerationRequested,
    revision: self.revision + 1L,
    updated_unix_ms: now_unix_ms,
  }
}

///|
pub fn ContractPacket::complete_generation(
  self : ContractPacket,
  expected_revision : Int64,
  docx : ContractGeneratedArtifact,
  pdf : ContractGeneratedArtifact,
  now_unix_ms : Int64,
) -> ContractPacket raise ContractDocumentError {
  if self.revision != expected_revision {
    raise StaleRevision
  }
  if self.state != GenerationRequested ||
    docx.media_type !=
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
    pdf.media_type != "application/pdf" ||
    !valid_sha256(docx.sha256) ||
    !valid_sha256(pdf.sha256) ||
    !valid_sha256(docx.render_evidence_sha256) ||
    docx.render_evidence_sha256 != pdf.render_evidence_sha256 ||
    docx.byte_count <= 0L ||
    pdf.byte_count <= 0L ||
    docx.page_count <= 0 ||
    docx.page_count != pdf.page_count {
    raise InvalidInput("contract generation evidence is invalid")
  }
  {
    ..self,
    artifacts: self.artifacts + [docx, pdf],
    state: Generated,
    revision: self.revision + 1L,
    updated_unix_ms: now_unix_ms,
  }
}
