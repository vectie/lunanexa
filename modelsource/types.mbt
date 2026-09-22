///|
pub(all) enum ImportState {
  Queued
  Downloading
  Verifying
  Verified
  Failed
  Cancelled
} derive(Debug, Eq, FromJson, ToJson)

///|
pub extend ImportState with Debug::{to_repr}

///|
pub extend ImportState with Eq::{not_equal, equal}

///|
pub extend ImportState with FromJson::{from_json}

///|
pub extend ImportState with ToJson::{to_json}

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
pub extend CatalogModel with Debug::{to_repr}

///|
pub extend CatalogModel with Eq::{not_equal, equal}

///|
pub extend CatalogModel with ToJson::{to_json}

///|
pub(all) struct CatalogPage {
  models : Array[CatalogModel]
  total_count : Int64
  page_number : Int
  page_size : Int
} derive(Debug, Eq, ToJson)

///|
pub extend CatalogPage with Debug::{to_repr}

///|
pub extend CatalogPage with Eq::{not_equal, equal}

///|
pub extend CatalogPage with ToJson::{to_json}

///|
pub(all) struct ModelScopeFile {
  path : String
  revision : String
  sha256 : String
  size : Int64
  lfs : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub extend ModelScopeFile with Debug::{to_repr}

///|
pub extend ModelScopeFile with Eq::{not_equal, equal}

///|
pub extend ModelScopeFile with FromJson::{from_json}

///|
pub extend ModelScopeFile with ToJson::{to_json}

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
  local_directory : String
  error_code : String
  cancel_requested : Bool
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, FromJson, ToJson)

///|
pub extend ImportOperation with Debug::{to_repr}

///|
pub extend ImportOperation with Eq::{not_equal, equal}

///|
pub extend ImportOperation with FromJson::{from_json}

///|
pub extend ImportOperation with ToJson::{to_json}

///|
pub(all) struct ImportRequest {
  model_id : String
  revision : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub extend ImportRequest with Debug::{to_repr}

///|
pub extend ImportRequest with Eq::{not_equal, equal}

///|
pub extend ImportRequest with FromJson::{from_json}

///|
pub extend ImportRequest with ToJson::{to_json}

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
pub extend ModelSourceError with Debug::{to_repr}

///|
pub extend ModelSourceError with Eq::{not_equal, equal}

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
/// A directory the operator already populated inside the managed model store.
/// The value is store-root relative, so it can never escape the store.
pub fn valid_local_directory(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 180 &&
  !value.has_prefix("/") &&
  !value.has_suffix("/") &&
  !value.contains("\\") &&
  !value.contains("..") &&
  !value.contains("//") &&
  !value.contains_char('\n') &&
  !value.contains_char('\r') &&
  !value.contains_char(' ') &&
  value
  .split("/")
  .all(segment => {
    segment != "" &&
    segment != "." &&
    segment != ".." &&
    segment.length() <= 90 &&
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
/// One entry of the managed model store listing the console scans. `bytes` is
/// an `Int64`, and `Int64` crosses this API as a JSON string everywhere else,
/// so it is emitted as a string rather than a bare number: a console decoding
/// it then never has to guess, and a bare number would silently break every
/// operator action on the Models page.
pub fn local_directory_entry(
  directory : String,
  files : Int,
  bytes : Int64,
  registered : Bool,
) -> Json raise ModelSourceError {
  if !valid_local_directory(directory) || files < 0 || bytes < 0L {
    raise InvalidRepositoryPath
  }
  Json::object({
    "directory": Json::string(directory),
    "files": Json::number(files.to_double()),
    "bytes": Json::string(bytes.to_string()),
    "registered": Json::boolean(registered),
  })
}

///|
/// The one artifact-URI form LunaNexa serves from its own managed store: the
/// path segment is the key inside `LUNANEXA_MODEL_STORE_ROOT`.
pub fn local_artifact_uri(directory : String) -> String raise ModelSourceError {
  if !valid_local_directory(directory) {
    raise InvalidRepositoryPath
  }
  "modelstore://\{directory}"
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
