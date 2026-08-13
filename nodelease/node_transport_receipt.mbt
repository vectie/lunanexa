///|
fn node_transport_payload(
  lease : ExclusiveNodeLease,
  node_id : String,
) -> String {
  let unsigned : ExclusiveNodeLease = { ..lease, authority_receipt: "" }
  "lunanexa.node-lease-envelope.v1|\{node_id}|\{unsigned.to_json().stringify()}"
}

///|
/// Replaces the controller-only lease authority receipt with a MAC scoped to
/// the authenticated node transport. The persisted authority receipt must
/// never be returned to a node agent.
pub fn node_transport_lease(
  lease : ExclusiveNodeLease,
  node_id : String,
  node_credential : String,
) -> ExclusiveNodeLease {
  if lease.intent.node_id != node_id || node_credential == "" {
    return { ..lease, authority_receipt: "" }
  }
  let mac = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(node_credential).view(),
      @utf8.encode(node_transport_payload(lease, node_id)).view(),
    ),
  )
  { ..lease, authority_receipt: "node-envelope-v1:\{mac}" }
}

///|
fn helper_actions_for_lease(
  lease : ExclusiveNodeLease,
) -> Array[LeaseAgentAction] {
  [
    ProvisionAccess(
      lease_id=lease.intent.lease_id,
      username=lease.intent.unix_username,
      credential_ref=lease.intent.access_credential_ref,
      expires_unix_ms=lease.intent.expires_unix_ms,
      generation=lease.generation,
    ),
    RevokeAccess(
      lease_id=lease.intent.lease_id,
      username=lease.intent.unix_username,
      generation=lease.generation,
    ),
    SanitizeLease(
      lease_id=lease.intent.lease_id,
      username=lease.intent.unix_username,
      generation=lease.generation,
    ),
    QuarantineNode(
      lease_id=lease.intent.lease_id,
      username=lease.intent.unix_username,
      generation=lease.generation,
    ),
  ]
}

///|
pub fn node_transport_lease_with_helper_authorizations(
  lease : ExclusiveNodeLease,
  node_id : String,
  node_credential : String,
  helper_secret : String,
  issued_unix_ms : Int64,
) -> ExclusiveNodeLease {
  let transported = node_transport_lease(lease, node_id, node_credential)
  if transported.authority_receipt == "" ||
    helper_secret.length() < 32 ||
    issued_unix_ms <= 0L ||
    lease.intent.expires_unix_ms > 9223372036768375807L ||
    issued_unix_ms > 9223372036768375807L {
    return transported
  }
  let authorizations : Array[String] = []
  for action in helper_actions_for_lease(lease) {
    let not_before : Int64? = match action {
      ProvisionAccess(..) =>
        if lease.state == Provisioning || lease.state == Active {
          Some(issued_unix_ms)
        } else {
          None
        }
      RevokeAccess(..) =>
        match lease.state {
          Active => Some(lease.intent.expires_unix_ms)
          Expiring
          | Draining
          | RevokingAccess
          | Sanitizing
          | Completed
          | Cancelled => Some(issued_unix_ms)
          _ => None
        }
      SanitizeLease(..) =>
        if lease.state == Sanitizing || lease.state == Completed {
          Some(issued_unix_ms)
        } else {
          None
        }
      QuarantineNode(..) =>
        match lease.state {
          Requested | Reserved | Completed | Cancelled => None
          _ => Some(issued_unix_ms)
        }
      NoAction => None
    }
    match not_before {
      Some(start) if start <= 9223372036768375807L => {
        let fields = signed_helper_authorization(
            action,
            start,
            start + 86400000L,
            helper_secret,
          )
          .split(":")
          .collect()
        authorizations.push("\{fields[1]}:\{fields[2]}:\{fields[3]}")
      }
      _ => authorizations.push("0:0:\{"0".repeat(64)}")
    }
  }
  {
    ..transported,
    authority_receipt: "\{transported.authority_receipt}:helper-actions-v2:\{authorizations.join(":")}",
  }
}

///|
fn transport_receipt_prefix(receipt : String) -> String? {
  let expected_length = "node-envelope-v1:".length() + 64
  if receipt.length() < expected_length {
    None
  } else {
    Some(receipt[:expected_length].to_owned())
  }
}

///|
pub fn helper_authorization_from_transport_lease(
  lease : ExclusiveNodeLease,
  action : LeaseAgentAction,
  now_unix_ms : Int64,
) -> String? {
  let mut action_index : Int? = None
  for index, candidate in helper_actions_for_lease(lease) {
    if candidate == action {
      action_index = Some(index)
    }
  }
  guard action_index is Some(index) &&
    lease.authority_receipt.find(":helper-actions-v2:") is Some(separator) else {
    return None
  }
  let fields = lease.authority_receipt[separator + 19:].split(":").collect()
  if fields.length() != 12 || index >= 4 {
    return None
  }
  let offset = index * 3
  let authorization = "lunanexa-helper-action-v1:\{fields[offset]}:\{fields[offset + 1]}:\{fields[offset + 2]}"
  if helper_authorization_framed(authorization, now_unix_ms) {
    Some(authorization)
  } else {
    None
  }
}

///|
pub fn valid_node_transport_lease(
  lease : ExclusiveNodeLease,
  node_id : String,
  node_credential : String,
) -> Bool {
  guard transport_receipt_prefix(lease.authority_receipt) is Some(received) else {
    return false
  }
  if lease.intent.node_id != node_id || node_credential == "" {
    return false
  }
  let expected = node_transport_lease(
      { ..lease, authority_receipt: "" },
      node_id,
      node_credential,
    ).authority_receipt
  let mut difference = 0
  for index in 0..<expected.length() {
    difference = difference |
      (expected[index].to_int() ^ received[index].to_int())
  }
  difference == 0
}
