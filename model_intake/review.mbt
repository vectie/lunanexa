///|
fn text_order(a : String, b : String) -> Int {
  for index = 0; index < a.length() && index < b.length(); index = index + 1 {
    let order = a[index].compare(b[index])
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
fn comparable(model : @contracts.ModelRecord) -> Map[String, Json] {
  let architectures = model.compatible_architectures.copy()
  architectures.sort_by(text_order)
  {
    "artifact.digest": Json::string(model.artifact.digest),
    "artifact.uri": Json::string(model.artifact.uri),
    "artifact.size_bytes": Json::string(model.artifact.size_bytes.to_string()),
    "artifact.signature_ref": Json::string(model.artifact.signature_ref),
    "license_id": Json::string(model.license_id),
    "provenance": Json::string(model.provenance),
    "compatible_architectures": ToJson::to_json(architectures),
    "minimum_memory_mib": Json::number(model.minimum_memory_mib.to_double()),
  }
}

///|
/// Compare metadata with a saved registry. Recorded state is shown separately;
/// an existing identity is never eligible for new-request extraction.
pub fn review(
  draft : Draft,
  registered : Array[@contracts.ModelRecord],
) -> Review raise IntakeError {
  if draft.schema_version != 1 {
    raise InvalidInput("unsupported draft version")
  }
  validate_models(draft.models, true)
  validate_models(registered, false)
  let existing : Map[String, @contracts.ModelRecord] = Map([])
  for model in registered {
    existing[key(model)] = model
  }
  let rows : Array[ReviewRow] = []
  let mut new_count = 0
  let mut already_registered_count = 0
  let mut conflict_count = 0
  for model in sorted_models(draft.models) {
    let differences : Array[Difference] = []
    let (status, state) = match existing.get(key(model)) {
      None => {
        new_count += 1
        ("new", None)
      }
      Some(prior) => {
        let left = comparable(model)
        let right = comparable(prior)
        for field, value in left {
          if value != right[field] {
            differences.push({
              field,
              candidate: value,
              registered: right[field],
            })
          }
        }
        if differences.is_empty() {
          already_registered_count += 1
          ("already-registered", Some(prior.state))
        } else {
          conflict_count += 1
          ("conflict", Some(prior.state))
        }
      }
    }
    rows.push({
      model_id: model.model_id,
      version: model.version,
      status,
      registered_state: state,
      differences,
    })
  }
  {
    schema_version: 1,
    new_count,
    already_registered_count,
    conflict_count,
    rows,
  }
}

///|
/// Extract one existing-contract request only when its exact identity is absent
/// from the supplied saved registry. This neither sends nor reserves the identity.
pub fn registration_request(
  draft : Draft,
  registered : Array[@contracts.ModelRecord],
  model_id : String,
  version : String,
) -> @contracts.ModelRecord raise IntakeError {
  let result = review(draft, registered)
  for row in result.rows {
    if row.model_id == model_id && row.version == version {
      if row.status != "new" {
        raise InvalidInput(
          "identity already exists in the saved registry; registration request is blocked",
        )
      }
      for model in draft.models {
        if model.model_id == model_id && model.version == version {
          return model
        }
      }
    }
  }
  raise InvalidInput("selected model/version is absent from the draft")
}
