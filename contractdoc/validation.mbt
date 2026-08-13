///|
fn valid_identifier(value : String) -> Bool {
  @contracts.valid_identifier(value, maximum_length=256)
}

///|
fn valid_sha256(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].all(character => character.is_ascii_hexdigit())
}

///|
fn printable_bounded(value : String, maximum : Int) -> Bool {
  value.length() <= maximum &&
  value.all(character => character.is_printable() && character != '\u{0000}')
}

///|
pub fn validate_manifest(
  manifest : ContractTemplateManifest,
) -> Unit raise ContractDocumentError {
  if manifest.contract_version != contract_version ||
    !valid_identifier(manifest.collection_id) ||
    !valid_identifier(manifest.template_id) ||
    !valid_identifier(manifest.template_version) ||
    !valid_identifier(manifest.locale) ||
    manifest.filename.trim() == "" ||
    manifest.filename.length() > 180 ||
    manifest.media_type !=
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
    !valid_sha256(manifest.sha256) ||
    manifest.fillable_filename.trim() == "" ||
    manifest.fillable_filename.length() > 180 ||
    !valid_sha256(manifest.fillable_sha256) ||
    manifest.fillable_sha256 == manifest.sha256 ||
    manifest.byte_count <= 0L ||
    manifest.byte_count > 100000000L ||
    manifest.page_count <= 0 ||
    manifest.page_count > 1000 ||
    manifest.section_count <= 0 ||
    manifest.forms.length() == 0 ||
    manifest.fields.length() == 0 {
    raise InvalidInput("invalid contract template manifest")
  }
  let field_ids : Map[String, ContractFieldDefinition] = Map([])
  for field in manifest.fields {
    if !valid_identifier(field.field_id) ||
      field.label_zh_cn.trim() == "" ||
      field.label_en.trim() == "" ||
      field.maximum_characters <= 0 ||
      field.maximum_characters > 4000 ||
      field.locator.trim() == "" ||
      field.locator.length() > 256 ||
      field_ids.contains(field.field_id) ||
      (field.kind == Choice && field.allowed_values.length() < 2) ||
      (field.kind != Choice && field.allowed_values.length() > 0) ||
      (field.collection_policy == CompleteOffline && field.required) {
      raise InvalidInput("invalid or duplicate contract field definition")
    }
    field_ids[field.field_id] = field
  }
  let forms : Array[ContractFormKind] = []
  for form in manifest.forms {
    if form.title_zh_cn.trim() == "" ||
      form.title_en.trim() == "" ||
      form.field_ids.length() == 0 ||
      forms.contains(form.form) {
      raise InvalidInput("invalid or duplicate contract form definition")
    }
    forms.push(form.form)
    let seen : Map[String, Unit] = Map([])
    for field_id in form.field_ids {
      guard field_ids.get(field_id) is Some(field) && field.form == form.form else {
        raise InvalidInput("contract form references an invalid field")
      }
      if seen.contains(field_id) {
        raise InvalidInput("contract form repeats a field")
      }
      seen[field_id] = ()
    }
  }
  if manifest.fields.any(field => !forms.contains(field.form)) {
    raise InvalidInput("contract field has no owning form")
  }
}

///|
pub fn validate_field_value(
  definition : ContractFieldDefinition,
  value : String,
) -> Unit raise ContractDocumentError {
  if definition.collection_policy == CompleteOffline {
    raise ForbiddenSecret(definition.field_id)
  }
  if !printable_bounded(value, definition.maximum_characters) {
    raise InvalidInput("contract field value is invalid or too long")
  }
  if value.trim() == "" {
    if definition.required {
      raise InvalidInput("required contract field is empty")
    }
    return
  }
  match definition.kind {
    Identifier if !valid_identifier(value) =>
      raise InvalidInput("contract identifier field is invalid")
    WholeNumber if value.any(character => !character.is_ascii_digit()) =>
      raise InvalidInput("contract whole-number field is invalid")
    Choice if !definition.allowed_values.contains(value) =>
      raise InvalidInput("contract choice is outside the source options")
    _ => ()
  }
}

///|
pub fn ContractTemplateManifest::field(
  self : ContractTemplateManifest,
  field_id : String,
) -> ContractFieldDefinition? {
  match self.fields.search_by(field => field.field_id == field_id) {
    Some(index) => self.fields.get(index)
    None => None
  }
}

///|
pub fn ContractPacket::value(
  self : ContractPacket,
  field_id : String,
) -> String? {
  match self.values.search_by(value => value.field_id == field_id) {
    Some(index) => self.values.get(index).map(value => value.value)
    None => None
  }
}

///| Canonical, length-delimited information used only to derive a confirmation

///|
/// digest. The material itself must never be written to an audit record.
pub fn ContractPacket::canonical_values_material(
  self : ContractPacket,
) -> String {
  let ordered = self.values.copy()
  ordered.sort_by((left, right) => left.field_id.compare(right.field_id))
  let parts = ["contract-values-v1"]
  for item in ordered {
    parts.push(
      "\{item.field_id.length()}:\{item.field_id}\n\{item.value.length()}:\{item.value}",
    )
  }
  parts.join("\n")
}

///|
pub fn missing_required_fields(
  manifest : ContractTemplateManifest,
  packet : ContractPacket,
) -> Array[String] {
  let missing = []
  for definition in manifest.fields {
    if packet.active_forms.contains(definition.form) &&
      definition.required &&
      packet
      .value(definition.field_id)
      .map_or(true, value => value.trim() == "") {
      missing.push(definition.field_id)
    }
  }
  missing
}
