///|
pub(all) suberror RemoteRuntimeError {
  InsecureEndpoint(String)
  InvalidNodeRouting(String)
  RoutingTargetUnavailable(String)
  UnsupportedCapability
  UpstreamRejected(status~ : Int, body~ : String)
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
  delta : String?
  output_text : String?
  usage : UpstreamUsage?
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
  }
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
  if request.capability != TextGenerate {
    raise UnsupportedCapability
  }
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
  let upstream_request : Json = {
    "model": request.model_selector,
    "input": request.payload,
    "stream": false,
    "max_output_tokens": request.resource_ceiling.max_output_units,
    "metadata": {
      "workload_id": request.workload_id,
      "trace_token": request.trace_token,
    },
  }
  let endpoint = self.endpoint_for(node_id)
  let (response, body) = @http.post(endpoint, upstream_request, headers~)
  let body_text = body.text()
  if body_text.length() > 16777216 {
    raise InvalidUpstreamResponse("upstream response exceeded the 16 MiB limit")
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
  let upstream_request : Json = {
    "model": request.model_selector,
    "input": request.payload,
    "stream": true,
    "max_output_tokens": request.resource_ceiling.max_output_units,
    "metadata": {
      "workload_id": request.workload_id,
      "trace_token": request.trace_token,
    },
  }
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
  while stream.read_until("\n") is Some(line) {
    let trimmed = line.trim()
    if !trimmed.has_prefix("data:") {
      continue
    }
    let data = trimmed["data:".length():].trim()
    if data.length() > 1048576 {
      raise InvalidUpstreamResponse(
        "upstream stream event exceeded the 1 MiB limit",
      )
    }
    if data == "[DONE]" {
      saw_done = true
      break
    }
    let event_json = @json.parse(data) catch {
      error => raise InvalidUpstreamResponse("\{Repr(error)}")
    }
    let event : UpstreamStreamEnvelope = @json.from_json(event_json) catch {
      _ => { delta: None, output_text: None, usage: None }
    }
    if event.usage is Some(usage) {
      input_units = usage.input_tokens
      output_units = usage.output_tokens
    }
    let text = match event.delta {
      Some(value) => Some(value)
      None => event.output_text
    }
    if text is Some(value) {
      total_output_bytes += value.length()
      if total_output_bytes > 16777216 {
        raise InvalidUpstreamResponse(
          "upstream stream exceeded the 16 MiB limit",
        )
      }
      sequence += 1
      if sequence > request.resource_ceiling.max_output_units {
        raise InvalidUpstreamResponse("stream exceeded output event ceiling")
      }
      let chunk : Json = { "text_delta": value }
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
    output: { "chunks": chunks },
    artifact_digest: self.artifact_digest,
    runtime_version: self.runtime_version,
    input_units,
    output_units,
  }
}
