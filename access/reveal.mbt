///|
/// Recreate only the owner's active credential, verifying the result against
/// its durable digest. No plaintext is added to snapshots or public lists.
pub async fn AccessStore::secret_for_subject(
  self : AccessStore,
  key_id : String,
  tenant_ref : String,
  subject_ref : String,
  now_unix_ms : Int64,
) -> String {
  self.mutex.acquire()
  defer self.mutex.release()
  guard self.credentials.get(key_id) is Some(current) &&
    current.tenant_ref == tenant_ref &&
    current.subject_ref == subject_ref &&
    current.revoked_unix_ms is None &&
    current.expires_unix_ms > now_unix_ms &&
    now_unix_ms >= current.issued_unix_ms &&
    current.organization_id is Some(organization_id) &&
    current.project_id is Some(project_id) else {
    raise Unauthorized
  }
  let secret = self.issue_secret(
    {
      key_id: current.key_id,
      tenant_ref: current.tenant_ref,
      subject_ref: current.subject_ref,
      organization_id,
      project_id,
      display_name: current.display_name,
      scopes: current.scopes,
      allowed_models: current.allowed_models,
      expires_unix_ms: current.expires_unix_ms,
      maximum_requests: 0L,
    },
    current.issued_unix_ms,
  )
  guard constant_time_equal(digest_secret(secret), current.secret_sha256) else {
    raise Unauthorized
  }
  secret
}
