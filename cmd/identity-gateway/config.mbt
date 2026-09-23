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
  let prefix = if redirect_uri.has_prefix("https://") {
    8
  } else if redirect_uri.has_prefix("http://") {
    7
  } else {
    raise Failure("redirect URI protocol is invalid")
  }
  let rest = redirect_uri[prefix:]
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
      canonical_identity_issuer: None,
      oidc_transport_origin: None,
      oidc_ca_file: None,
      operator_host: "",
      enterprise_host: "",
      alternate_https_port: false,
      browser_oidc_enabled: false,
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
      registration_admin_origin: None,
      registration_client_id: None,
      registration_client_secret: None,
    }
  }
  let issuer = required_environment("LUNANEXA_OIDC_ISSUER_URL")
  let operator_redirect_uri = required_environment(
    "LUNANEXA_OIDC_OPERATOR_REDIRECT_URI",
  )
  let enterprise_redirect_uri = required_environment(
    "LUNANEXA_OIDC_ENTERPRISE_REDIRECT_URI",
  )
  let public_http = match optional_environment("LUNANEXA_PUBLIC_HTTP_ENABLED") {
    None | Some("false") => false
    Some("true") => true
    _ => raise Failure("invalid LUNANEXA_PUBLIC_HTTP_ENABLED")
  }
  validate_browser_endpoint(issuer, public_http)
  let canonical_identity_issuer = optional_environment(
    "LUNANEXA_IDENTITY_CANONICAL_ISSUER",
  )
  match canonical_identity_issuer {
    Some(canonical) => {
      guard public_http && canonical == "https://\{issuer[7:]}" else {
        raise Failure(
          "canonical identity issuer may only preserve the same HTTPS issuer during public HTTP migration",
        )
      }
    }
    None => ()
  }
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
  if public_http && oidc_transport_origin is None {
    raise Failure("public HTTP requires a separate HTTPS OIDC transport")
  }
  validate_browser_redirects(
    operator_redirect_uri, enterprise_redirect_uri, public_http,
  )
  let operator_host = configured_host(operator_redirect_uri)
  let enterprise_host = configured_host(enterprise_redirect_uri)
  let alternate_https_port = match
    optional_environment("LUNANEXA_BROWSER_ALTERNATE_HTTPS_PORT") {
    None => false
    Some("8443") if operator_host == enterprise_host &&
      !operator_host.contains(":") &&
      operator_redirect_uri.has_prefix("https://") => true
    _ => raise Failure("invalid alternate HTTPS browser port")
  }
  let browser_oidc_enabled = match
    optional_environment("LUNANEXA_BROWSER_OIDC_ENABLED") {
    None | Some("true") => true
    Some("false") => false
    _ => raise Failure("invalid browser OIDC switch")
  }
  if operator_host == enterprise_host {
    guard operator_redirect_uri ==
      "https://\{operator_host}/mana/auth/oidc/callback" &&
      enterprise_redirect_uri ==
      "https://\{enterprise_host}/user/auth/oidc/callback" else {
      raise Failure(
        "shared OIDC host requires the /mana and /user callback paths",
      )
    }
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
    valid_browser_cookie_name(operator_cookie_name, public_http) &&
    valid_browser_cookie_name(enterprise_cookie_name, public_http) &&
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
  // Customer self-registration is optional: a deployment that does not want the
  // gateway to hold any provider-admin credential simply leaves these unset.
  let registration_admin_origin = optional_environment(
    "LUNANEXA_OIDC_ADMIN_ORIGIN",
  )
  let registration_client_id = optional_environment(
    "LUNANEXA_OIDC_REALM_REGISTRATION_CLIENT_ID",
  )
  let registration_client_secret = optional_environment(
    "LUNANEXA_OIDC_REALM_REGISTRATION_CLIENT_SECRET",
  )
  match registration_admin_origin {
    Some(origin) => {
      guard registration_client_id is Some(client_id) &&
        registration_client_secret is Some(secret) else {
        raise Failure(
          "LUNANEXA_OIDC_ADMIN_ORIGIN requires the registration client id and secret",
        )
      }
      validate_https_origin(origin, "LUNANEXA_OIDC_ADMIN_ORIGIN")
      guard !origin[8:].contains("/") else {
        raise Failure("OIDC admin origin must not include a path")
      }
      guard secret.length() >= 32 &&
        client_id != operator_client_id &&
        client_id != enterprise_client_id else {
        raise Failure(
          "the registration client must be distinct and its secret at least 32 bytes",
        )
      }
    }
    None => {
      guard registration_client_id is None && registration_client_secret is None else {
        raise Failure(
          "the registration client id and secret require LUNANEXA_OIDC_ADMIN_ORIGIN",
        )
      }
    }
  }
  {
    mode,
    listen_address,
    issuer,
    canonical_identity_issuer,
    oidc_transport_origin,
    oidc_ca_file: optional_environment("LUNANEXA_OIDC_CA_FILE"),
    operator_host,
    enterprise_host,
    alternate_https_port,
    browser_oidc_enabled,
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
    registration_admin_origin,
    registration_client_id,
    registration_client_secret,
  }
}

///|
/// The provider realm the gateway serves, read from the configured issuer. The
/// admin API is addressed by realm, so the same realm the browser logs in to is
/// the realm self-registration creates accounts in -- there is no second
/// setting that could disagree.
fn configured_realm(issuer : String) -> String raise {
  guard issuer.find("/realms/") is Some(index) else {
    raise Failure("OIDC issuer does not name a realm")
  }
  let realm = issuer[index + 8:].to_owned()
  guard realm.length() > 0 &&
    realm.length() <= 128 &&
    !realm.contains("/") &&
    realm
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_'
    }) else {
    raise Failure("OIDC issuer realm name is invalid")
  }
  realm
}

///|
fn validate_browser_endpoint(value : String, public_http : Bool) -> Unit raise {
  validate_http_upstream(value, "browser endpoint")
  let prefix = if public_http { "http://" } else { "https://" }
  guard value.has_prefix(prefix) && configured_host(value) != "" else {
    raise Failure(
      "browser endpoint does not match the explicit public transport mode",
    )
  }
}

///|
fn validate_browser_redirects(
  operator_redirect_uri : String,
  enterprise_redirect_uri : String,
  public_http : Bool,
) -> Unit raise {
  // The existing OIDC issuer can remain on its HTTP migration address while
  // the new public browser callbacks are served over the shared HTTPS domain.
  let https_callbacks = operator_redirect_uri.has_prefix("https://") &&
    enterprise_redirect_uri.has_prefix("https://")
  validate_browser_endpoint(
    operator_redirect_uri,
    public_http && !https_callbacks,
  )
  validate_browser_endpoint(
    enterprise_redirect_uri,
    public_http && !https_callbacks,
  )
}

///|
fn valid_browser_cookie_name(name : String, public_http : Bool) -> Bool {
  let prefix = if public_http { "lunanexa_http_" } else { "__Host-" }
  name.has_prefix(prefix) &&
  name.length() > prefix.length() &&
  name
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-'
  })
}

///|
fn GatewayConfig::browser_secure(self : GatewayConfig) -> Bool {
  self.operator_redirect_uri.has_prefix("https://") &&
  self.enterprise_redirect_uri.has_prefix("https://")
}

///|
fn GatewayConfig::browser_scheme(self : GatewayConfig) -> String {
  if self.browser_secure() {
    "https"
  } else {
    "http"
  }
}

///|
fn GatewayConfig::host_audience(
  self : GatewayConfig,
  host : String,
) -> BrowserAudience? {
  if self.operator_host == self.enterprise_host {
    return None
  }
  if self.matches_browser_host(host, self.operator_host) {
    Some(Operator)
  } else if self.matches_browser_host(host, self.enterprise_host) {
    Some(Enterprise)
  } else {
    None
  }
}

///|
fn GatewayConfig::browser_audience(
  self : GatewayConfig,
  host : String,
  forwarded_prefix : String?,
) -> BrowserAudience? {
  if self.operator_host != self.enterprise_host {
    return self.host_audience(host)
  }
  if !self.matches_browser_host(host, self.operator_host) {
    return None
  }
  match forwarded_prefix {
    Some("/mana") => Some(Operator)
    Some("/user") => Some(Enterprise)
    _ => None
  }
}

///|
fn GatewayConfig::matches_browser_host(
  self : GatewayConfig,
  host : String,
  expected : String,
) -> Bool {
  host == expected || (self.alternate_https_port && host == "\{expected}:8443")
}

///|
fn GatewayConfig::public_ui_path(
  self : GatewayConfig,
  audience : BrowserAudience,
) -> String {
  if self.operator_host == self.enterprise_host {
    match audience {
      Operator => "/mana/"
      Enterprise => "/user/"
    }
  } else {
    match audience {
      Operator => "/console/"
      Enterprise => "/enterprise/"
    }
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
fn GatewayConfig::redirect_uri_for_host(
  self : GatewayConfig,
  audience : BrowserAudience,
  host : String,
) -> String {
  let configured = self.redirect_uri(audience)
  if self.alternate_https_port && host == "\{self.operator_host}:8443" {
    "https://\{host}\{configured[8 + self.operator_host.length():]}"
  } else {
    configured
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
fn GatewayConfig::cookie_name_for_host(
  self : GatewayConfig,
  audience : BrowserAudience,
  host : String,
) -> String {
  let name = self.cookie_name(audience)
  if self.alternate_https_port && host == "\{self.operator_host}:8443" {
    "\{name}_8443"
  } else {
    name
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
