///|
fn required_environment(name : String) -> String raise {
  guard @env.get_env_var(name) is Some(value) && value.trim() != "" else {
    raise Failure(
      "required identity-gateway environment is unavailable: \{name}",
    )
  }
  value.trim().to_owned()
}

///|
fn optional_environment(name : String) -> String? {
  match @env.get_env_var(name) {
    Some(value) if value.trim() != "" => Some(value.trim().to_owned())
    _ => None
  }
}

///|
fn environment_seconds(name : String, fallback : Int64) -> Int64 raise {
  match optional_environment(name) {
    None => fallback
    Some(value) => {
      let seconds = @string.parse_int64(value)
      guard seconds > 0L && seconds <= 86400L else {
        raise Failure("invalid identity-gateway duration: \{name}")
      }
      seconds
    }
  }
}

///|
fn validate_https_origin(value : String, name : String) -> Unit raise {
  guard value.has_prefix("https://") &&
    !value.contains("?") &&
    !value.contains("#") &&
    !value.contains("@") &&
    !value.contains("\\") else {
    raise Failure("invalid HTTPS identity-gateway origin: \{name}")
  }
}

///|
fn validate_http_upstream(value : String, name : String) -> Unit raise {
  guard (value.has_prefix("http://") || value.has_prefix("https://")) &&
    !value.contains("?") &&
    !value.contains("#") &&
    !value.contains("@") &&
    !value.contains("\\") else {
    raise Failure("invalid identity-gateway upstream: \{name}")
  }
}

///|
fn configured_host(redirect_uri : String) -> String raise {
  guard redirect_uri.has_prefix("https://") else {
    raise Failure("redirect URI is not HTTPS")
  }
  let rest = redirect_uri[8:]
  guard rest.find("/") is Some(index) && index > 0 else {
    raise Failure("redirect URI has no callback path")
  }
  rest[:index].to_owned()
}

///|
fn load_config() -> GatewayConfig raise {
  let mode = match required_environment("LUNANEXA_IDENTITY_GATEWAY_MODE") {
    "proxy" => Proxy
    "relay" => Relay
    _ => raise Failure("invalid identity-gateway mode")
  }
  let listen_address = required_environment("LUNANEXA_LISTEN_ADDRESS")
  if mode == Relay {
    let control_endpoint = required_environment("LUNANEXA_CONTROL_ENDPOINT")
    validate_http_upstream(control_endpoint, "LUNANEXA_CONTROL_ENDPOINT")
    return {
      mode,
      listen_address,
      issuer: "",
      oidc_transport_origin: None,
      oidc_ca_file: None,
      operator_host: "",
      enterprise_host: "",
      operator_redirect_uri: "",
      enterprise_redirect_uri: "",
      operator_client_id: "",
      enterprise_client_id: "",
      operator_client_secret: "",
      enterprise_client_secret: "",
      operator_cookie_name: "",
      enterprise_cookie_name: "",
      operator_cookie_secret: "",
      enterprise_cookie_secret: "",
      assertion_secret: "",
      database_url: "",
      relay_endpoint: "",
      control_endpoint,
      operator_upstream: "",
      enterprise_upstream: "",
      session_idle_ms: 0L,
      session_absolute_ms: 0L,
      assertion_lifetime_ms: 0L,
    }
  }
  let issuer = required_environment("LUNANEXA_OIDC_ISSUER_URL")
  let operator_redirect_uri = required_environment(
    "LUNANEXA_OIDC_OPERATOR_REDIRECT_URI",
  )
  let enterprise_redirect_uri = required_environment(
    "LUNANEXA_OIDC_ENTERPRISE_REDIRECT_URI",
  )
  validate_https_origin(issuer, "LUNANEXA_OIDC_ISSUER_URL")
  let oidc_transport_origin = optional_environment(
    "LUNANEXA_OIDC_TRANSPORT_ORIGIN",
  )
  match oidc_transport_origin {
    Some(origin) => {
      validate_https_origin(origin, "LUNANEXA_OIDC_TRANSPORT_ORIGIN")
      guard !origin[8:].contains("/") else {
        raise Failure("OIDC transport origin must not include a path")
      }
    }
    None => ()
  }
  validate_https_origin(operator_redirect_uri, "operator redirect")
  validate_https_origin(enterprise_redirect_uri, "enterprise redirect")
  let operator_host = configured_host(operator_redirect_uri)
  let enterprise_host = configured_host(enterprise_redirect_uri)
  guard operator_host != enterprise_host else {
    raise Failure("operator and enterprise OIDC hosts must differ")
  }
  let operator_client_secret = required_environment(
    "LUNANEXA_OIDC_OPERATOR_CLIENT_SECRET",
  )
  let enterprise_client_secret = required_environment(
    "LUNANEXA_OIDC_ENTERPRISE_CLIENT_SECRET",
  )
  let operator_cookie_secret = required_environment(
    "LUNANEXA_OIDC_OPERATOR_COOKIE_SECRET",
  )
  let enterprise_cookie_secret = required_environment(
    "LUNANEXA_OIDC_ENTERPRISE_COOKIE_SECRET",
  )
  let assertion_secret = required_environment(
    "LUNANEXA_IDENTITY_ASSERTION_SECRET",
  )
  let operator_client_id = required_environment(
    "LUNANEXA_OIDC_OPERATOR_CLIENT_ID",
  )
  let enterprise_client_id = required_environment(
    "LUNANEXA_OIDC_ENTERPRISE_CLIENT_ID",
  )
  let operator_cookie_name = required_environment(
    "LUNANEXA_OIDC_OPERATOR_COOKIE_NAME",
  )
  let enterprise_cookie_name = required_environment(
    "LUNANEXA_OIDC_ENTERPRISE_COOKIE_NAME",
  )
  guard operator_cookie_secret.length() >= 32 &&
    enterprise_cookie_secret.length() >= 32 &&
    assertion_secret.length() >= 32 &&
    operator_cookie_secret != enterprise_cookie_secret &&
    operator_cookie_secret != assertion_secret &&
    enterprise_cookie_secret != assertion_secret else {
    raise Failure(
      "identity-gateway keys must be distinct and at least 32 bytes",
    )
  }
  guard operator_client_id != enterprise_client_id &&
    operator_client_secret != enterprise_client_secret &&
    operator_cookie_name.has_prefix("__Host-") &&
    enterprise_cookie_name.has_prefix("__Host-") &&
    operator_cookie_name != enterprise_cookie_name &&
    !operator_cookie_name.contains(";") &&
    !enterprise_cookie_name.contains(";") else {
    raise Failure("identity-gateway clients and host cookies must be distinct")
  }
  let relay_endpoint = required_environment("LUNANEXA_IDENTITY_RELAY_ENDPOINT")
  let control_endpoint = required_environment(
    "LUNANEXA_CONTROL_BEARER_ENDPOINT",
  )
  let operator_upstream = required_environment("LUNANEXA_OPERATOR_UPSTREAM")
  let enterprise_upstream = required_environment("LUNANEXA_ENTERPRISE_UPSTREAM")
  validate_http_upstream(relay_endpoint, "LUNANEXA_IDENTITY_RELAY_ENDPOINT")
  validate_http_upstream(control_endpoint, "LUNANEXA_CONTROL_BEARER_ENDPOINT")
  validate_http_upstream(operator_upstream, "LUNANEXA_OPERATOR_UPSTREAM")
  validate_http_upstream(enterprise_upstream, "LUNANEXA_ENTERPRISE_UPSTREAM")
  let assertion_lifetime_ms = environment_seconds(
      "LUNANEXA_IDENTITY_ASSERTION_MAXIMUM_SECONDS", 30L,
    ) *
    1000L
  guard assertion_lifetime_ms <= 30000L else {
    raise Failure("identity assertion lifetime exceeds 30 seconds")
  }
  {
    mode,
    listen_address,
    issuer,
    oidc_transport_origin,
    oidc_ca_file: optional_environment("LUNANEXA_OIDC_CA_FILE"),
    operator_host,
    enterprise_host,
    operator_redirect_uri,
    enterprise_redirect_uri,
    operator_client_id,
    enterprise_client_id,
    operator_client_secret,
    enterprise_client_secret,
    operator_cookie_name,
    enterprise_cookie_name,
    operator_cookie_secret,
    enterprise_cookie_secret,
    assertion_secret,
    database_url: required_environment("LUNANEXA_IDENTITY_GATEWAY_DATABASE_URL"),
    relay_endpoint,
    control_endpoint,
    operator_upstream,
    enterprise_upstream,
    session_idle_ms: environment_seconds(
      "LUNANEXA_SESSION_IDLE_TIMEOUT_SECONDS", 1800L,
    ) *
    1000L,
    session_absolute_ms: environment_seconds(
      "LUNANEXA_SESSION_ABSOLUTE_TIMEOUT_SECONDS", 28800L,
    ) *
    1000L,
    assertion_lifetime_ms,
  }
}

///|
fn GatewayConfig::host_audience(
  self : GatewayConfig,
  host : String,
) -> BrowserAudience? {
  if host == self.operator_host {
    Some(Operator)
  } else if host == self.enterprise_host {
    Some(Enterprise)
  } else {
    None
  }
}

///|
fn GatewayConfig::client_id(
  self : GatewayConfig,
  audience : BrowserAudience,
) -> String {
  match audience {
    Operator => self.operator_client_id
    Enterprise => self.enterprise_client_id
  }
}

///|
fn GatewayConfig::client_secret(
  self : GatewayConfig,
  audience : BrowserAudience,
) -> String {
  match audience {
    Operator => self.operator_client_secret
    Enterprise => self.enterprise_client_secret
  }
}

///|
fn GatewayConfig::redirect_uri(
  self : GatewayConfig,
  audience : BrowserAudience,
) -> String {
  match audience {
    Operator => self.operator_redirect_uri
    Enterprise => self.enterprise_redirect_uri
  }
}

///|
fn GatewayConfig::cookie_name(
  self : GatewayConfig,
  audience : BrowserAudience,
) -> String {
  match audience {
    Operator => self.operator_cookie_name
    Enterprise => self.enterprise_cookie_name
  }
}

///|
fn GatewayConfig::cookie_secret(
  self : GatewayConfig,
  audience : BrowserAudience,
) -> String {
  match audience {
    Operator => self.operator_cookie_secret
    Enterprise => self.enterprise_cookie_secret
  }
}

///|
fn GatewayConfig::ui_upstream(
  self : GatewayConfig,
  audience : BrowserAudience,
) -> String {
  match audience {
    Operator => self.operator_upstream
    Enterprise => self.enterprise_upstream
  }
}
