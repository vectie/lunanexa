///|
fn bounded_text(
  value : String,
  name : String,
  allow_empty~ : Bool,
) -> Unit raise CompatibilityError {
  if (!allow_empty && value.trim().is_empty()) || value.length() > 512 {
    raise InvalidInput(
      name + " must contain 1..512 characters (filters may be empty)",
    )
  }
}

///|
fn validate_query(query : Query) -> Unit raise CompatibilityError {
  if query.schema_version != "lunanexa.model-fleet.query.v1" {
    raise InvalidInput("unsupported model-fleet query version")
  }
  if query.memory_reserve_mib < 0 {
    raise InvalidInput("memory_reserve_mib must be nonnegative whole MiB")
  }
  if query.now_unix_ms < 0L ||
    query.now_unix_ms > 9007199254740991L ||
    query.maximum_age_ms < 0L ||
    query.maximum_age_ms > 9007199254740991L {
    raise InvalidInput(
      "query times must be within 0..9007199254740991 milliseconds",
    )
  }
  bounded_text(query.model_id, "model_id", allow_empty=true)
  bounded_text(query.version, "version", allow_empty=true)
  bounded_text(query.node_id, "node_id", allow_empty=true)
}

///|
pub fn import_query(text : String) -> Query raise {
  if text.length() > 16384 {
    raise InvalidInput("query exceeds 16 Ki characters")
  }
  let json = @json.parse(text)
  let query : Query = @json.from_json(json)
  if query.to_json() != json {
    raise InvalidInput("query contains unsupported fields")
  }
  validate_query(query)
  query
}

///|
fn validate_models(
  models : Array[@contracts.ModelRecord],
) -> Unit raise CompatibilityError {
  if models.length() > 1000 {
    raise InvalidInput("at most 1000 models are supported")
  }
  let seen : Map[(String, String), Bool] = Map([])
  for model in models {
    bounded_text(model.model_id, "model ID", allow_empty=false)
    bounded_text(model.version, "model version", allow_empty=false)
    if seen.contains((model.model_id, model.version)) {
      raise InvalidInput("duplicate model/version identity")
    }
    seen[(model.model_id, model.version)] = true
    if !@contracts.valid_sha256_digest(model.artifact.digest) {
      raise InvalidInput("model artifact needs an exact SHA-256 digest")
    }
    if model.minimum_memory_mib <= 0 {
      raise InvalidInput(
        "model minimum memory is missing or nonpositive; an explicit positive declaration is required",
      )
    }
    if model.compatible_architectures.is_empty() ||
      model.compatible_architectures.length() > 32 {
      raise InvalidInput(
        "model requires 1..32 explicit architectures; an empty list is not a wildcard",
      )
    }
    let architectures : Map[String, Bool] = Map([])
    for architecture in model.compatible_architectures {
      bounded_text(architecture, "model architecture", allow_empty=false)
      if architectures.contains(architecture) {
        raise InvalidInput("duplicate model architecture")
      }
      architectures[architecture] = true
    }
  }
}

///|
/// Import the models projection of saved registry JSON or an existing Candidate
/// intake draft. This validates fields used for comparison, not model approval.
pub fn import_models(
  text : String,
  source_kind : String,
) -> Array[@contracts.ModelRecord] raise {
  if text.length() > 8388608 {
    raise InvalidInput("model source exceeds 8 Mi characters")
  }
  let json = @json.parse(text)
  let raw = match (source_kind, json) {
    (
      "registry",
      { "schema_version": "lunanexa.registry.v1", "models": Array(rows), .. },
    ) => rows
    ("draft", Object(fields)) => {
      if fields.length() != 2 ||
        fields.get("schema_version") != Some(Json::number(1)) {
        raise InvalidInput(
          "expected an unchanged schema_version 1 Candidate intake draft",
        )
      }
      guard fields.get("models") is Some(Array(rows)) else {
        raise InvalidInput("draft requires models")
      }
      rows
    }
    _ =>
      raise InvalidInput(
        "expected registry or draft source with the matching schema version",
      )
  }
  if raw.length() > 1000 {
    raise InvalidInput("at most 1000 models are supported")
  }
  let models : Array[@contracts.ModelRecord] = @json.from_json(Json::array(raw))
  if models.to_json() != Json::array(raw) {
    raise InvalidInput("model record contains unsupported fields")
  }
  validate_models(models)
  if source_kind == "draft" && models.any(model => model.state != Candidate) {
    raise InvalidInput("intake draft models must remain Candidate")
  }
  models
}
