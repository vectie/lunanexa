///|
const MaximumBytes : Int = 67108864

///|
priv struct Intent {
  session_id : String
  idempotency_key : String
  direction : @offline.OfflineTransferDirection
  object_ref : String
  session_token_sha256 : String
  media_types : Array[String]
  maximum_byte_count : Int64
  expected_sha256 : String?
  expires_unix_ms : Int64
  upload_grant_id : String?
} derive(ToJson, FromJson, Eq)

///|
priv struct Completion {
  session_id : String
  session_token : String
  media_type : String
  byte_count : Int64
  sha256 : String
  provider_receipt : String
} derive(ToJson, FromJson)

///|
extend Completion with ToJson::{to_json}

///|
priv struct Record {
  intent : Intent
  // issued -> pending -> consumed. Pending is a durable callback outbox.
  state : String
  completion : Completion?
  upload : @offline.EvidenceUploadCallback?
} derive(ToJson, FromJson)

///|
extend Record with ToJson::{to_json}

///|
priv struct Config {
  root : String
  endpoint : String
  token : String
  scanner_token : String
  controller : String
  bucket : String
  s3_endpoint : String
}

///|
fn digest(bytes : Bytes) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(bytes))}"
}

///|
fn same_digest(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for i in 0..<left.length() {
    difference = difference | (left[i].to_int() ^ right[i].to_int())
  }
  difference == 0
}

///|
fn failure_status(error : Error) -> (Int, String) {
  match error {
    Failure::Failure("body-too-large") => (413, "body-too-large")
    Failure::Failure("session-conflict" | "object-write-conflict") =>
      (409, "immutable-conflict")
    Failure::Failure(
      "invalid-object-reference"
      | "invalid-transfer-intent"
      | "invalid-session"
      | "invalid-size"
      | "invalid-object-read"
      | "media-type-mismatch"
      | "digest-mismatch"
    ) => (400, "invalid-transfer")
    Failure::Failure(
      "active-content"
      | "active-content-or-invalid-office-document"
      | "malware-detected"
    ) => (422, "unsafe-document")
    _ => (503, "transfer-unavailable")
  }
}

///|
fn safe_component(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 256 &&
  value != "." &&
  value != ".." &&
  value
  .iter()
  .all(c => c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.'))
}

///|
fn valid_public_endpoint(endpoint : String) -> Bool {
  endpoint == "/v1/offline-transfers" ||
  (
    (endpoint.has_prefix("https://") || endpoint.has_prefix("http://")) &&
    endpoint.has_suffix("/v1/offline-transfers") &&
    endpoint.length() <= 768 &&
    !endpoint.contains("@") &&
    !endpoint.contains("?") &&
    !endpoint.contains("#") &&
    !endpoint.contains("\\") &&
    !endpoint.any(c => c.is_whitespace())
  )
}

///|
fn trusted_service_endpoint(endpoint : String) -> Bool {
  if endpoint.contains("@") ||
    endpoint.contains("?") ||
    endpoint.contains("#") ||
    endpoint.contains("\\") ||
    endpoint.any(c => c.is_whitespace()) {
    return false
  }
  if endpoint.has_prefix("https://") {
    return endpoint.length() > 8
  }
  for prefix in ["http://127.0.0.1:", "http://[::1]:"] {
    if endpoint.has_prefix(prefix) {
      let authority = endpoint[prefix.length():].split("/").next().unwrap_or("")
      return !authority.is_empty() &&
        authority.iter().all(c => c is ('0'..='9'))
    }
  }
  false
}

///|
fn object_key(reference : String, bucket : String) -> String raise {
  let key = if reference.has_prefix("object://") {
    reference[9:].to_owned()
  } else if reference.has_prefix("s3://\{bucket}/") {
    reference[6 + bucket.length():].to_owned()
  } else {
    raise Failure("invalid-object-reference")
  }
  if key.length() > 1024 ||
    !key.split("/").all(s => safe_component(s.to_owned())) {
    raise Failure("invalid-object-reference")
  }
  key
}

///|
fn validate(intent : Intent, bucket : String, now : Int64) -> Unit raise {
  ignore(object_key(intent.object_ref, bucket))
  if !safe_component(intent.session_id) ||
    intent.idempotency_key.length() == 0 ||
    intent.idempotency_key.length() > 256 ||
    !@offline.valid_sha256(intent.session_token_sha256) ||
    intent.maximum_byte_count <= 0L ||
    intent.maximum_byte_count > MaximumBytes.to_int64() ||
    intent.expires_unix_ms <= now ||
    intent.expires_unix_ms > now + 86400000L ||
    intent.media_types.is_empty() ||
    intent.media_types.length() > 8 ||
    intent.media_types.any(t => !supported_media(t)) ||
    intent.expected_sha256.map_or(false, d => !@offline.valid_sha256(d)) ||
    (intent.direction == UploadTransfer && intent.upload_grant_id is None) {
    raise Failure("invalid-transfer-intent")
  }
}

///|
fn supported_media(media : String) -> Bool {
  [
    "application/pdf", "image/png", "image/jpeg", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ].contains(media)
}

///|
fn matches_magic(bytes : Bytes, media : String) -> Bool {
  match media {
    "application/pdf" => bytes is [b'%', b'P', b'D', b'F', b'-', ..]
    "image/png" => bytes is [0x89, b'P', b'N', b'G', 13, 10, 26, 10, ..]
    "image/jpeg" => bytes is [0xff, 0xd8, 0xff, ..]
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    | "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" =>
      bytes is [b'P', b'K', 3, 4, ..]
    _ => false
  }
}

///|
async fn bounded(reader : &@io.Reader, limit : Int) -> Bytes {
  let buffer = @buffer.Buffer()
  for total = 0 {
    match reader.read_some(max_len=(limit + 1 - total).min(65536)) {
      None => break
      Some(bytes) => {
        if total + bytes.length() > limit {
          raise Failure("body-too-large")
        }
        buffer.write_bytes(bytes)
        continue total + bytes.length()
      }
    }
  }
  buffer.to_bytes()
}

///|
async fn bounded_file(file : @fs.File, limit : Int) -> Bytes {
  // Use the filesystem read operation for regular files. Generic IO Reader
  // polling is not supported by epoll for regular files on Linux.
  let output = @buffer.Buffer()
  let chunk = FixedArray::make(65536, b'\x00')
  for total = 0 {
    let count = file.read(chunk, max_len=(limit + 1 - total).min(65536))
    if count == 0 {
      break
    }
    if total + count > limit {
      raise Failure("body-too-large")
    }
    output.write_bytes(Bytes::from_array(chunk[:count]))
    continue total + count
  }
  output.to_bytes()
}

///|
async fn persist(config : Config, record : Record) -> Unit {
  let path = "\{config.root}/\{record.intent.session_id}.json"
  @fs.write_file(
    "\{path}.tmp",
    record.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename("\{path}.tmp", path, replace=true)
}

///|
async fn load(config : Config, id : String) -> Record {
  if !safe_component(id) {
    raise Failure("invalid-session")
  }
  @json.from_json(
    @json.parse(@fs.read_file("\{config.root}/\{id}.json").text()),
  )
}

///|
async fn command(program : String, args : Array[String]) -> Unit {
  let status = @async.with_timeout(120000, () => @process.run(program, args))
  if status != 0 {
    raise Failure("dependency-rejected")
  }
}

///|
async fn s3(config : Config, args : Array[String]) -> Unit {
  // Do not write provider metadata or object disposition names to service logs.
  let (status, _, _) = @async.with_timeout(120000, () => {
    @process.collect_output(
      "aws",
      ["--endpoint-url", config.s3_endpoint, "--no-cli-pager", ..args],
    )
  })
  if status != 0 {
    raise Failure("dependency-rejected")
  }
}

///|
async fn bounded_command_output(
  program : String,
  args : Array[String],
  limit : Int,
) -> (Int, Bytes) {
  let (reader, writer) = @pipe.pipe()
  defer reader.close()
  let mut status = -1
  let bytes = @async.with_timeout(30000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        defer writer.close()
        status = @process.run(program, args, stdout=writer)
      })
      bounded(reader, limit)
    })
  })
  (status, bytes)
}

///|
async fn read_object(
  config : Config,
  reference : String,
  maximum : Int,
) -> Bytes {
  let key = object_key(reference, config.bucket)
  let directory = @fs.tmpdir(prefix="lunanexa-offline-get-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/object"
  // Range bounds disk use even if the object metadata is hostile.
  s3(config, [
    "s3api",
    "get-object",
    "--bucket",
    config.bucket,
    "--key",
    key,
    "--range",
    "bytes=0-\{maximum}",
    path,
  ])
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  bounded_file(file, maximum)
}

///|
async fn write_object(
  config : Config,
  reference : String,
  bytes : Bytes,
  media : String,
) -> Unit {
  let key = object_key(reference, config.bucket)
  let directory = @fs.tmpdir(prefix="lunanexa-offline-put-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/object"
  @fs.write_file(
    path,
    bytes,
    create_mode=CreateNew,
    permission=0o600,
    sync=Full,
  )
  // Conditional create prevents a different session replacing an immutable artifact.
  let stored = try {
    s3(config, [
      "s3api",
      "put-object",
      "--bucket",
      config.bucket,
      "--key",
      key,
      "--body",
      path,
      "--content-type",
      media,
      "--if-none-match",
      "*",
    ])
    true
  } catch {
    _ => false
  }
  let actual = read_object(config, reference, bytes.length())
  if digest(actual) != digest(bytes) {
    raise Failure("object-write-conflict")
  }
  ignore(stored)
}

///|
async fn scan(bytes : Bytes, media : String) -> String {
  if !matches_magic(bytes, media) {
    raise Failure("media-type-mismatch")
  }
  let directory = @fs.tmpdir(prefix="lunanexa-offline-scan-")
  defer @fs.rmdir(directory, recursive=true)
  let path = "\{directory}/artifact"
  @fs.write_file(path, bytes, create_mode=CreateNew, permission=0o600)
  // clamscan errors (including missing or stale database policy) never mean clean.
  let scanner_status = @async.with_timeout(120000, () => {
    @process.run("clamscan", [
      "--no-summary", "--stdout", "--alert-exceeds-max=yes", "--alert-encrypted=yes",
      "--alert-macros=yes", "--alert-broken-media=yes", "--official-db-only=yes",
      "--fail-if-cvd-older-than=3", "--max-scantime=0", "--max-filesize=64M", "--max-scansize=128M",
      path,
    ])
  })
  if scanner_status == 1 {
    raise Failure("malware-detected")
  }
  if scanner_status != 0 {
    raise Failure("scanner-unavailable")
  }
  if media.has_prefix("application/vnd.openxmlformats-") {
    // Inspect archived XML without extracting attacker-controlled paths.
    // Macro documents and encryption are also rejected by ClamAV above.
    let (status, xml) = bounded_command_output(
      "unzip",
      ["-p", path, "*.xml", "*.rels"],
      MaximumBytes,
    )
    if status != 0 {
      raise Failure("active-content-or-invalid-office-document")
    }
    if office_active_content(@utf8.decode(xml)) {
      raise Failure("active-content-or-invalid-office-document")
    }
  }
  if media == "application/pdf" {
    command("qpdf", ["--check", path])
    let normalized = "\{directory}/structure.json"
    command("qpdf", [
      "--json-output", "--json-stream-data=none", path, normalized,
    ])
    let file = @fs.open(normalized, mode=ReadOnly)
    defer file.close()
    let expanded = bounded_file(file, MaximumBytes)
    if pdf_active_content(@json.parse(@utf8.decode(expanded))) {
      raise Failure("active-content")
    }
  }
  "clamav:\{digest(bytes)}"
}

///|
fn pdf_active_content(value : Json) -> Bool {
  let forbidden = [
    "/JavaScript", "/JS", "/Launch", "/EmbeddedFile", "/OpenAction", "/AA",
  ]
  match value {
    Object(fields) =>
      fields
      .iter()
      .any(pair => forbidden.contains(pair.0) || pdf_active_content(pair.1))
    Array(values) => values.any(pdf_active_content)
    String(name) => forbidden.contains(name)
    _ => false
  }
}

///|
fn office_active_content(xml : String) -> Bool {
  let builder = StringBuilder()
  for c in xml.to_lower() {
    if !c.is_whitespace() {
      builder.write_char(c)
    }
  }
  let compact = builder.to_string()
  [
    "targetmode=\"external\"", "targetmode='external'", "ddeauto", "oleobject", "activex",
  ].any(value => compact.contains(value))
}

///|
async fn callback(
  config : Config,
  suffix : String,
  token : String,
  body : Json,
) -> Unit {
  @async.with_timeout(15000, () => callback_once(config, suffix, token, body))
}

///|
async fn callback_once(
  config : Config,
  suffix : String,
  token : String,
  body : Json,
) -> Unit {
  let stream = @http.post_stream("\{config.controller}\{suffix}", headers={
    "Authorization": "Bearer \{token}",
    "Content-Type": "application/json",
  })
  defer stream.close()
  stream.write(body)
  let response = stream.end_request()
  if response.code < 200 || response.code >= 300 {
    raise Failure("callback-rejected")
  }
  ignore(bounded(stream, 1048576))
}

///|
async fn flush(config : Config, record : Record) -> Unit {
  guard record.completion is Some(completion) else { return }
  callback(
    config,
    "/v1/offline-commerce/operator/transfer-results",
    config.token,
    completion.to_json(),
  )
  if record.upload is Some(upload) {
    callback(
      config,
      "/v1/offline-commerce/operator/upload-callbacks",
      config.scanner_token,
      upload.to_json(),
    )
  }
  persist(config, {
    ..record,
    state: "consumed",
    completion: None,
    upload: None,
  })
}

///|
fn header(request : @http.Request, name : String) -> String {
  request.headers
  .iter()
  .find_first(pair => pair.0.to_lower() == name)
  .map(pair => pair.1)
  .unwrap_or("")
}

///|
async fn json_reply(
  connection : @http.ServerConnection,
  code : Int,
  body : Json,
) -> Unit {
  connection.send_response(code, "Response", extra_headers={
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  })
  connection.write_string(body.stringify())
  connection.end_response()
}

///|
async fn bytes_reply(
  connection : @http.ServerConnection,
  bytes : Bytes,
  media : String,
) -> Unit {
  connection.send_response(200, "OK", extra_headers={
    "Content-Type": media,
    "Content-Length": bytes.length().to_string(),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Content-Disposition": "attachment",
  })
  connection.write(bytes)
  connection.end_response()
}

///|
async fn handle(
  config : Config,
  request : @http.Request,
  reader : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  let path = request.path
  if path == "/healthz" {
    return json_reply(connection, 200, { "live": true })
  }
  let server_auth = header(request, "authorization") == "Bearer \{config.token}"
  if path == "/internal/v1/objects/read" && server_auth && request.meth == Post {
    let body = @json.parse(@utf8.decode(bounded(reader, 16384)))
    guard body
      is { "object_ref": String(reference), "maximum_byte_count": size, .. } else {
      raise Failure("invalid-object-read")
    }
    let maximum : Int64 = @json.from_json(size)
    if maximum <= 0L || maximum > MaximumBytes.to_int64() {
      raise Failure("invalid-size")
    }
    return bytes_reply(
      connection,
      read_object(config, reference, maximum.to_int()),
      "application/octet-stream",
    )
  }
  if path == "/internal/v1/objects/write" && server_auth && request.meth == Post {
    let bytes = bounded(reader, MaximumBytes)
    let sha = digest(bytes)
    let media = header(request, "content-type")
    if sha != header(request, "x-lunanexa-sha256") {
      raise Failure("digest-mismatch")
    }
    ignore(scan(bytes, media))
    write_object(config, header(request, "x-lunanexa-object-ref"), bytes, media)
    return json_reply(connection, 201, {
      "sha256": sha,
      "byte_count": bytes.length().to_int64().to_json(),
      "provider_receipt": "s3:\{sha}",
    })
  }
  if path == "/v1/offline-transfers" && server_auth && request.meth == Post {
    let intent : Intent = @json.from_json(
      @json.parse(@utf8.decode(bounded(reader, 16384))),
    )
    validate(intent, config.bucket, @async.now())
    let filename = "\{config.root}/\{intent.session_id}.json"
    if @fs.exists(filename) {
      let previous = load(config, intent.session_id)
      if previous.intent != intent || previous.state != "issued" {
        raise Failure("session-conflict")
      }
    } else {
      persist(config, {
        intent,
        state: "issued",
        completion: None,
        upload: None,
      })
    }
    return json_reply(connection, 201, {
      "session_id": intent.session_id,
      "transfer_url": "\{config.endpoint}/\{intent.session_id}",
      "expires_unix_ms": intent.expires_unix_ms.to_json(),
      "provider_receipt": "s3-grant:\{intent.session_id}",
    })
  }
  if !path.has_prefix("/v1/offline-transfers/") {
    return json_reply(connection, 401, { "error": "unauthorized" })
  }
  let record = load(config, path[22:].to_owned())
  let intent = record.intent
  let auth = header(request, "authorization")
  if !auth.has_prefix("Bearer ") {
    return json_reply(connection, 401, { "error": "unauthorized" })
  }
  let token = auth[7:].to_owned()
  if !same_digest(digest(@utf8.encode(token)), intent.session_token_sha256) ||
    intent.expires_unix_ms <= @async.now() {
    return json_reply(connection, 401, { "error": "unauthorized" })
  }
  if record.state != "issued" {
    return json_reply(connection, 409, { "error": "already-consumed" })
  }
  let (bytes, media, upload) = if intent.direction == UploadTransfer &&
    request.meth == Put {
    let bytes = bounded(reader, intent.maximum_byte_count.to_int())
    let media = header(request, "content-type")
    if !intent.media_types.contains(media) {
      raise Failure("media-type-mismatch")
    }
    let receipt = scan(bytes, media)
    if intent.expected_sha256.map_or(false, d => d != digest(bytes)) {
      raise Failure("digest-mismatch")
    }
    write_object(config, intent.object_ref, bytes, media)
    let upload : @offline.EvidenceUploadCallback = {
      callback_id: "scan-\{intent.session_id}",
      grant_id: intent.upload_grant_id.unwrap(),
      expected_object_ref: intent.object_ref,
      media_type: media,
      byte_count: bytes.length().to_int64(),
      sha256: digest(bytes),
      scan_passed: true,
      active_content_detected: false,
      scanner_receipt: receipt,
      verified: true,
      completed_unix_ms: @async.now(),
    }
    (bytes, media, Some(upload))
  } else if intent.direction == DownloadTransfer && request.meth == Get {
    let bytes = read_object(
      config,
      intent.object_ref,
      intent.maximum_byte_count.to_int(),
    )
    let media = intent.media_types[0]
    if !matches_magic(bytes, media) ||
      intent.expected_sha256.map_or(false, d => d != digest(bytes)) {
      raise Failure("digest-mismatch")
    }
    (bytes, media, None)
  } else {
    return json_reply(connection, 405, { "error": "method-not-allowed" })
  }
  let pending = {
    ..record,
    state: "pending",
    upload,
    completion: Some({
      session_id: intent.session_id,
      session_token: token,
      media_type: media,
      byte_count: bytes.length().to_int64(),
      sha256: digest(bytes),
      provider_receipt: "s3-transfer:\{intent.session_id}:\{digest(bytes)}",
    }),
  }
  persist(config, pending)
  flush(config, pending)
  if intent.direction == DownloadTransfer {
    bytes_reply(connection, bytes, media)
  } else {
    json_reply(connection, 200, { "completed": true, "sha256": digest(bytes) })
  }
}

///|
fn required(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value != "" else {
    raise Failure("missing configuration: \{name}")
  }
  value
}

///|
async fn main {
  let config : Config = {
    root: required("LUNANEXA_OFFLINE_TRANSFER_STATE_ROOT"),
    endpoint: required("LUNANEXA_OFFLINE_TRANSFER_PUBLIC_ENDPOINT"),
    token: required("LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN"),
    scanner_token: required("LUNANEXA_ARTIFACT_SCANNER_CALLBACK_TOKEN"),
    controller: required("LUNANEXA_CONTROLLER_ENDPOINT"),
    bucket: required("LUNANEXA_OFFLINE_S3_BUCKET"),
    s3_endpoint: required("LUNANEXA_OFFLINE_S3_ENDPOINT"),
  }
  if config.token.length() < 32 ||
    config.scanner_token.length() < 32 ||
    !safe_component(config.bucket) ||
    !valid_public_endpoint(config.endpoint) ||
    !trusted_service_endpoint(config.s3_endpoint) ||
    !trusted_service_endpoint(config.controller) {
    raise Failure("invalid-configuration")
  }
  if @env.args().contains("--self-test") {
    let directory = @fs.tmpdir(prefix="lunanexa-transfer-selftest-")
    defer @fs.rmdir(directory, recursive=true)
    let fixture = "\{directory}/fixture.pdf"
    command("qpdf", ["--empty", fixture])
    let bytes = @fs.read_file(fixture).binary()
    ignore(scan(bytes, "application/pdf"))
    let reference = "object://verification/\{@async.now()}/fixture.pdf"
    write_object(config, reference, bytes, "application/pdf")
    assert_true(read_object(config, reference, bytes.length()) == bytes)
    write_object(config, reference, bytes, "application/pdf")
    let different = @utf8.encode("%PDF-1.7\nnot-the-original-document")
    let conflict_rejected = try {
      write_object(config, reference, different, "application/pdf")
      false
    } catch {
      _ => true
    }
    assert_true(conflict_rejected)
    let eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
    let eicar_path = "\{directory}/eicar-test.txt"
    @fs.write_file(eicar_path, eicar, create_mode=CreateNew, permission=0o600)
    let scan_status = @async.with_timeout(120000, () => {
      @process.run("clamscan", ["--no-summary", eicar_path])
    })
    assert_eq(scan_status, 1)
    println(
      (
        {
          "schema": "lunanexa.offline-transfer.self-test.v1",
          "s3_roundtrip": true,
          "immutable_retry": true,
          "conflicting_write_rejected": true,
          "pdf_scan": true,
          "eicar_rejected": true,
          "sha256": digest(bytes),
        } : Json).stringify(),
    )
    return
  }
  if !@fs.exists(config.root) {
    @fs.mkdir(config.root, recursive=true, permission=0o700)
  }
  let lock = @fs.open(
    "\{config.root}/adapter.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  if !lock.try_lock(Exclusive) {
    raise Failure("adapter-state-already-owned")
  }
  let server = @http.Server(
    @socket.Addr::parse(
      @env.get_env_var("LUNANEXA_OFFLINE_TRANSFER_ADDRESS").unwrap_or(
        "0.0.0.0:8096",
      ),
    ),
  )
  defer server.close()
  let mutex = @async.Mutex()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for ;; {
        mutex.acquire()
        {
          defer mutex.release()
          for name in @fs.readdir(config.root) {
            if name.has_suffix(".json") {
              let record = load(config, name[:name.length() - 5].to_owned())
              if record.state == "pending" {
                flush(config, record) catch {
                  _ => ()
                }
              }
            }
          }
        }
        @async.sleep(5000)
      }
    })
    group.spawn_bg(() => {
      server.run_forever(max_connections=8, allow_failure=true, (
        request,
        reader,
        connection,
      ) => {
        if request.path == "/healthz" {
          return json_reply(connection, 200, { "live": true })
        }
        mutex.acquire()
        defer mutex.release()
        @async.with_timeout(300000, () => {
          handle(config, request, reader, connection)
        }) catch {
          error => {
            let (status, code) = failure_status(error)
            json_reply(connection, status, { "error": code })
          }
        }
      })
    })
  })
}
