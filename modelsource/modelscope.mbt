///|
pub(all) struct ModelScopeTree {
  revision : String
  files : Array[ModelScopeFile]
} derive(Debug, Eq, ToJson)

///|
pub struct ModelScopeClient {
  origin : String
}

///| Keep every response Content-Length inside MoonBit async HTTP's current

///|
/// Int-backed parser while still streaming arbitrarily large model files.
const ModelScopeDownloadChunkBytes : Int64 = 67108864L

///|
fn modelscope_download_chunk_end(file_size : Int64, start : Int64) -> Int64 {
  if file_size - start > ModelScopeDownloadChunkBytes {
    start + ModelScopeDownloadChunkBytes - 1L
  } else {
    file_size - 1L
  }
}

///|
fn source_int64(value : Json) -> Int64 raise ModelSourceError {
  guard value is Number(number, repr~) &&
    number != @double.infinity &&
    number != @double.neg_infinity &&
    number == number.trunc() else {
    raise InvalidUpstreamResponse
  }
  match repr {
    Some(text) =>
      @string.parse_int64(text) catch {
        _ => raise InvalidUpstreamResponse
      }
    None => {
      if number > 9007199254740991.0 || number < -9007199254740991.0 {
        raise InvalidUpstreamResponse
      }
      number.to_int64()
    }
  }
}

///|
fn[T : FromJson] source_field(
  fields : Map[String, Json],
  name : String,
) -> T raise ModelSourceError {
  guard fields.get(name) is Some(value) else { raise InvalidUpstreamResponse }
  try @json.from_json(value) catch {
    _ => raise InvalidUpstreamResponse
  } noraise {
    decoded => decoded
  }
}

///|
fn source_int64_field(
  fields : Map[String, Json],
  name : String,
) -> Int64 raise ModelSourceError {
  guard fields.get(name) is Some(value) else { raise InvalidUpstreamResponse }
  source_int64(value)
}

///|
fn decode_catalog_model(value : Json) -> CatalogModel raise ModelSourceError {
  guard value is Object(fields) else { raise InvalidUpstreamResponse }
  {
    id: source_field(fields, "id"),
    display_name: source_field(fields, "display_name"),
    description: source_field(fields, "description"),
    downloads: source_int64_field(fields, "downloads"),
    likes: source_int64_field(fields, "likes"),
    license: source_field(fields, "license"),
    tasks: source_field(fields, "tasks"),
    created_at: source_field(fields, "created_at"),
    last_modified: source_field(fields, "last_modified"),
    file_size: source_int64_field(fields, "file_size"),
    params: source_int64_field(fields, "params"),
    tags: source_field(fields, "tags"),
    private: source_field(fields, "private"),
    gated: source_field(fields, "gated"),
  }
}

///|
fn decode_catalog_page(value : Json) -> CatalogPage raise ModelSourceError {
  guard value is Object(fields) &&
    fields.get("models") is Some(Array(raw_models)) else {
    raise InvalidUpstreamResponse
  }
  let models : Array[CatalogModel] = []
  for model in raw_models {
    models.push(decode_catalog_model(model))
  }
  {
    models,
    total_count: source_int64_field(fields, "total_count"),
    page_number: source_field(fields, "page_number"),
    page_size: source_field(fields, "page_size"),
  }
}

///|
pub fn ModelScopeClient::new(
  origin? : String = "https://modelscope.cn",
) -> ModelScopeClient raise ModelSourceError {
  if origin != "https://modelscope.cn" && origin != "https://www.modelscope.cn" {
    raise UntrustedOrigin
  }
  { origin, }
}

///|
fn percent_encode(value : String) -> String {
  let builder = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in @utf8.encode(value) {
    let number = byte.to_int()
    if (number >= 65 && number <= 90) ||
      (number >= 97 && number <= 122) ||
      (number >= 48 && number <= 57) ||
      number == 45 ||
      number == 46 ||
      number == 95 ||
      number == 126 {
      builder.write_char(number.to_char().unwrap())
    } else {
      builder.write_char('%')
      builder.write_char(hex[number / 16].to_char().unwrap())
      builder.write_char(hex[number % 16].to_char().unwrap())
    }
  }
  builder.to_string()
}

///|
async fn get_json(url : String) -> Json {
  let headers : Map[String, String] = {
    "Accept": "application/json",
    "User-Agent": "LunaNexa-ModelSource/0.2",
  }
  let (response, body) = @http.get(url, headers~)
  if response.code < 200 || response.code >= 300 {
    raise UpstreamRejected
  }
  try @json.parse(body.text()) catch {
    _ => raise InvalidUpstreamResponse
  } noraise {
    value => value
  }
}

///|
pub async fn ModelScopeClient::search(
  self : ModelScopeClient,
  query : String,
  page_number? : Int = 1,
  page_size? : Int = 12,
) -> CatalogPage {
  if query.length() > 120 || page_number < 1 || page_size < 1 || page_size > 50 {
    raise InvalidUpstreamResponse
  }
  let url = "\{self.origin}/openapi/v1/models?search=\{percent_encode(query)}&page_number=\{page_number}&page_size=\{page_size}"
  guard get_json(url) is { "success": True, "data": data, .. } else {
    raise InvalidUpstreamResponse
  }
  decode_catalog_page(data)
}

///|
pub async fn ModelScopeClient::detail(
  self : ModelScopeClient,
  model_id : String,
) -> CatalogModel {
  if !valid_model_id(model_id) {
    raise InvalidModelId
  }
  guard model_id.split("/").collect() is [owner, name] else {
    raise InvalidModelId
  }
  let url = "\{self.origin}/openapi/v1/models/\{percent_encode(owner.to_owned())}/\{percent_encode(name.to_owned())}"
  guard get_json(url) is { "success": True, "data": data, .. } else {
    raise InvalidUpstreamResponse
  }
  decode_catalog_model(data)
}

///|
fn legacy_file(value : Json) -> ModelScopeFile raise ModelSourceError {
  guard value
    is {
      "Path": String(path),
      "Revision": String(revision),
      "Sha256": String(sha256),
      "Size": size,
      "IsLFS": lfs_value,
      ..
    } else {
    raise InvalidUpstreamResponse
  }
  let size = source_int64(size)
  let lfs : Bool = try @json.from_json(lfs_value) catch {
    _ => raise InvalidUpstreamResponse
  } noraise {
    decoded => decoded
  }
  if !valid_repository_path(path) ||
    !valid_revision(revision) ||
    size < 0L ||
    sha256.length() != 64 ||
    !sha256.all(character => character.is_ascii_hexdigit()) {
    raise InvalidUpstreamResponse
  }
  { path, revision, sha256: sha256.to_lower(), size, lfs }
}

///|
pub async fn ModelScopeClient::tree(
  self : ModelScopeClient,
  model_id : String,
  revision : String,
) -> ModelScopeTree {
  if !valid_model_id(model_id) {
    raise InvalidModelId
  }
  if !valid_revision(revision) {
    raise InvalidRevision
  }
  guard model_id.split("/").collect() is [owner, name] else {
    raise InvalidModelId
  }
  let url = "\{self.origin}/api/v1/models/\{percent_encode(owner.to_owned())}/\{percent_encode(name.to_owned())}/repo/files?Revision=\{percent_encode(revision)}&Recursive=true"
  let value = get_json(url)
  guard value
    is {
      "Success": True,
      "Data": {
        "Files": Array(raw_files),
        "LatestCommitter": { "ShortId": String(short_id), .. },
        ..
      },
      ..
    } &&
    raw_files.length() > 0 &&
    raw_files.length() <= 10000 else {
    raise InvalidUpstreamResponse
  }
  let files : Array[ModelScopeFile] = []
  let paths : Map[String, Bool] = Map([])
  for file in raw_files {
    let decoded = legacy_file(file)
    if paths.contains(decoded.path) {
      raise InvalidUpstreamResponse
    }
    paths[decoded.path] = true
    files.push(decoded)
  }
  let resolved_revision = if short_id == "" { revision } else { short_id }
  { revision: resolved_revision, files }
}

///|
fn file_url(
  client : ModelScopeClient,
  model_id : String,
  revision : String,
  path : String,
) -> String raise ModelSourceError {
  if !valid_model_id(model_id) {
    raise InvalidModelId
  }
  if !valid_revision(revision) {
    raise InvalidRevision
  }
  if !valid_repository_path(path) {
    raise InvalidRepositoryPath
  }
  let segments = path
    .split("/")
    .map(segment => percent_encode(segment.to_owned()))
    .join("/")
  "\{client.origin}/models/\{model_id}/resolve/\{percent_encode(revision)}/\{segments}"
}

///|
fn response_header(headers : Map[String, String], name : String) -> String? {
  for key, value in headers {
    if key.to_lower() == name.to_lower() {
      return Some(value)
    }
  }
  None
}

///| ModelScope serves LFS objects through short-lived HTTPS redirects. Keep

///| redirect handling inside the provider boundary: no userinfo, ports,

///|
/// fragments, non-HTTPS schemes, or lookalike parent domains are accepted.
fn trusted_modelscope_download_redirect(location : String) -> Bool {
  guard location.has_prefix("https://") else { return false }
  let authority_and_path = location[8:]
  guard authority_and_path.find("/") is Some(path_offset) else { return false }
  let authority = authority_and_path[:path_offset].to_owned().to_lower()
  authority != "" &&
  authority.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '.'
  }) &&
  !authority.contains("@") &&
  !authority.contains(":") &&
  !authority.contains("\\") &&
  (
    authority == "modelscope.cn" ||
    authority == "www.modelscope.cn" ||
    authority.has_suffix(".modelscope.cn")
  ) &&
  !location.contains("#")
}

///| Follow only the bounded, provider-owned redirect chain used for LFS

///| objects. Request headers (including Range) are preserved so retries remain

///|
/// resumable; each intermediate response body is closed before continuing.
async fn modelscope_download_stream(
  initial_url : String,
  headers : Map[String, String],
) -> (@http.Response, @http.Client) {
  let mut current_url = initial_url
  let mut redirects = 0
  while true {
    // The async HTTP client takes ownership of and mutates its header map
    // (including Host). Each redirect hop therefore receives a fresh copy.
    let (response, stream) = @http.get_stream(
      current_url,
      headers=headers.copy(),
    )
    if response.code >= 200 && response.code < 300 {
      return (response, stream)
    }
    let redirect = response.code == 301 ||
      response.code == 302 ||
      response.code == 303 ||
      response.code == 307 ||
      response.code == 308
    if redirect && redirects < 3 {
      match response_header(response.headers, "location") {
        Some(location) if trusted_modelscope_download_redirect(location) => {
          stream.close()
          current_url = location
          redirects += 1
          continue
        }
        _ => ()
      }
    }
    stream.close()
    raise UpstreamRejected
  }
  raise UpstreamRejected
}

///|
pub async fn ModelScopeClient::download_file(
  self : ModelScopeClient,
  model_id : String,
  revision : String,
  file : ModelScopeFile,
  destination : String,
  progress : async (Int64) -> Unit,
  cancelled : async () -> Bool,
) -> Unit {
  let headers : Map[String, String] = {
    "Accept": "application/octet-stream",
    "User-Agent": "LunaNexa-ModelSource/0.2",
  }
  let digest = @crypto.SHA256::new()
  let mut offset = 0L
  if @fs.exists(destination) {
    let existing = @fs.open(destination, mode=ReadOnly)
    if existing.size() > file.size {
      existing.close()
    } else {
      try {
        while existing.read_some(max_len=1048576) is Some(chunk) {
          offset += chunk.length().to_int64()
          digest.update(chunk)
        }
      } catch {
        error => {
          existing.close()
          raise error
        }
      } noraise {
        _ => existing.close()
      }
      if offset == file.size {
        let actual = @crypto.bytes_to_hex_string(digest.finalize())
        if actual == file.sha256 {
          progress(offset)
          return
        }
        offset = 0L
        digest.reset()
      }
    }
  }
  if offset > 0L {
    progress(offset)
  }
  let mut size = offset
  while size < file.size {
    let request_start = size
    let request_end = modelscope_download_chunk_end(file.size, request_start)
    headers["Range"] = "bytes=\{request_start}-\{request_end}"
    let (response, stream) = modelscope_download_stream(
      file_url(self, model_id, revision, file.path),
      headers,
    )
    let mut expected_end = request_end
    let append = if response.code == 206 {
      let expected_range = "bytes \{request_start}-\{request_end}/\{file.size}"
      if response_header(response.headers, "content-range") !=
        Some(expected_range) {
        stream.close()
        raise InvalidUpstreamResponse
      }
      request_start > 0L
    } else if response.code == 200 {
      // Small non-LFS objects may ignore Range. A resumed small file can be
      // safely restarted, but a large unbounded 200 response is rejected.
      if file.size > ModelScopeDownloadChunkBytes {
        stream.close()
        raise FileSizeMismatch
      }
      if request_start > 0L {
        progress(-request_start)
        size = 0L
        digest.reset()
      }
      expected_end = file.size - 1L
      false
    } else {
      stream.close()
      raise UpstreamRejected
    }
    let output = @fs.open(
      destination,
      mode=WriteOnly,
      create_mode=if append { OpenOrCreate } else { CreateOrTruncate },
      permission=0o600,
      append~,
    )
    try {
      while stream.read_some(max_len=1048576) is Some(chunk) {
        if cancelled() {
          raise ImportCancelled
        }
        size += chunk.length().to_int64()
        if size > expected_end + 1L {
          raise FileSizeMismatch
        }
        digest.update(chunk)
        output.write(chunk)
        progress(chunk.length().to_int64())
      }
      output.sync(only_data=false)
    } catch {
      error => {
        output.close()
        stream.close()
        raise error
      }
    } noraise {
      _ => {
        output.close()
        stream.close()
      }
    }
    if size != expected_end + 1L {
      raise FileSizeMismatch
    }
  }
  if size != file.size {
    raise FileSizeMismatch
  }
  let actual = @crypto.bytes_to_hex_string(digest.finalize())
  if actual != file.sha256 {
    raise FileDigestMismatch
  }
}
