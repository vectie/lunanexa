///|
// The controller's legacy ToJson and current Json serializer differ for
// optional values. Decode this small public projection explicitly so a saved
// numeric budget cannot invalidate the entire signed-in portal view.
pub fn decode_trial_projection(json : Json) -> TrialEntitlementView? raise {
  let row = match json {
    Null | Array([]) => return None
    Array([row]) => row
    _ => json
  }
  // Optional struct fields are omitted by the legacy decoder, not wrapped
  // like a top-level Option. Normalize only explicit null optional fields.
  if row is Object(fields) {
    for
      name in [
        "consumed_requests", "max_output_tokens", "api_key_id", "revoked_unix_ms",
      ] {
      if fields.get(name) is Some(Null) {
        fields.remove(name)
      }
    }
  }
  Some(@json.from_json(row))
}
