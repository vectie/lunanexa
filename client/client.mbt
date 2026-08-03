///|
pub(all) struct ClientConfig {
  endpoint : String
  inference_credential_ref : String
  timeout_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CapabilityDescriptor {
  capability : @contracts.Capability
  selectors : Array[String]
  streaming : Bool
  cancellation : Bool
  healthy : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ClientErrorCode {
  Transport
  Contract
  ProviderRejected
  ProviderUnavailable
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror ClientError {
  ClientError(code~ : ClientErrorCode, message~ : String, retryable~ : Bool)
} derive(Debug, Eq)

///|
pub(open) trait ProviderTransport {
  async fn invoke(Self, ClientConfig, String) -> String raise ClientError
  async fn cancel(Self, ClientConfig, String) -> Bool raise ClientError
  async fn discover(Self, ClientConfig) -> Array[CapabilityDescriptor] raise ClientError
  async fn health(Self, ClientConfig) -> Bool raise ClientError
  async fn stream(
    Self,
    ClientConfig,
    String,
    async (@contracts.WorkloadStreamEvent) -> Unit noraise,
  ) -> Unit raise ClientError
}

///|
pub struct Client[T] {
  config : ClientConfig
  transport : T
}

///|
pub fn[T] Client::new(config : ClientConfig, transport : T) -> Client[T] {
  { config, transport }
}

///|
fn validate_client_config(config : ClientConfig) -> Unit raise ClientError {
  let secure = config.endpoint.has_prefix("https://")
  let loopback = config.endpoint.has_prefix("http://127.0.0.1:") ||
    config.endpoint.has_prefix("http://localhost:")
  if !secure && !loopback {
    raise ClientError(
      code=Contract,
      message="provider endpoint must use HTTPS outside loopback",
      retryable=false,
    )
  }
  if config.timeout_ms <= 0L ||
    config.timeout_ms > 86400000L ||
    config.inference_credential_ref == "" {
    raise ClientError(
      code=Contract,
      message="client timeout or credential reference is invalid",
      retryable=false,
    )
  }
}

///|
pub async fn[T : ProviderTransport] Client::invoke(
  self : Client[T],
  request : @contracts.WorkloadEnvelope,
) -> @contracts.WorkloadResponse {
  validate_client_config(self.config)
  @contracts.validate_workload(request) catch {
    error =>
      raise ClientError(
        code=Contract,
        message="invalid canonical request: \{to_repr(error)}",
        retryable=false,
      )
  }
  let body = request.to_json().stringify()
  let response_body = ProviderTransport::invoke(
    self.transport,
    self.config,
    body,
  )
  let response : @contracts.WorkloadResponse = @json.from_json(
    @json.parse(response_body),
  ) catch {
    error =>
      raise ClientError(
        code=Contract,
        message="invalid canonical response: \{to_repr(error)}",
        retryable=false,
      )
  }
  response
}

///|
pub async fn[T : ProviderTransport] Client::cancel(
  self : Client[T],
  workload_id : String,
) -> Bool raise ClientError {
  validate_client_config(self.config)
  if !@contracts.valid_identifier(workload_id) {
    raise ClientError(
      code=Contract,
      message="workload identifier is invalid",
      retryable=false,
    )
  }
  ProviderTransport::cancel(self.transport, self.config, workload_id)
}

///|
pub async fn[T : ProviderTransport] Client::discover(
  self : Client[T],
) -> Array[CapabilityDescriptor] raise ClientError {
  validate_client_config(self.config)
  ProviderTransport::discover(self.transport, self.config)
}

///|
pub async fn[T : ProviderTransport] Client::healthy(
  self : Client[T],
) -> Bool raise ClientError {
  validate_client_config(self.config)
  ProviderTransport::health(self.transport, self.config)
}

///|
pub async fn[T : ProviderTransport] Client::stream(
  self : Client[T],
  request : @contracts.WorkloadEnvelope,
  on_event : async (@contracts.WorkloadStreamEvent) -> Unit noraise,
) -> Unit raise ClientError {
  validate_client_config(self.config)
  @contracts.validate_workload(request) catch {
    error =>
      raise ClientError(
        code=Contract,
        message="invalid canonical request: \{to_repr(error)}",
        retryable=false,
      )
  }
  ProviderTransport::stream(
    self.transport,
    self.config,
    request.to_json().stringify(),
    on_event,
  )
}

///|
pub struct FixtureTransport {
  response : @contracts.WorkloadResponse
  capabilities : Array[CapabilityDescriptor]
  mut cancelled_workload : String?
  healthy_value : Bool
}

///|
pub fn FixtureTransport::new(
  response : @contracts.WorkloadResponse,
  capabilities : Array[CapabilityDescriptor],
  healthy? : Bool = true,
) -> FixtureTransport {
  { response, capabilities, cancelled_workload: None, healthy_value: healthy }
}

///|
pub fn FixtureTransport::cancelled_workload(self : FixtureTransport) -> String? {
  self.cancelled_workload
}

///|
pub impl ProviderTransport for FixtureTransport with fn invoke(
  self,
  _,
  request_body,
) {
  let request : @contracts.WorkloadEnvelope = @json.from_json(
    @json.parse(request_body),
  ) catch {
    error =>
      raise ClientError(
        code=Contract,
        message="fixture received invalid request: \{to_repr(error)}",
        retryable=false,
      )
  }
  if request.version != @contracts.contract_version {
    raise ClientError(
      code=Contract,
      message="unsupported version",
      retryable=false,
    )
  }
  self.response.to_json().stringify()
}

///|
pub impl ProviderTransport for FixtureTransport with fn cancel(
  self,
  _,
  workload_id,
) {
  self.cancelled_workload = Some(workload_id)
  true
}

///|
pub impl ProviderTransport for FixtureTransport with fn discover(self, _) {
  self.capabilities.copy()
}

///|
pub impl ProviderTransport for FixtureTransport with fn health(self, _) {
  self.healthy_value
}

///|
pub impl ProviderTransport for FixtureTransport with fn stream(
  self,
  _,
  _,
  on_event,
) {
  on_event({
    workload_id: self.response.workload_id,
    sequence: 1,
    kind: Chunk,
    output: self.response.output,
    response: None,
  })
  on_event({
    workload_id: self.response.workload_id,
    sequence: 2,
    kind: Completed,
    output: None,
    response: Some({ ..self.response, output: None }),
  })
}

///|
priv struct CapabilityResponse {
  contract_version : String
  capabilities : Array[String]
  selectors : Array[String]
  streaming : Bool
  cancellation : Bool
} derive(FromJson)

///|
pub struct HttpTransport {
  credential_value : String
}

///|
pub fn HttpTransport::new(credential_value : String) -> HttpTransport {
  { credential_value, }
}

///|
fn HttpTransport::headers(self : HttpTransport) -> Map[String, String] {
  {
    "Authorization": "Bearer \{self.credential_value}",
    "Content-Type": "application/json",
    "Accept": "application/json",
  }
}

///|
fn endpoint(config : ClientConfig, path : String) -> String {
  if config.endpoint.has_suffix("/") {
    "\{config.endpoint[:-1]}\{path}"
  } else {
    "\{config.endpoint}\{path}"
  }
}

///|
fn transport_error(status : Int) -> ClientError {
  if status >= 500 {
    ClientError(
      code=ProviderUnavailable,
      message="provider unavailable",
      retryable=true,
    )
  } else {
    ClientError(
      code=ProviderRejected,
      message="provider rejected request",
      retryable=false,
    )
  }
}

///|
fn transport_failure() -> ClientError {
  ClientError(
    code=Transport,
    message="provider transport failed",
    retryable=true,
  )
}

///|
pub impl ProviderTransport for HttpTransport with fn invoke(self, config, body) {
  let (response, response_body) = @async.with_timeout(
    config.timeout_ms.to_int(),
    () => {
      @http.post(
        endpoint(config, "/v1/workloads"),
        body,
        headers=self.headers(),
      )
    },
  ) catch {
    _ => raise transport_failure()
  }
  if response.code < 200 || response.code >= 300 {
    raise transport_error(response.code)
  }
  response_body.text() catch {
    _ => raise transport_failure()
  }
}

///|
pub impl ProviderTransport for HttpTransport with fn cancel(
  self,
  config,
  workload_id,
) {
  let (response, _) = @async.with_timeout(config.timeout_ms.to_int(), () => {
    @http.post(
      endpoint(config, "/v1/workloads/\{workload_id}/cancel"),
      "",
      headers=self.headers(),
    )
  }) catch {
    _ => raise transport_failure()
  }
  response.code == 202
}

///|
pub impl ProviderTransport for HttpTransport with fn discover(self, config) {
  let (response, body) = @async.with_timeout(config.timeout_ms.to_int(), () => {
    @http.get(endpoint(config, "/v1/capabilities"), headers=self.headers())
  }) catch {
    _ => raise transport_failure()
  }
  if response.code < 200 || response.code >= 300 {
    raise transport_error(response.code)
  }
  let decoded : CapabilityResponse = @json.from_json(
    @json.parse(body.text() catch { _ => raise transport_failure() }),
  ) catch {
    _ =>
      raise ClientError(
        code=Contract,
        message="invalid capability response",
        retryable=false,
      )
  }
  if decoded.contract_version != @contracts.contract_version {
    raise ClientError(
      code=Contract,
      message="unsupported provider contract version",
      retryable=false,
    )
  }
  [
    for capability in decoded.capabilities if capability == "TextGenerate" => {
      {
        capability: @contracts.Capability::TextGenerate,
        selectors: decoded.selectors,
        streaming: decoded.streaming,
        cancellation: decoded.cancellation,
        healthy: true,
      }
    }
  ]
}

///|
pub impl ProviderTransport for HttpTransport with fn health(self, config) {
  let (response, _) = @async.with_timeout(config.timeout_ms.to_int(), () => {
    @http.get(endpoint(config, "/health"), headers=self.headers())
  }) catch {
    _ => raise transport_failure()
  }
  response.code == 200
}

///|
pub impl ProviderTransport for HttpTransport with fn stream(
  self,
  config,
  body,
  on_event,
) {
  let canonical_request = @contracts.decode_workload(body) catch {
    _ =>
      raise ClientError(
        code=Contract,
        message="invalid outbound canonical stream request",
        retryable=false,
      )
  }
  let stream = @async.with_timeout(config.timeout_ms.to_int(), () => {
    @http.post_stream(
      endpoint(config, "/v1/workloads:stream"),
      headers=self.headers(),
    )
  }) catch {
    _ => raise transport_failure()
  }
  defer stream.close()
  stream.write(body) catch {
    _ => raise transport_failure()
  }
  let response = @async.with_timeout(config.timeout_ms.to_int(), () => {
    stream.end_request()
  }) catch {
    _ => raise transport_failure()
  }
  if response.code < 200 || response.code >= 300 {
    raise transport_error(response.code)
  }
  let mut saw_terminal = false
  let mut last_sequence = 0
  let mut event_count = 0
  let mut total_event_bytes = 0
  while (@async.with_timeout(config.timeout_ms.to_int(), () => {
          stream.read_until("\n")
        }) catch {
          _ => raise transport_failure()
        })
        is Some(line) {
    let trimmed = line.trim()
    if !trimmed.has_prefix("data:") {
      continue
    }
    if trimmed.length() > 1048576 {
      raise ClientError(
        code=Contract,
        message="canonical stream event exceeded the 1 MiB limit",
        retryable=false,
      )
    }
    total_event_bytes += trimmed.length()
    event_count += 1
    if total_event_bytes > 16777216 || event_count > 65536 {
      raise ClientError(
        code=Contract,
        message="canonical stream exceeded its bounded session limit",
        retryable=false,
      )
    }
    let event : @contracts.WorkloadStreamEvent = @json.from_json(
      @json.parse(trimmed["data:".length():].trim()),
    ) catch {
      _ =>
        raise ClientError(
          code=Contract,
          message="invalid canonical stream event",
          retryable=false,
        )
    }
    if event.workload_id != canonical_request.workload_id ||
      event.sequence <= last_sequence {
      raise ClientError(
        code=Contract,
        message="canonical stream identity or sequence is invalid",
        retryable=false,
      )
    }
    last_sequence = event.sequence
    let terminal = event.kind == Completed ||
      event.kind == Failed ||
      event.kind == Cancelled
    if terminal && event.response is None {
      raise ClientError(
        code=Contract,
        message="canonical terminal event is missing its response",
        retryable=false,
      )
    }
    on_event(event)
    if terminal {
      saw_terminal = true
      break
    }
  }
  if !saw_terminal {
    raise ClientError(
      code=Contract,
      message="canonical stream ended without a terminal event",
      retryable=false,
    )
  }
}
