///|
pub(all) suberror RemoteRuntimeError {
  InsecureEndpoint(String)
  InvalidNodeRouting(String)
  RoutingTargetUnavailable(String)
  UnsupportedCapability
  UpstreamRejected(status~ : Int, body~ : String)
  UpstreamFailed(code~ : String, retryable~ : Bool)
  InvalidUpstreamResponse(String)
} derive(Debug, Eq)

///|
pub(all) struct RuntimeInvocationResult {
  output : Json
  artifact_digest : String
  runtime_version : String
  input_units : Int
  output_units : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct OpenAiTextRuntime {
  endpoint : String
  node_endpoints : Map[String, String]
  direct_node_routing : Bool
  allow_http_loopback : Bool
  credential_value : String
  runtime_version : String
  image_digest : String
  artifact_digest : String
  maximum_event_bytes : Int
  maximum_response_bytes : Int
  lunaflux_streaming_responses : Bool
}

///|
pub(all) struct NodeRuntimeEndpoint {
  node_id : String
  endpoint : String
} derive(Debug, Eq, ToJson, FromJson)

///|
priv struct UpstreamUsage {
  input_tokens : Int
  output_tokens : Int
} derive(FromJson)

///|
priv struct UpstreamEnvelope {
  usage : UpstreamUsage?
} derive(FromJson)

///|
priv struct UpstreamStreamEnvelope {
  usage : UpstreamUsage?
} derive(FromJson)

///|
priv struct UpstreamCompletedResponse {
  usage : UpstreamUsage?
} derive(FromJson)

///|
priv struct UpstreamCompletedEvent {
  response : UpstreamCompletedResponse?
} derive(FromJson)

///|
pub fn OpenAiTextRuntime::new(
  endpoint : String,
  credential_value : String,
  runtime_version : String,
  image_digest : String,
  artifact_digest : String,
  allow_http_loopback? : Bool = false,
) -> OpenAiTextRuntime raise RemoteRuntimeError {
  if !valid_endpoint(endpoint, allow_http_loopback) {
    raise InsecureEndpoint(endpoint)
  }
  if !@contracts.valid_sha256_digest(image_digest) ||
    !@contracts.valid_sha256_digest(artifact_digest) {
    raise InvalidUpstreamResponse("runtime and artifact must be digest pinned")
  }
  {
    endpoint,
    node_endpoints: Map([]),
    direct_node_routing: false,
    allow_http_loopback,
    credential_value,
    runtime_version,
    image_digest,
    artifact_digest,
    maximum_event_bytes: 1048576,
    maximum_response_bytes: 16777216,
    lunaflux_streaming_responses: false,
  }
}

///|
/// Selects LunaFlux's bounded Responses profile: streaming transport, string
/// input, and a fail-closed request field set.
pub fn OpenAiTextRuntime::with_lunaflux_streaming_responses(
  self : OpenAiTextRuntime,
) -> OpenAiTextRuntime {
  { ..self, lunaflux_streaming_responses: true }
}

///|
pub fn OpenAiTextRuntime::with_response_budgets(
  self : OpenAiTextRuntime,
  maximum_event_bytes : Int,
  maximum_response_bytes : Int,
) -> OpenAiTextRuntime raise RemoteRuntimeError {
  if maximum_event_bytes < 65536 ||
    maximum_event_bytes > 1048576 ||
    maximum_response_bytes < maximum_event_bytes ||
    maximum_response_bytes > 16777216 {
    raise InvalidUpstreamResponse("runtime response budgets are invalid")
  }
  { ..self, maximum_event_bytes, maximum_response_bytes }
}

///|
fn valid_endpoint(endpoint : String, allow_http_loopback : Bool) -> Bool {
  let scheme_allowed = endpoint.has_prefix("https://") ||
    (
      allow_http_loopback &&
      (
        endpoint.has_prefix("http://127.0.0.1:") ||
        endpoint.has_prefix("http://localhost:")
      )
    )
  let authority_start = if endpoint.has_prefix("https://") { 8 } else { 7 }
  scheme_allowed &&
  endpoint.length() > authority_start &&
  !endpoint[authority_start:].has_prefix("/") &&
  !endpoint.contains_char('@') &&
  !endpoint.contains_char(' ') &&
  !endpoint.contains_char('\n') &&
  !endpoint.contains_char('\r') &&
  !endpoint.contains_char('?') &&
  !endpoint.contains_char('#')
}

///|
fn valid_node_id(node_id : String) -> Bool {
  node_id != "" &&
  node_id.length() <= 128 &&
  node_id.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.'
  })
}

///|
fn responses_input(payload : Json) -> Json raise RemoteRuntimeError {
  let input = match payload {
    String(_) | Array(_) => payload
    Object(fields) =>
      match fields.get("input") {
        Some(value) => value
        None =>
          match fields.get("prompt") {
            Some(value) => value
            None =>
              match fields.get("messages") {
                Some(value) => value
                None =>
                  raise InvalidUpstreamResponse(
                    "text payload must contain input, prompt, or messages",
                  )
              }
          }
      }
    _ =>
      raise InvalidUpstreamResponse(
        "text payload must be a string, array, or supported object",
      )
  }
  match input {
    String(_) | Array(_) => input
    _ =>
      raise InvalidUpstreamResponse(
        "text input must resolve to a string or message array",
      )
  }
}

///|
fn lunaflux_responses_input(input : Json) -> Json raise RemoteRuntimeError {
  match input {
    String(value) if value != "" => Json::string(value)
    Array([Object(fields)]) if fields.get("role") is Some(String("user")) &&
      fields.get("content") is Some(String(content)) &&
      content != "" => Json::string(content)
    _ =>
      raise InvalidUpstreamResponse(
        "LunaFlux Responses accepts text or one non-empty user message",
      )
  }
}

///|
fn responses_tool_from_chat(tool : Json) -> Json {
  guard tool is Object(fields) &&
    fields.get("type") is Some(String("function")) &&
    fields.get("function") is Some(Object(function)) else {
    return tool
  }
  let result : Map[String, Json] = { "type": Json::string("function") }
  for key in ["name", "description", "parameters", "strict"] {
    if function.get(key) is Some(value) {
      result[key] = value
    }
  }
  Json::object(result)
}

///|
fn responses_tool_choice_from_chat(choice : Json) -> Json {
  guard choice is Object(fields) &&
    fields.get("type") is Some(String("function")) &&
    fields.get("function") is Some(Object(function)) else {
    return choice
  }
  let result : Map[String, Json] = { "type": Json::string("function") }
  if function.get("name") is Some(name) {
    result["name"] = name
  }
  Json::object(result)
}

///|
fn responses_upstream_request(
  request : @contracts.WorkloadEnvelope,
  input : Json,
  stream : Bool,
  lunaflux_streaming_responses : Bool,
) -> Json raise RemoteRuntimeError {
  let fields : Map[String, Json] = {
    "model": Json::string(request.model_selector),
    "input": if lunaflux_streaming_responses {
      lunaflux_responses_input(input)
    } else {
      input
    },
    "stream": Json::boolean(
      if lunaflux_streaming_responses {
        true
      } else {
        stream
      },
    ),
  }
  if lunaflux_streaming_responses {
    if request.payload is Object(payload) {
      if payload.get("tools") is Some(Array(tools)) && !tools.is_empty() {
        raise UnsupportedCapability
      }
      for key in ["temperature", "top_p"] {
        if payload.get(key) is Some(value) {
          fields[key] = value
        }
      }
    }
  } else {
    fields["max_output_tokens"] = request.resource_ceiling.max_output_units.to_json()
    fields["metadata"] = Json::object({
      "workload_id": Json::string(request.workload_id),
      "trace_token": Json::string(request.trace_token),
    })
    if request.payload is Object(payload) {
      if payload.get("tools") is Some(Array(tools)) {
        let converted : Array[Json] = []
        for tool in tools {
          converted.push(responses_tool_from_chat(tool))
        }
        fields["tools"] = Json::array(converted)
      }
      if payload.get("tool_choice") is Some(choice) {
        fields["tool_choice"] = responses_tool_choice_from_chat(choice)
      }
      for key in ["parallel_tool_calls", "temperature", "top_p"] {
        if payload.get(key) is Some(value) {
          fields[key] = value
        }
      }
    }
  }
  Json::object(fields)
}

///|
fn normalized_responses_stream_chunk(event : Json) -> Json? {
  guard event is Object(fields) else { return None }
  let event_type = match fields.get("type") {
    Some(String(value)) => value
    _ => ""
  }
  if event_type == "response.output_text.delta" || event_type == "" {
    let text = match fields.get("delta") {
      Some(String(value)) => Some(value)
      _ =>
        match fields.get("output_text") {
          Some(String(value)) => Some(value)
          _ => None
        }
    }
    return text.map(value => ({ "text_delta": value } : Json))
  }
  if event_type == "response.output_item.added" &&
    fields.get("item") is Some(Object(item)) &&
    item.get("type") is Some(String("function_call")) {
    let index = fields.get("output_index").unwrap_or(Json::number(0.0))
    let id = match item.get("call_id") {
      Some(String(value)) => value
      _ =>
        match item.get("id") {
          Some(String(value)) => value
          _ => "call-lunanexa"
        }
    }
    let name = match item.get("name") {
      Some(String(value)) => value
      _ => ""
    }
    return Some({
      "tool_call_delta": {
        "index": index,
        "id": id,
        "type": "function",
        "function": { "name": name, "arguments": "" },
      },
    })
  }
  if event_type == "response.function_call_arguments.delta" {
    let index = fields.get("output_index").unwrap_or(Json::number(0.0))
    let arguments = match fields.get("delta") {
      Some(String(value)) => value
      _ => ""
    }
    return Some({
      "tool_call_delta": {
        "index": index,
        "function": { "arguments": arguments },
      },
    })
  }
  None
}

///|
fn responses_event_completed(event : Json) -> UpstreamUsage?? {
  guard event is Object(fields) &&
    fields.get("type") is Some(String("response.completed")) else {
    return None
  }
  let completed : UpstreamCompletedEvent = @json.from_json(event) catch {
    _ => { response: None }
  }
  let usage = match completed.response {
    Some(response) => response.usage
    None => None
  }
  Some(usage)
}

///|
fn responses_event_failed(event : Json) -> (String, Bool)? {
  guard event is Object(fields) &&
    fields.get("type") is Some(String("response.failed")) else {
    return None
  }
  let mut code = "runtime-failed"
  let mut retryable = false
  if fields.get("response") is Some(Object(response)) &&
    response.get("error") is Some(Object(error)) {
    if error.get("code") is Some(String(value)) {
      code = value
    }
    match error.get("retryable") {
      Some(True) => retryable = true
      Some(False) => retryable = false
      _ => ()
    }
  }
  Some((code, retryable))
}

///|
pub fn OpenAiTextRuntime::with_node_endpoints(
  self : OpenAiTextRuntime,
  entries : Array[NodeRuntimeEndpoint],
) -> OpenAiTextRuntime raise RemoteRuntimeError {
  if entries.length() == 0 {
    raise InvalidNodeRouting("at least one node endpoint is required")
  }
  let node_endpoints : Map[String, String] = Map([])
  for entry in entries {
    if !valid_node_id(entry.node_id) ||
      !valid_endpoint(entry.endpoint, self.allow_http_loopback) ||
      node_endpoints.contains(entry.node_id) {
      raise InvalidNodeRouting(entry.node_id)
    }
    node_endpoints[entry.node_id] = entry.endpoint
  }
  { ..self, node_endpoints, direct_node_routing: true }
}

///|
pub fn OpenAiTextRuntime::with_node_endpoints_json(
  self : OpenAiTextRuntime,
  document : String,
) -> OpenAiTextRuntime raise {
  let entries : Array[NodeRuntimeEndpoint] = @json.from_json(
    @json.parse(document),
  )
  self.with_node_endpoints(entries)
}

///|
fn OpenAiTextRuntime::endpoint_for(
  self : OpenAiTextRuntime,
  node_id : String,
) -> String raise RemoteRuntimeError {
  if !self.direct_node_routing || node_id == "" {
    return self.endpoint
  }
  guard self.node_endpoints.get(node_id) is Some(endpoint) else {
    raise RoutingTargetUnavailable(node_id)
  }
  endpoint
}

///|
pub fn OpenAiTextRuntime::image_digest(self : OpenAiTextRuntime) -> String {
  self.image_digest
}

///|
pub fn OpenAiTextRuntime::artifact_digest(self : OpenAiTextRuntime) -> String {
  self.artifact_digest
}

///|
pub fn OpenAiTextRuntime::runtime_version(self : OpenAiTextRuntime) -> String {
  self.runtime_version
}

///|
pub fn OpenAiTextRuntime::uses_direct_node_routing(
  self : OpenAiTextRuntime,
) -> Bool {
  self.direct_node_routing
}

///|
pub async fn OpenAiTextRuntime::invoke(
  self : OpenAiTextRuntime,
  request : @contracts.WorkloadEnvelope,
) -> RuntimeInvocationResult {
  self.invoke_at(request, "")
}

///|
pub async fn OpenAiTextRuntime::invoke_at(
  self : OpenAiTextRuntime,
  request : @contracts.WorkloadEnvelope,
  node_id : String,
) -> RuntimeInvocationResult {
  if self.lunaflux_streaming_responses {
    return self.invoke_stream_at(request, node_id, _ => ())
  }
  if request.capability != TextGenerate {
    raise UnsupportedCapability
  }
  let input = responses_input(request.payload)
  let headers : Map[String, String] = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Idempotency-Key": "\{request.tenant_ref}:\{request.credential_scope}:\{request.idempotency_key}",
  }
  if self.credential_value != "" {
    headers["Authorization"] = "Bearer \{self.credential_value}"
  }
  if node_id != "" {
    headers["X-LunaNexa-Target-Node"] = node_id
  }
  let upstream_request = responses_upstream_request(
    request,
    input,
    false,
    self.lunaflux_streaming_responses,
  )
  let endpoint = self.endpoint_for(node_id)
  let (response, body) = @http.post(endpoint, upstream_request, headers~)
  let body_text = body.text()
  if body_text.length() > self.maximum_response_bytes {
    raise InvalidUpstreamResponse(
      "upstream response exceeded the configured limit",
    )
  }
  if response.code < 200 || response.code >= 300 {
    raise UpstreamRejected(status=response.code, body=body_text)
  }
  let output = @json.parse(body_text) catch {
    error => raise InvalidUpstreamResponse("\{Repr(error)}")
  }
  let envelope : UpstreamEnvelope = @json.from_json(output) catch {
    _ => { usage: None }
  }
  {
    output,
    artifact_digest: self.artifact_digest,
    runtime_version: self.runtime_version,
    input_units: envelope.usage.map(usage => usage.input_tokens).unwrap_or(0),
    output_units: envelope.usage.map(usage => usage.output_tokens).unwrap_or(0),
  }
}

///|
pub async fn OpenAiTextRuntime::invoke_stream(
  self : OpenAiTextRuntime,
  request : @contracts.WorkloadEnvelope,
  on_chunk : async (Json) -> Unit,
) -> RuntimeInvocationResult {
  self.invoke_stream_at(request, "", on_chunk)
}

///|
pub async fn OpenAiTextRuntime::invoke_stream_at(
  self : OpenAiTextRuntime,
  request : @contracts.WorkloadEnvelope,
  node_id : String,
  on_chunk : async (Json) -> Unit,
) -> RuntimeInvocationResult {
  if request.capability != TextGenerate {
    raise UnsupportedCapability
  }
  let input = responses_input(request.payload)
  let headers : Map[String, String] = {
    "Content-Type": "application/json",
    "Accept": "text/event-stream",
    "Idempotency-Key": "\{request.tenant_ref}:\{request.credential_scope}:\{request.idempotency_key}",
  }
  if self.credential_value != "" {
    headers["Authorization"] = "Bearer \{self.credential_value}"
  }
  if node_id != "" {
    headers["X-LunaNexa-Target-Node"] = node_id
  }
  let upstream_request = responses_upstream_request(
    request,
    input,
    true,
    self.lunaflux_streaming_responses,
  )
  let endpoint = self.endpoint_for(node_id)
  let stream = @http.post_stream(endpoint, headers~)
  defer stream.close()
  stream.write(upstream_request)
  let response = stream.end_request()
  if response.code < 200 || response.code >= 300 {
    raise UpstreamRejected(status=response.code, body="stream rejected")
  }
  let chunks : Array[Json] = []
  let mut input_units = 0
  let mut output_units = 0
  let mut sequence = 0
  let mut total_output_bytes = 0
  let mut saw_done = false
  let output_text : Array[String] = []
  while stream.read_until("\n") is Some(line) {
    let trimmed = line.trim()
    if !trimmed.has_prefix("data:") {
      continue
    }
    let data = trimmed["data:".length():].trim()
    if data.length() > self.maximum_event_bytes {
      raise InvalidUpstreamResponse(
        "upstream stream event exceeded the configured limit",
      )
    }
    if data == "[DONE]" {
      if !self.lunaflux_streaming_responses {
        saw_done = true
      }
      break
    }
    let event_json = @json.parse(data) catch {
      error => raise InvalidUpstreamResponse("\{Repr(error)}")
    }
    if responses_event_completed(event_json) is Some(completed_usage) {
      if completed_usage is Some(usage) {
        input_units = usage.input_tokens
        output_units = usage.output_tokens
      }
      saw_done = true
      break
    }
    if responses_event_failed(event_json) is Some((code, retryable)) {
      raise UpstreamFailed(code~, retryable~)
    }
    let event : UpstreamStreamEnvelope = @json.from_json(event_json) catch {
      _ => { usage: None }
    }
    if event.usage is Some(usage) {
      input_units = usage.input_tokens
      output_units = usage.output_tokens
    }
    if normalized_responses_stream_chunk(event_json) is Some(chunk) {
      if chunk is Object(fields) &&
        fields.get("text_delta") is Some(String(value)) {
        output_text.push(value)
      }
      total_output_bytes += chunk.stringify().length()
      if total_output_bytes > self.maximum_response_bytes {
        raise InvalidUpstreamResponse(
          "upstream stream exceeded the configured limit",
        )
      }
      sequence += 1
      if sequence > request.resource_ceiling.max_output_units {
        raise InvalidUpstreamResponse("stream exceeded output event ceiling")
      }
      chunks.push(chunk)
      on_chunk(chunk)
    }
  }
  if !saw_done {
    raise InvalidUpstreamResponse(
      "upstream stream ended before its completion marker",
    )
  }
  {
    output: { "output_text": output_text.join(""), "chunks": chunks },
    artifact_digest: self.artifact_digest,
    runtime_version: self.runtime_version,
    input_units,
    output_units,
  }
}
