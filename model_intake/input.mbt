///|
fn names(columns : Columns) -> Array[String] {
  [
    columns.model_id,
    columns.version,
    columns.artifact_digest,
    columns.artifact_uri,
    columns.artifact_size_bytes,
    columns.signature_ref,
    columns.license_id,
    columns.provenance,
    columns.compatible_architectures,
    columns.minimum_memory_mib,
  ]
}

///|
pub fn default_mapping() -> Mapping {
  {
    schema_version: 1,
    columns: {
      model_id: "model_id",
      version: "version",
      artifact_digest: "artifact_digest",
      artifact_uri: "artifact_uri",
      artifact_size_bytes: "artifact_size_bytes",
      signature_ref: "signature_ref",
      license_id: "license_id",
      provenance: "provenance",
      compatible_architectures: "compatible_architectures",
      minimum_memory_mib: "minimum_memory_mib",
    },
  }
}

///|
fn validate_mapping(mapping : Mapping) -> Unit raise IntakeError {
  if mapping.schema_version != 1 {
    raise InvalidInput("unsupported mapping version")
  }
  let seen : Map[String, Bool] = Map([])
  for name in names(mapping.columns) {
    if name == "" ||
      name.length() > 256 ||
      name.trim().to_owned() != name ||
      seen.contains(name) {
      raise InvalidInput(
        "map each field to a distinct, nonempty header of at most 256 characters",
      )
    }
    seen[name] = true
  }
}

///|
pub fn import_mapping(text : String) -> Mapping raise {
  if text.length() > 16384 {
    raise InvalidInput("mapping exceeds 16 Ki characters")
  }
  let json = @json.parse(text)
  let mapping : Mapping = @json.from_json(json)
  if mapping.to_json() != json {
    raise InvalidInput("mapping contains unsupported fields")
  }
  validate_mapping(mapping)
  mapping
}

///|
fn key(model : @contracts.ModelRecord) -> String {
  model.model_id + "\n" + model.version
}

///|
fn validate_model(model : @contracts.ModelRecord) -> Unit raise IntakeError {
  if !@contracts.valid_candidate_model({ ..model, state: Candidate, }) {
    raise InvalidInput(
      "model metadata does not meet the registry registration contract",
    )
  }
  for value in [model.model_id, model.version, model.license_id] {
    if !@contracts.valid_identifier(value, maximum_length=128) {
      raise InvalidInput(
        "model, version and license IDs must be valid 1..128-character contract identifiers",
      )
    }
  }
  let artifact = model.artifact
  if !@contracts.valid_sha256_digest(artifact.digest) ||
    artifact.size_bytes <= 0L {
    raise InvalidInput(
      "artifact needs an exact SHA-256 digest and positive Int64 byte size",
    )
  }
  if artifact.uri.length() > 2048 ||
    !(artifact.uri.has_prefix("s3://") ||
    artifact.uri.has_prefix("oci://") ||
    artifact.uri.has_prefix(@contracts.model_store_scheme)) ||
    artifact.uri.contains("../") ||
    artifact.uri.contains("file://") ||
    artifact.uri.contains("<script") ||
    artifact.uri.any(c => c.to_int() <= 32 || c.to_int() == 127) {
    raise InvalidInput(
      "artifact URI must be a bounded s3://, oci:// or modelstore:// reference without ASCII controls, spaces or traversal",
    )
  }
  let prefix = if artifact.uri.has_prefix("s3://") {
    5
  } else if artifact.uri.has_prefix("oci://") {
    6
  } else {
    @contracts.model_store_scheme.length()
  }
  if artifact.uri.length() <= prefix {
    raise InvalidInput("artifact URI needs a resource after its scheme")
  }
  if artifact.signature_ref == "" ||
    artifact.signature_ref.length() > 2048 ||
    artifact.signature_ref.any(c => c.to_int() < 32 || c.to_int() == 127) {
    raise InvalidInput(
      "signature reference needs 1..2048 characters without ASCII control bytes",
    )
  }
  if model.provenance.trim().is_empty() ||
    model.provenance.length() > 4096 ||
    model.provenance.contains_char('\u0000') {
    raise InvalidInput(
      "provenance needs 1..4096 characters of operator-supplied context",
    )
  }
  if model.minimum_memory_mib <= 0 ||
    model.compatible_architectures.is_empty() ||
    model.compatible_architectures.length() > 32 {
    raise InvalidInput(
      "positive memory MiB and 1..32 explicit architectures are required",
    )
  }
  let seen : Map[String, Bool] = Map([])
  for arch in model.compatible_architectures {
    if !@contracts.valid_identifier(arch, maximum_length=128) ||
      seen.contains(arch) {
      raise InvalidInput(
        "architectures must be distinct valid contract identifiers",
      )
    }
    seen[arch] = true
  }
}

///|
fn validate_models(
  models : Array[@contracts.ModelRecord],
  candidate : Bool,
) -> Unit raise IntakeError {
  if models.length() > 1000 {
    raise InvalidInput("at most 1000 models are supported")
  }
  let seen : Map[String, Bool] = Map([])
  for model in models {
    validate_model(model)
    if candidate && model.state != Candidate {
      raise InvalidInput("draft models must remain Candidate")
    }
    let identity = key(model)
    if seen.contains(identity) {
      raise InvalidInput(
        "duplicate model/version identity: " +
        model.model_id +
        " / " +
        model.version,
      )
    }
    seen[identity] = true
  }
}

///|
fn sorted_models(
  models : Array[@contracts.ModelRecord],
) -> Array[@contracts.ModelRecord] {
  let result = models.copy()
  result.sort_by((a, b) => {
    let order = text_order(a.model_id, b.model_id)
    if order == 0 {
      text_order(a.version, b.version)
    } else {
      order
    }
  })
  result
}

///|
pub fn import_draft(text : String) -> Draft raise {
  if text.length() > 8388608 {
    raise InvalidInput("draft exceeds 8 Mi characters")
  }
  let json = @json.parse(text)
  let draft : Draft = @json.from_json(json)
  if draft.schema_version != 1 || draft.to_json() != json {
    raise InvalidInput("unsupported draft version or fields")
  }
  validate_models(draft.models, true)
  { schema_version: 1, models: sorted_models(draft.models), }
}

///|
/// Read the models projection of an existing GET /v1/registry response.
/// Other registry domains are intentionally neither imported nor validated.
pub fn import_registry(text : String) -> Array[@contracts.ModelRecord] raise {
  if text.length() > 8388608 {
    raise InvalidInput("registry exceeds 8 Mi characters")
  }
  let json = @json.parse(text)
  guard json
    is { "schema_version": "lunanexa.registry.v1", "models": Array(rows), .. } else {
    raise InvalidInput(
      "expected a saved lunanexa.registry.v1 response with a models array",
    )
  }
  if rows.length() > 1000 {
    raise InvalidInput("at most 1000 registered models are supported")
  }
  let models : Array[@contracts.ModelRecord] = @json.from_json(
    Json::array(rows),
  )
  if ToJson::to_json(models) != Json::array(rows) {
    raise InvalidInput("registered model contains unsupported fields")
  }
  validate_models(models, false)
  sorted_models(models)
}

///|
fn positive_integer(
  value : String,
  record : Int,
  header : String,
) -> Int64 raise {
  let value = value.trim()
  if value.is_empty() || !value.iter().all(c => c >= '0' && c <= '9') {
    raise InvalidInput(
      "CSV record \{record}, column \{header}: expected positive whole decimal integer",
    )
  }
  let number = @string.parse_int64(value, base=10) catch {
    _ =>
      raise InvalidInput(
        "CSV record \{record}, column \{header}: integer exceeds Int64 range",
      )
  }
  if number <= 0L {
    raise InvalidInput(
      "CSV record \{record}, column \{header}: expected positive integer",
    )
  }
  number
}

///|
/// Convert every CSV record into an explicit Candidate draft. No record is
/// dropped, no evidence is authenticated and no registry mutation occurs.
pub fn import_csv(text : String, mapping : Mapping) -> Draft raise {
  validate_mapping(mapping)
  let table = @csv.parse(text)
  guard table.rows.length() >= 2 && table.rows.length() <= 1001 else {
    raise InvalidInput("CSV requires a header and 1..1000 model records")
  }
  let headers = table.rows[0].map(s => s.trim().to_owned())
  let seen : Map[String, Bool] = Map([])
  for header in headers {
    if header == "" || header.length() > 256 || seen.contains(header) {
      raise InvalidInput("CSV headers must be nonempty and unique")
    }
    seen[header] = true
  }
  let columns = names(mapping.columns)
  let indices : Array[Int] = []
  for column in columns {
    let mut found = -1
    for index, header in headers {
      if header == column {
        found = index
      }
    }
    if found < 0 {
      raise InvalidInput("missing mapped CSV header: " + column)
    }
    indices.push(found)
  }
  let models : Array[@contracts.ModelRecord] = []
  for index = 1; index < table.rows.length(); index = index + 1 {
    let row = table.rows[index]
    if row.length() != headers.length() {
      raise InvalidInput(
        "CSV record \{index + 1}: column count differs from header",
      )
    }
    let values = indices.map(i => row[i].trim().to_owned())
    let size = positive_integer(values[4], index + 1, columns[4])
    let memory = positive_integer(values[9], index + 1, columns[9])
    if memory > 2147483647L {
      raise InvalidInput("CSV record \{index + 1}: memory exceeds Int range")
    }
    let architectures = values[8]
      .split(";")
      .map(s => s.trim().to_owned())
      .collect()
    architectures.sort_by(text_order)
    let model : @contracts.ModelRecord = {
      model_id: values[0],
      version: values[1],
      artifact: {
        digest: values[2],
        uri: values[3],
        size_bytes: size,
        signature_ref: values[5],
      },
      license_id: values[6],
      provenance: row[indices[7]],
      compatible_architectures: architectures,
      minimum_memory_mib: memory.to_int(),
      state: Candidate,
    }
    validate_model(model) catch {
      InvalidInput(message) =>
        raise InvalidInput("CSV record \{index + 1}: " + message)
    }
    models.push(model)
  }
  validate_models(models, true)
  { schema_version: 1, models: sorted_models(models), }
}
