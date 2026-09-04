///|
fn model_source_path(path : String) -> Bool {
  path == "/v1/model-sources/modelscope/search" ||
  path == "/v1/model-sources/modelscope/detail" ||
  path == "/v1/model-sources/modelscope/imports" ||
  (
    path.has_prefix("/v1/model-sources/modelscope/imports/") &&
    (
      path.has_suffix("/cancel") ||
      path.has_suffix("/retry") ||
      path.has_suffix(":adopt")
    )
  )
}

///|
priv struct AdoptVerifiedImportIntent {
  model_id : String
  version : String
  license_id : String
  compatible_architectures : Array[String]
  minimum_memory_mib : Int
} derive(FromJson)

///|
fn decode_adopt_verified_import(body : String) -> AdoptVerifiedImportIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn adopted_import_id(path : String) -> String? {
  let prefix = "/v1/model-sources/modelscope/imports/"
  let suffix = ":adopt"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return None
  }
  let value = path[prefix.length():path.length() - suffix.length()].to_owned()
  if @contracts.valid_identifier(value, maximum_length=128) {
    Some(value)
  } else {
    None
  }
}

///|
fn internal_model_source_path(path : String) -> String? {
  let public_prefix = "/v1/model-sources/modelscope"
  let internal_prefix = "/internal/v1/modelscope"
  if !path.has_prefix(public_prefix) {
    return None
  }
  Some("\{internal_prefix}\{path[public_prefix.length():]}")
}

///|
async fn request_model_source_adapter(
  endpoint : String,
  token : String,
  verb : ApiMethod,
  path : String,
  body : String,
) -> HttpReply {
  guard internal_model_source_path(path) is Some(internal_path) else {
    return api_error(404, "NotFound", "model-source route not found", false)
  }
  let url = "\{endpoint}\{internal_path}"
  let headers : Map[String, String] = {
    "Authorization": "Bearer \{token}",
    "Accept": "application/json",
    "Content-Type": "application/json",
  }
  let (response, payload) = match verb {
    Get => @http.get(url, headers~)
    Post => @http.post(url, body, headers~)
    _ =>
      return api_error(
        405, "MethodNotAllowed", "model-source method is not allowed", false,
      )
  }
  if response.code >= 300 && response.code < 400 {
    return api_error(
      502, "ModelSourceRedirectRejected", "model-source redirect was rejected", false,
    )
  }
  let content_type = response.headers
    .iter()
    .find_first(entry => entry.0.to_lower() == "content-type")
    .map(entry => entry.1.to_lower())
  if !content_type.map_or(false, value => value.has_prefix("application/json")) {
    return api_error(
      502, "ModelSourceInvalidResponse", "model-source response type was rejected",
      true,
    )
  }
  let bytes = payload.binary()
  if bytes.length() > 1048576 {
    return api_error(
      502, "ModelSourceInvalidResponse", "model-source response exceeded its bound",
      true,
    )
  }
  let text = try @utf8.decode(bytes) catch {
    _ =>
      return api_error(
        502, "ModelSourceInvalidResponse", "model-source response was not UTF-8",
        true,
      )
  } noraise {
    value => value
  }
  {
    status: response.code,
    body: text,
    content_type: "application/json; charset=utf-8",
  }
}

///|
async fn ApiService::handle_model_source(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.operator_identity(headers) is Some(operator) else {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  guard self.model_source_adapter_endpoint is Some(endpoint) &&
    self.model_source_adapter_token is Some(token) else {
    return api_error(
      503, "ModelSourceUnavailable", "model-source adapter is unavailable", true,
    )
  }
  if verb == Post && adopted_import_id(path) is Some(import_id) {
    guard self.registry is Some(registry) else {
      return api_error(
        503, "RegistryUnavailable", "durable registry is unavailable", true,
      )
    }
    guard decode_adopt_verified_import(body) is Some(intent) else {
      return api_error(400, "InvalidRequest", "invalid adoption request", false)
    }
    if !@contracts.valid_identifier(intent.model_id) ||
      !@contracts.valid_identifier(intent.version) ||
      !@contracts.valid_identifier(intent.license_id) ||
      intent.minimum_memory_mib <= 0 ||
      intent.compatible_architectures.length() == 0 ||
      intent.compatible_architectures.length() > 16 ||
      intent.compatible_architectures.any(value => {
        !@contracts.valid_identifier(value, maximum_length=128)
      }) {
      return api_error(
        400, "InvalidRequest", "model identity, version, license, architecture and memory are required",
        false,
      )
    }
    let imports_reply = try
      request_model_source_adapter(
        endpoint,
        token,
        Get,
        "/v1/model-sources/modelscope/imports",
        "",
      )
    catch {
      _ =>
        return api_error(
          503, "ModelSourceUnavailable", "model-source import inventory failed",
          true,
        )
    } noraise {
      value => value
    }
    if imports_reply.status != 200 {
      return api_error(
        503, "ModelSourceUnavailable", "model-source import inventory is unavailable",
        true,
      )
    }
    let imports : Array[@modelsource.ImportOperation] = try
      @json.from_json(@json.parse(imports_reply.body))
    catch {
      _ =>
        return api_error(
          502, "ModelSourceInvalidResponse", "model-source import inventory is invalid",
          true,
        )
    } noraise {
      value => value
    }
    guard imports.iter().find_first(value => value.import_id == import_id)
      is Some(operation) else {
      return api_error(
        404, "ImportNotFound", "model import was not found", false,
      )
    }
    if operation.state != Verified ||
      !operation.artifact_uri.has_prefix("s3://") ||
      !@contracts.valid_sha256_digest(operation.manifest_digest) ||
      operation.bytes_total <= 0L ||
      operation.bytes_completed != operation.bytes_total ||
      operation.license.trim() == "" {
      return api_error(
        409, "ImportNotAdoptable", "only a complete S3-published verified import can enter the registry",
        false,
      )
    }
    let model : @contracts.ModelRecord = {
      model_id: intent.model_id,
      version: intent.version,
      artifact: {
        digest: operation.manifest_digest,
        uri: operation.artifact_uri,
        size_bytes: operation.bytes_total,
        signature_ref: "\{operation.artifact_uri}.sig",
      },
      license_id: intent.license_id,
      provenance: "modelscope:\{operation.model_id}@\{operation.revision}:\{operation.import_id}",
      compatible_architectures: intent.compatible_architectures,
      minimum_memory_mib: intent.minimum_memory_mib,
      state: Candidate,
    }
    try
      registry.adopt_import(model, {
        license_id: intent.license_id,
        model_id: intent.model_id,
        status: Pending,
        accepted_by: "",
        evidence_ref: "modelscope-license:\{operation.license}",
        expires_unix_ms: None,
      })
    catch {
      _ =>
        return api_error(
          409, "RegistryRejected", "the verified import conflicts with registry state",
          false,
        )
    } noraise {
      _ => ()
    }
    self.operator_audit_as(
      operator,
      "modelsource.import.adopt",
      intent.model_id,
      "modelsource:\{operation.import_id}:candidate",
    )
    return json_reply(201, {
      "model": model.to_json(),
      "state": "LicenseReviewRequired",
      "next_actions": [
        "accept-license", "verify-signed-manifest", "run-evaluation", "approve-model",
        "promote-alias", "deploy",
      ],
    })
  }
  let reply = try
    request_model_source_adapter(endpoint, token, verb, path, body)
  catch {
    _ =>
      return api_error(
        503, "ModelSourceUnavailable", "model-source adapter request failed", true,
      )
  } noraise {
    value => value
  }
  if verb == Post &&
    path.has_prefix("/v1/model-sources/modelscope/imports") &&
    reply.status >= 200 &&
    reply.status < 300 {
    self.operator_audit_as(
      operator,
      if path.has_suffix("/cancel") {
        "modelsource.import.cancel"
      } else if path.has_suffix("/retry") {
        "modelsource.import.retry"
      } else {
        "modelsource.import.create"
      },
      "modelscope",
      "modelsource:\{@async.now()}",
    )
  }
  reply
}
