///|
fn decimal_port(value : String) -> Bool {
  if value == "" ||
    value.length() > 5 ||
    !value.all(character => character >= '0' && character <= '9') {
    return false
  }
  let port = @string.parse_int64(value) catch { _ => return false }
  port > 0L && port <= 65535L
}

///|
fn loopback_authority(authority : String) -> Bool {
  if authority.has_prefix("127.0.0.1:") {
    decimal_port(authority[10:].to_owned()) &&
    (try @socket.Addr::parse(authority) catch {
      _ => return false
    } noraise {
      _ => true
    })
  } else if authority.has_prefix("localhost:") {
    decimal_port(authority[10:].to_owned())
  } else if authority.has_prefix("[::1]:") {
    decimal_port(authority[6:].to_owned()) &&
    (try @socket.Addr::parse(authority) catch {
      _ => return false
    } noraise {
      _ => true
    })
  } else {
    false
  }
}

///|
fn https_authority(authority : String) -> Bool {
  if authority == "" ||
    authority.length() > 253 ||
    authority.contains("@") ||
    authority.contains("/") ||
    authority.contains("?") ||
    authority.contains("#") ||
    authority.contains("\\") {
    return false
  }
  let mut host = authority
  if authority.has_prefix("[") {
    match authority.find("]") {
      Some(close) => {
        if close <= 1 {
          return false
        }
        let suffix = authority[close + 1:].to_owned()
        if suffix != "" &&
          (!suffix.has_prefix(":") || !decimal_port(suffix[1:].to_owned())) {
          return false
        }
        host = authority[1:close].to_owned()
      }
      None => return false
    }
  } else {
    match authority.rev_find(":") {
      Some(colon) => {
        let suffix = authority[colon + 1:].to_owned()
        if !decimal_port(suffix) || authority[:colon].contains(":") {
          return false
        }
        host = authority[:colon].to_owned()
      }
      None => ()
    }
  }
  host != "" &&
  host.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '.' ||
    character == '-' ||
    character == ':'
  })
}

/// Only an exact loopback HTTP origin or an explicitly enabled HTTPS origin is
/// accepted. Paths, credentials, queries, fragments, whitespace, and deceptive
/// loopback suffixes are rejected before the network is touched.

///|
pub fn validate_origin(
  origin : String,
  allow_https : Bool,
) -> Unit raise GuideProbeError {
  if origin == "" || origin != origin.trim().to_owned() || origin.length() > 320 {
    raise InvalidConfiguration("guide probe origin is invalid")
  }
  if origin.has_prefix("http://") && loopback_authority(origin[7:].to_owned()) {
    return
  }
  if allow_https &&
    origin.has_prefix("https://") &&
    https_authority(origin[8:].to_owned()) {
    return
  }
  raise InvalidConfiguration("guide probe origin is not an allowed origin")
}

///|
fn validate_config(config : GuideProbeConfig) -> Unit raise GuideProbeError {
  validate_origin(config.origin, config.allow_https)
  if !@contracts.valid_identifier(config.actor_ref, maximum_length=128) ||
    (config.role != "operator" && config.role != "administrator") ||
    config.maximum_response_bytes < 1024 ||
    config.maximum_response_bytes > 262144 ||
    config.request_timeout_ms < 250 ||
    config.request_timeout_ms > 10000 {
    raise InvalidConfiguration(
      "guide probe configuration is outside bounded limits",
    )
  }
}
