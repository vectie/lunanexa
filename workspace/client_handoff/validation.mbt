///|
fn valid_text(value : String, maximum : Int) -> Bool {
  value.length() > 0 &&
  value.length() <= maximum &&
  value.all(character => {
    character.is_printable() && character != '<' && character != '>'
  })
}

///|
fn valid_authority_character(character : Char) -> Bool {
  (character >= 'a' && character <= 'z') ||
  (character >= 'A' && character <= 'Z') ||
  (character >= '0' && character <= '9') ||
  ['-', '.', ':', '[', ']'].contains(character)
}

///|
fn valid_port(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 5 &&
  value.all(character => character.is_ascii_digit())
}

///|
fn loopback_authority(authority : String) -> Bool {
  let lower = authority.to_lower()
  if lower == "localhost" || lower == "127.0.0.1" || lower == "[::1]" {
    return true
  }
  for prefix in ["localhost:", "127.0.0.1:", "[::1]:"] {
    if lower.has_prefix(prefix) {
      return valid_port(lower[prefix.length():].to_owned())
    }
  }
  false
}

///|
fn safe_client_url(
  value : String,
  allow_custom_scheme : Bool,
  allow_query : Bool,
  allowed_http_origins? : Array[String] = [],
) -> Bool {
  if value == "" ||
    value.length() > 2048 ||
    value.trim() != value ||
    value.contains_char('@') ||
    value.contains_char('\\') ||
    value.contains_char('#') ||
    value.contains_char('\n') ||
    value.contains_char('\r') ||
    (!allow_query && value.contains_char('?')) {
    return false
  }
  if allow_custom_scheme && value.has_prefix("lunanexa-client://") {
    return value.length() > "lunanexa-client://".length()
  }
  let (secure, remainder) = if value.has_prefix("https://") {
    (true, value[8:].to_owned())
  } else if value.has_prefix("http://") {
    (false, value[7:].to_owned())
  } else {
    return false
  }
  let slash = remainder.find("/")
  let query = remainder.find("?")
  let boundary = match (slash, query) {
    (Some(left), Some(right)) => left.min(right)
    (Some(index), None) | (None, Some(index)) => index
    (None, None) => remainder.length()
  }
  let authority = remainder[:boundary].to_owned()
  if authority == "" ||
    authority.length() > 255 ||
    !authority.all(valid_authority_character) {
    return false
  }
  secure ||
  loopback_authority(authority) ||
  allowed_http_origins.contains("http://" + authority)
}

///|
pub fn valid_client_launch_config(
  config : ClientLaunchConfig,
  allowed_http_launch_origins? : Array[String] = [],
  allowed_http_api_origins? : Array[String] = [],
) -> Bool {
  @contracts.valid_identifier(config.client_id) &&
  valid_text(config.display_name, 128) &&
  safe_client_url(
    config.launch_uri,
    true,
    true,
    allowed_http_origins=allowed_http_launch_origins,
  ) &&
  safe_client_url(
    config.public_api_base_url,
    false,
    false,
    allowed_http_origins=allowed_http_api_origins,
  ) &&
  config.handoff_lifetime_ms >= 30000L &&
  config.handoff_lifetime_ms <= 300000L &&
  config.maximum_requests > 0L &&
  config.maximum_requests <= 1000000000L
}

///|
/// A deployment-owned WebIDE catalog. IDs must be unique; clients never supply
/// their own launch or provider URLs when requesting a handoff.
pub fn valid_client_launch_catalog(
  configs : Array[ClientLaunchConfig],
  allowed_http_launch_origins? : Array[String] = [],
  allowed_http_api_origins? : Array[String] = [],
) -> Bool {
  configs.length() > 0 &&
  configs.length() <= 32 &&
  configs.all(config => {
    valid_client_launch_config(
      config,
      allowed_http_launch_origins~,
      allowed_http_api_origins~,
    )
  }) &&
  configs.all(config => {
    configs.filter(other => other.client_id == config.client_id).length() == 1
  })
}

///|
pub fn validate_issue_intent(
  intent : ClientHandoffIssueIntent,
  now_unix_ms : Int64,
  allow_model_free? : Bool = false,
) -> Unit raise ClientHandoffError {
  if !@contracts.valid_identifier(intent.request_id) ||
    !@contracts.valid_identifier(intent.client_id) ||
    !@contracts.valid_identifier(intent.tenant_ref) ||
    !@contracts.valid_identifier(intent.subject_ref) ||
    !@contracts.valid_identifier(intent.organization_id) ||
    !@contracts.valid_identifier(intent.project_id) ||
    !valid_text(intent.display_name, 128) ||
    (intent.allowed_models.length() == 0 && !allow_model_free) ||
    intent.allowed_models.length() > 128 ||
    intent.allowed_models.any(model => !@contracts.valid_identifier(model)) ||
    intent.allowed_models.any(model => intent.allowed_models.count(model) != 1) ||
    intent.handoff_expires_unix_ms <= now_unix_ms ||
    intent.handoff_expires_unix_ms - now_unix_ms > 300000L ||
    intent.credential_expires_unix_ms <= intent.handoff_expires_unix_ms ||
    intent.credential_expires_unix_ms - now_unix_ms > 31536000000L ||
    intent.maximum_requests <= 0L ||
    intent.maximum_requests > 1000000000L {
    raise InvalidInput("invalid client handoff intent")
  }
}
