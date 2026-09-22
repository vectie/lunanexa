///|
fn valid_atom(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 256 &&
  value.all(c => c >= '!' && c <= '~')
}

///|
fn valid_origin(
  value : String,
  allow_insecure_public_http? : Bool = false,
) -> Bool {
  let prefix = if value.has_prefix("https://") {
    8
  } else if value.has_prefix("http://127.0.0.1:") {
    7
  } else if allow_insecure_public_http &&
    value.has_prefix("http://") &&
    explicit_ipv4_authority(value[7:].to_owned()) {
    7
  } else {
    return false
  }
  let authority = value[prefix:]
  authority.length() > 0 &&
  authority.length() <= 253 &&
  authority.all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '.' ||
    c == ':'
  })
}

///|
/// Temporary no-TLS deployments must name an exact IPv4 address and port.
/// Do not accept wildcard binds, DNS aliases, credentials, paths or URL tricks.
fn explicit_ipv4_authority(value : String) -> Bool {
  guard value.split(":").to_array() is [host, port] else { return false }
  let octets = host.split(".").to_array()
  if octets.length() != 4 || host == "0.0.0.0" {
    return false
  }
  for octet in octets {
    if !bounded_decimal(octet.to_owned(), 255, allow_zero=true) {
      return false
    }
  }
  bounded_decimal(port.to_owned(), 65535, allow_zero=false)
}

///|
fn bounded_decimal(value : String, maximum : Int, allow_zero~ : Bool) -> Bool {
  if value.is_empty() ||
    value.length() > 5 ||
    (value.length() > 1 && value.has_prefix("0")) {
    return false
  }
  let mut number = 0
  for digit in value {
    if digit < '0' || digit > '9' {
      return false
    }
    number = number * 10 + digit.to_int() - 48
  }
  number <= maximum && (allow_zero || number > 0)
}

///|
pub fn Bridge::new(
  config : BridgeConfig,
  redeem : async (String) -> Grant,
  authorize : async (Grant) -> Bool,
  provision : async (String, Grant) -> Backend,
  allow_insecure_public_http? : Bool = false,
  allow_model_free_workspace? : Bool = false,
) -> Bridge raise BridgeError {
  if !valid_atom(config.client_id) ||
    !valid_origin(config.public_origin, allow_insecure_public_http~) ||
    config.maximum_sessions < 1 ||
    config.maximum_sessions > 10000 ||
    config.maximum_request_bytes < 1024 ||
    config.maximum_request_bytes > 67108864 ||
    config.maximum_socket_message_bytes < 1024 ||
    config.maximum_socket_message_bytes > 16777216 ||
    config.request_timeout_ms < 100 ||
    config.request_timeout_ms > 300000 ||
    config.authorization_interval_ms < 100 ||
    config.authorization_interval_ms > 10000 {
    raise InvalidConfiguration
  }
  {
    allow_model_free_workspace,
    config,
    redeem,
    authorize,
    provision,
    sessions: {},
    challenges: {},
    authorizations: {},
    mutex: Mutex(),
  }
}

///|
/// Runtime identity includes the authority dimensions plus client/delivery for
/// bound sessions. JSON encoding avoids delimiter collisions; legacy IDs stay
/// unchanged. It reveals neither account nor model secrets.
pub fn workspace_id(grant : Grant) -> String {
  let identity = [
    grant.tenant_ref,
    grant.subject_ref,
    grant.organization_id,
    grant.project_id,
  ]
  if grant.delivery_id is Some(delivery) {
    identity.push(grant.client_id)
    identity.push(delivery)
  }
  "webide-" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(identity.to_json().stringify())),
  )
}

///|
/// Retain user data across deliveries of the same client without sharing an
/// IaaS home with a ComfyUI workspace. Legacy identities remain unchanged.
pub fn workspace_storage_id(grant : Grant) -> String {
  if grant.delivery_id is None {
    return workspace_id(grant)
  }
  let identity = [
    grant.tenant_ref,
    grant.subject_ref,
    grant.organization_id,
    grant.project_id,
    grant.client_id,
  ]
  "webide-" +
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(identity.to_json().stringify())),
  )
}

///|
fn Bridge::valid_grant(self : Bridge, grant : Grant, now : Int64) -> Bool {
  grant.client_id == self.config.client_id &&
  grant.delivery_id.map_or(true, valid_atom) &&
  [grant.tenant_ref, grant.subject_ref, grant.organization_id, grant.project_id].all(
    valid_atom,
  ) &&
  grant.api_secret.length() >= 32 &&
  grant.api_secret.length() <= 4096 &&
  grant.api_secret.all(c => c >= '!' && c <= '~') &&
  (self.allow_model_free_workspace || grant.allowed_models.length() > 0) &&
  grant.allowed_models.length() <= 128 &&
  grant.allowed_models.all(valid_atom) &&
  grant.expires_unix_ms > now
}

///|
fn header(headers : Map[String, String], name : String) -> String? {
  let matches = headers
    .iter()
    .filter(pair => pair.0.to_lower() == name)
    .to_array()
  if matches.length() == 1 {
    Some(matches[0].1)
  } else {
    None
  }
}

///|
fn cookie(headers : Map[String, String], name : String) -> String? {
  guard header(headers, "cookie") is Some(raw) else { return None }
  let matches = raw
    .split(";")
    .filter_map(part => {
      let item = part.trim().to_owned()
      if item.has_prefix(name + "=") {
        Some(item[name.length() + 1:].to_owned())
      } else {
        None
      }
    })
    .to_array()
  if matches.length() == 1 &&
    matches[0].length() == 64 &&
    matches[0].all(c => (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9')) {
    Some(matches[0])
  } else {
    None
  }
}

///|
fn Bridge::cookie_name(self : Bridge, challenge : Bool) -> String {
  (if self.config.public_origin.has_prefix("https://") {
    "__Host-"
  } else {
    ""
  }) +
  (if challenge { "webide-connect" } else { "webide-session" })
}

///|
/// This gateway is deliberately not an unrestricted HTTP tunnel. Administrative
/// extension installation and filesystem administration stay operator-only.
fn allowed_path(verb : @http.RequestMethod, path : String) -> Bool {
  if path.length() > 4096 ||
    !path.has_prefix("/") ||
    path.has_prefix("//") ||
    path.contains("\\") ||
    path.contains("#") ||
    !path.all(c => c >= '!' && c <= '~') {
    return false
  }
  guard decoded_path(path.split("?").next().unwrap_or("").to_owned())
    is Some(route) else {
    return false
  }
  if route.contains("%") ||
    route.contains("\\") ||
    route.contains("//") ||
    route.split("/").any(part => part == ".." || part == ".") {
    return false
  }
  let route = if route.has_prefix("/api/") {
    route[4:].to_owned()
  } else {
    route
  }
  match verb {
    Get | Head =>
      [
        "/", "/ws", "/queue", "/history", "/prompt", "/object_info", "/system_stats",
        "/features", "/extensions", "/embeddings", "/models", "/settings", "/users",
        "/userdata", "/v2/userdata", "/view", "/favicon.ico", "/jobs", "/workflow_templates",
        "/i18n", "/experiment/models", "/node_replacements", "/assets",
      ].contains(route) ||
      [
        "/assets/", "/scripts/", "/extensions/", "/locales/", "/object_info/", "/history/",
        "/models/", "/userdata/", "/settings/", "/jobs/", "/templates/", "/view_metadata/",
        "/experiment/models/",
      ].any(prefix => route.has_prefix(prefix))
    Post =>
      [
        "/prompt", "/queue", "/interrupt", "/history", "/upload/image", "/upload/mask",
        "/settings", "/free", "/jobs/cancel",
      ].contains(route) ||
      (route.has_prefix("/jobs/") && route.has_suffix("/cancel")) ||
      route.has_prefix("/userdata/") ||
      route.has_prefix("/settings/")
    Delete => route.has_prefix("/userdata/")
    _ => false
  }
}

///|
/// ComfyUI encodes workflow names (including their folder slash) in userdata
/// paths. Decode once for authorization, reject double encoding/traversal, and
/// forward the original URI to preserve the upstream route's semantics.
fn decoded_path(value : String) -> String? {
  let buffer = Buffer()
  let mut index = 0
  while index < value.length() {
    let code = value[index].to_int()
    if code == 37 {
      if index + 2 >= value.length() {
        return None
      }
      let digits = value[index + 1:index + 3].to_lower()
      let alphabet = "0123456789abcdef"
      let high = alphabet.find(digits[0:1]).unwrap_or(-1)
      let low = alphabet.find(digits[1:2]).unwrap_or(-1)
      if high < 0 || low < 0 {
        return None
      }
      let byte = high * 16 + low
      if byte < 32 || byte == 127 {
        return None
      }
      buffer.write_byte(byte.to_byte())
      index += 3
    } else {
      buffer.write_byte(code.to_byte())
      index += 1
    }
  }
  Some(@utf8.decode(buffer.to_bytes())) catch {
    _ => None
  }
}
