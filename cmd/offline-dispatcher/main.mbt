///|
/// Durable single-consumer dispatcher. The controller owns bounded claim retries;
/// local journals close the crash window between external completion and callback.
struct Config {
  origin : String
  token : String
  root : String
}

///|
async fn ensure_directory(path : String) -> Unit {
  @fs.mkdir(path, permission=0o700, recursive=true) catch {
    _ => ignore(@fs.readdir(path))
  }
}

///|
fn required(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value.trim() != "" else {
    raise Failure("missing dispatcher configuration: \{name}")
  }
  value
}

///|
fn digest(bytes : Bytes) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(bytes.to_fixedarray()))}"
}

///|
fn work_directory(root : String, id : String) -> String {
  let hash = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(id).to_fixedarray()),
  )
  "\{root}/\{hash}"
}

///|
fn field(value : Json, name : String) -> String raise {
  guard value is Object(fields) && fields.get(name) is Some(String(text)) else {
    raise Failure("invalid execution plan field: \{name}")
  }
  text
}

///|
fn filename(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 180 &&
  value != "." &&
  value != ".." &&
  value.all(c => {
    c.is_ascii_alphabetic() ||
    c.is_ascii_digit() ||
    c == '_' ||
    c == '-' ||
    c == '.'
  })
}

///|
async fn write_atomic(path : String, bytes : Bytes) -> Unit {
  @fs.write_file(
    "\{path}.next",
    bytes,
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename("\{path}.next", path, replace=true)
}

///|
async fn exchange(
  origin : String,
  token : String,
  path : String,
  verb : @http.RequestMethod,
  body : Bytes,
  extra? : Map[String, String] = {},
  maximum? : Int = 8388608,
) -> (Int, Bytes) {
  @async.with_timeout(30000, () => {
    let headers = extra.copy()
    headers["Authorization"] = "Bearer \{token}"
    let client = @http.Client(origin, headers~)
    defer client.close()
    client.request(verb, path)
    client.write(body)
    let response = client.end_request()
    let chunks = @buffer.Buffer()
    let mut count = 0
    while client.read_some(max_len=65536) is Some(chunk) {
      count += chunk.length()
      if count > maximum {
        raise Failure("dispatcher response exceeds limit")
      }
      chunks.write_bytes(chunk)
    }
    (response.code, chunks.to_bytes())
  })
}

///|
async fn api(
  config : Config,
  path : String,
  verb : @http.RequestMethod,
  body : Json,
) -> Json {
  let (code, bytes) = exchange(
    config.origin,
    config.token,
    path,
    verb,
    if verb == Get {
      b""
    } else {
      @utf8.encode(body.stringify())
    },
    extra={ "Content-Type": "application/json" },
  )
  if code < 200 || code >= 300 {
    raise Failure("dispatcher API rejected request: \{code}")
  }
  @json.parse(@utf8.decode(bytes))
}

///|
async fn callback(config : Config, path : String, result : Json) -> Unit {
  ignore(api(config, path, Post, result))
}

///|
async fn execute(program : String, root : String, mode : String) -> Unit {
  let process_env : Map[String, String] = {
    "PATH": "/usr/local/bin:/usr/bin:/bin",
    "LUNANEXA_OFFLINE_ARTIFACT_STAGING_ROOT": root,
    "LUNANEXA_OFFLINE_ARTIFACT_JOB_FILENAME": "job.json",
    "LUNANEXA_OFFLINE_ARTIFACT_MODE": mode,
  }
  for
    name in [
      "LUNANEXA_RENDER_EVIDENCE_SECRET", "LUNANEXA_OFFLINE_FONT_CONFIG_FILENAME",
      "LUNANEXA_OFFLINE_FONT_ROOT", "LUNANEXA_OFFLINE_PDFTOPPM_BIN",
    ] {
    if @env.get_env_var(name) is Some(value) {
      process_env[name] = value
    }
  }
  let code = @async.with_timeout(240000, () => {
    @process.run(program, [], extra_env=process_env, inherit_env=false)
  })
  if code != 0 {
    raise Failure("artifact subprocess failed")
  }
}

///|
async fn artifact(
  config : Config,
  request : @offline.ArtifactGenerationRequest,
) -> Unit {
  let root = work_directory(config.root, request.request_id)
  ensure_directory(root)
  let pending_path = "\{root}/artifact-pending.json"
  write_atomic(pending_path, @utf8.encode(request.to_json().stringify()))
  let receipt_path = "\{root}/published.json"
  let cached = @fs.read_file(receipt_path).text() catch { _ => "" }
  if cached != "" {
    let result : @offline.ArtifactGenerationResult = @json.from_json(
      @json.parse(cached),
    )
    if result.request_id != request.request_id ||
      result.artifact_id != request.artifact_id ||
      result.expected_object_ref != request.expected_object_ref {
      raise Failure("journal identity mismatch")
    }
    callback(config, "/v1/offline-commerce/operator/generation-results", {
      "result": result.to_json(),
    })
    write_atomic(pending_path, @utf8.encode("null"))
    return
  }
  let plan = api(
    config,
    "/v1/offline-commerce/operator/generation-plan",
    Post,
    request.to_json(),
  )
  let transfer_origin = required("LUNANEXA_OFFLINE_TRANSFER_OBJECT_ENDPOINT")
  let transfer_token = required("LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN")
  let (status, template) = exchange(
    transfer_origin,
    transfer_token,
    "/internal/v1/objects/read",
    Post,
    @utf8.encode(
      (
        {
          "object_ref": field(plan, "template_object_ref"),
          "maximum_byte_count": "67108864",
        } : Json).stringify(),
    ),
    extra={ "Content-Type": "application/json" },
    maximum=67108864,
  )
  if status != 200 || digest(template) != field(plan, "template_sha256") {
    raise Failure("template retrieval integrity failure")
  }
  let resolved_plan = if request.kind == EditableContractDocx ||
    request.kind == PrintReadyContractPdf {
    let markers = @worker.exact_docx_markers(template.to_fixedarray())
    api(config, "/v1/offline-commerce/operator/generation-plan", Post, {
      "request": request.to_json(),
      "markers": markers.to_json(),
    })
  } else {
    plan
  }
  if field(resolved_plan, "template_sha256") != digest(template) ||
    field(resolved_plan, "template_object_ref") !=
    field(plan, "template_object_ref") {
    raise Failure("resolved template identity changed")
  }
  guard resolved_plan is { "job": job_json, .. } && job_json is Object(job) else {
    raise Failure("missing artifact job")
  }
  guard job.get("request") is Some(job_request) &&
    job_request == request.to_json() else {
    raise Failure("execution plan request mismatch")
  }
  for
    name in [
      "template_filename", "prepared_filename", "output_filename", "result_filename",
      "render_manifest_filename",
    ] {
    if !filename(field(job_json, name)) {
      raise Failure("unsafe artifact job filename")
    }
  }
  // Finalization already fsyncs the result and output. Keep these exact bytes
  // across an ambiguous object PUT; rerendering could change PDF timestamps and
  // conflict with an object that was committed before a network failure.
  let previous_job = @fs.read_file("\{root}/job.json").text() catch { _ => "" }
  let previous_result = @fs.read_file(
    "\{root}/\{field(job_json, "result_filename")}",
  ).text() catch {
    _ => ""
  }
  let reuse_finalized = previous_job == job_json.stringify() &&
    previous_result != ""
  if !reuse_finalized {
    write_atomic("\{root}/\{field(job_json, "template_filename")}", template)
    write_atomic("\{root}/job.json", @utf8.encode(job_json.stringify()))
    execute_artifact_pipeline(root)
  }
  let result_text = @fs.read_file(
    "\{root}/\{field(job_json, "result_filename")}",
  ).text()
  let result : @offline.ArtifactGenerationResult = @json.from_json(
    @json.parse(result_text),
  )
  let output = @fs.read_file("\{root}/\{field(job_json, "output_filename")}").binary()
  if result.request_id != request.request_id ||
    result.artifact_id != request.artifact_id ||
    result.expected_object_ref != request.expected_object_ref ||
    result.sha256 != digest(output) ||
    result.byte_count != output.length().to_int64() ||
    !result.verified ||
    !result.render_verified ||
    !result.moonleaf_verified ||
    result.active_content_detected ||
    result.formula_error_count != 0 {
    raise Failure("worker output verification failed")
  }
  let (written, response) = exchange(
    transfer_origin,
    transfer_token,
    "/internal/v1/objects/write",
    Post,
    output,
    extra={
      "Content-Type": result.media_type,
      "X-LunaNexa-Object-Ref": result.expected_object_ref,
      "X-LunaNexa-Sha256": result.sha256,
    },
  )
  if written < 200 || written >= 300 {
    raise Failure("object publish rejected")
  }
  let published = @json.parse(@utf8.decode(response))
  if field(published, "sha256") != result.sha256 ||
    field(published, "byte_count") != result.byte_count.to_string() ||
    field(published, "provider_receipt").trim() == "" {
    raise Failure("object publish verification failed")
  }
  write_atomic(receipt_path, @utf8.encode(result_text))
  callback(config, "/v1/offline-commerce/operator/generation-results", {
    "result": result.to_json(),
  })
  write_atomic(pending_path, @utf8.encode("null"))
}

///|
/// Resume only work with real finalized output or a publication receipt. A
/// permanently invalid template/renderer remains bounded by controller claims.
async fn resume_artifacts(config : Config) -> Unit {
  for directory in @fs.readdir(config.root) {
    if directory.length() != 64 ||
      !directory.all(c => c.is_ascii_digit() || (c >= 'a' && c <= 'f')) {
      continue
    }
    let root = "\{config.root}/\{directory}"
    let pending = @fs.read_file("\{root}/artifact-pending.json").text() catch {
      _ => "null"
    }
    if pending == "null" {
      continue
    }
    let published = @fs.read_file("\{root}/published.json").text() catch {
      _ => ""
    }
    let finalized = @fs.read_file("\{root}/result.json").text() catch {
      _ => ""
    }
    if published == "" && finalized == "" {
      continue
    }
    let request : @offline.ArtifactGenerationRequest = @json.from_json(
      @json.parse(pending),
    )
    artifact(config, request) catch {
      _ => println("finalized artifact pending; durable retry retained")
    }
  }
}

///|
async fn authority(
  config : Config,
  id : String,
  request : Json,
  reversal : Bool,
) -> Unit {
  let root = work_directory(config.root, id)
  ensure_directory(root)
  let pending_path = "\{root}/pending.json"
  write_atomic(
    pending_path,
    @utf8.encode(
      ({ "id": id, "request": request, "reversal": reversal } : Json).stringify(),
    ),
  )
  let path = "\{root}/authority.json"
  let cached = @fs.read_file(path).text() catch { _ => "" }
  let result = if cached != "" {
    @json.parse(cached)
  } else {
    let result = api(
      config,
      "/v1/offline-commerce/operator/entitlement-execute",
      Post,
      if reversal {
        { "reversal": request }
      } else {
        { "activation": request }
      },
    )
    // Pending authority is not a success. It is retried under the persisted claim.
    if reversal {
      let value : @offline.CommercialReversal = @json.from_json(result)
      if value.reversal_id != id ||
        (value.state != ReversalConfirmed && value.state != ReversalFailed) ||
        value.authority_receipt is None {
        raise Failure("authority is not terminal")
      }
    } else {
      let value : @offline.EntitlementActivation = @json.from_json(result)
      if value.activation_id != id ||
        (
          value.state != EntitlementActivationConfirmed &&
          value.state != EntitlementActivationRejected
        ) ||
        value.authority_receipt is None {
        raise Failure("authority is not terminal")
      }
    }
    write_atomic(path, @utf8.encode(result.stringify()))
    result
  }
  callback(
    config,
    if reversal {
      "/v1/offline-commerce/operator/entitlement-reversal-results"
    } else {
      "/v1/offline-commerce/operator/entitlement-activation-results"
    },
    result,
  )
  write_atomic(pending_path, @utf8.encode("null"))
}

///|
/// Restart resumes already-claimed authority work without consuming a new claim
/// attempt. A confirmed provider operation is never re-executed after journaling.
async fn resume_authority(config : Config) -> Unit {
  let entries = @fs.readdir(config.root)
  for directory in entries {
    if directory.length() != 64 ||
      !directory.all(c => c.is_ascii_digit() || (c >= 'a' && c <= 'f')) {
      continue
    }
    let contents = @fs.read_file("\{config.root}/\{directory}/pending.json").text() catch {
      _ => "null"
    }
    match @json.parse(contents) {
      { "id": String(id), "request": request, "reversal": True, .. } =>
        authority(config, id, request, true) catch {
          _ => println("reversal pending; durable retry retained")
        }
      { "id": String(id), "request": request, "reversal": False, .. } =>
        authority(config, id, request, false) catch {
          _ => println("activation pending; durable retry retained")
        }
      Null => ()
      _ => raise Failure("invalid pending authority journal")
    }
  }
}

///|
async fn poll(config : Config, kind : String) -> Unit {
  let failures = Ref(0)
  if kind == "artifact" {
    resume_artifacts(config)
    let requests : Array[@offline.ArtifactGenerationRequest] = @json.from_json(
      api(
        config,
        "/v1/offline-commerce/operator/generation-requests/pending",
        Get,
        Json::null(),
      ),
    )
    if requests.length() > 100 {
      raise Failure("claim batch exceeds bound")
    }
    for request in requests {
      artifact(config, request) catch {
        _ => {
          failures.val += 1
          println("artifact attempt failed; controller claim retry retained")
        }
      }
    }
  } else {
    resume_authority(config)
    let batch : @offline.OfflineAuthorityWorkBatch = @json.from_json(
      api(
        config,
        "/v1/offline-commerce/operator/entitlement-work/pending",
        Get,
        Json::null(),
      ),
    )
    if batch.activations.length() + batch.reversals.length() > 100 {
      raise Failure("claim batch exceeds bound")
    }
    for value in batch.activations {
      authority(config, value.activation_id, value.to_json(), false) catch {
        _ => {
          failures.val += 1
          println("activation attempt pending or failed; claim retry retained")
        }
      }
    }
    for value in batch.reversals {
      authority(config, value.reversal_id, value.to_json(), true) catch {
        _ => {
          failures.val += 1
          println("reversal attempt pending or failed; claim retry retained")
        }
      }
    }
  }
  if failures.val > 0 {
    raise Failure("one or more dispatcher attempts are incomplete")
  }
}

///|
async fn main {
  let kind = required("LUNANEXA_OFFLINE_DISPATCHER_KIND")
  if kind != "artifact" && kind != "entitlement" {
    raise Failure("unknown dispatcher kind")
  }
  let config = Config::{
    origin: required("LUNANEXA_CONTROLLER_ENDPOINT"),
    token: required(
      if kind == "artifact" {
        "LUNANEXA_ARTIFACT_WORKER_CALLBACK_TOKEN"
      } else {
        "LUNANEXA_ENTITLEMENT_AUTHORITY_CALLBACK_TOKEN"
      },
    ),
    root: required("LUNANEXA_OFFLINE_DISPATCHER_STATE_ROOT"),
  }
  ensure_directory(config.root)
  let lock = @fs.open(
    "\{config.root}/dispatcher.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  if !lock.try_lock(Exclusive) {
    raise Failure("dispatcher state already owned by another process")
  }
  if @env.get_env_var("LUNANEXA_OFFLINE_DISPATCHER_ONCE") == Some("1") {
    // Acceptance mode must fail visibly, not exit zero after a failed poll.
    poll(config, kind)
    return
  }
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for ;; {
        let worker_kind : @offline.OfflineWorkerKind = if kind == "artifact" {
          ArtifactDispatcher
        } else {
          EntitlementDispatcher
        }
        callback(config, "/v1/offline-commerce/operator/dispatcher-heartbeat", {
          "worker_kind": worker_kind.to_json(),
        }) catch {
          _ => println("dispatcher heartbeat unavailable")
        }
        @async.sleep(15000)
      }
    })
    for ;; {
      poll(config, kind) catch {
        _ => println("dispatcher poll unavailable; retrying")
      }
      @async.sleep(5000)
    }
  })
}
