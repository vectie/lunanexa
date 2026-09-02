///|
/// Payload-free failures emitted while joining LunaFlux's ready publication
/// to its same-origin observational control routes.
pub suberror LunaFluxRuntimeDiscoveryError {
  MissingReadyPublication
  DuplicateReadyPublication
  MissingDiscoveryField
  DuplicateDiscoveryField
  StaleOrLateDiscoveryPublication
  InvalidRuntimeOrigin
  InvalidControlOrigin
  InvalidContainerAddress
  RuntimeProtocolMismatch
  InvalidControlProbeTimeout
  ControlProbeFailed
} derive(Debug, Eq)

///|
/// One immutable same-origin runtime/control publication parsed from an approved
/// LunaFlux process. Construction remains inside the opaque adapter boundary.
pub struct LunaFluxRuntimeDiscovery {
  priv runtime_origin : String
  priv runtime_protocol : String
  priv control_origin : String
}

///|
pub fn LunaFluxRuntimeDiscovery::runtime_origin(
  self : LunaFluxRuntimeDiscovery,
) -> String {
  self.runtime_origin
}

///|
pub fn LunaFluxRuntimeDiscovery::runtime_protocol(
  self : LunaFluxRuntimeDiscovery,
) -> String {
  self.runtime_protocol
}

///|
pub fn LunaFluxRuntimeDiscovery::control_origin(
  self : LunaFluxRuntimeDiscovery,
) -> String {
  self.control_origin
}

///|
fn lunaflux_discovery_value(line : String, field : String) -> String? {
  let prefix = field + "="
  if line.has_prefix(prefix) {
    Some(line[prefix.length():].to_owned())
  } else {
    None
  }
}

///|
fn valid_lunaflux_root_free_origin(origin : String, scheme : String) -> Bool {
  let prefix = scheme + "://"
  guard origin.has_prefix(prefix) else { return false }
  let authority = origin[prefix.length():].to_owned()
  if authority == "" ||
    authority.contains_char('/') ||
    authority.contains_char('@') ||
    authority.contains_char(' ') ||
    authority.contains_char('\t') ||
    authority.contains_char('\n') ||
    authority.contains_char('\r') ||
    authority.contains_char('?') ||
    authority.contains_char('#') {
    return false
  }
  try @socket.Addr::parse(authority) catch {
    _ => false
  } noraise {
    addr => addr.port() > 0 && addr.port() <= 65535
  }
}

///|
fn lunaflux_origin_is_wildcard(origin : String) -> Bool {
  origin.has_prefix("http://0.0.0.0:") || origin.has_prefix("http://[::]:")
}

///|
fn parse_lunaflux_ready_publication(
  output : String,
) -> LunaFluxRuntimeDiscovery raise LunaFluxRuntimeDiscoveryError {
  let lines : Array[String] = output
    .split("\n")
    .map(line => line.to_owned())
    .collect()
  let mut ready_index = -1
  let mut ready_count = 0
  let mut runtime_index = -1
  let mut runtime_count = 0
  let mut runtime_origin = ""
  let mut protocol_index = -1
  let mut protocol_count = 0
  let mut runtime_protocol = ""
  let mut control_index = -1
  let mut control_count = 0
  let mut control_origin = ""
  for index, line in lines {
    if line == "readiness: true" {
      ready_count += 1
      ready_index = index
    }
    match lunaflux_discovery_value(line, "runtime_origin") {
      Some(value) => {
        runtime_count += 1
        runtime_index = index
        runtime_origin = value
      }
      None => ()
    }
    match lunaflux_discovery_value(line, "control_origin") {
      Some(value) => {
        control_count += 1
        control_index = index
        control_origin = value
      }
      None => ()
    }
    match lunaflux_discovery_value(line, "runtime_protocol") {
      Some(value) => {
        protocol_count += 1
        protocol_index = index
        runtime_protocol = value
      }
      None => ()
    }
  }
  if ready_count == 0 {
    raise MissingReadyPublication
  }
  if ready_count != 1 {
    raise DuplicateReadyPublication
  }
  if runtime_count == 0 || control_count == 0 || protocol_count == 0 {
    raise MissingDiscoveryField
  }
  if runtime_count != 1 || control_count != 1 || protocol_count != 1 {
    raise DuplicateDiscoveryField
  }
  if runtime_index != ready_index + 1 ||
    control_index != ready_index + 2 ||
    protocol_index != ready_index + 3 {
    raise StaleOrLateDiscoveryPublication
  }
  if !valid_lunaflux_root_free_origin(runtime_origin, "http") {
    raise InvalidRuntimeOrigin
  }
  if !valid_lunaflux_root_free_origin(control_origin, "http") ||
    control_origin != runtime_origin {
    raise InvalidControlOrigin
  }
  if runtime_protocol != "openai-responses-v1" {
    raise RuntimeProtocolMismatch
  }
  { runtime_origin, runtime_protocol, control_origin }
}

///|
fn map_lunaflux_wildcard_origin(
  origin : String,
  container_address : String,
) -> String raise LunaFluxRuntimeDiscoveryError {
  if !lunaflux_origin_is_wildcard(origin) {
    raise InvalidContainerAddress
  }
  let container_address = @node.private_runtime_container_address(
    container_address,
  ) catch {
    _ => raise InvalidContainerAddress
  }
  let authority = origin[7:].to_owned()
  let addr = @socket.Addr::parse(authority) catch {
    _ => raise InvalidRuntimeOrigin
  }
  let host = if container_address.contains_char(':') {
    "[\{container_address}]"
  } else {
    container_address
  }
  "http://\{host}:\{addr.port()}"
}

///|
/// Parses the singular machine-readable publication emitted after LunaFlux
/// reaches readiness. The adapter is already bound to the approved OpenAI
/// Responses contract, so native-framed or substituted protocols fail closed.
pub fn LunaFluxOpaqueAdapter::parse_ready_publication(
  self : LunaFluxOpaqueAdapter,
  output : String,
) -> LunaFluxRuntimeDiscovery raise LunaFluxRuntimeDiscoveryError {
  ignore(self)
  parse_lunaflux_ready_publication(output)
}

///|
/// Joins a wildcard publication to the one private address obtained from the
/// already-inspected isolated OCI network. No host port or public route is
/// introduced by this projection.
fn LunaFluxOpaqueAdapter::parse_private_ready_publication(
  self : LunaFluxOpaqueAdapter,
  output : String,
  container_address : String,
) -> LunaFluxRuntimeDiscovery raise LunaFluxRuntimeDiscoveryError {
  ignore(self)
  let discovered = parse_lunaflux_ready_publication(output)
  let runtime_origin = map_lunaflux_wildcard_origin(
    discovered.runtime_origin,
    container_address,
  )
  {
    runtime_origin,
    runtime_protocol: discovered.runtime_protocol,
    control_origin: runtime_origin,
  }
}

///|
/// Uses only the address returned by the OCI supervisor's exact network
/// inspection, joining discovery to the container instance that was started.
pub fn LunaFluxOpaqueAdapter::parse_private_ready_publication_from_instance(
  self : LunaFluxOpaqueAdapter,
  output : String,
  instance : @node.RuntimeInstance,
) -> LunaFluxRuntimeDiscovery raise LunaFluxRuntimeDiscoveryError {
  self.parse_private_ready_publication(output, instance.container_address)
}

///|
async fn probe_lunaflux_control_endpoint(
  url : String,
  expected_body : String,
) -> Unit {
  let (response, body) = @http.get(url)
  if response.code != 200 || body.text() != expected_body {
    raise LunaFluxRuntimeDiscoveryError::ControlProbeFailed
  }
}

///|
/// Observes same-origin control routes from the launcher's network namespace.
/// This does not publish, proxy, or upgrade the endpoint to TLS.
pub async fn LunaFluxRuntimeDiscovery::probe_control(
  self : LunaFluxRuntimeDiscovery,
  timeout_milliseconds? : Int = 5000,
) -> Unit {
  if timeout_milliseconds <= 0 || timeout_milliseconds > 60000 {
    raise LunaFluxRuntimeDiscoveryError::InvalidControlProbeTimeout
  }
  if self.runtime_protocol != "openai-responses-v1" ||
    self.control_origin != self.runtime_origin ||
    lunaflux_origin_is_wildcard(self.control_origin) {
    raise LunaFluxRuntimeDiscoveryError::ControlProbeFailed
  }
  let observed = @async.with_timeout_opt(timeout_milliseconds, () => {
    probe_lunaflux_control_endpoint(
      self.control_origin + "/healthz",
      "{\"status\":\"healthy\"}\n",
    )
    probe_lunaflux_control_endpoint(
      self.control_origin + "/readyz",
      "{\"status\":\"ready\"}\n",
    )
  }) catch {
    error if @async.is_cancellation_error(error) => raise error
    _ => raise LunaFluxRuntimeDiscoveryError::ControlProbeFailed
  }
  if observed is None {
    raise LunaFluxRuntimeDiscoveryError::ControlProbeFailed
  }
}
