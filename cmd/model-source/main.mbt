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
fn safe_error_code(error : Error) -> String {
  match error {
    @modelsource.ModelSourceError::ImportCancelled => "cancelled"
    @modelsource.ModelSourceError::ArtifactTooLarge => "artifact-too-large"
    @modelsource.ModelSourceError::FileDigestMismatch => "digest-mismatch"
    @modelsource.ModelSourceError::FileSizeMismatch => "size-mismatch"
    @modelsource.ModelSourceError::UpstreamRejected => "upstream-rejected"
    @modelsource.ModelSourceError::InvalidUpstreamResponse =>
      "invalid-upstream-response"
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
    let manifest : VerifiedManifest = {
      schema_version: "lunanexa.modelsource.verified.v1",
      source: "modelscope",
      model_id: operation.model_id,
      requested_revision: operation.revision,
      observed_revision: tree.revision,
      generated_unix_ms: @async.now(),
      files: tree.files,
    }
    let manifest_text = manifest.to_json().stringify(indent=2)
    @fs.write_file(
      "\{staging}/lunanexa-source-manifest.json",
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
      artifact_uri: "modelstore://modelscope/\{operation.import_id}",
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
async fn worker_loop(
  store : @modelsource.FileImportStore,
  client : @modelsource.ModelScopeClient,
  model_root : String,
  maximum_import_bytes : Int64,
) -> Unit {
  for ;; {
    match store.next_queued() {
      Some(operation) =>
        run_import(store, client, model_root, maximum_import_bytes, operation)
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
      serve(address, token, store, client)
    }
  }
}
