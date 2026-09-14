///|
fn request_header(headers : Map[String, String], name : String) -> String? {
  let values = headers
    .iter()
    .filter(pair => pair.0.to_lower() == name)
    .to_array()
  if values.length() == 1 {
    Some(values[0].1)
  } else {
    None
  }
}

///|
fn decode_component(value : String) -> String raise {
  let bytes = Buffer()
  let mut index = 0
  while index < value.length() {
    let c = value[index]
    if c == '%' {
      if index + 2 >= value.length() {
        raise HostError::ControllerRejected
      }
      let digits = value[index + 1:index + 3].to_lower()
      let alphabet = "0123456789abcdef"
      let high = alphabet.find(digits[0:1]).unwrap_or(-1)
      let low = alphabet.find(digits[1:2]).unwrap_or(-1)
      if high < 0 || low < 0 {
        raise HostError::ControllerRejected
      }
      bytes.write_byte((high * 16 + low).to_byte())
      index += 3
    } else {
      if c == '+' {
        bytes.write_byte(b' ')
      } else {
        bytes.write_bytes(@utf8.encode(value[index:index + 1].to_owned()))
      }
      index += 1
    }
  }
  @utf8.decode(bytes.to_bytes())
}

///|
fn form_model(content_type : String, payload : Bytes) -> String? {
  try {
    let text = @utf8.decode(payload)
    let models : Array[String] = []
    if content_type == "application/x-www-form-urlencoded" {
      for part in text.split("&") {
        guard part.find("=") is Some(separator) else { return None }
        let name = decode_component(part[:separator].to_owned())
        if name == "model" {
          models.push(decode_component(part[separator + 1:].to_owned()))
        }
      }
    } else if content_type.has_prefix("multipart/form-data; boundary=") {
      let boundary = content_type["multipart/form-data; boundary=".length():].to_owned()
      if boundary.length() < 1 ||
        boundary.length() > 70 ||
        !boundary.all(c => {
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '-' ||
          c == '_'
        }) {
        return None
      }
      if !text.has_prefix("--" + boundary + "\r\n") ||
        !text.has_suffix("--" + boundary + "--\r\n") {
        return None
      }
      let parts = text.split("--" + boundary).to_array()
      for part in parts {
        if part == "" || part == "--\r\n" {
          continue
        }
        guard part.has_prefix("\r\n") &&
          part.has_suffix("\r\n") &&
          part.find("\r\n\r\n") is Some(separator) else {
          return None
        }
        let headers = part[2:separator].to_owned()
        // This first profile is text-to-video. File/reference multipart bodies
        // require a separately qualified profile instead of lossy text parsing.
        let lines = headers.split("\r\n").to_array()
        if lines.length() > 2 {
          return None
        }
        let disposition = lines[0].to_owned()
        let prefix = "Content-Disposition: form-data; name=\""
        if !disposition.has_prefix(prefix) || !disposition.has_suffix("\"") {
          return None
        }
        let name = disposition[prefix.length():disposition.length() - 1].to_owned()
        if !name.all(c => (c >= 'a' && c <= 'z') || c == '_') {
          return None
        }
        if lines.length() == 2 &&
          !lines[1].has_prefix("Content-Type: text/plain") {
          return None
        }
        if name == "model" {
          models.push(part[separator + 4:part.length() - 2].to_owned())
        }
      }
    } else if content_type == "application/json" {
      match @json.parse(text) {
        { "model": String(model), .. } => models.push(model)
        _ => return None
      }
    } else {
      return None
    }
    if models.length() == 1 {
      Some(models[0])
    } else {
      None
    }
  } catch {
    _ => None
  }
}

///|
fn model_route(verb : @http.RequestMethod, path : String) -> Bool {
  if verb == Get && path == "/v1/models" {
    return true
  }
  if verb == Post &&
    ["/v1/videos", "/v1/images/generations", "/v1/chat/completions"].contains(
      path,
    ) {
    return true
  }
  if !path.has_prefix("/v1/videos/") || (verb != Get && verb != Delete) {
    return false
  }
  let suffix = path[11:].to_owned()
  let id = if suffix.has_suffix("/content") && verb == Get {
    suffix[:suffix.length() - 8].to_owned()
  } else {
    suffix
  }
  id.length() > 0 &&
  id.length() <= 128 &&
  id.all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '_'
  })
}

///|
async fn proxy_reply(
  connection : @http.ServerConnection,
  code : Int,
  message : String,
) -> Unit {
  connection.send_response(code, "Model gateway", extra_headers={
    "content-type": "application/json",
    "cache-control": "no-store",
  })
  let body : Json = {
    "error": { "message": message, "type": "managed_workspace" },
  }
  connection.write(body)
  connection.end_response()
}

///|
/// Loopback-only credential injector used by the pinned third-party ComfyUI
/// nodes. The Secret volume is read on every request, so rotation needs no
/// restart. No caller-supplied endpoint, authorization or identity is forwarded.
pub async fn handle_model_proxy(
  config_file : String,
  request : @http.Request,
  body : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  if request_header(request.headers, "origin") is Some(_) ||
    !model_route(request.meth, request.path) {
    return proxy_reply(connection, 403, "Unsupported managed model operation")
  }
  @async.with_timeout(300000, () => {
    let file = @fs.open(config_file, mode=ReadOnly)
    defer file.close()
    let config : ModelProxyConfig = @json.from_json(
      @json.parse(@utf8.decode(limited(file, 32768))),
    )
    if !origin(config.controller_origin) ||
      !origin(config.model_gateway_origin) ||
      !authorize_grant(config.controller_origin, config.grant()) {
      return proxy_reply(connection, 401, "Workspace model authority has ended")
    }
    if request.path == "/v1/models" {
      let response : Json = {
        "object": "list",
        "data": config.allowed_models
        .map(model => {
          let entry : Json = {
            "id": model,
            "object": "model",
            "owned_by": "lunanexa",
          }
          entry
        })
        .to_json(),
      }
      connection.send_response(200, "OK", extra_headers={
        "content-type": "application/json",
        "cache-control": "no-store",
      })
      connection.write(response)
      return connection.end_response()
    }
    let payload = limited(body, 1048576)
    let content_type = request_header(request.headers, "content-type").unwrap_or(
      "application/json",
    )
    if request.meth == Post {
      guard form_model(content_type, payload) is Some(model) &&
        config.allowed_models.contains(model) else {
        return proxy_reply(
          connection, 403, "An approved model and supported request format are required",
        )
      }
    }
    let upstream = @http.Client(config.model_gateway_origin)
    defer upstream.close()
    let upstream_headers = {
      "authorization": "Bearer " + config.api_secret,
      "content-type": content_type,
      "accept": "application/json, video/mp4",
    }
    if request.meth == Post && request.path == "/v1/videos" {
      guard request_header(request.headers, "idempotency-key") is Some(key) &&
        key.length() > 0 &&
        key.length() <= 128 &&
        key.all(c => {
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '-' ||
          c == '_'
        }) else {
        return proxy_reply(
          connection, 400, "A stable video Idempotency-Key is required",
        )
      }
      upstream_headers["idempotency-key"] = key
    }
    upstream.request(request.meth, request.path, extra_headers=upstream_headers)
    upstream.write(payload)
    let response = upstream.end_request()
    if response.code < 200 || response.code >= 300 {
      // Suppress internal addresses, prompts and provider exception details.
      return proxy_reply(
        connection,
        if response.code >= 400 && response.code < 500 {
          response.code
        } else {
          502
        },
        "Model request was rejected or the backend is not ready",
      )
    }
    let response_type = request_header(response.headers, "content-type").unwrap_or(
      "application/octet-stream",
    )
    connection.send_response(response.code, "OK", extra_headers={
      "content-type": response_type,
      "cache-control": "no-store",
    })
    let mut checked_at = @async.now()
    while upstream.read_some(max_len=65536) is Some(bytes) {
      if @async.now() - checked_at >= 5000L {
        if !authorize_grant(config.controller_origin, config.grant()) {
          raise HostError::ControllerRejected
        }
        checked_at = @async.now()
      }
      connection.write(bytes)
    }
    connection.end_response()
  }) catch {
    _ => {
      proxy_reply(connection, 502, "Managed model operation could not complete") catch {
        _ => ()
      }
      connection.close()
    }
  }
}
