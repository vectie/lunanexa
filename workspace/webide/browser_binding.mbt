///|
/// Deployment-owned browser binding. A consumer can compare its authenticated
/// browser principal with the controller-issued grant without forwarding a
/// platform credential into the user workspace. No product schema lives here.
async fn Bridge::check_browser(
  self : Bridge,
  grant : Grant,
  headers : @http.Headers,
) -> Unit {
  guard self.authorize_browser is Some(authorize) else { return }
  let cookie = header(headers, "cookie").unwrap_or("")
  if cookie.length() > 16384 || !authorize(grant, cookie) {
    raise BridgeError::Unauthorized
  }
}

///|
/// A definite mismatch closes the old browser session. An unavailable identity
/// authority denies the request but preserves the session and saved workspace.
async fn Bridge::check_bound_browser(
  self : Bridge,
  token : String,
  grant : Grant,
  headers : @http.Headers,
) -> Unit {
  self.check_browser(grant, headers) catch {
    BridgeError::Unauthorized => {
      self.sessions.remove(token)
      raise BridgeError::Unauthorized
    }
    error => raise error
  }
  // A concurrent identity mismatch/logout must not leave an in-flight allow.
  guard self.sessions.contains(token) else { raise BridgeError::Unauthorized }
}
