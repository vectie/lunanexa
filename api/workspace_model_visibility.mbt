///|
/// Public API-key views use zero for an unbounded request limit. A valid
/// unlimited key must remain discoverable by the personal workbench.
fn workspace_model_key_visible(
  credential : @access.ApiCredentialView,
  now_unix_ms : Int64,
) -> Bool {
  credential.revoked_unix_ms is None &&
  credential.expires_unix_ms > now_unix_ms &&
  credential.scopes.contains(Inference) &&
  (
    credential.maximum_requests == 0L ||
    credential.consumed_requests < credential.maximum_requests
  )
}
