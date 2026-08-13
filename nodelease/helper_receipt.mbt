///|
fn helper_action_binding(action : LeaseAgentAction) -> (String, String, Int64) {
  match action {
    ProvisionAccess(lease_id~, generation~, ..) =>
      ("provision", lease_id, generation)
    RevokeAccess(lease_id~, generation~, ..) => ("revoke", lease_id, generation)
    SanitizeLease(lease_id~, generation~, ..) =>
      ("sanitize", lease_id, generation)
    QuarantineNode(lease_id~, generation~, ..) =>
      ("quarantine", lease_id, generation)
    NoAction => ("none", "none", 0L)
  }
}

///|
pub fn helper_receipt(
  action : LeaseAgentAction,
  verified_unix_ms : Int64,
) -> String {
  let (name, lease_id, generation) = helper_action_binding(action)
  "lunanexa-helper-v1:\{name}:\{lease_id}:\{generation}:verified:\{verified_unix_ms}"
}

///|
fn helper_receipt_mac_payload(
  action : LeaseAgentAction,
  verified_unix_ms : Int64,
) -> String {
  let (name, lease_id, generation) = helper_action_binding(action)
  // The human-readable receipt prefix stays short, but the MAC binds the
  // complete typed action. In particular, a provision receipt cannot be
  // replayed for a different Unix account, credential reference or expiry.
  "lunanexa-helper-v2|\{name}|\{lease_id}|\{generation}|\{verified_unix_ms}|\{action.to_json().stringify()}"
}

///|
fn helper_authorization_mac_payload(
  action : LeaseAgentAction,
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
) -> String {
  "lunanexa-helper-action-v1|\{issued_unix_ms}|\{expires_unix_ms}|\{action.to_json().stringify()}"
}

///|
pub fn signed_helper_authorization(
  action : LeaseAgentAction,
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
  signing_secret : String,
) -> String {
  if action == NoAction ||
    issued_unix_ms <= 0L ||
    expires_unix_ms <= issued_unix_ms ||
    signing_secret.length() < 32 {
    return ""
  }
  let signature = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(signing_secret).view(),
      @utf8.encode(
        helper_authorization_mac_payload(
          action, issued_unix_ms, expires_unix_ms,
        ),
      ).view(),
    ),
  )
  "lunanexa-helper-action-v1:\{issued_unix_ms}:\{expires_unix_ms}:\{signature}"
}

///|
fn parse_helper_authorization(
  authorization : String,
) -> (Int64, Int64, String)? {
  let prefix = "lunanexa-helper-action-v1:"
  if !authorization.has_prefix(prefix) || authorization.length() > 180 {
    return None
  }
  let fields = authorization[prefix.length():].split(":").collect()
  if fields.length() != 3 ||
    fields[0].length() == 0 ||
    fields[0].length() > 20 ||
    fields[1].length() == 0 ||
    fields[1].length() > 20 ||
    fields[2].length() != 64 ||
    !fields[0].all(character => character >= '0' && character <= '9') ||
    !fields[1].all(character => character >= '0' && character <= '9') ||
    !fields[2].all(character => {
      (character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')
    }) {
    return None
  }
  let issued = @string.parse_int64(fields[0]) catch { _ => return None }
  let expires = @string.parse_int64(fields[1]) catch { _ => return None }
  if issued <= 0L || expires <= issued {
    None
  } else {
    Some((issued, expires, fields[2].to_owned()))
  }
}

///|
pub fn helper_authorization_framed(
  authorization : String,
  now_unix_ms : Int64,
) -> Bool {
  match parse_helper_authorization(authorization) {
    Some((issued, expires, _)) => now_unix_ms >= issued && now_unix_ms < expires
    None => false
  }
}

///|
pub fn valid_helper_authorization(
  action : LeaseAgentAction,
  authorization : String,
  signing_secret : String,
  now_unix_ms : Int64,
) -> Bool {
  guard action != NoAction &&
    signing_secret.length() >= 32 &&
    parse_helper_authorization(authorization) is Some((issued, expires, _)) &&
    now_unix_ms >= issued &&
    now_unix_ms < expires else {
    return false
  }
  let expected = signed_helper_authorization(
    action, issued, expires, signing_secret,
  )
  if expected.length() != authorization.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<expected.length() {
    difference = difference |
      (expected[index].to_int() ^ authorization[index].to_int())
  }
  difference == 0
}

///|
pub fn signed_helper_receipt(
  action : LeaseAgentAction,
  verified_unix_ms : Int64,
  signing_secret : String,
) -> String {
  if action == NoAction ||
    verified_unix_ms <= 0L ||
    signing_secret.length() < 32 {
    return ""
  }
  let (name, lease_id, generation) = helper_action_binding(action)
  let signature = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(signing_secret).view(),
      @utf8.encode(helper_receipt_mac_payload(action, verified_unix_ms)).view(),
    ),
  )
  "lunanexa-helper-v2:\{name}:\{lease_id}:\{generation}:verified:\{verified_unix_ms}:mac:\{signature}"
}

///|
pub fn signed_helper_receipt_timestamp(
  action : LeaseAgentAction,
  receipt : String,
  signing_secret : String,
) -> Int64? {
  if action == NoAction ||
    signing_secret.length() < 32 ||
    receipt.length() > 640 {
    return None
  }
  let (name, lease_id, generation) = helper_action_binding(action)
  let prefix = "lunanexa-helper-v2:\{name}:\{lease_id}:\{generation}:verified:"
  if !receipt.has_prefix(prefix) {
    return None
  }
  let suffix = receipt[prefix.length():].to_owned()
  guard suffix.find(":mac:") is Some(separator) else { return None }
  let timestamp_text = suffix[:separator].to_owned()
  let signature = suffix[separator + 5:].to_owned()
  if timestamp_text == "" ||
    timestamp_text.length() > 20 ||
    !timestamp_text.all(character => character >= '0' && character <= '9') ||
    signature.length() != 64 ||
    !signature.all(character => {
      (character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')
    }) {
    return None
  }
  let timestamp = @string.parse_int64(timestamp_text) catch { _ => return None }
  if timestamp <= 0L {
    return None
  }
  let expected = signed_helper_receipt(action, timestamp, signing_secret)
  if expected.length() != receipt.length() {
    return None
  }
  let mut difference = 0
  for index in 0..<expected.length() {
    difference = difference |
      (expected[index].to_int() ^ receipt[index].to_int())
  }
  if difference == 0 {
    Some(timestamp)
  } else {
    None
  }
}

///|
pub fn valid_signed_helper_receipt(
  action : LeaseAgentAction,
  receipt : String,
  signing_secret : String,
) -> Bool {
  signed_helper_receipt_timestamp(action, receipt, signing_secret) is Some(_)
}

///|
/// Node-side framing check for the v2 receipt. The node agent intentionally
/// does not hold the root-helper MAC key; only the controller verifies the MAC.
pub fn signed_helper_receipt_timestamp_unverified(
  action : LeaseAgentAction,
  receipt : String,
) -> Int64? {
  if action == NoAction || receipt.length() > 640 {
    return None
  }
  let (name, lease_id, generation) = helper_action_binding(action)
  let prefix = "lunanexa-helper-v2:\{name}:\{lease_id}:\{generation}:verified:"
  if !receipt.has_prefix(prefix) {
    return None
  }
  let suffix = receipt[prefix.length():].to_owned()
  guard suffix.find(":mac:") is Some(separator) else { return None }
  let timestamp_text = suffix[:separator].to_owned()
  let signature = suffix[separator + 5:].to_owned()
  if timestamp_text == "" ||
    timestamp_text.length() > 20 ||
    !timestamp_text.all(character => character >= '0' && character <= '9') ||
    signature.length() != 64 ||
    !signature.all(character => {
      (character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')
    }) {
    return None
  }
  let parsed = @string.parse_int64(timestamp_text) catch { _ => return None }
  if parsed > 0L {
    Some(parsed)
  } else {
    None
  }
}

///|
pub fn helper_receipt_timestamp_unverified(
  action : LeaseAgentAction,
  receipt : String,
) -> Int64? {
  match signed_helper_receipt_timestamp_unverified(action, receipt) {
    Some(value) => Some(value)
    None => helper_receipt_timestamp(action, receipt)
  }
}

///|
pub fn valid_helper_receipt(
  action : LeaseAgentAction,
  receipt : String,
) -> Bool {
  helper_receipt_timestamp_unverified(action, receipt) is Some(_)
}

///|
pub fn helper_receipt_timestamp(
  action : LeaseAgentAction,
  receipt : String,
) -> Int64? {
  if action == NoAction || receipt.length() == 0 || receipt.length() > 512 {
    return None
  }
  let (name, lease_id, generation) = helper_action_binding(action)
  let prefix = "lunanexa-helper-v1:\{name}:\{lease_id}:\{generation}:verified:"
  if !receipt.has_prefix(prefix) || receipt.length() == prefix.length() {
    return None
  }
  let timestamp = receipt[prefix.length():]
  if timestamp.length() > 20 ||
    !timestamp.all(character => character >= '0' && character <= '9') {
    return None
  }
  let parsed = @string.parse_int64(timestamp) catch { _ => return None }
  if parsed > 0L {
    Some(parsed)
  } else {
    None
  }
}
