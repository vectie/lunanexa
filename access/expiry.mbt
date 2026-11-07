///|
/// Shorten a credential to its existing entitlement without reissuing it or
/// changing usage. Never extends, revives or changes another subject's key.
pub async fn AccessStore::cap_expiry_for_subject(
  self : AccessStore,
  key_id : String,
  tenant_ref : String,
  subject_ref : String,
  expires_unix_ms : Int64,
  now_unix_ms : Int64,
) -> Bool {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.credentials.get(key_id) is Some(current) &&
    current.tenant_ref == tenant_ref &&
    current.subject_ref == subject_ref &&
    current.revoked_unix_ms is None &&
    current.expires_unix_ms > now_unix_ms &&
    expires_unix_ms > now_unix_ms &&
    expires_unix_ms > current.issued_unix_ms else {
    raise Unauthorized
  }
  if current.expires_unix_ms <= expires_unix_ms {
    return false
  }
  let previous = self.credentials.copy()
  errdefer {
    self.credentials = previous
  }
  self.credentials[key_id] = { ..current, expires_unix_ms, }
  self.persist()
  true
}
