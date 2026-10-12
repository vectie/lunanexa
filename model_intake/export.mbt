///|
fn editable_cell(value : String, field : String) -> Unit raise IntakeError {
  let trimmed = value.trim()
  if trimmed.has_prefix("=") ||
    trimmed.has_prefix("+") ||
    trimmed.has_prefix("-") ||
    trimmed.has_prefix("@") ||
    value.has_prefix("\t") ||
    value.has_prefix("\r") ||
    value.has_prefix("\n") {
    raise InvalidInput(
      "editable CSV cannot safely preserve formula-like text in " +
      field +
      "; retain the original JSON instead",
    )
  }
}

///|
fn recorded_state(state : @contracts.ModelState) -> String {
  match state {
    Candidate => "Candidate"
    Verified => "Verified"
    Evaluated => "Evaluated"
    Approved => "Approved"
    Deprecated => "Deprecated"
    Revoked => "Revoked"
  }
}

///|
/// Export saved registry metadata into the existing mapped CSV intake format.
/// The extra lunanexa_registered_state column is informational only. Reimport
/// always creates Candidates; review still blocks every existing identity.
/// Text is never prefixed or normalized to conceal a lossy round trip. Values
/// that would trigger spreadsheet formulas or lose signature whitespace fail.
pub fn export_registry_csv(
  registered : Array[@contracts.ModelRecord],
  mapping : Mapping,
) -> String raise IntakeError {
  validate_mapping(mapping)
  validate_models(registered, false)
  let headers = names(mapping.columns)
  if headers.contains("lunanexa_registered_state") {
    raise InvalidInput(
      "lunanexa_registered_state is reserved for recorded state in editable exports",
    )
  }
  for header in headers {
    editable_cell(header, "mapping header")
  }
  headers.push("lunanexa_registered_state")
  let rows = [headers]
  for model in sorted_models(registered) {
    if model.artifact.signature_ref.trim().to_owned() !=
      model.artifact.signature_ref {
      raise InvalidInput(
        "editable CSV would trim signature_ref for " +
        model.model_id +
        " / " +
        model.version +
        "; retain the original JSON instead",
      )
    }
    let architectures = model.compatible_architectures.copy()
    architectures.sort_by(text_order)
    let values = [
      model.model_id,
      model.version,
      model.artifact.digest,
      model.artifact.uri,
      model.artifact.size_bytes.to_string(),
      model.artifact.signature_ref,
      model.license_id,
      model.provenance,
      architectures.join(";"),
      model.minimum_memory_mib.to_string(),
      recorded_state(model.state),
    ]
    for index, value in values {
      editable_cell(value, model.model_id + " / " + headers[index])
    }
    rows.push(values)
  }
  let table : @csv.Table = { rows, delimiter: ',', }
  let output = table.serialize_quoted() + "\r\n"
  if output.length() > 2097152 {
    raise InvalidInput("editable CSV exceeds the 2 Mi-character intake limit")
  }
  output
}
