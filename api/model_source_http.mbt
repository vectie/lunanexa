///|
fn model_source_path(path : String) -> Bool {
  path == "/v1/model-sources/modelscope/search" ||
  path == "/v1/model-sources/modelscope/detail" ||
  path == "/v1/model-sources/modelscope/imports" ||
  (
    path.has_prefix("/v1/model-sources/modelscope/imports/") &&
    (path.has_suffix("/cancel") || path.has_suffix("/retry"))
  )
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
