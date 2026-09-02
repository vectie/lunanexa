///|
pub(all) enum ImportState {
  Queued
  Downloading
  Verified
  Failed
  Cancelled
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CatalogModel {
  id : String
  display_name : String
  description : String
  downloads : Int64
  likes : Int64
  license : String
  tasks : Array[String]
  created_at : String
  last_modified : String
  file_size : Int64
  params : Int64
  tags : Array[String]
  private : Bool
  gated : Bool
} derive(Debug, Eq, ToJson)

///|
pub(all) struct CatalogPage {
  models : Array[CatalogModel]
  total_count : Int64
  page_number : Int
  page_size : Int
} derive(Debug, Eq, ToJson)

///|
pub(all) struct ModelScopeFile {
  path : String
  revision : String
  sha256 : String
  size : Int64
  lfs : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ImportOperation {
  import_id : String
  source : String
  model_id : String
  revision : String
  state : ImportState
  files_total : Int
  files_completed : Int
  bytes_total : Int64
  bytes_completed : Int64
  manifest_digest : String
  artifact_uri : String
  license : String
  error_code : String
  cancel_requested : Bool
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ImportRequest {
  model_id : String
  revision : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) suberror ModelSourceError {
  InvalidModelId
  InvalidRevision
  InvalidRepositoryPath
  UntrustedOrigin
  UpstreamRejected
  InvalidUpstreamResponse
  ImportAlreadyExists
  ImportNotFound
  ImportNotCancelable
  ImportNotRetryable
  ImportCancelled
  ArtifactTooLarge
  FileDigestMismatch
  FileSizeMismatch
  FilesystemRejected
} derive(Debug, Eq)

///|
pub fn valid_model_id(value : String) -> Bool {
  let segments = value.split("/").collect()
  if value.length() < 3 || value.length() > 180 || segments.length() != 2 {
    return false
  }
  value
  .split("/")
  .all(segment => {
    segment.length() >= 1 &&
    segment.length() <= 90 &&
    segment != "." &&
    segment != ".." &&
    segment.all(character => {
      character.is_ascii_alphabetic() ||
      character.is_ascii_digit() ||
      character == '-' ||
      character == '_' ||
      character == '.'
    })
  })
}

///|
pub fn valid_revision(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 96 &&
  value != "." &&
  value != ".." &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == '.'
  })
}

///|
pub fn valid_repository_path(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 512 &&
  !value.has_prefix("/") &&
  !value.contains("\\") &&
  value.all(character => character.to_int() >= 32) &&
  value
  .split("/")
  .all(segment => {
    segment != "" &&
    segment != "." &&
    segment != ".." &&
    segment.length() <= 180
  })
}

///|
pub fn import_id(
  model_id : String,
  revision : String,
) -> String raise ModelSourceError {
  if !valid_model_id(model_id) {
    raise InvalidModelId
  }
  if !valid_revision(revision) {
    raise InvalidRevision
  }
  let material = "modelscope|\{model_id}|\{revision}"
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(material)),
  )
  "ms-\{digest[:24]}"
}
