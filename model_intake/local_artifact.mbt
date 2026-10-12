///|
/// Operator declarations for one local artifact. Digest and size are supplied
/// separately by the native reader, never accepted from this metadata document.
pub(all) struct ArtifactMetadata {
  schema_version : String
  model_id : String
  version : String
  artifact_uri : String
  signature_ref : String
  license_id : String
  provenance : String
  compatible_architectures : Array[String]
  minimum_memory_mib : Int
  maximum_artifact_bytes : Int64
} derive(ToJson, FromJson)

///|
pub extend ArtifactMetadata with ToJson::{to_json}

///|
pub extend ArtifactMetadata with FromJson::{from_json}

///|
fn artifact_model(
  metadata : ArtifactMetadata,
  digest : String,
  size_bytes : Int64,
) -> @contracts.ModelRecord {
  let architectures = metadata.compatible_architectures.copy()
  architectures.sort_by(text_order)
  {
    model_id: metadata.model_id,
    version: metadata.version,
    artifact: {
      digest,
      uri: metadata.artifact_uri,
      size_bytes,
      signature_ref: metadata.signature_ref,
    },
    license_id: metadata.license_id,
    provenance: metadata.provenance,
    compatible_architectures: architectures,
    minimum_memory_mib: metadata.minimum_memory_mib,
    state: Candidate,
  }
}

///|
fn validate_artifact_metadata(
  metadata : ArtifactMetadata,
) -> Unit raise IntakeError {
  if metadata.schema_version != "lunanexa.local-artifact.v1" {
    raise InvalidInput("unsupported local artifact metadata version")
  }
  if metadata.maximum_artifact_bytes <= 0L ||
    metadata.maximum_artifact_bytes > 1099511627776L {
    raise InvalidInput("maximum_artifact_bytes must be 1..1099511627776 bytes")
  }
  // Validate declarations before opening a potentially large artifact. These
  // sentinel computed fields are used only for validation and are never output.
  validate_model(artifact_model(metadata, "sha256:" + "0".repeat(64), 1L))
}

///|
/// Strictly decode bounded declarations. This does not open a file or establish
/// that the declared URI, license, signature or runtime requirements are true.
pub fn import_artifact_metadata(text : String) -> ArtifactMetadata raise {
  if text.length() > 16384 {
    raise InvalidInput("local artifact metadata exceeds 16 Ki characters")
  }
  let json = @json.parse(text)
  let metadata : ArtifactMetadata = @json.from_json(json)
  if metadata.to_json() != json {
    raise InvalidInput("local artifact metadata contains unsupported fields")
  }
  validate_artifact_metadata(metadata)
  metadata
}

///|
/// Combine declarations with an observed digest and size into the existing
/// Candidate draft. Pure callers are responsible for measuring those bytes.
/// The native local-artifact command provides that reader; this function does
/// not verify signatures, license eligibility, model format or remote content.
pub fn artifact_draft(
  metadata : ArtifactMetadata,
  digest : String,
  size_bytes : Int64,
) -> Draft raise IntakeError {
  validate_artifact_metadata(metadata)
  if size_bytes <= 0L || size_bytes > metadata.maximum_artifact_bytes {
    raise InvalidInput(
      "artifact size must be positive and within maximum_artifact_bytes",
    )
  }
  let model = artifact_model(metadata, digest, size_bytes)
  validate_model(model)
  { schema_version: 1, models: [model], }
}
