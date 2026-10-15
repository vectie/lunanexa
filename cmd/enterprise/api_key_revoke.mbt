///|
/// Accept both the controller's legacy Option encoding and nullable JSON.
/// Successful revocation must close the confirmation and update the key card.
impl @json.FromJson for PortalApiKeyRevokeView with fn from_json(value, path) {
  guard value is { "key_id": key_id, .. } else {
    raise @json.JsonDecodeError((path, "expected revoked API key"))
  }
  let revoked_unix_ms : Int64? = match value {
    { "revoked_unix_ms": Array([timestamp]), .. } =>
      Some(@json.from_json(timestamp, path=path.add_key("revoked_unix_ms")))
    { "revoked_unix_ms": Null | Array([]), .. } => None
    { "revoked_unix_ms": timestamp, .. } =>
      Some(@json.from_json(timestamp, path=path.add_key("revoked_unix_ms")))
    _ => None
  }
  {
    key_id: @json.from_json(key_id, path=path.add_key("key_id")),
    revoked_unix_ms,
  }
}
