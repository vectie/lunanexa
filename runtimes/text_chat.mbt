///|
/// Selects the text-only Chat Completions wire contract. Conversations stay
/// structured; no model-specific template or prompt flattening lives here.
pub fn OpenAiTextRuntime::with_text_chat_completions(self : Self) -> Self {
  { ..self, text_chat_completions: true, lunaflux_streaming_responses: false, }
}

///|
fn chat_content(value : Json) -> Json raise RemoteRuntimeError {
  match value {
    String(_) => value
    Array(parts) => {
      let text : Array[String] = []
      for part in parts {
        guard part
          is { "type": String("text" | "input_text"), "text": String(s), .. } else {
          raise UnsupportedCapability
        }
        text.push(s)
      }
      Json::string(text.join(""))
    }
    _ => raise UnsupportedCapability
  }
}

///|
fn text_chat_request(
  request : @contracts.WorkloadEnvelope,
  served : String?,
  streaming : Bool,
) -> Json raise RemoteRuntimeError {
  guard request.capability == TextGenerate else { raise UnsupportedCapability }
  if request.payload is Object(fields) {
    for key in ["tools", "tool_choice", "parallel_tool_calls"] {
      if fields.contains(key) {
        raise UnsupportedCapability
      }
    }
  }
  let input = responses_input(request.payload)
  let messages : Array[Json] = match input {
    String(text) => [{ "role": "user", "content": text }]
    Array(items) =>
      items.map(item => {
        guard item is { "role": String(role), "content": content, .. } &&
          ["system", "user", "assistant"].contains(role) else {
          raise UnsupportedCapability
        }
        { "role": Json::string(role), "content": chat_content(content) }
      })
    _ => raise UnsupportedCapability
  }
  let fields : Map[String, Json] = {
    "model": Json::string(served.unwrap_or(request.model_selector)),
    "messages": Json::array(messages),
    "stream": Json::boolean(streaming),
    "max_tokens": Json::number(
      request.resource_ceiling.max_output_units.to_double(),
    ),
  }
  if request.payload is Object(payload) {
    for
      key in ["temperature", "top_p", "top_k", "seed", "stop", "stop_token_ids"] {
      if payload.get(key) is Some(value) {
        fields[key] = value
      }
    }
  }
  Json::object(fields)
}

///|
fn chat_usage(value : Json) -> (Int32, Int32) {
  match value {
    {
      "usage": {
        "prompt_tokens": Number(p, ..),
        "completion_tokens": Number(c, ..),
        ..
      },
      ..
    } if p >= 0 &&
      c >= 0 &&
      p.to_int().to_double() == p &&
      c.to_int().to_double() == c => (p.to_int(), c.to_int())
    _ => (0, 0)
  }
}

///|
fn chat_text(value : Json, streaming : Bool) -> String? {
  match value {
    {
      "choices": Array([{ "message": { "content": String(text), .. }, .. }]),
      ..
    } if !streaming => Some(text)
    { "choices": Array([{ "delta": { "content": String(text), .. }, .. }]), .. } if streaming =>
      Some(text)
    _ => None
  }
}

///|
fn OpenAiTextRuntime::chat_headers(
  self : Self,
  request : @contracts.WorkloadEnvelope,
  node_id : String,
  streaming : Bool,
) -> @http.Headers {
  let headers : @http.Headers = {
    "Content-Type": "application/json",
    "Accept": if streaming {
      "text/event-stream"
    } else {
      "application/json"
    },
    "Idempotency-Key": "\{request.tenant_ref}:\{request.credential_scope}:\{request.idempotency_key}",
  }
  if self.credential_value != "" {
    headers["Authorization"] = "Bearer \{self.credential_value}"
  }
  if node_id != "" {
    headers["X-LunaNexa-Target-Node"] = node_id
  }
  headers
}

///|
async fn OpenAiTextRuntime::invoke_text_chat(
  self : Self,
  request : @contracts.WorkloadEnvelope,
  node_id : String,
) -> RuntimeInvocationResult {
  let stream = self.open_text_chat_request(
    request,
    node_id,
    false,
    text_chat_request(request, self.served_model_name, false),
  )
  defer stream.close()
  let response = stream.end_request()
  let text = stream.read_all().text()
  guard text.length() <= self.maximum_response_bytes else {
    raise InvalidUpstreamResponse("chat response exceeded configured limit")
  }
  guard response.code >= 200 && response.code < 300 else {
    raise UpstreamRejected(status=response.code, body=text)
  }
  let value = @json.parse(text) catch {
    _ => raise InvalidUpstreamResponse("invalid chat JSON")
  }
  guard chat_text(value, false) is Some(output) else {
    raise InvalidUpstreamResponse("chat answer absent")
  }
  let (input_units, output_units) = chat_usage(value)
  {
    output: { "output_text": output },
    artifact_digest: self.artifact_digest,
    runtime_version: self.runtime_version,
    input_units,
    output_units,
  }
}

///|
/// Request framing is independent of response streaming. Serialize once to
/// supply the exact UTF-8 byte extent; a chunked request is not required for SSE.
async fn OpenAiTextRuntime::open_text_chat_request(
  self : Self,
  request : @contracts.WorkloadEnvelope,
  node_id : String,
  streaming : Bool,
  upstream : Json,
) -> @http.Client {
  let endpoint = self.endpoint_for(node_id)
  guard endpoint.find("://") is Some(scheme) &&
    endpoint[scheme + 3:].find("/") is Some(offset) else {
    raise InvalidUpstreamResponse("chat endpoint lacks request path")
  }
  let path_start = scheme + 3 + offset
  let body = @utf8.encode(upstream.stringify())
  let client = @http.Client(
    endpoint[:path_start].to_owned(),
    headers=self.chat_headers(request, node_id, streaming),
  )
  errdefer client.close()
  client.request(Post, endpoint[path_start:], extra_headers={
    "Content-Length": body.length().to_string(),
  })
  client.write(body)
  client
}

///|
async fn OpenAiTextRuntime::invoke_text_chat_stream(
  self : Self,
  request : @contracts.WorkloadEnvelope,
  node_id : String,
  on_chunk : async (Json) -> Unit,
) -> RuntimeInvocationResult {
  let upstream = text_chat_request(request, self.served_model_name, true)
  let stream = self.open_text_chat_request(request, node_id, true, upstream)
  defer stream.close()
  let response = stream.end_request()
  guard response.code >= 200 && response.code < 300 else {
    raise UpstreamRejected(status=response.code, body="chat stream rejected")
  }
  let texts : Array[String] = []
  let mut input_units = 0
  let mut output_units = 0
  let mut total = 0
  let mut done = false
  while stream.read_until("\n") is Some(line) {
    let line = line.trim()
    if !line.has_prefix("data:") {
      continue
    }
    let data = line[5:].trim()
    guard data.length() <= self.maximum_event_bytes else {
      raise InvalidUpstreamResponse("chat event too large")
    }
    if data == "[DONE]" {
      done = true
      break
    }
    let event = @json.parse(data) catch {
      _ => raise InvalidUpstreamResponse("invalid chat event")
    }
    if event is { "error": _, .. } {
      raise UpstreamFailed(code="chat-stream-failed", retryable=false)
    }
    let (p, c) = chat_usage(event)
    if p != 0 || c != 0 {
      input_units = p
      output_units = c
    }
    if chat_text(event, true) is Some(text) && text != "" {
      total += text.length()
      guard total <= self.maximum_response_bytes else {
        raise InvalidUpstreamResponse("chat stream too large")
      }
      texts.push(text)
      on_chunk({ "text_delta": text })
    }
  }
  guard done else {
    raise InvalidUpstreamResponse("chat stream ended before DONE")
  }
  {
    output: { "output_text": texts.join("") },
    artifact_digest: self.artifact_digest,
    runtime_version: self.runtime_version,
    input_units,
    output_units,
  }
}
