///|
/// Persist the generated name before sending: retries address the same service.
fn quick_deployment_named(
  state : @ui.ConsoleState,
  generated : String,
) -> @ui.ConsoleState {
  if state.quick_deployment_id.trim() == "" {
    { ..state, quick_deployment_id: generated, }
  } else {
    state
  }
}

///|
fn adoption_defaults(import_ : @ui.ModelImportRow) -> @ui.ModelAdoptionDraft {
  let identifier = import_.model_id.replace(old="/", new="-")
  {
    ..empty_model_adoption_draft(),
    import_id: import_.import_id,
    model_id: if @contracts.valid_identifier(identifier) {
      identifier
    } else {
      ""
    },
    version: if @contracts.valid_identifier(import_.revision) {
      import_.revision
    } else {
      ""
    },
    license_id: if @contracts.valid_identifier(import_.license) {
      import_.license
    } else {
      ""
    },
  }
}
