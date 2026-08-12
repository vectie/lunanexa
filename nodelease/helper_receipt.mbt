///|
fn helper_action_binding(action : LeaseAgentAction) -> (String, String, Int64) {
  match action {
    ProvisionAccess(lease_id~, generation~, ..) =>
      ("provision", lease_id, generation)
    RevokeAccess(lease_id~, generation~, ..) => ("revoke", lease_id, generation)
    SanitizeLease(lease_id~, generation~, ..) =>
      ("sanitize", lease_id, generation)
    QuarantineNode(lease_id~, generation~) =>
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
pub fn valid_helper_receipt(
  action : LeaseAgentAction,
  receipt : String,
) -> Bool {
  helper_receipt_timestamp(action, receipt) is Some(_)
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
