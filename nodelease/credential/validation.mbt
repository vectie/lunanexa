///|
fn safe_host_alias(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 253 &&
  !value.has_prefix(".") &&
  !value.has_suffix(".") &&
  !value.contains("..") &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '.' ||
    character == '-'
  })
}

///|
fn safe_host_fingerprint(value : String) -> Bool {
  let prefix = "SHA256:"
  value.has_prefix(prefix) &&
  value.length() >= prefix.length() + 32 &&
  value.length() <= prefix.length() + 88 &&
  value[prefix.length():].all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '+' ||
    character == '/' ||
    character == '-' ||
    character == '_'
  })
}

///|
fn safe_issuer_url(value : String) -> Bool {
  if value.length() == 0 ||
    value.length() > 1024 ||
    value != value.trim().to_owned() {
    return false
  }
  let remainder = if value.has_prefix("https://") {
    value[8:].to_owned()
  } else if value.has_prefix("http://127.0.0.1:") {
    value[7:].to_owned()
  } else if value.has_prefix("http://localhost:") {
    value[7:].to_owned()
  } else if value.has_prefix("http://[::1]:") {
    value[7:].to_owned()
  } else {
    return false
  }
  guard remainder.find("/") is Some(slash) else { return false }
  let authority = remainder[:slash].to_owned()
  let path = remainder[slash:].to_owned()
  authority != "" &&
  path.length() > 1 &&
  !value.contains("@") &&
  !value.contains("?") &&
  !value.contains("#") &&
  !value.contains("\\") &&
  !value.contains("%") &&
  !path.contains("//") &&
  value.all(character => character.is_printable() && !character.is_whitespace())
}

///|
fn issuer_origin(value : String) -> String? {
  if !safe_issuer_url(value) {
    return None
  }
  guard value.find("/") is Some(first_slash) &&
    value[first_slash + 2:].find("/") is Some(relative_slash) else {
    return None
  }
  let authority_end = first_slash + 2 + relative_slash
  Some(value[:authority_end].to_owned().to_lower())
}

///| A retained health proof authorizes redirects only for the exact issuer

///| origin it checked. An operator cannot substitute another HTTPS service in

///|
/// an otherwise valid handoff intent.
pub fn credential_issuer_origin_matches(
  evidence : CredentialIssuerReadinessEvidence,
  redirect_url : String,
) -> Bool {
  match (issuer_origin(evidence.health_endpoint), issuer_origin(redirect_url)) {
    (Some(health_origin), Some(redirect_origin)) =>
      health_origin == redirect_origin
    _ => false
  }
}

///|
pub fn credential_issuer_evidence_ready(
  evidence : CredentialIssuerReadinessEvidence,
  now_unix_ms : Int64,
) -> Bool {
  evidence.version == issuer_readiness_contract_version &&
  @contracts.valid_identifier(evidence.adapter_id, maximum_length=128) &&
  safe_issuer_url(evidence.health_endpoint) &&
  @contracts.valid_identifier(evidence.evidence_ref, maximum_length=256) &&
  evidence.checked_unix_ms > 0L &&
  evidence.expires_unix_ms > evidence.checked_unix_ms &&
  evidence.expires_unix_ms - evidence.checked_unix_ms <= 86400000L &&
  now_unix_ms >= evidence.checked_unix_ms &&
  now_unix_ms < evidence.expires_unix_ms &&
  evidence.healthy &&
  evidence.signature.length() == 64 &&
  evidence.signature.all(character => {
    (character >= '0' && character <= '9') ||
    (character >= 'a' && character <= 'f')
  })
}

///|
pub fn validate_issue_intent(
  intent : CredentialHandoffIssueIntent,
) -> Unit raise CredentialHandoffError {
  if !@contracts.valid_identifier(intent.request_id) ||
    !@contracts.valid_identifier(intent.lease_id) ||
    intent.expected_generation <= 0L ||
    !safe_host_alias(intent.host_alias) ||
    intent.ssh_port <= 0 ||
    intent.ssh_port > 65535 ||
    !safe_host_fingerprint(intent.host_key_fingerprint) ||
    !safe_issuer_url(intent.issuer_redirect_url) {
    raise InvalidInput("credential handoff intent is invalid")
  }
}

///|
pub fn connection_command(
  username : String,
  host_alias : String,
  ssh_port : Int,
) -> String raise CredentialHandoffError {
  if !@nodelease.valid_unix_username(username) ||
    !safe_host_alias(host_alias) ||
    ssh_port <= 0 ||
    ssh_port > 65535 {
    raise InvalidInput("credential connection metadata is invalid")
  }
  "ssh -p \{ssh_port} \{username}@\{host_alias}"
}

///|
pub fn customer_view(
  record : CredentialHandoffRecord,
  subject_ref : String,
  now_unix_ms : Int64,
) -> CustomerCredentialHandoffView raise CredentialHandoffError {
  if record.subject_ref != subject_ref {
    raise NotFound
  }
  {
    handoff_ref: record.handoff_ref,
    lease_ref: record.lease_id,
    generation: record.generation,
    username: record.username,
    host_alias: record.host_alias,
    ssh_port: record.ssh_port,
    host_key_fingerprint: record.host_key_fingerprint,
    connection_command: connection_command(
      record.username,
      record.host_alias,
      record.ssh_port,
    ),
    valid_until_unix_ms: record.expires_unix_ms,
    can_redeem: record.redeemed_unix_ms is None &&
    record.revoked_unix_ms is None &&
    now_unix_ms < record.expires_unix_ms,
    can_recover: record.redeemed_unix_ms is Some(_) &&
    record.revoked_unix_ms is None &&
    now_unix_ms < record.expires_unix_ms,
  }
}
