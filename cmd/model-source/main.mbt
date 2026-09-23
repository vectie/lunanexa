///|
const MaximumRequestBytes : Int = 16384

///|
priv struct SearchRequest {
  query : String
  page_number : Int
  page_size : Int
} derive(FromJson)

///|
priv struct DetailRequest {
  model_id : String
} derive(FromJson)

///|
/// A revision the operator already placed inside the managed model store. The
/// adapter re-derives every digest from ModelScope; `directory` is only a
/// location claim, never an integrity claim.
priv struct LocalRegistrationRequest {
  model_id : String
  revision : String
  directory : String
  component : String
} derive(FromJson)

///|
priv struct VerifiedManifest {
  schema_version : String
  source : String
  model_id : String
  requested_revision : String
  observed_revision : String
  generated_unix_ms : Int64
  files : Array[@modelsource.ModelScopeFile]
} derive(ToJson)

///|
extend VerifiedManifest with ToJson::{to_json}

///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value.trim() != "" else {
    raise Failure("required model-source environment is unavailable: \{name}")
  }
  value
}

///|
fn bearer_authorized(headers : Map[String, String], token : String) -> Bool {
  let value = match headers.get("Authorization") {
    Some(value) => Some(value)
    None => headers.get("authorization")
  }
  value == Some("Bearer \{token}")
}

///|
fn response_reason(status : Int) -> String {
  match status {
    200 => "OK"
    202 => "Accepted"
    400 => "Bad Request"
    401 => "Unauthorized"
    404 => "Not Found"
    409 => "Conflict"
    413 => "Payload Too Large"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    _ => "Response"
  }
}

///|
async fn send_json(
  connection : @http.ServerConnection,
  status : Int,
  value : Json,
) -> Unit {
  connection.send_response(status, response_reason(status), extra_headers={
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  })
  connection.write_string(value.stringify())
  connection.end_response()
}

///|
fn error_json(code : String, message : String) -> Json {
  { "error": { "code": code, "message": message } }
}

///|
async fn read_body(reader : &@io.Reader) -> String {
  let bytes = reader.read_all().binary()
  if bytes.length() > MaximumRequestBytes {
    raise Failure("request-body-too-large")
  }
  @utf8.decode(bytes)
}

///|
fn[T : FromJson] decode(body : String) -> T raise {
  @json.from_json(@json.parse(body))
}

///|
/// Older consoles omit `component`; keep whole-revision registration wire
/// compatible while new consoles can request a separately named component.
fn decode_local_registration(body : String) -> LocalRegistrationRequest raise {
  let value = @json.parse(body)
  guard value is Object(fields) else {
    raise @modelsource.ModelSourceError::InvalidRepositoryPath
  }
  let fields = fields.copy()
  if !fields.contains("component") {
    fields["component"] = Json::string("")
  }
  @json.from_json(Json::object(fields))
}

///|
fn safe_error_code(error : Error) -> String {
  match error {
    @modelsource.ModelSourceError::ImportCancelled => "cancelled"
    @modelsource.ModelSourceError::ArtifactTooLarge => "artifact-too-large"
    @modelsource.ModelSourceError::FileDigestMismatch => "digest-mismatch"
    @modelsource.ModelSourceError::FileSizeMismatch => "size-mismatch"
    @modelsource.ModelSourceError::UpstreamRejected => "upstream-rejected"
    @modelsource.ModelSourceError::InvalidUpstreamResponse =>
      "invalid-upstream-response"
    @modelsource.ModelSourceError::FilesystemRejected => "filesystem-rejected"
    @modelsource.ModelSourceError::InvalidRepositoryPath => "invalid-directory"
    _ => "import-failed"
  }
}

///|
fn parent_path(path : String) -> String {
  match path.rev_find("/") {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
fn source_manifest(
  operation : @modelsource.ImportOperation,
  tree : @modelsource.ModelScopeTree,
) -> String {
  let manifest : VerifiedManifest = {
    schema_version: "lunanexa.modelsource.verified.v1",
    source: "modelscope",
    model_id: operation.model_id,
    requested_revision: operation.revision,
    observed_revision: tree.revision,
    generated_unix_ms: @async.now(),
    files: tree.files,
  }
  manifest.to_json().stringify(indent=2)
}

///|
/// The manifest is the artifact: its digest names the revision, and every
/// consumer enumerates exactly the files it lists.
async fn write_source_manifest(directory : String, text : String) -> String {
  @fs.write_file(
    "\{directory}/\{SourceManifestFileName}",
    text,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))}"
}

///|
const SourceManifestFileName : String = "lunanexa-source-manifest.json"

///|
async fn ensure_directory(path : String, permission : Int) -> Unit {
  if !@fs.exists(path) {
    @fs.mkdir(path, permission~, recursive=true)
  }
}

///|
async fn run_import(
  store : @modelsource.FileImportStore,
  client : @modelsource.ModelScopeClient,
  model_root : String,
  maximum_import_bytes : Int64,
  operation : @modelsource.ImportOperation,
) -> Unit {
  let staging = "\{model_root}/.imports/\{operation.import_id}.partial"
  let destination = "\{model_root}/models/modelscope/\{operation.import_id}"
  let mut latest = operation
  let completed = try {
    let tree = client.tree(operation.model_id, operation.revision)
    let mut total = 0L
    for file in tree.files {
      if file.size > maximum_import_bytes - total {
        raise @modelsource.ModelSourceError::ArtifactTooLarge
      }
      total += file.size
    }
    if total <= 0L {
      raise @modelsource.ModelSourceError::ArtifactTooLarge
    }
    ensure_directory(staging, 0o700)
    latest = {
      ..operation,
      files_total: tree.files.length(),
      files_completed: 0,
      bytes_total: total,
      bytes_completed: 0L,
      manifest_digest: "",
      artifact_uri: "",
      error_code: "",
      cancel_requested: false,
      updated_unix_ms: @async.now(),
    }
    ignore(store.replace(latest))
    for file in tree.files {
      guard store.get(operation.import_id) is Some(observed) else {
        raise @modelsource.ModelSourceError::ImportNotFound
      }
      if observed.cancel_requested {
        raise @modelsource.ModelSourceError::ImportCancelled
      }
      let path = "\{staging}/\{file.path}"
      ensure_directory(parent_path(path), 0o700)
      let mut unsaved_progress = 0L
      client.download_file(
        operation.model_id,
        tree.revision,
        file,
        path,
        delta => {
          latest = {
            ..latest,
            bytes_completed: latest.bytes_completed + delta,
            updated_unix_ms: @async.now(),
          }
          unsaved_progress += delta
          if unsaved_progress >= 67108864L {
            guard store.get(operation.import_id) is Some(progress_state) else {
              raise @modelsource.ModelSourceError::ImportNotFound
            }
            if progress_state.cancel_requested {
              raise @modelsource.ModelSourceError::ImportCancelled
            }
            ignore(store.replace(latest))
            unsaved_progress = 0L
          }
        },
        () => {
          match store.get(operation.import_id) {
            Some(value) => value.cancel_requested
            None => true
          }
        },
      )
      latest = {
        ..latest,
        files_completed: latest.files_completed + 1,
        updated_unix_ms: @async.now(),
      }
      ignore(store.replace(latest))
    }
    let manifest_text = source_manifest(operation, tree)
    @fs.write_file(
      "\{staging}/\{SourceManifestFileName}",
      manifest_text,
      create_mode=CreateOrTruncate,
      permission=0o600,
      sync=Full,
    )
    ensure_directory(parent_path(destination), 0o750)
    if @fs.exists(destination) {
      raise @modelsource.ModelSourceError::FilesystemRejected
    }
    @fs.rename(staging, destination, replace=false)
    let digest = @crypto.bytes_to_hex_string(
      @crypto.sha256(@utf8.encode(manifest_text)),
    )
    {
      ..latest,
      state: Verified,
      bytes_completed: total,
      manifest_digest: "sha256:\{digest}",
      // The artifact URI is the store-relative key of the revision, so the
      // control plane can serve exactly these bytes without a second mapping.
      artifact_uri: @modelsource.local_artifact_uri(
        "models/modelscope/\{operation.import_id}",
      ),
      error_code: "",
      updated_unix_ms: @async.now(),
    }
  } catch {
    error => {
      let cancelled = error is @modelsource.ModelSourceError::ImportCancelled
      {
        ..latest,
        state: if cancelled {
          Cancelled
        } else {
          Failed
        },
        error_code: safe_error_code(error),
        updated_unix_ms: @async.now(),
      }
    }
  } noraise {
    value => value
  }
  ignore(store.replace(completed))
}

///|
/// Re-derive a local revision from ModelScope. Every file the upstream
/// revision declares must already be present with the upstream size and
/// SHA-256; a file that is absent, truncated, or drifted is restored from
/// ModelScope instead of being silently accepted, because the upstream
/// revision — not the local copy — is the authority for this plane.
async fn run_local_registration(
  store : @modelsource.FileImportStore,
  client : @modelsource.ModelScopeClient,
  model_root : String,
  operation : @modelsource.ImportOperation,
) -> Unit {
  let directory = "\{model_root}/\{operation.local_directory}"
  let mut latest = operation
  let completed = try {
    if !@fs.exists(directory) {
      raise @modelsource.ModelSourceError::FilesystemRejected
    }
    let upstream_tree = client.tree(operation.model_id, operation.revision)
    let tree = if operation.component == "" {
      upstream_tree
    } else {
      @modelsource.component_tree(upstream_tree, operation.component)
    }
    let mut total = 0L
    for file in tree.files {
      total += file.size
    }
    if total <= 0L {
      raise @modelsource.ModelSourceError::ArtifactTooLarge
    }
    latest = {
      ..operation,
      files_total: tree.files.length(),
      files_completed: 0,
      bytes_total: total,
      bytes_completed: 0L,
      manifest_digest: "",
      artifact_uri: "",
      error_code: "",
      cancel_requested: false,
      updated_unix_ms: @async.now(),
    }
    ignore(store.replace(latest))
    let mut confirmed = 0L
    let mut in_flight = 0L
    let mut unsaved_progress = 0L
    let mut restored = 0
    let mut file_index = 0
    let record_progress : async (Int64) -> Unit = delta => {
      in_flight += delta
      if delta > 0L {
        unsaved_progress += delta
      }
      latest = {
        ..latest,
        bytes_completed: confirmed + in_flight,
        updated_unix_ms: @async.now(),
      }
      if unsaved_progress >= 268435456L {
        guard store.get(operation.import_id) is Some(progress_state) else {
          raise @modelsource.ModelSourceError::ImportNotFound
        }
        if progress_state.cancel_requested {
          raise @modelsource.ModelSourceError::ImportCancelled
        }
        ignore(store.replace(latest))
        unsaved_progress = 0L
      }
    }
    // Pass one proves the tree; pass two repairs only what disagreed. Keeping
    // the two apart is what makes the repair budget decidable before a single
    // byte is fetched.
    let repairs : Array[@modelsource.ModelScopeFile] = []
    for file in tree.files {
      guard store.get(operation.import_id) is Some(observed) else {
        raise @modelsource.ModelSourceError::ImportNotFound
      }
      if observed.cancel_requested {
        raise @modelsource.ModelSourceError::ImportCancelled
      }
      let path = "\{directory}/\{file.path}"
      let mut matched = false
      if @fs.exists(path) {
        let existing = @fs.open(path, mode=ReadOnly)
        if existing.size() == file.size {
          let digest = @crypto.SHA256::new()
          while existing.read_some(max_len=1048576) is Some(chunk) {
            digest.update(chunk)
            record_progress(chunk.length().to_int64())
          }
          if @crypto.bytes_to_hex_string(digest.finalize()) == file.sha256 {
            matched = true
          }
        }
        existing.close()
      }
      if !matched {
        repairs.push(file)
      }
      confirmed += file.size
      in_flight = 0L
      unsaved_progress = 0L
      file_index += 1
      latest = {
        ..latest,
        files_completed: file_index,
        bytes_completed: confirmed,
        updated_unix_ms: @async.now(),
      }
      ignore(store.replace(latest))
    }
    // A named revision is a claim about *this* directory. When the two
    // disagree by more than a sliver, the directory is not that revision, and
    // silently fetching the difference could pull hundreds of gigabytes from
    // upstream. Refuse instead so the operator names the right revision.
    let mut repair_bytes = 0L
    for file in repairs {
      repair_bytes += file.size
    }
    if repair_bytes > (total / 100L).max(1073741824L) {
      raise @modelsource.ModelSourceError::FileSizeMismatch
    }
    for file in repairs {
      guard store.get(operation.import_id) is Some(observed) else {
        raise @modelsource.ModelSourceError::ImportNotFound
      }
      if observed.cancel_requested {
        raise @modelsource.ModelSourceError::ImportCancelled
      }
      let path = "\{directory}/\{file.path}"
      // Publish the restore to a sibling first so a failure never leaves a
      // half-written file at the served path.
      in_flight = 0L
      restored += 1
      let staging = "\{path}.lunanexa-restore"
      ensure_directory(parent_path(path), 0o750)
      errdefer (@fs.remove(staging) catch { _ => () })
      let upstream_file = if operation.component == "" {
        file
      } else {
        @modelsource.component_upstream_file(file, operation.component)
      }
      client.download_file(
        operation.model_id,
        tree.revision,
        upstream_file,
        staging,
        record_progress,
        () => {
          match store.get(operation.import_id) {
            Some(value) => value.cancel_requested
            None => true
          }
        },
      )
      @fs.rename(staging, path, replace=true)
      latest = {
        ..latest,
        error_code: "restored-\{restored}-from-modelscope",
        updated_unix_ms: @async.now(),
      }
      ignore(store.replace(latest))
    }
    let manifest_text = source_manifest(operation, tree)
    let manifest_digest = write_source_manifest(directory, manifest_text)
    {
      ..latest,
      state: Verified,
      bytes_completed: total,
      manifest_digest,
      artifact_uri: @modelsource.local_artifact_uri(operation.local_directory),
      error_code: if restored > 0 {
        "restored-\{restored}-from-modelscope"
      } else {
        ""
      },
      updated_unix_ms: @async.now(),
    }
  } catch {
    error => {
      let cancelled = error is @modelsource.ModelSourceError::ImportCancelled
      {
        ..latest,
        state: if cancelled {
          Cancelled
        } else {
          Failed
        },
        error_code: safe_error_code(error),
        updated_unix_ms: @async.now(),
      }
    }
  } noraise {
    value => value
  }
  ignore(store.replace(completed))
}

///|
async fn read_directory(path : String) -> Array[String] {
  try @fs.readdir(path, sort=true) catch {
    _ => []
  } noraise {
    value => value
  }
}

///|
async fn entry_size(path : String) -> Int64 {
  let file = try @fs.open(path, mode=ReadOnly) catch {
    _ => return 0L
  } noraise {
    value => value
  }
  defer file.close()
  try file.size() catch {
    _ => 0L
  } noraise {
    value => value
  }
}

///|
/// Bounded tree measurement: enough for an operator to recognise a directory,
/// cheap enough that listing the store root stays a fast read.
async fn measure_tree(root : String, depth : Int) -> (Int, Int64) {
  if depth > 6 {
    return (0, 0L)
  }
  let mut files = 0
  let mut bytes = 0L
  for name in read_directory(root) {
    let path = "\{root}/\{name}"
    let kind = try @fs.kind(path, follow_symlink=false) catch {
      _ => continue
    } noraise {
      value => value
    }
    match kind {
      Regular => {
        files += 1
        bytes += entry_size(path)
      }
      Directory => {
        let (nested_files, nested_bytes) = measure_tree(path, depth + 1)
        files += nested_files
        bytes += nested_bytes
      }
      _ => ()
    }
  }
  (files, bytes)
}

///|
/// A revision root is the directory that directly holds a model's entry
/// point. A deeper layout (a diffusers tree, a ComfyUI asset split) belongs to
/// the root above it, so the walk stops as soon as it finds one.
async fn is_model_root(path : String) -> Bool {
  if @fs.exists("\{path}/config.json") || @fs.exists("\{path}/model_index.json") {
    return true
  }
  read_directory(path).any(name => name.has_suffix(".gguf"))
}

///|
/// Where the adapter writes what it downloaded. That area is already in the
/// plane as imports, so it is not offered as a directory to register.
let managed_download_prefix : String = "models/modelscope"

///|
let model_root_search_depth : Int = 4

///|
let model_root_search_limit : Int = 256

///|
/// Find every revision root under the store. Hidden directories count: a
/// leading dot is how these staging areas were named, and skipping them hid
/// roughly 700 GB of real checkpoints from the operator entirely.
async fn collect_model_roots(
  root : String,
  relative : String,
  depth : Int,
  found : Array[String],
) -> Unit {
  if depth > model_root_search_depth ||
    found.length() >= model_root_search_limit {
    return
  }
  let path = if relative == "" { root } else { "\{root}/\{relative}" }
  for name in read_directory(path) {
    if name == "_build" ||
      name == ".git" ||
      name == "receipts" ||
      name == "sources" {
      continue
    }
    if !@modelsource.valid_local_directory(name) {
      continue
    }
    let child = "\{path}/\{name}"
    let child_relative = if relative == "" {
      name
    } else {
      "\{relative}/\{name}"
    }
    if child_relative == managed_download_prefix ||
      child_relative.has_prefix("\{managed_download_prefix}/") {
      continue
    }
    let kind = try @fs.kind(child, follow_symlink=false) catch {
      _ => continue
    } noraise {
      value => value
    }
    if kind != Directory {
      continue
    }
    if is_model_root(child) || @fs.exists("\{child}/\{SourceManifestFileName}") {
      found.push(child_relative)
    }
    // A model root can contain separately deliverable submodels. Continue the
    // bounded walk so FL2VA and Ref2VA are selectable alongside MiniMax-H3.
    collect_model_roots(root, child_relative, depth + 1, found)
  }
}

///|
/// Directories the operator can register. Size and file count are advisory;
/// the revision is only believed after ModelScope confirms it.
async fn local_directory_listing(
  store : @modelsource.FileImportStore,
  model_root : String,
) -> Json {
  let registered : Map[String, Bool] = Map([])
  for operation in store.list() {
    if operation.local_directory != "" {
      registered[operation.local_directory] = true
    }
  }
  let roots : Array[String] = []
  collect_model_roots(model_root, "", 0, roots)
  roots.sort_by((left, right) => left.compare(right))
  let entries : Array[Json] = []
  for relative in roots {
    let (files, bytes) = measure_tree("\{model_root}/\{relative}", 0)
    entries.push(
      @modelsource.local_directory_entry(
        relative,
        files,
        bytes,
        registered.get(relative).unwrap_or(false),
      ),
    )
  }
  Json::object({ "directories": Json::array(entries) })
}

///|
async fn worker_loop(
  store : @modelsource.FileImportStore,
  client : @modelsource.ModelScopeClient,
  model_root : String,
  maximum_import_bytes : Int64,
) -> Unit {
  for ;; {
    match store.next_queued() {
      Some(operation) =>
        if operation.local_directory == "" {
          run_import(store, client, model_root, maximum_import_bytes, operation)
        } else {
          run_local_registration(store, client, model_root, operation)
        }
      None => @async.sleep(500)
    }
  }
}

///|
async fn serve(
  address : String,
  token : String,
  store : @modelsource.FileImportStore,
  client : @modelsource.ModelScopeClient,
  model_root : String,
) -> Unit {
  let server = @http.Server(@socket.Addr::parse(address), reuse_addr=true)
  server.run_forever(allow_failure=true, max_connections=32) <| ((
    request,
    reader,
    connection,
  ) => {
    if request.meth == Get && request.path == "/health" {
      send_json(connection, 200, { "status": "ok" })
      return
    }
    if !bearer_authorized(request.headers, token) {
      send_json(
        connection,
        401,
        error_json("Unauthenticated", "model-source authority is required"),
      )
      return
    }
    let body = if request.meth == Post { read_body(reader) } else { "" }
    let result : (Int, Json) = try {
      match (request.meth, request.path) {
        (Post, "/internal/v1/modelscope/search") => {
          let input : SearchRequest = decode(body)
          let page = client.search(
            input.query,
            page_number=input.page_number,
            page_size=input.page_size,
          )
          (200, page.to_json())
        }
        (Post, "/internal/v1/modelscope/detail") => {
          let input : DetailRequest = decode(body)
          (200, client.detail(input.model_id).to_json())
        }
        (Get, "/internal/v1/modelscope/local-directories") =>
          (200, local_directory_listing(store, model_root))
        (Get, "/internal/v1/modelscope/imports") =>
          (200, store.list().to_json())
        (Post, "/internal/v1/modelscope/imports") => {
          let input : @modelsource.ImportRequest = decode(body)
          let detail = client.detail(input.model_id)
          if detail.private || detail.gated {
            raise @modelsource.ModelSourceError::UpstreamRejected
          }
          let created = store.create(input, detail.license, @async.now())
          (202, created.to_json())
        }
        (Post, "/internal/v1/modelscope/imports:register-local") => {
          let input = decode_local_registration(body)
          if !@modelsource.valid_model_id(input.model_id) {
            raise @modelsource.ModelSourceError::InvalidModelId
          }
          if !@modelsource.valid_revision(input.revision) {
            raise @modelsource.ModelSourceError::InvalidRevision
          }
          if !@modelsource.valid_local_directory(input.directory) {
            raise @modelsource.ModelSourceError::InvalidRepositoryPath
          }
          if input.component != "" &&
            (
              !@modelsource.valid_component(input.component) ||
              !input.directory.has_suffix("/\{input.component}")
            ) {
            raise @modelsource.ModelSourceError::InvalidRepositoryPath
          }
          let detail = client.detail(input.model_id)
          if detail.private || detail.gated {
            raise @modelsource.ModelSourceError::UpstreamRejected
          }
          let created = store.create_local(
            { model_id: input.model_id, revision: input.revision, },
            detail.license,
            input.directory,
            model_root,
            @async.now(),
            component=input.component,
          )
          (202, created.to_json())
        }
        (Post, path) if path.has_prefix("/internal/v1/modelscope/imports/") &&
          path.has_suffix("/cancel") => {
          let prefix = "/internal/v1/modelscope/imports/".length()
          let suffix = "/cancel".length()
          let id = path[prefix:path.length() - suffix].to_owned()
          (202, store.cancel(id, @async.now()).to_json())
        }
        (Post, path) if path.has_prefix("/internal/v1/modelscope/imports/") &&
          path.has_suffix("/retry") => {
          let prefix = "/internal/v1/modelscope/imports/".length()
          let suffix = "/retry".length()
          let id = path[prefix:path.length() - suffix].to_owned()
          (202, store.retry(id, @async.now()).to_json())
        }
        _ => (404, error_json("NotFound", "model-source route not found"))
      }
    } catch {
      @modelsource.ModelSourceError::ImportAlreadyExists =>
        (
          409,
          error_json("ImportAlreadyExists", "this exact import already exists"),
        )
      @modelsource.ModelSourceError::ImportNotFound =>
        (404, error_json("ImportNotFound", "the import does not exist"))
      @modelsource.ModelSourceError::ImportNotCancelable =>
        (
          409,
          error_json(
            "ImportNotCancelable", "the import is no longer cancelable",
          ),
        )
      @modelsource.ModelSourceError::ImportNotRetryable =>
        (
          409,
          error_json(
            "ImportNotRetryable", "only a failed or cancelled import can be retried",
          ),
        )
      @modelsource.ModelSourceError::UpstreamRejected =>
        (
          502,
          error_json("ModelScopeRejected", "ModelScope rejected the request"),
        )
      @modelsource.ModelSourceError::InvalidUpstreamResponse =>
        (
          502,
          error_json(
            "InvalidModelScopeResponse", "ModelScope returned an invalid response",
          ),
        )
      error => {
        println("[model-source] request failed: \{error}")
        (
          400,
          error_json("InvalidRequest", "the model-source request is invalid"),
        )
      }
    } noraise {
      value => value
    }
    send_json(connection, result.0, result.1)
  })
}

///|
async fn main {
  let token = required_environment("LUNANEXA_MODEL_SOURCE_TOKEN")
  if token.length() < 32 || token.length() > 4096 {
    raise Failure("model-source authority must contain 32 to 4096 bytes")
  }
  let address = @env.get_env_var("LUNANEXA_MODEL_SOURCE_ADDRESS").unwrap_or(
    "0.0.0.0:8090",
  )
  let model_root = required_environment("LUNANEXA_MODEL_STORE_ROOT")
  let state_root = required_environment("LUNANEXA_MODEL_SOURCE_STATE_ROOT")
  let maximum_import_bytes : Int64 = @env.get_env_var(
    "LUNANEXA_MODEL_SOURCE_MAXIMUM_IMPORT_BYTES",
  ).map_or(214748364800L, value => @string.parse_int64(value))
  if maximum_import_bytes <= 0L {
    raise Failure("maximum import bytes must be positive")
  }
  ensure_directory(model_root, 0o750)
  ensure_directory(state_root, 0o700)
  let store = @modelsource.FileImportStore::open(
    "\{state_root}/modelsource-imports.json",
  )
  let client = @modelsource.ModelScopeClient::new()
  @async.with_task_group <| group => {
    group.spawn_bg(allow_failure=false) <| () => {
      worker_loop(store, client, model_root, maximum_import_bytes)
    }
    group.spawn_bg(allow_failure=false) <| () => {
      serve(address, token, store, client, model_root)
    }
  }
}
